# safetyfactor_lib.tcl — shared library for the Safety Factor tools.
# Procs only: no stdin prompts, no auto-run. Sourced by the console
# wrappers and by SafetyFactor_Panel.tcl.
#
# Unlike the Max Stress sibling (Tcl_VonMises-stress...), there is no
# frame sweep and no derived load case: Safety Factor lives on ONE load
# case / simulation (defaults: subcase 1, simulation 0) and we track the
# MINIMUM per selection set.

namespace eval ::SafetyFactor {
    variable PINK        "252 62 255"      ;# marker color (GUI read-back)
    variable MEA_FSIZE   15                ;# measure marker text size
    variable NOTE_FSIZE  10                ;# summary note text size
    variable DATATYPE    "1. Endure_SF_A"  ;# contour data type label
    variable QUERY_TYPE  "1.  Endure_SF_A" ;# query "Result Type" (two spaces — as in the original, verified working)
    variable SUBCASE     1                 ;# load case holding the SF result
    variable SIMULATION  0                 ;# simulation step index
    variable LIB_DIR     [file dirname [file normalize [info script]]]
}

proc ::SafetyFactor::CleanHandles {} {
    foreach handle {sess proj object page win clt model rctrl sub con leg iso math query vw se sys mea mtmp setc mfont note ntmp nfont iter} {
        catch {${handle} ReleaseHandle}
    }
    catch {hwi CloseStack}
}

proc ::SafetyFactor::OpenChain {} {
    hwi OpenStack
    hwi GetSessionHandle sess
    sess GetProjectHandle proj
    proj GetPageHandle page [proj GetActivePage]
}

# Sets the SF contour + current frame on the already-grabbed window handles.
proc ::SafetyFactor::SetupContour {} {
    variable DATATYPE
    variable SUBCASE
    variable SIMULATION

    rctrl GetContourCtrlHandle con
    con GetLegendHandle leg

    con SetDataType $DATATYPE
    con SetDataComponent {Scalar value}
    con SetAverageMode none
    con SetCornerDataEnabled false
    con SetEnableState true
    leg SetNumericPrecision 5
    rctrl SetCurrentSubcase $SUBCASE
    rctrl SetCurrentSimulation $SIMULATION
}

# ─────────────────────────────────────────────────────────────────────
# EXPORT — min Safety Factor per selection set, every window on the page
# ─────────────────────────────────────────────────────────────────────

proc ::SafetyFactor::processWindow {pageHandle winIdx selectionSets summaryRowsVar} {
    variable QUERY_TYPE
    variable SUBCASE
    variable SIMULATION
    upvar 1 $summaryRowsVar summaryRows

    foreach handle {win clt model rctrl con leg iso math query vw se sys iter setc} {
        catch {${handle} ReleaseHandle}
    }

    # GetWindowHandle takes an INDEX 1..N (confirmed live), not an ID
    $pageHandle GetWindowHandle win $winIdx
    win GetClientHandle clt
    clt GetModelHandle model [clt GetActiveModel]
    model GetResultCtrlHandle rctrl

    puts ""
    puts "===================================================="
    puts " Window $winIdx"
    puts "===================================================="

    model GetQueryCtrlHandle query
    SetupContour
    set subLabel [rctrl GetSubcaseLabel $SUBCASE]
    puts "Load case: $subLabel"

    query SetDataSourceProperty result "Simulation Step" $SIMULATION
    query SetDataSourceProperty result "Model ID" 1
    query SetDataSourceProperty result "Result Type" $QUERY_TYPE
    query SetDataSourceProperty result "Load Case" $SUBCASE
    query SetDataSourceProperty result complex real
    query SetDataSourceProperty result complex_format real
    query SetDataSourceProperty result mutiline true
    query SetDataSourceProperty result dataformat csv
    query SetDataSourceProperty result datatype real
    query SetDataSourceProperty result layer all

    foreach setID $selectionSets {
        if {[catch {model GetSelectionSetHandle setc $setID} err]} {
            puts "  skip set $setID: not in this window's model ($err)"
            continue
        }
        set setName [setc GetLabel]
        setc ReleaseHandle

        query SetSelectionSet $setID
        query SetQuery "node.id contour.value"
        query GetQuery

        set minSF 1e30
        set minNodeID ""

        query GetIteratorHandle iter
        for {iter First} {[iter Valid]} {iter Next} {
            set data [iter GetDataList]
            set nodeID [lindex $data 0]
            set sfVal [lindex $data 1]
            if {$sfVal < $minSF} {
                set minSF $sfVal
                set minNodeID $nodeID
            }
        }
        iter ReleaseHandle

        if {$minNodeID eq ""} {
            puts "  WARNING set '$setName': no data returned — row skipped"
            continue
        }

        puts "  Set '$setName': Min SF = $minSF at Node $minNodeID"
        lappend summaryRows [list $winIdx $setName $minNodeID [format "%.5f" $minSF] $subLabel]
    }

    win ReleaseHandle
    puts "--- Window $winIdx done ---"
}

