---
kinds: [fix]
---

# Case: The revenue walk counts the airport fee twice

**Anchor:** `finance.mart_revenue_component_bridge`, and the `fare_residual` it carries through `int_trip_fare_components`.
**Symptom:** the Q1 2024 walk sums to 2,641,448.07 against billable revenue of 2,629,185.82 — 12,262.25 high (0.4664%), every month and every test green.
**Window:** the Q1 2024 reporting window (2024-01-01 to 2024-04-01), Domain warehouse built at `1184020`, reported by the Finance Lead on 2026-11-24.
**Category:** `data-quality`.

## Root-cause analysis

**Blast radius.** `finance.mart_revenue_component_bridge` (its `c_residual` and `c_airport_fee` rows, and any total taken over the walk), `int_trip_fare_components.fare_residual` and `has_unexplained_residual`, `core.fct_trip.fare_residual`, `ops.mart_trip_quality_scorecard.unbalanced_total_count`, and the semantic layer's `fare_residual_total` metric. The consumers of `billable_revenue` are untouched: it reads `fct_trip.total_amount`, and `mart_daily_zone_revenue.total_revenue` already agrees with it. Within the window the walk is high by 12,262.25 over 95,958 billable trips in 44 bridge groups; 9 groups miss balance and one green group carries 8 component rows with no value effect. Correcting the residual moves 5,942 in-window trips out of `unbalanced_total_count` and 530 into it.

**Root cause.**

1. `fare_residual()` is `total_amount − fare − tip − tolls − total_surcharges()`, and `surcharge_columns()` names only `extra`, `mta_tax`, `improvement_surcharge` and `congestion_surcharge`. `airport_fee` is not among them, so whatever the fee's relation to the total, it stays inside the residual. [`code-inspection`: `transformation/macros/finance.sql`]
2. `mart_revenue_component_bridge.sql` unpivots `c_airport_fee` as the eighth of nine components *on top of* `c_residual`, so on any trip carrying a fee the same money appears in two rows of the walk. [`code-inspection`: `transformation/models/marts/finance/mart_revenue_component_bridge.sql`]
3. The money therefore appears twice: over the window the nine components exceed the total by exactly `sum(airport_fee)`, on every group. [`sql-probe`: Discovery, "Dropping `c_airport_fee` balances every group" and "9 groups that miss balance do so by their own `c_airport_fee`"]
4. At trip grain the identity `all nine components = total + airport_fee` holds on all 95,958 billable trips with no exception, which is the same statement per row: the residual is carrying the fee. [`sql-probe`: Discovery, "Per trip the nine components equal the total plus the fee"]
5. Nothing caught it because no test asserts that the bridge's components sum to the group's total. The suite's tests over this area check the fee's presence (`assert_airport_fee_only_on_yellow`) and rejoin integrity, neither of which looks at the walk. [`code-inspection`: `transformation/tests/`]

**Confidence.** High. The probe in step 3 is arithmetic over the built relation and closes to the cent; step 4 is an independent row-grain identity; step 1–2 are the code that produces both. The three evidence planes agree: the repo's macro and unpivot, the live relation's group arithmetic, and the run history's green suite (no test covers the walk, so green is expected and proves nothing).

**Checks run.**

| Check | Outcome |
| --- | --- |
| Walk total against billable revenue at the window | 2,641,448.07 vs 2,629,185.82, +12,262.25 |
| Group walk against group total, all 44 groups | 9 groups off, each by its own `c_airport_fee` |
| Group walk with `c_airport_fee` excluded | 0 groups off |
| Per-trip component identity against `total_amount` | 95,958 trips, 0 breaks |
| Source shapes (fee inside / outside / neither) | 5,765 / 530 / 712 billable trips; fee total 12,262.25 |
| Simulated corrected residual at group grain | 44 groups, 0 off, walk = total = 2,629,185.82 |
| Green `ehail_fee` in the window | 0 trips, 0.00: not a factor here |

Not checked: whether any consumer outside this repo reads the walk's total before the fix (none is known); `sqlfluff` (not installed in this runtime).

**Data-loss check.** The fix changes an arithmetic expression and adds a test; it removes no row, filters nothing and deduplicates nothing. The bridge keeps its nine component rows at its existing grain.

## Decision

`code-change`. Class: failing or missing dbt test. Sandbox verification: re-run the affected models and tests, then assert the walk balances per group and totals 2,629,185.82.

The candidate repairs and the one chosen are settled in [`docs/adr/0018-the-revenue-walk-decomposes-the-total-it-reports.md`](../adr/0018-the-revenue-walk-decomposes-the-total-it-reports.md) and the design records it lists: the residual stops absorbing `airport_fee`, so the nine published components are a true decomposition of the total the same row group reports. The alternative — drop `c_airport_fee` as a component and leave the fee in the residual — was rejected because it would hide the airport fee from the walk the finance team reads it in.

## Approvals
