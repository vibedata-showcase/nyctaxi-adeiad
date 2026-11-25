---
kinds: [fix]
---

# Case: The revenue component walk double counts the airport fee

## Defect

**Statement (Finance, Priya Nair):** "For Q1 2024, the revenue walk adds up to more than billable revenue." The nine `component_amount` lines of `finance.mart_revenue_component_bridge` sum to $2,641,448.07 against Q1 2024 billable revenue of $2,629,185.82 — an overstatement of $12,262.25 (0.47%), by month January $3,997.00, February $3,550.75, March $4,714.50.

**Anchor:** `finance.mart_revenue_component_bridge` (boundary, schema `finance`, built by `transformation/models/marts/finance/mart_revenue_component_bridge.sql`).

**Time window:** the reporting window `2024-01-01` … `2024-04-01` (dbt vars `report_start` / `report_end`), on the Domain warehouse at commit `1184020`.

**Category:** `data-quality`.

## Root-cause analysis

### Blast radius

- **Billable revenue is not affected and does not change.** `core.fct_trip` summed over `is_billable` in the window, the semantic metric `billable_revenue`, and `finance.mart_daily_zone_revenue.total_revenue` all read $2,629,185.82 over 95,958 billable trips. Only the walk is wrong; the number Finance must give the CFO is $2,629,185.82 and the walk is what has to move.
- **Inside the repo, the bridge has no model or exposure downstream** (`dbt ls --select mart_revenue_component_bridge+` returns the model and its own `not_null` test only). Its consumers are Finance reading it directly, in this repo's terms an external consumer, so the published shape is a contract question (see `## Open decisions`).
- **`finance` gold surface:** `mart_revenue_component_bridge` only. `mart_daily_zone_revenue` and `mart_monthly_service_summary` apply the same billable rule but never touch `fare_residual` or `airport_fee` in their revenue arithmetic.
- **Adjacent, not repaired by this case (separate finding):** `core.fct_trip.fare_residual` carries the same absorbed fee, so `ops.mart_trip_quality_scorecard` counts fee-bearing trips as `unbalanced_total` that the fee actually explains. That mart counts every trip in the window, billable or not (ADR 0003), so its figures are not the bridge's: 31,869 trips flagged now against 26,457 if the fee were netted. That surface is out of this anchor's scope; see `## Open decisions`.

### Cause

1. `transformation/macros/finance.sql` `fare_residual` subtracts `total_amount - fare_amount - tip_amount - tolls_amount - (extra + mta_tax + improvement_surcharge + congestion_surcharge)`. It never subtracts `airport_fee`, so on a fee-bearing trip the $1.75 fee stays inside the residual. [`code-inspection`: `transformation/macros/finance.sql:24-33`]
2. `mart_revenue_component_bridge.sql` selects both `sum(coalesce(f.airport_fee, 0)) as c_airport_fee` and `sum(f.fare_residual) as c_residual`, and unpivots both into the walk as orders 8 and 9. [`code-inspection`: `transformation/models/marts/finance/mart_revenue_component_bridge.sql:19-20,37-45`]
3. So the fee is counted twice: once as its own line and once inside the residual. The walk therefore overstates by exactly the fee collected — 7,007 billable trips at $1.75 = $12,262.25. [`sql-probe`: see `## Checks run` rows 1 and 3]
4. No test asserts that the components of a grain sum to its `total_amount`. `_finance.yml` carries only `not_null` on `component_name`, so the build stays green with the walk broken. [`code-inspection`: `transformation/models/marts/finance/_finance.yml:63-95`; `transformation/tests/` has no bridge test]

**Confidence.** High. The arithmetic reproduces exactly at every grain, the overcount equals the fee line to the cent, and dropping the fee line closes the walk at all 44 grains.

### Checks run

| # | Check | Outcome |
| --- | --- | --- |
| 1 | Nine-line vs eight-line walk against the bridge's own `total_amount`, per `(trip_month, service_type_key, borough_name)` grain | 44 grains; 9 differ on nine lines, 0 on eight; overcount $12,262.25; delta after fix $0.00 |
| 2 | Billable revenue three ways | `fct_trip` over `is_billable` = $2,629,185.82 / 95,958 trips; `mart_daily_zone_revenue` = $2,629,185.82; bridge `total_amount` = $2,629,185.82 |
| 3 | Fee-bearing billable trips | 7,007 trips, every one at $1.75 = $12,262.25; on 5,765 of them the published `fare_residual` equals the fee exactly |
| 4 | Residual, published and net of the fee | published −$20,376.50; net of the fee −$32,638.75 |
| 5 | Option A (keep the fee line, residual excluding it) at grain | 44 grains, 0 differing, max delta 2e-9, total $2,629,185.82 |
| 6 | Ruled out — genuine source imbalance | on the 88,951 billable trips with no airport fee the nine-line walk less `total_amount` is $0.00 |
| 7 | Ruled out — a different population | bridge `total_amount` = $2,629,185.82 = 95,958 trips = `mart_daily_zone_revenue` |
| 8 | Adjacent surface, quality scorecard | 31,869 trips flagged `unbalanced_total` now vs 26,457 with the fee netted — 5,942 stop being flagged and 530 start, since netting the fee moves the residual off zero in both directions. That mart counts all trips, not only billable ones. Out of scope for this anchor |
| 9 | Run history | `list_runs` finds no dbt run record for the model on this platform, so the defect is proven from the built relation, not from a failed run |

