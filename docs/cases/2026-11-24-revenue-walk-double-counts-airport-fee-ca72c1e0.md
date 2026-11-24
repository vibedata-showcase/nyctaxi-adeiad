---
kinds: [fix]
---

# Case: the revenue walk counts the airport fee twice

**Anchor:** `finance.mart_revenue_component_bridge`, the fare-to-total walk.

## Defect

For Q1 2024 the walk's nine component rows sum to 2,641,448.07 while the walk's own `total_amount`, read once per group, is 2,629,185.82 — an overstatement of 12,262.25 (0.47%). The total line is right; only summing the component rows overcounts. Window: pickups from 2024-01-01 to 2024-04-01, the loaded Q1 2024 dataset built from `1184020d14`.

Evidence category: `data-quality`.

## Root-cause analysis

**Blast radius.**

- `finance.mart_revenue_component_bridge` — `c_residual` and `component_share` change on every group; the component rows begin to sum to `total_amount`. Same columns, same nine components, same grain and same rows: values only.
- `core.fct_trip.fare_residual` — a published column under `contract: enforced`. Its value changes on the 5,412 in-window trips whose residual was the airport fee; name, type and row count are unchanged.
- The semantic metric `fare_residual_total` (`SUM(trips.fare_residual)` on `fct_trip`) falls by the fee total.
- `ops.mart_trip_quality_scorecard.unbalanced_total_count` falls on those 5,412 trips (31,869 → 26,457 in-window), inside the vendor and month groups they sit in.
- Unaffected: `mart_daily_zone_revenue`, `mart_monthly_service_summary`, `agg_trip_zone_daypart_dow` and `int_shift_economics` read `total_surcharges`, which this fix does not touch; the remaining aggregates do not read the residual. The bridge sits in `repo-map.json` `semantic_exclusions`, so no semantic source binds it, and no consumer outside this repository is declared.

**Root cause.**

1. `fare_residual` subtracts only fare, tip, tolls and the four surcharges in `surcharge_columns()`; `airport_fee` is not among them, so the fee stays inside the residual. [`code-inspection`: `transformation/macros/finance.sql`]
2. The walk sums `coalesce(f.airport_fee, 0)` as its own component `c_airport_fee` (component_order 8) *and* sums `f.fare_residual` as `c_residual`, so the fee enters twice. [`code-inspection`: `transformation/models/marts/finance/mart_revenue_component_bridge.sql`]
3. `airport_fee` is a modelled fare component everywhere else: `int_trip_fare_components` carries it as a column beside `fare_residual`, and `fct_trip` publishes both. [`code-inspection`: `transformation/models/intermediate/int_trip_fare_components.sql`, `transformation/models/marts/core/fct_trip.sql`]
4. The overstatement is the fee, exactly, in every month: component sum minus walk total gives 3,997.00 in January, 3,550.75 in February and 4,714.50 in March, which are those months' `c_airport_fee`. [`sql-probe`: the per-month reproduction in the Verification's `## Discovery`]
5. The fee really is inside `total_amount`, so the residual is the side to correct: 5,942 of the 7,184 in-window airport-fee trips (5,765 of the 7,007 billable ones) have a total equal to the other components plus the fee to the cent. [`sql-probe`: the per-trip probe in `## Discovery`]
6. The wrong numbers come from the code as it stands, not from a stale build: the loaded data's `audit_runs.git_sha` is this branch's base commit. [`runtime-audit`: `bronze.audit_runs` → `1184020d14474dceb6e933849792bff9033070f3`]
7. Nothing failed because no test asserts that the walk's components sum to its total. [`code-inspection`: `transformation/tests/` holds no test over `component_amount`]

**Confidence.** High. The reproduction and the per-trip probe agree with the macro's own text, and the glossary already states the intended rule: `CONTEXT.md` defines a fare component as "the fare itself, tip, tolls, taxes and surcharges" and the residual as what is left "after every modelled fare component". The `fare_residual` doc block in `transformation/models/docs.md` enumerates the components and omits the fee, so it repeats the defect and is corrected with it. Not checked: whether any consumer outside this repo read the residual before the fix (none is declared).

**Checks run.**

| Check | Outcome |
| --- | --- |
| Per-month reproduction on the deployed data | component sum − total = `c_airport_fee` in all three months: confirms |
| Per-trip probe: is the fee inside `total_amount`? | 5,942 of 7,184 in-window fee trips (5,765 of 7,007 billable) balance to the cent with the fee: confirms |
| Canonical `billable_revenue` | 2,629,185.82, unchanged by the fix: the walk's total is the right number |
| Row coverage of the walk against the fact | 95,958 walk trips = 95,958 billable trips; the walk drops no trip through its zone join |
| `audit_runs.git_sha` of the loaded data | the branch's base commit: the defect is in the current code |

## Decision

`code-change`. Class: failing or missing dbt test — the balance assertion is added, fails before the fix and passes after it. Sandbox verification: rebuild `fct_trip` and its downstream with `--full-refresh --select fct_trip+` in the sandbox, re-run the affected models and tests, and re-read the walk's per-month reconciliation.

- Subtract `coalesce(airport_fee, 0)` inside the `fare_residual` macro, so the residual is what `CONTEXT.md` says it is: the total minus every modelled component. The fee stays a component of its own (`c_airport_fee`, order 8): the walk's shape does not change.
- Leave `total_surcharges` and `surcharge_columns()` alone. Folding the fee in would move `fct_trip.total_surcharges`, `mart_daily_zone_revenue.surcharge_revenue`, `agg_trip_zone_daypart_dow.surcharge_revenue` and `int_shift_economics.surcharge_collected` — four published measures this case did not find wrong — and would relabel a fee the walk models separately.
- Correct the `fare_residual` doc block in `transformation/models/docs.md` to name the airport fee among the subtracted components.
- Add the missing singular test: the walk's component rows must sum to its `total_amount` per group, to the cent.

Data-loss check: the fix is a subtraction. It adds no deduplication, no filter and no row-level collapse, and it changes no key.

Decisions check: consistent with `CONTEXT.md` `Fare residual` and `Fare component`; no ADR states which components the residual subtracts; no contract column is removed, added or retyped. Not `needs-human`.

**Findings reported, not fixed.**

- The residual stays negative after the fix: −32,638.75 for Q1 (−20,376.50 today plus the 12,262.25 fee), on trips whose total is below the sum of the modelled components. That is a data-quality signal the walk exists to show; correcting it is a separate question about the source.
- `mart_monthly_service_summary` totals 2,625,634.75, 3,551.07 below billable revenue, because its inner join to the payment-method dimension drops 106 billable trips with a null payment method. Outside this defect.
- The fix only reaches history through a `--full-refresh` of `fct_trip`, which is incremental by `trip_key` over a closed window: an incremental run would process no row. The rebuild is done in the sandbox here, and production needs the same full refresh when the branch is deployed.

## Approvals
