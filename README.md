# Conrod Safety Factor Extractor — HyperView Tcl

Automated post-processing for **AVL EXCITE Power Unit** results inside **Altair HyperView**.
Finds the **minimum Safety Factor** across user-defined nodesets for Load Case 1 in one pass.

**Author:** Nguyen Tan Loc — Simulation Engineer
**Context:** EHD simulation support · conrod stress analysis

---

## What it replaces

Manually switching to each nodeset, running a query, reading the minimum SF value, recording node ID — repeated for every component spec.

## What it does

- **Loops over every window on the active page** (multi-window layouts supported)
- Queries `Endure_SF_A` (Safety Factor) on each nodeset — single load case,
  no frame sweep needed
- Finds minimum SF value and corresponding Node ID per set, per window
- Exports one clean summary CSV
- **Annotate step**: per window, marks the min-SF node (pink ID marker,
  size 15) + a screen-anchored summary note (node ID + min SF, size 10)

```
Input:  Selection Set IDs (space-separated)
Output: SafetyFactor_Summary.csv  (one row per window × nodeset —
         WindowID, SetName, MinNodeID, MinSafetyFactor, LoadCaseLabel)
```

---

## How to run

### Option A — button panel (recommended)

```tcl
source /path/to/SafetyFactor_Panel.tcl
```
A floating **Safety Factor Tools** panel opens with Export / Annotate
buttons and options (marker/note size, color, load case, data type label).
Auto-open at startup:
```
hw.exe <model_or_session> -tcl /path/to/SafetyFactor_Panel.tcl
```

### Option B — console scripts

1. Open HyperView with your simulation result loaded.
2. Open the Tcl console: `View → Command Window`.
3. Source the script:
   ```tcl
   source /path/to/Conrod_SF_Find_NodeSet.tcl   ;# min-SF query → CSV
   source /path/to/TCL_SFAnnotate.tcl           ;# markers + notes from CSV
   ```
4. Enter Selection Set IDs when prompted (space-separated):
   ```
   => Enter selection set IDs: 1 2 3 4 5 6 7 8
   ```
5. Results export automatically to the script directory.

### File layout

| File | Role |
|------|------|
| `safetyfactor_lib.tcl` | All logic (procs, no UI) — sourced by everything below |
| `SafetyFactor_Panel.tcl` | Floating button panel (add-in style) |
| `Conrod_SF_Find_NodeSet.tcl` | Console wrapper: prompt → `::SafetyFactor::RunExport` |
| `TCL_SFAnnotate.tcl` | Console wrapper: prompt → `::SafetyFactor::RunAnnotate` |

---

## Requirements

- Altair HyperView (tested with HyperWorks 2021+)
- AVL EXCITE Power Unit result files loaded
- Selection Sets pre-defined in the model (nodesets per component spec)
- Tcl/Tk (bundled with HyperWorks — no separate install needed)

---

## Companion tool

For full-sweep Von Mises stress tracking across all crank angles, see
**[Tcl_VonMises-stress-on-mutiple-step-load-](https://github.com/NeuJin/Tcl_VonMises-stress-on-mutiple-step-load-)** — the two scripts together cover the full post-processing pipeline from raw solver output to report-ready data.

---

## Author

**Nguyen Tan Loc** — Simulation Engineer
Technostar Co., Ltd (Outsourced to Suzuki Motor Corporation)
[LinkedIn](https://linkedin.com/in/nguyentanloc-cae)

*Previously: Bosch Global Software Technologies Vietnam · Datbike EV Startup*