### What could not be checked

- Whether any consumer outside this repo reads the walk, or which of the two published shapes it depends on. No exposure is declared in the dbt project and nothing in the repository names a consumer; the contract question is therefore put to Finance rather than decided from the repo.

### Corrections to the request

- The request cites **ADR 0225** as the rule that makes this a breaking contract change. This Domain's `docs/adr/` holds ADR 0001–0017 only; `ADR-0225` is the plugin's own contract-boundary rule (input and boundary layers owe a contract), named in `repo-map.json` and in the `data-contract` skill, not a decision recorded in this repository.
- Measured against the version rule that does apply (the `data-contract` skill's: removed, renamed, retyped, re-keyed, re-grained, a rule withdrawn or `required` turned is major; added is minor; prose is patch), **neither fix shape is mechanically a major change**. Both keep all nine properties, keep `component_name` and `component_amount` as typed and not-null, and change only descriptions — plus, under option B, one of the nine values the `component_name` description enumerates. The contract carries no `invalidValues` rule on `component_name`, so no declared rule is withdrawn. The case is a published-meaning change rather than a schema break, and whether a consumer that switches on `c_airport_fee` should be treated as broken is Finance's call, not a lint result.

### Decision

`code-change`. Class: failing or missing dbt test. Sandbox verification: re-run the affected model and tests.

Both candidate fixes pass the two checks:

- **Data loss:** neither drops a trip, a grain or an amount. Option A keeps all nine lines and recomputes the residual; option B removes one component row per grain but leaves its amount inside the residual, so no money is lost and the walk still closes.
- **Decisions:** neither contradicts an accepted ADR. Both keep ADR 0003's billable rule and reporting window, and both keep ADR 0015's null dimension keys. The choice between them is a published-meaning decision, not an ADR conflict.

**The fix, once the shape is chosen:**

1. `mart_revenue_component_bridge.sql` — either keep `c_airport_fee` at order 8 and publish the residual net of the fee, or drop the `c_airport_fee` line from the unpivot and the ordering join, keeping the residual as published.
2. A singular test that would have failed first, `assert_revenue_bridge_walk_sums_to_total_amount`: group the bridge by its grain, and return every grain whose `sum(component_amount)` differs from its `total_amount` by more than $0.01. It returns 9 grains today and must return none after the fix.
3. The contract and its generated keys (`contracts/finance/mart_revenue_component_bridge.odcs.yaml`, `generate`, then `check` / `diff`), and the matching description text in `_finance.yml`, `repo-map.json` `semantic_exclusions` and `transformation/models/docs.md`'s `fare_residual` doc block.
4. A design record for the model under `docs/design/models/finance/`, which does not exist today.

## Open decisions

1. **The published shape.** Keep `c_airport_fee` as its own line with a residual redefined to exclude it (nine lines, residual −$32,638.75), or drop the fee as its own line and leave it inside the residual (eight lines, residual −$20,376.50, and `component_name` loses a published value, which breaks a consumer that switches on it even though the contract's typed columns are unchanged — see `### Corrections to the request`). Both close the walk to $2,629,185.82. This is Finance's decision, asked at the design stop and **not answered**: the question timed out, so nothing was changed.

   Note for whoever settles it: the contradiction is inside the repository's own words, not between the words and the code. `transformation/models/docs.md` defines the residual as total minus "fare, tip, tolls, extra, MTA tax, improvement surcharge and congestion surcharge" — a list that omits `airport_fee`, which matches what the macro subtracts; but the same file says the residual is published "as its own row in the revenue bridge, rather than being absorbed into a real component", and the bridge does publish `c_airport_fee` as a real component of its own. `CONTEXT.md`'s **Fare residual** ("what is left of a trip's total after every modelled fare component") follows whichever of the two the reader takes "modelled" from. So the glossary does not settle the choice, and the published meaning has to be restated either way.

2. **`ops.mart_trip_quality_scorecard`.** `fct_trip.fare_residual` carries the same absorbed fee, so fee-bearing trips are counted as `unbalanced_total` although the fee explains them: 31,869 trips are flagged now against 26,457 with the fee netted. Repairing it means changing `fare_residual` at its source (`int_trip_fare_components`, `fct_trip`, the `fare_residual_total` semantic metric and the scorecard together), which is a different anchor and was offered as a separate intent; not answered.

## Approvals
