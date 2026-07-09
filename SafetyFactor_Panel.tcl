# SafetyFactor_Panel.tcl — button panel ("add-in") for the Safety Factor tools.
#
# Load inside HyperView:   source <path>/SafetyFactor_Panel.tcl
# Or auto-open at startup: hw.exe <model> -tcl <path>/SafetyFactor_Panel.tcl
#
# The panel is a floating always-on-top window. All logic lives in
# safetyfactor_lib.tcl; this file is UI only.

source [file join [file dirname [file normalize [info script]]] safetyfactor_lib.tcl]

package require Tk

namespace eval ::SFPanel {
    variable W .sfPanel
}

proc ::SFPanel::SetStatus {msg {color black}} {
    variable W
    $W.status configure -text $msg -foreground $color
    update idletasks
}

proc ::SFPanel::DoExport {} {
    variable W
    set ids [split [string trim [$W.exp.ids get]]]
    if {[llength $ids] == 0} {
        SetStatus "Enter selection set IDs first." red
        return
    }
    SetStatus "Export running..." blue
    if {[catch {::SafetyFactor::RunExport $ids} result]} {
        SetStatus "Export FAILED: $result" red
    } else {
        LoadResults
        SetStatus "Export done -> $result" darkgreen
    }
}

# Fill the results table from SafetyFactor_Summary.csv
# (columns: WindowID,SetName,MinNodeID,MinSafetyFactor,LoadCaseLabel)
proc ::SFPanel::LoadResults {} {
    variable W
    set csvFile [file join $::SafetyFactor::LIB_DIR "SafetyFactor_Summary.csv"]

    $W.res.tv delete [$W.res.tv children {}]

    if {![file exists $csvFile]} {
        SetStatus "No CSV yet — run Export first." red
        return
    }
    set f [open $csvFile r]
    set lineNo 0
    set n 0
    while {[gets $f line] >= 0} {
        incr lineNo
        if {$lineNo == 1} { continue }
        if {[string trim $line] eq ""} { continue }
        set fields [split $line ","]
        if {[llength $fields] < 4} { continue }
        lassign $fields rWin rSetName rNodeID rSF
        set sf3 ""
        catch {set sf3 [format "%.3f" $rSF]}
        $W.res.tv insert {} end -values [list $rWin $rSetName $rNodeID $sf3]
        incr n
    }
    close $f
    SetStatus "Results table: $n row(s) loaded." darkgreen
}

# Row selected -> copy its Node ID into the edit field
proc ::SFPanel::OnSelect {} {
    variable W
    set sel [$W.res.tv selection]
    if {[llength $sel] == 0} { return }
    set vals [$W.res.tv item [lindex $sel 0] -values]
    lassign $vals rWin rSet rNode rSF
    $W.res.node delete 0 end ; $W.res.node insert 0 $rNode
}

# Re-query the SF value for the selected row using the edited Node ID,
# then update the table row and the CSV.
proc ::SFPanel::DoRequery {} {
    variable W
    set sel [$W.res.tv selection]
    if {[llength $sel] == 0} {
        SetStatus "Select a row in the table first." red
        return
    }
    set item [lindex $sel 0]
    lassign [$W.res.tv item $item -values] rWin rSet oldNode oldSF
    set newNode [string trim [$W.res.node get]]
    if {$newNode eq ""} {
        SetStatus "Enter a Node ID first." red
        return
    }
    SetStatus "Re-querying win $rWin node $newNode ..." blue
    if {[catch {::SafetyFactor::QueryNodeValue $rWin $newNode} result]} {
        SetStatus "Re-query FAILED: $result" red
        return
    }
    set sf3 [format "%.3f" $result]
    $W.res.tv item $item -values [list $rWin $rSet $newNode $sf3]
    UpdateCsvRow $rWin $rSet $newNode $result
    SetStatus "Win $rWin / $rSet -> node $newNode = SF $sf3 (CSV updated)" darkgreen
}

# Rewrite the matching (WindowID,SetName) row in SafetyFactor_Summary.csv
proc ::SFPanel::UpdateCsvRow {rWin rSet nodeID val} {
    set csvFile [file join $::SafetyFactor::LIB_DIR "SafetyFactor_Summary.csv"]
    if {![file exists $csvFile]} { return }
    set f [open $csvFile r]
    set lines {}
    while {[gets $f line] >= 0} { lappend lines $line }
    close $f

    set out {}
    foreach line $lines {
        set fields [split $line ","]
        if {[llength $fields] >= 4 && [lindex $fields 0] == $rWin && [lindex $fields 1] eq $rSet} {
            set lcLabel ""
            catch {set lcLabel [join [lrange $fields 4 end] ","]}
            lappend out "$rWin,$rSet,$nodeID,[format "%.5f" $val],$lcLabel"
        } else {
            lappend out $line
        }
    }
    set f [open $csvFile w]
    foreach line $out { puts $f $line }
    close $f
}

proc ::SFPanel::DoAnnotate {} {
    variable W
    set setID [string trim [$W.ann.id get]]
    if {$setID eq ""} {
        SetStatus "Enter one selection set ID first." red
        return
    }
    SetStatus "Annotating set $setID..." blue
    if {[catch {::SafetyFactor::RunAnnotate $setID} result]} {
        SetStatus "Annotate FAILED: $result" red
    } else {
        SetStatus "Annotate done (set $setID)." darkgreen
    }
}

