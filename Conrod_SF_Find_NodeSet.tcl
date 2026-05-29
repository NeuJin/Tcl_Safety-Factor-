puts "---Max Stress Evaluation (Load Case 1)---"
puts "########  BY NGUYEN TAN LOC  ########"
puts ""
puts " "

#### CLEAN UP HANDLES ####
foreach handle {sess proj object page win clt model rctrl sub con leg iso math query vw se sys} {
    catch {${handle} ReleaseHandle}
}
catch {hwi CloseStack}

set outputDir [file dirname [file normalize [info script]]]

### OPEN SESSION AND GET HANDLES ###
hwi OpenStack
hwi GetSessionHandle sess
sess GetProjectHandle proj
proj GetPageHandle page [proj GetActivePage]
page GetWindowHandle win [page GetActiveWindow]
win GetClientHandle clt
clt GetModelHandle model [clt GetActiveModel]

model GetResultCtrlHandle rctrl

### USER INPUT ###
puts -nonewline "=> Enter selection set IDs (space-separated): "
update idletasks
gets stdin userInput
set selectionSets [split $userInput]

#### INITIALIZE HANDLES ####
rctrl GetContourCtrlHandle con
con GetLegendHandle leg
rctrl GetIsoValueCtrlHandle iso
rctrl GetResultMathCtrlHandle math
model GetQueryCtrlHandle query
iso SetAverageMode Simple
win GetViewControlHandle vw
con GetSelectionSetHandle se
rctrl GetSystemCtrlHandle sys

##### SAFETY FACTOR QUERY #####
        con SetDataType {1. Endure_SF_A}
        con SetDataComponent {Scalar value}
        con SetAverageMode none
        con SetCornerDataEnabled false
        con SetEnableState true
        leg SetNumericPrecision 5
        rctrl SetCurrentSubcase 1
        rctrl SetCurrentSimulation 0
        set subLabel [rctrl GetSubcaseLabel 1]

# Configure query data source properties for Safety Factor
        query SetDataSourceProperty result "Simulation Step" 0
        query SetDataSourceProperty result "Model ID" 1
        query SetDataSourceProperty result "Result Type" "1.  Endure_SF_A"
        query SetDataSourceProperty result "Load Case" 1
        query SetDataSourceProperty result complex real
        query SetDataSourceProperty result complex_format real
        query SetDataSourceProperty result mutiline true
        query SetDataSourceProperty result dataformat csv
        query SetDataSourceProperty result datatype real
        query SetDataSourceProperty result layer all

# Set selection set and query string
        query SetSelectionSet 1
        query SetQuery "node.id contour.value"
        set sfFile "$outputDir/SF_Results_Get_ID.csv"
        query WriteData $sfFile csv

puts "Querying min Safety Factor for Load Case 1..."

#### MIN SAFETY FACTOR TRACKING ####
array set minSF {}
array set minNodeID {}

# Initialize min SF with a very large number
foreach setID $selectionSets {
    set minSF($setID) 1e30
    set minNodeID($setID) ""
}

foreach setID $selectionSets {
    model GetSelectionSetHandle setc $setID
    set setName [setc GetLabel]
    setc ReleaseHandle

    query SetSelectionSet $setID
    query SetQuery "node.id contour.value"
    query GetQuery

    query GetIteratorHandle iter

    for {iter First} {[iter Valid]} {iter Next} {
        set data [iter GetDataList]
        set nodeID [lindex $data 0]
        set sfVal [lindex $data 1]
        if {$sfVal < $minSF($setID)} {
            set minSF($setID) $sfVal
            set minNodeID($setID) $nodeID
        }
    }

    iter ReleaseHandle

    puts "Set $setName: Min Safety Factor = $minSF($setID) at Node $minNodeID($setID)"
}

#### WRITE SUMMARY CSV ####
set summaryFileName [file join $outputDir "SafetyFactor_Summary_LoadCase1.csv"]
set f [open $summaryFileName w+]
puts $f "SetName,MinNodeID,MinSafetyFactor"
foreach setID $selectionSets {
    model GetSelectionSetHandle setc $setID
    set setName [setc GetLabel]
    setc ReleaseHandle
    puts $f "$setName,$minNodeID($setID),$minSF($setID)"
}
close $f

puts "-------------------------------------"
puts "Exported min Safety Factor summary to $summaryFileName"
puts "-------------------------------------"
puts "################  Process completed.  ################"
