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
    variable SHOW_NOTE   1                 ;# 1 = create the summary note header, 0 = marker only
    variable SHOW_LEGEND 1                 ;# legend on/off (ApplyDisplay)
    variable LEGEND_TCL  ""                ;# optional legend TCL sourced per window
                                            # during Annotate — capture styling ONLY,
                                            # never touches the CSV or results table
    variable NOTE_WHITE  1                 ;# 1 = white filled note (left-aligned, bordered,
                                            #     leading-space text — white pad for the triad);
                                            # 0 = old transparent right-aligned style
    variable DATACOMP    "Scalar value"    ;# contour/query component
    variable PRECISION   3                 ;# decimals for displayed values AND
                                            # legend numeric precision (cap 10)
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

# Format a value with the configured number of decimals (fallback 3)
proc ::SafetyFactor::Fmt {v} {
    variable PRECISION
    set p $PRECISION
    if {![string is integer -strict $p] || $p < 0 || $p > 10} { set p 3 }
    if {[catch {set out [format "%.${p}f" $v]}]} { return $v }
    return $out
}

# Data-type list of a window's model (for the panel droplist).
proc ::SafetyFactor::FetchTypeList {{winIdx 1}} {
    variable SUBCASE
    CleanHandles
    OpenChain
    catch {page SetActiveWindow $winIdx}
    page GetWindowHandle win $winIdx
    win GetClientHandle clt
    clt GetModelHandle model [clt GetActiveModel]
    model GetResultCtrlHandle rctrl
    catch {rctrl SetCurrentSubcase $SUBCASE}
    set dts ""
    if {[catch {set dts [rctrl GetDataTypeList [rctrl GetCurrentSubcase]]}]} {
        catch {set dts [rctrl GetDataTypeList]}
    }
    catch {hwi CloseStack}
    return $dts
}