# Runs the full export. Returns the summary CSV path.
proc ::SafetyFactor::RunExport {selectionSets {outputDir ""}} {
    variable LIB_DIR
    if {$outputDir eq ""} { set outputDir $LIB_DIR }

    if {[llength $selectionSets] == 0} {
        error "No selection set IDs given."
    }

    CleanHandles
    OpenChain

    set numWindows [page GetNumberOfWindows]
    puts "--- Found $numWindows window(s) on this page ---"

    set summaryRows {}
    for {set winIdx 1} {$winIdx <= $numWindows} {incr winIdx} {
        if {[catch {processWindow page $winIdx $selectionSets summaryRows} err]} {
            puts ""
            puts "!!!! Window $winIdx failed, skipping it: $err"
        }
    }

    # One clean CSV: single header, one row per (window, selection set).
    set summaryFileName [format "%s/SafetyFactor_Summary.csv" $outputDir]
    set f [open $summaryFileName w+]
    puts $f "WindowID,SetName,MinNodeID,MinSafetyFactor,LoadCaseLabel"
    foreach row $summaryRows {
        lassign $row rWin rSetName rNodeID rSF rLabel
        puts $f "$rWin,$rSetName,$rNodeID,$rSF,\"$rLabel\""
    }
    close $f

    puts ""
    puts "-------------------------------------"
    puts "Exported min Safety Factor for $numWindows window(s)"
    puts "Summary: $summaryFileName"
    puts "-------------------------------------"
    catch {hwi CloseStack}
    return $summaryFileName
}

# ─────────────────────────────────────────────────────────────────────
# ANNOTATE — per-window measure marker + summary note from the CSV
# ─────────────────────────────────────────────────────────────────────

