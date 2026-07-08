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
    variable DATATYPE    "1. Endure_SF_A"  ;# contour/query data type label —
                                            # MUST match the loaded result file
                                            # (AVL EXCITE: "1. Endure_SF_A";
                                            # FEMFAT etc.: run once and copy the
                                            # exact label from the console's
                                            # "Available data types" listing)
    variable SUBCASE     1                 ;# load case holding the SF result
    variable SIMULATION  0                 ;# simulation step index
    variable RESOLVED_DT ""                ;# DATATYPE resolved to the file's exact label (set by SetupContour)
    variable LIB_DIR     [file dirname [file normalize [info script]]]
}

# Print the model's REAL selection-set table (IDs from GetSelectionSetList —
# they are NOT guaranteed to be 1..N; GetSelectionSetHandle silently returns
# an EMPTY set for a nonexistent ID, which is exactly how the "no data
# returned" bug happened). Returns a dict-ish list {id label id label ...}.
proc ::SafetyFactor::ListSets {} {
    set out {}
    catch {
        foreach sid [model GetSelectionSetList] {
            model GetSelectionSetHandle _sfls $sid
            set lbl [_sfls GetLabel]
            set sz  ""
            catch {set sz [_sfls GetSize]}
            _sfls ReleaseHandle
            puts "    set id $sid -> '$lbl' (size $sz)"
            lappend out $sid $lbl
        }
    }
    return $out
}