# Component list for one data type (signature not documented — try variants).
proc ::SafetyFactor::FetchComponentList {dt {winIdx 1}} {
    variable SUBCASE
    CleanHandles
    OpenChain
    catch {page SetActiveWindow $winIdx}
    page GetWindowHandle win $winIdx
    win GetClientHandle clt
    clt GetModelHandle model [clt GetActiveModel]
    model GetResultCtrlHandle rctrl
    catch {rctrl SetCurrentSubcase $SUBCASE}
    set comps ""
    if {[catch {set comps [rctrl GetDataComponentList $dt]}]} {
        if {[catch {set comps [rctrl GetDataComponentList [rctrl GetCurrentSubcase] $dt]}]} {
            catch {set comps [rctrl GetDataComponentList $dt [rctrl GetCurrentSubcase]]}
        }
    }
    catch {hwi CloseStack}
    return $comps
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

    variable DATACOMP
    variable PRECISION
    con SetDataComponent $DATACOMP
    con SetAverageMode none
    con SetCornerDataEnabled false
    con SetEnableState true
    set _prec $PRECISION
    if {![string is integer -strict $_prec] || $_prec < 0 || $_prec > 10} { set _prec 3 }
    leg SetNumericPrecision $_prec

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
# DISPLAY — legend on/off + element display mode, every window,
# every component. meshMode: meshlines / features / none — the toolbar
# "Shaded Elements [and Mesh/Feature Lines]" buttons = component
# SetPolygonMode opaque + SetMeshMode (console-confirmed mapping).
# ─────────────────────────────────────────────────────────────────────

proc ::SafetyFactor::ApplyDisplay {legendOn meshMode} {
    CleanHandles
    OpenChain

    set numWindows [page GetNumberOfWindows]
    for {set wi 1} {$wi <= $numWindows} {incr wi} {
        if {[catch {
            foreach handle {win clt model rctrl con leg _comp0 _ch} {
                catch {${handle} ReleaseHandle}
            }
            catch {page SetActiveWindow $wi}
            page GetWindowHandle win $wi
            win GetClientHandle clt
            clt GetModelHandle model [clt GetActiveModel]

            # Legend visibility (both the handle and the display option)
            catch {
                model GetResultCtrlHandle rctrl
                rctrl GetContourCtrlHandle con
                con GetLegendHandle leg
                leg SetVisibility $legendOn
            }
            catch {clt SetDisplayOptions "legend" $legendOn}

            # Element display on every component of the model
            model GetComponentHandle _comp0 0
            set _children [_comp0 GetChildrenList]
            _comp0 ReleaseHandle
            foreach cid $_children {
                catch {
                    model GetComponentHandle _ch $cid
                    _ch SetPolygonMode opaque
                    _ch SetMeshMode $meshMode
                    _ch ReleaseHandle
                }
            }
            clt Draw
            puts "  window $wi: legend=$legendOn, mesh=$meshMode ([llength $_children] components)"
        } err]} {
            puts "!!!! Window $wi display apply failed: $err"
        }
    }
    catch {hwi CloseStack}
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
    variable DATACOMP
    query SetDataSourceProperty result "Result Type" $RESOLVED_DT
    query SetDataSourceProperty result "Component" $DATACOMP
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
# RE-QUERY — SF value for ONE node in ONE window (used by the panel's
# editable results table). Returns the contour value at that node on
# SUBCASE/SIMULATION.
# ─────────────────────────────────────────────────────────────────────

proc ::SafetyFactor::QueryNodeValue {winIdx nodeID} {
    variable SUBCASE
    variable SIMULATION

    CleanHandles
    OpenChain

    catch {page SetActiveWindow $winIdx}
    page GetWindowHandle win $winIdx
    win GetClientHandle clt
    set modelID [clt GetActiveModel]
    clt GetModelHandle model $modelID
    model GetResultCtrlHandle rctrl
    model GetQueryCtrlHandle query

    # Applies + resolves the datatype label (sets RESOLVED_DT)
    SetupContour
    variable RESOLVED_DT

    # Temp single-node selection set (query needs a set)
    set tid [model AddSelectionSet node]
    model GetSelectionSetHandle _ts $tid
    _ts Add "id == $nodeID"
    set sz 0
    catch {set sz [_ts GetSize]}
    _ts ReleaseHandle
    if {$sz == 0} {
        catch {model RemoveSelectionSet $tid}
        catch {hwi CloseStack}
        error "node $nodeID not found in window $winIdx's model"
    }

    variable DATACOMP
    query SetDataSourceProperty result "Simulation Step" $SIMULATION
    query SetDataSourceProperty result "Model ID" $modelID
    query SetDataSourceProperty result "Result Type" $RESOLVED_DT
    query SetDataSourceProperty result "Component" $DATACOMP
    query SetDataSourceProperty result "Load Case" $SUBCASE
    query SetDataSourceProperty result complex real
    query SetDataSourceProperty result complex_format real
    query SetDataSourceProperty result mutiline true
    query SetDataSourceProperty result dataformat csv
    query SetDataSourceProperty result datatype real
    query SetDataSourceProperty result layer all
    query SetSelectionSet $tid
    query SetQuery "node.id contour.value"
    query GetQuery

    set val ""
    query GetIteratorHandle iter
    for {iter First} {[iter Valid]} {iter Next} {
        set data [iter GetDataList]
        if {[lindex $data 1] ne ""} { set val [lindex $data 1] }
    }
    iter ReleaseHandle
    catch {model RemoveSelectionSet $tid}

    if {$val eq ""} {
        catch {hwi CloseStack}
        error "no contour value returned for node $nodeID (window $winIdx)"
    }

    catch {hwi CloseStack}
    return $val
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

    # Optional legend TCL — capture styling only. Sourced AFTER the CSV row
    # was read, so it can never affect stored data or the results table.
    variable LEGEND_TCL
    if {$LEGEND_TCL ne ""} {
        if {![file exists $LEGEND_TCL]} {
            puts "  WARNING: legend TCL not found: $LEGEND_TCL"
        } else {
            if {[catch {uplevel #0 [list source $LEGEND_TCL]} _lerr]} {
                puts "  WARNING: legend TCL failed: $_lerr"
            } else {
                # GUI-saved legend files only DEFINE ::post::LoadSettings
                # {legend_handle} — call it with our legend handle name.
                if {[llength [info procs ::post::LoadSettings]]} {
                    if {[catch {::post::LoadSettings leg} _lerr2]} {
                        puts "  WARNING: ::post::LoadSettings failed: $_lerr2"
                    } else {
                        puts "  legend TCL applied: [file tail $LEGEND_TCL] (::post::LoadSettings)"
                    }
                } else {
                    puts "  legend TCL sourced: [file tail $LEGEND_TCL]"
                }
            }
        }
    }

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
    # HIDDEN (only while our note is enabled); this script's own MinSF_*
    # notes are always removed first — so annotating with the toggle OFF
    # also CLEARS old note headers. Toggle: ::SafetyFactor::SHOW_NOTE.
    variable SHOW_NOTE
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
            } elseif {$SHOW_NOTE} {
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

    if {!$SHOW_NOTE} {
        clt Draw
        puts "  measure 'MinSF_$setName' created (id $mid), note header OFF"
        return
    }

    set nid [clt AddNote 0]
    clt GetNoteHandle note $nid            ;# handle NAME first, then id
    catch {note SetName  "MinSF_$setName"}
    catch {note SetLabel "MinSF_$setName"}
    set sf3 [Fmt $sfVal]
    set line1 "SF: $setName"
    if {$lcLabel ne ""} { set line1 "SF: $lcLabel" }
    variable NOTE_WHITE
    if {$NOTE_WHITE} {
        # White filled style. Big left padding leaves a white area for the
        # axis triad to render on; the first line starts with "." because
        # HV auto-trims leading whitespace on line 1 (the dot anchors the
        # indent), and every line is padded to the same column so all 3
        # lines align.
        # No load-case line: Node ID first, MIN second, and a bottom spacer
        # row marked with "." at BOTH ends (leading dot anchors the indent,
        # trailing dot stops HV trimming the whitespace between them).
        note SetText ".                  Node ID: $nodeID\n                   MIN: $sf3\n.                                  ."
        catch {note SetAlignment left}
        catch {note SetBorderThickness 1}
        catch {note SetTransparency false}
        catch {note SetBackgroundColor "255 255 255"}
    } else {
        note SetText "$line1\nNode ID: $nodeID\nMin SF: $sf3"
        catch {note SetAlignment right}
        catch {note SetBorderThickness 0}
        catch {note SetTransparency true}
    }
    catch {note SetScreenAnchor true}
    if {$NOTE_WHITE} {
        # Bottom-left placement (white pad sits under the triad) — sniff
        # SetPosition's coordinate system from GetPosition: values <= 1
        # treated as normalized (origin assumed top-left), larger as pixels.
        set curPos ""
        catch {set curPos [note GetPosition]}
        set placed 0
        if {[llength $curPos] >= 2} {
            lassign $curPos px py
            if {[string is double -strict $px] && [string is double -strict $py]} {
                if {$px <= 1.0 && $py <= 1.0} {
                    if {![catch {note SetPosition "0.02 0.97"}]} { set placed 1 }
                } else {
                    set gh ""
                    catch {set gh [win GetGraphicsHeight]}
                    if {$gh ne "" && ![catch {note SetPosition "10 [expr {int($gh) - 20}]"}]} {
                        set placed 1
                    }
                }
            }
        }
        set rb ""
        catch {set rb [note GetPosition]}
        puts "  note position: '$curPos' -> '$rb' (placed=$placed)"
    } elseif {$cornerPos ne ""} {
        # Old style: reuse the hidden built-in note's corner spot
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