proc ::SafetyFactor::annotateWindow {pageHandle winIdx setID csvRows pink meaSize noteSize} {

    foreach handle {win clt model rctrl con leg mea mtmp setc mfont note ntmp nfont} {
        catch {${handle} ReleaseHandle}
    }

    $pageHandle GetWindowHandle win $winIdx
    win GetClientHandle clt
    clt GetModelHandle model [clt GetActiveModel]
    model GetResultCtrlHandle rctrl

    puts ""
    puts "===== Window $winIdx ====="

    # Resolve set ID -> set name (CSV stores names, not IDs)
    if {[catch {model GetSelectionSetHandle setc $setID} err]} {
        puts "  skip: this window's model has no selection set $setID ($err)"
        return
    }
    set setName [setc GetLabel]
    setc ReleaseHandle

    # Find this window's CSV row
    set nodeID "" ; set sfVal "" ; set lcLabel ""
    foreach row $csvRows {
        lassign $row rWin rSetName rNodeID rSF
        if {$rWin == $winIdx && $rSetName eq $setName} {
            set nodeID $rNodeID
            set sfVal $rSF
            set lcLabel [string trim [join [lrange $row 4 end] ","] {"}]
            break
        }
    }
    if {$nodeID eq ""} {
        puts "  skip: no CSV row for window $winIdx / set '$setName'"
        return
    }
    puts "  set '$setName' -> node $nodeID, min SF $sfVal"

    # Make sure the window displays the SF contour on the right frame
    SetupContour

    # Remove this script's stale measures (re-runnable)
    set staleIDs {}
    catch {
        foreach mid [clt GetMeasureList] {
            clt GetMeasureHandle mtmp $mid
            if {[string match "MinSF_*" [mtmp GetLabel]]} {
                lappend staleIDs $mid
            }
            mtmp ReleaseHandle
        }
    }
    foreach mid $staleIDs {
        catch {clt RemoveMeasure $mid}
    }

    # Create the measure marker.
    # ⚠️ Display-mode flags: everything except id must be switched OFF
    # explicitly — "scalar" defaults ON for Nodal Contour measures.
    set mid [clt AddMeasure "Nodal Contour"]
    clt GetMeasureHandle mea $mid
    mea SetLabel "MinSF_$setName"
    mea AddNode $nodeID
    foreach _flag {label project mag x_comp y_comp z_comp scalar system min max node_path distance prefix} {
        catch {mea SetDisplayMode $_flag false}
    }
    mea SetDisplayMode "id" true
    mea SetColor $pink

    if {![catch {mea GetFontHandle mfont}]} {
        catch {mfont SetSize $meaSize}      ;# SetSize points — console-confirmed
        catch {mfont ReleaseHandle}
    } else {
        puts "  WARNING: mea GetFontHandle failed — font size left at default"
    }

    mea SetVisibility true

    # ── Summary note ──
    # Pre-existing window notes (e.g. templex "Model Info") are kept but
    # HIDDEN; only this script's own MinSF_* notes are removed.
    set staleNotes {}
    set cornerPos ""
    catch {
        foreach nid [clt GetNoteList] {
            clt GetNoteHandle ntmp $nid
            set nname ""
            catch {set nname [ntmp GetName]}
            if {$nname eq ""} { catch {set nname [ntmp GetLabel]} }
            if {[string match "MinSF_*" $nname]} {
                lappend staleNotes $nid
            } else {
                if {$cornerPos eq ""} {
                    catch {set cornerPos [ntmp GetPosition]}
                }
                catch {ntmp SetVisibility false}
            }
            ntmp ReleaseHandle
        }
    }
    foreach nid $staleNotes {
        catch {clt RemoveNote $nid}
    }

    set nid [clt AddNote 0]
    clt GetNoteHandle note $nid            ;# handle NAME first, then id
    catch {note SetName  "MinSF_$setName"}
    catch {note SetLabel "MinSF_$setName"}
    set sf3 [format "%.3f" $sfVal]
    set line1 "SF: $setName"
    if {$lcLabel ne ""} { set line1 "SF: $lcLabel" }
    note SetText "$line1\nNode ID: $nodeID\nMin SF: $sf3"
    catch {note SetScreenAnchor true}
    catch {note SetAlignment right}
    catch {note SetBorderThickness 0}
    if {$cornerPos ne ""} {
        if {[catch {note SetPosition $cornerPos} err]} {
            puts "  WARNING: SetPosition '$cornerPos' failed: $err"
        }
    }
    if {![catch {note GetFontHandle nfont}]} {
        catch {nfont SetSize $noteSize}
        catch {nfont ReleaseHandle}
    }
    note SetVisibility true

    clt Draw
    puts "  measure 'MinSF_$setName' created (id $mid), note id $nid"
}

# Runs the full annotation pass for ONE selection set ID.
proc ::SafetyFactor::RunAnnotate {setID {outputDir ""}} {
    variable PINK
    variable MEA_FSIZE
    variable NOTE_FSIZE
    variable LIB_DIR
    if {$outputDir eq ""} { set outputDir $LIB_DIR }

    if {[string trim $setID] eq ""} {
        error "No selection set ID given."
    }
    set setID [lindex [split [string trim $setID]] 0]

    set csvFile "$outputDir/SafetyFactor_Summary.csv"
    if {![file exists $csvFile]} {
        error "Summary CSV not found: $csvFile — run the export first."
    }

    set f [open $csvFile r]
    set csvRows {}
    set lineNo 0
    while {[gets $f line] >= 0} {
        incr lineNo
        if {$lineNo == 1} { continue }
        if {[string trim $line] eq ""} { continue }
        set fields [split $line ","]
        if {[llength $fields] < 4} { continue }
        lappend csvRows $fields
    }
    close $f
    puts "--- Loaded [llength $csvRows] row(s) from $csvFile ---"

    CleanHandles
    OpenChain

    set numWindows [page GetNumberOfWindows]
    puts "--- Found $numWindows window(s) on this page ---"

    for {set winIdx 1} {$winIdx <= $numWindows} {incr winIdx} {
        if {[catch {annotateWindow page $winIdx $setID $csvRows $PINK $MEA_FSIZE $NOTE_FSIZE} err]} {
            puts ""
            puts "!!!! Window $winIdx failed, skipping it: $err"
        }
    }

    puts ""
    puts "################  Annotation done.  ################"
    catch {hwi CloseStack}
}
