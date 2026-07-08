puts "---Min Safety Factor Annotation---"
puts "########  BY NGUYEN TAN LOC  ########"
puts ""

# Console wrapper — all logic lives in safetyfactor_lib.tcl.
# For the button-panel version, source SafetyFactor_Panel.tcl instead.
source [file join [file dirname [file normalize [info script]]] safetyfactor_lib.tcl]

puts -nonewline "=> Enter ONE selection set ID to annotate: "
update idletasks
gets stdin userInput

::SafetyFactor::RunAnnotate $userInput