# Resolve user input (a real ID or a set NAME like "Pos3") against the
# model's actual selection-set list. Returns the real ID, or "" if no match.
proc ::SafetyFactor::ResolveSet {input setTable} {
    foreach {sid lbl} $setTable {
        if {$sid eq $input} { return $sid }
    }
    foreach {sid lbl} $setTable {
        if {[string equal -nocase $lbl $input]} { return $sid }
    }
    return ""
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
# HyperView SILENTLY ignores an unknown data-type label (no error, contour
# just stays grey) — so read the label back and, on mismatch, print the
# file's real data-type list so the correct spelling can be copied into
# ::SafetyFactor::DATATYPE (panel Options → "Data type").
proc ::SafetyFactor::SetupContour {} {
    variable DATATYPE
    variable SUBCASE
    variable SIMULATION

    rctrl GetContourCtrlHandle con
    con GetLegendHandle leg

    variable RESOLVED_DT

    rctrl SetCurrentSubcase $SUBCASE
    rctrl SetCurrentSimulation $SIMULATION

    # ★ Resolve DATATYPE against the file's ACTUAL data-type list. The real
    # labels carry internal padding (e.g. "1.  Endure_SF_A" with TWO spaces,
    # "1.       1/SF_A" — names are column-aligned after the "N." prefix).
    # A one-space lookalike is accepted silently AND GetDataType even echoes
    # it back — but it binds NO data (binding stays 'null', contour grey,
    # contour.value queries return 0 rows). Read-back equality proves
    # nothing here; only a whitespace-normalized match against
    # GetDataTypeList finds the file's true label.
    set dtList ""
    if {[catch {set dtList [rctrl GetDataTypeList [rctrl GetCurrentSubcase]]}]} {
        catch {set dtList [rctrl GetDataTypeList]}
    }
    set RESOLVED_DT $DATATYPE
    set normIn [string tolower [string trim [regsub -all {\s+} $DATATYPE " "]]]
    set found 0
    foreach dt $dtList {
        set norm [string tolower [string trim [regsub -all {\s+} $dt " "]]]
        if {$norm eq $normIn} {
            set RESOLVED_DT $dt
            set found 1
            break
        }
    }
    if {!$found && $dtList ne ""} {
        puts "  WARNING: '$DATATYPE' has no normalized match in the data-type list:"
        foreach dt $dtList { puts "      '$dt'" }
    }
    puts "  data type resolved: '$RESOLVED_DT'"
    con SetDataType $RESOLVED_DT

    con SetDataComponent {Scalar value}
    con SetAverageMode none
    con SetCornerDataEnabled false
    con SetEnableState true
    leg SetNumericPrecision 5

    # Materialize the contour — SetEnableState alone is NOT enough: without
    # the animator step-refresh + display options the model stays grey and
    # contour.value queries return 0 rows (recipe confirmed in the HW14
    # library §3 / prcApplyContour).
    catch {
        page GetAnimatorHandle _anim
        _anim SetCurrentStep [_anim GetCurrentStep]
        _anim ReleaseHandle
    }
    catch {clt SetDisplayOptions "contour" true}
    catch {clt SetDisplayOptions "legend"  true}
    clt Draw

    # Post-apply sanity: binding 'null' means the contour still bound no data
    set bind ""
    catch {set bind [con GetBinding]}
    puts "  contour binding   : '$bind'"
    if {$bind eq "null" || $bind eq ""} {
        puts "  WARNING: contour did not bind any data — the data-type label above is still wrong for this file"
    }
}

# ─────────────────────────────────────────────────────────────────────
# EXPORT — min Safety Factor per selection set, every window on the page
# ─────────────────────────────────────────────────────────────────────

proc ::SafetyFactor::processWindow {pageHandle winIdx selectionSets summaryRowsVar} {
    variable DATATYPE
    variable SUBCASE
    variable SIMULATION
    upvar 1 $summaryRowsVar summaryRows

    foreach handle {win clt model rctrl con leg iso math query vw se sys iter setc} {
        catch {${handle} ReleaseHandle}
    }

    # ★ ACTIVATE the window first — the original (working) script always ran
    # on [page GetActiveWindow]; querying contour.value on a never-activated
    # window is the prime suspect for empty results in the window loop.
    catch {$pageHandle SetActiveWindow $winIdx}

    # GetWindowHandle takes an INDEX 1..N (confirmed live), not an ID
    $pageHandle GetWindowHandle win $winIdx
    win GetClientHandle clt
    set modelID [clt GetActiveModel]
    clt GetModelHandle model $modelID
    model GetResultCtrlHandle rctrl

    puts ""
    puts "===================================================="
    puts " Window $winIdx (model id $modelID)"
    puts "===================================================="

    # Mirror the original handle set exactly (it worked single-window):
    rctrl GetIsoValueCtrlHandle iso
    rctrl GetResultMathCtrlHandle math
    model GetQueryCtrlHandle query
    catch {iso SetAverageMode Simple}

    SetupContour
    clt Draw
    set subLabel [rctrl GetSubcaseLabel $SUBCASE]
    puts "Load case: $subLabel"
    catch {puts "Subcase list: [rctrl GetSubcaseList model]"}

    query SetDataSourceProperty result "Simulation Step" $SIMULATION
    # Real model ID of THIS window — not hardcoded 1
    query SetDataSourceProperty result "Model ID" $modelID
    # Use the RESOLVED label (exact string from GetDataTypeList, including
    # its internal padding) — this is why the original AVL-era script needed
    # the mysterious two-space "1.  Endure_SF_A" here.
    variable RESOLVED_DT
    query SetDataSourceProperty result "Result Type" $RESOLVED_DT
    query SetDataSourceProperty result "Load Case" $SUBCASE
    query SetDataSourceProperty result complex real
    query SetDataSourceProperty result complex_format real
    query SetDataSourceProperty result mutiline true
    query SetDataSourceProperty result dataformat csv
    query SetDataSourceProperty result datatype real
    query SetDataSourceProperty result layer all

    # Real selection-set table for THIS window's model — user input is
    # resolved against it (by real ID or by name), never trusted blindly.
    puts "  Selection sets in this model:"
    set setTable [ListSets]

    # Primer pass — the original script always ran one WriteData before the
    # per-set loop; keep it in case that's what materializes the query.
    catch {
        query SetSelectionSet [lindex $setTable 0]
        query SetQuery "node.id contour.value"
        set _primer [file join $::SafetyFactor::LIB_DIR "_sf_primer_tmp.csv"]
        query WriteData $_primer csv
        file delete -force $_primer
    }

    foreach setInput $selectionSets {
        set setID [ResolveSet $setInput $setTable]
        if {$setID eq ""} {
            puts "  skip '$setInput': no selection set with that ID or name in this model (see table above)"
            continue
        }
        model GetSelectionSetHandle setc $setID
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

    catch {$pageHandle SetActiveWindow $winIdx}
    $pageHandle GetWindowHandle win $winIdx
    win GetClientHandle clt
    clt GetModelHandle model [clt GetActiveModel]
    model GetResultCtrlHandle rctrl

    puts ""
    puts "===== Window $winIdx ====="

    # Resolve input (real ID or name) against the model's actual set list
    set setTable [ListSets]
    set realID [ResolveSet $setID $setTable]
    if {$realID eq ""} {
        puts "  skip: no selection set with ID or name '$setID' in this model"
        return
    }
    model GetSelectionSetHandle setc $realID
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
