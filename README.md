# Conrod Safety Factor Extractor — HyperView Tcl

Automated post-processing for **AVL EXCITE Power Unit** results inside **Altair HyperView**.
Finds the **minimum Safety Factor** across user-defined nodesets for Load Case 1 in one pass.

**Author:** Nguyen Tan Loc — Simulation Engineer
**Context:** EHD simulation support · conrod stress analysis

---

## What it replaces

Manually switching to each nodeset, running a query, reading the minimum SF value, recording node ID — repeated for every component spec.

## What it does

- Takes a list of Selection Set IDs as input
- Queries `Endure_SF_A` (Safety Factor) on each nodeset
- Finds minimum SF value and corresponding Node ID per set
- Exports summary CSV

```
Input:  Selection Set IDs (space-separated, entered at runtime)
Output: SafetyFactor_Summary_LoadCase1.csv
        SF_Results_Get_ID.csv
```

---

## How to run

1. Open HyperView with your simulation result loaded.
2. Open the Tcl console: `View → Command Window`.
3. Source the script:
   ```tcl
   source /path/to/Conrod_SF_Find_NodeSet.tcl
   ```
4. Enter Selection Set IDs when prompted (space-separated):
   ```
   => Enter selection set IDs: 1 2 3 4 5 6 7 8
   ```
5. Results export automatically to the script directory.

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
