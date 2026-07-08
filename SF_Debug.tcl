# SF_Debug.tcl — layer-by-layer diagnostic for the empty-query problem.
# Run on the ACTIVE window (click a window first, like the original script):
#   source <path>/SF_Debug.tcl
# Then copy the FULL console output back for analysis.

set DT      "1. Endure_SF_A"
set SETID   ""    ;# auto-picked: first NON-EMPTY set (previous run used the
                   ;# empty set id 1, contaminating sections 7-9)
set SUBCASE 1
set SIM     0

puts "==================== SF DEBUG ===================="

foreach handle {sess proj object page win clt model rctrl sub con leg iso math query vw se sys iter setc} {
    catch {${handle} ReleaseHandle}
}
catch {hwi CloseStack}

hwi OpenStack
hwi GetSessionHandle sess
sess GetProjectHandle proj
proj GetPageHandle page [proj GetActivePage]
page GetWindowHandle win [page GetActiveWindow]
win GetClientHandle clt
set modelID [clt GetActiveModel]
clt GetModelHandle model $modelID
model GetResultCtrlHandle rctrl

puts "\n--- 1. MODEL / RESULT ---"
puts "active window index : [page GetActiveWindow]"
puts "model id            : $modelID"
catch {puts "result file         : [model GetResultFileName]"}

puts "\n--- 2. SUBCASES ---"
catch {puts "subcase list        : [rctrl GetSubcaseList model]"}
foreach sc [rctrl GetSubcaseList model] {
    catch {puts "  subcase $sc label : '[rctrl GetSubcaseLabel $sc]'"}
}
rctrl SetCurrentSubcase $SUBCASE
rctrl SetCurrentSimulation $SIM
puts "current subcase     : [rctrl GetCurrentSubcase]"
catch {puts "current simulation  : [rctrl GetCurrentSimulation]"}
catch {puts "simulation list     : [rctrl GetSimulationList $SUBCASE]"}

puts "\n--- 3. DATA TYPES ---"
set dtList ""
if {[catch {set dtList [rctrl GetDataTypeList $SUBCASE]} e1]} {
    catch {set dtList [rctrl GetDataTypeList]}
}
puts "data type list      :"
foreach dt $dtList { puts "   '$dt'" }

puts "\n--- 4. CONTOUR ---"
rctrl GetContourCtrlHandle con
con SetDataType $DT
puts "SetDataType '$DT' -> readback '[con GetDataType]'"
con SetDataComponent {Scalar value}
puts "SetDataComponent 'Scalar value' -> readback '[con GetDataComponent]'"
catch {puts "binding             : '[con GetBinding]'"}
con SetAverageMode none
con SetCornerDataEnabled false
con SetEnableState true
puts "enable state        : [con GetEnableState]"
# Full apply recipe (animator refresh + display options) — without this the
# contour may never materialize and binding stays 'null':
catch {
    page GetAnimatorHandle _anim
    _anim SetCurrentStep [_anim GetCurrentStep]
    _anim ReleaseHandle
}
catch {clt SetDisplayOptions "contour" true}
catch {clt SetDisplayOptions "legend"  true}
clt Draw
catch {puts "binding AFTER apply : '[con GetBinding]'"}
puts "(check the window NOW — is the contour colored?)"

puts "\n--- 5. QUERY SETUP ---"
model GetQueryCtrlHandle query
catch {puts "data sources        : [query GetDataSourceList]"}
catch {puts "result fields       : [query GetDataSourceFieldList result]"}
catch {puts "result props        : [query GetDataSourcePropertyList result]"}

# Set each property, then read it straight back
foreach {p v} [list "Simulation Step" $SIM "Model ID" $modelID "Result Type" $DT "Load Case" $SUBCASE complex real complex_format real mutiline true dataformat csv datatype real layer all] {
    set rb "?"
    catch {query SetDataSourceProperty result $p $v}
    catch {set rb [query GetDataSourceProperty result $p]}
    puts "  prop '$p' set '$v' -> readback '$rb'"
}

puts "\n--- 6. SELECTION SETS (real table) ---"
set pickID "" ; set pickLabel ""
catch {
    foreach sid [model GetSelectionSetList] {
        model GetSelectionSetHandle _s $sid
        set lbl [_s GetLabel] ; set sz ""
        catch {set sz [_s GetSize]}
        _s ReleaseHandle
        puts "  set id $sid -> '$lbl' (size $sz)"
        if {$pickID eq "" && $sz ne "" && $sz > 0 && $lbl ne "ALL_MASSIVE_ELEMENTS"} {
            set pickID $sid ; set pickLabel $lbl
        }
    }
}
if {$SETID ne ""} { set pickID $SETID }
if {$pickID eq ""} {
    puts "!! no non-empty set found — aborting query sections"
    return
}
puts "using set           : id $pickID ('$pickLabel')"
query SetSelectionSet $pickID
catch {puts "query sel set size  : [query GetSelectionSetSize]"}

proc _countRows {} {
    set n 0
    set first {}
    query GetIteratorHandle iter
    for {iter First} {[iter Valid]} {iter Next} {
        incr n
        if {$n <= 3} { lappend first [iter GetDataList] }
    }
    iter ReleaseHandle
    return [list $n $first]
}

puts "\n--- 7. QUERY: node.id ONLY (does the set itself resolve?) ---"
query SetQuery "node.id"
catch {puts "query string        : '[query GetQuery]'"}
lassign [_countRows] n first
puts "rows                : $n   first: $first"
catch {puts "query error         : '[query GetError]'"}

puts "\n--- 8. QUERY: node.id contour.value ---"
query SetQuery "node.id contour.value"
catch {puts "query string        : '[query GetQuery]'"}
lassign [_countRows] n first
puts "rows                : $n   first: $first"
catch {puts "query error         : '[query GetError]'"}

puts "\n--- 9. RESULT-TYPE VARIANTS (rows for each) ---"
foreach variant [list $DT "Endure_SF_A" "1.  Endure_SF_A" "1. Endure_SF_A (s)" "Endure_SF_A (s)"] {
    catch {query SetDataSourceProperty result "Result Type" $variant}
    query SetQuery "node.id contour.value"
    lassign [_countRows] n first
    puts "  '$variant' -> rows: $n"
}

puts "\n==================== END DEBUG ===================="
