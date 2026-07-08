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
        SetStatus "Export done -> $result" darkgreen
    }
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
    wm resizable $W 0 0

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
    pack $W.opt -fill x -padx 10 -pady 4

    # ── Status bar ──
    label $W.status -text "Ready." -anchor w -relief sunken -padx 6
    pack $W.status -fill x -side bottom -padx 10 -pady {4 10}
}

::SFPanel::Build
puts "Safety Factor panel loaded — window '[wm title $::SFPanel::W]' is open."