proc ::SFPanel::Build {} {
    variable W

    catch {destroy $W}
    toplevel $W
    wm title $W "Safety Factor Tools — Nguyen Tan Loc"
    wm attributes $W -topmost 1
    wm resizable $W 0 1     ;# vertically resizable for the results table

    # ── Export section ──
    labelframe $W.exp -text " 1. Min Safety Factor Export (all windows) " -padx 8 -pady 6
    label  $W.exp.lbl -text "Selection set IDs (space-separated):"
    entry  $W.exp.ids -width 32
    button $W.exp.run -text "Run Export" -width 14 -command ::SFPanel::DoExport
    grid $W.exp.lbl -row 0 -column 0 -sticky w
    grid $W.exp.ids -row 1 -column 0 -sticky we -pady 2
    grid $W.exp.run -row 1 -column 1 -padx {6 0}
    pack $W.exp -fill x -padx 10 -pady {10 4}

    # ── Annotate section ──
    labelframe $W.ann -text " 2. Annotate Min SF (from CSV) " -padx 8 -pady 6
    label  $W.ann.lbl -text "One selection set ID:"
    entry  $W.ann.id -width 12
    button $W.ann.run -text "Annotate" -width 14 -command ::SFPanel::DoAnnotate
    grid $W.ann.lbl -row 0 -column 0 -sticky w
    grid $W.ann.id  -row 1 -column 0 -sticky w -pady 2
    grid $W.ann.run -row 1 -column 1 -padx {6 0}
    pack $W.ann -fill x -padx 10 -pady 4

    # ── Options section ──
    labelframe $W.opt -text " Options " -padx 8 -pady 6
    label $W.opt.l1 -text "Marker size:"
    entry $W.opt.mea -width 5 -textvariable ::SafetyFactor::MEA_FSIZE
    label $W.opt.l2 -text "Note size:"
    entry $W.opt.note -width 5 -textvariable ::SafetyFactor::NOTE_FSIZE
    label $W.opt.l3 -text "Color (R G B):"
    entry $W.opt.color -width 12 -textvariable ::SafetyFactor::PINK
    label $W.opt.l4 -text "Load case:"
    entry $W.opt.lc -width 5 -textvariable ::SafetyFactor::SUBCASE
    label $W.opt.l5 -text "Data type:"
    entry $W.opt.dt -width 18 -textvariable ::SafetyFactor::DATATYPE
    grid $W.opt.l1    -row 0 -column 0 -sticky w
    grid $W.opt.mea   -row 0 -column 1 -sticky w -padx {4 12}
    grid $W.opt.l2    -row 0 -column 2 -sticky w
    grid $W.opt.note  -row 0 -column 3 -sticky w -padx {4 0}
    grid $W.opt.l3    -row 1 -column 0 -sticky w -pady {4 0}
    grid $W.opt.color -row 1 -column 1 -columnspan 3 -sticky w -padx {4 0} -pady {4 0}
    grid $W.opt.l4    -row 2 -column 0 -sticky w -pady {4 0}
    grid $W.opt.lc    -row 2 -column 1 -sticky w -padx {4 0} -pady {4 0}
    grid $W.opt.l5    -row 3 -column 0 -sticky w -pady {4 0}
    grid $W.opt.dt    -row 3 -column 1 -columnspan 3 -sticky w -padx {4 0} -pady {4 0}
    checkbutton $W.opt.shownote -text "Show note header" -variable ::SafetyFactor::SHOW_NOTE
    grid $W.opt.shownote -row 4 -column 0 -columnspan 3 -sticky w -pady {4 0}
    pack $W.opt -fill x -padx 10 -pady 4

    # ── Results table (all windows) ──
    labelframe $W.res -text " 3. Results — all windows " -padx 8 -pady 6
    ttk::treeview $W.res.tv -columns {win set node sf} -show headings -height 9 \
        -yscrollcommand [list $W.res.sb set]
    $W.res.tv heading win  -text "Win"
    $W.res.tv heading set  -text "Set"
    $W.res.tv heading node -text "Node ID"
    $W.res.tv heading sf   -text "Min SF"
    $W.res.tv column win  -width 40  -anchor center
    $W.res.tv column set  -width 90  -anchor w
    $W.res.tv column node -width 100 -anchor center
    $W.res.tv column sf   -width 90  -anchor e
    scrollbar $W.res.sb -orient vertical -command [list $W.res.tv yview]

    frame  $W.res.edit
    label  $W.res.edit.l1 -text "Node ID:"
    entry  $W.res.node -width 12
    button $W.res.requery -text "Re-query Value" -command ::SFPanel::DoRequery
    button $W.res.refresh -text "Refresh from CSV" -command ::SFPanel::LoadResults

    grid $W.res.tv      -row 0 -column 0 -sticky nswe
    grid $W.res.sb      -row 0 -column 1 -sticky ns
    grid $W.res.edit    -row 1 -column 0 -sticky w -pady {4 0}
    pack $W.res.edit.l1 -in $W.res.edit -side left
    pack $W.res.node    -in $W.res.edit -side left -padx {4 10}
    pack $W.res.requery -in $W.res.edit -side left
    grid $W.res.refresh -row 2 -column 0 -sticky w -pady {4 0}
    grid columnconfigure $W.res 0 -weight 1
    pack $W.res -fill both -expand 1 -padx 10 -pady 4

    bind $W.res.tv <<TreeviewSelect>> ::SFPanel::OnSelect

    # ── Status bar ──
    label $W.status -text "Ready." -anchor w -relief sunken -padx 6
    pack $W.status -fill x -side bottom -padx 10 -pady {4 10}

    # Pre-fill the table if a CSV from a previous run exists
    catch {LoadResults}
}

::SFPanel::Build
puts "Safety Factor panel loaded — window '[wm title $::SFPanel::W]' is open."
