---
kinds: [fix]
---

# Case: The revenue walk double-counts the airport fee

## Defect

**Anchor:** `finance.mart_revenue_component_bridge`, and the `fare_residual` macro in `transformation/macros/finance.sql` behind it.

**Statement** (Finance Lead, Priya Nair): for Q1 2024 the nine-line revenue walk sums to more than billable revenue. $2,641,448.07 against $2,629,185.82, a difference of +$12,262.25 — the Q1 airport-fee total.

**Window:** Q1 2024, the three-month load built from `1184020` (the sandbox the read ran against).

**Evidence category:** `data-quality` — a wrong published value, with the build and every test green.

**Measurements.** Billable revenue, `core.fct_trip` filtered on `is_billable` with `pickup_datetime` in `[2024-01-01, 2024-04-01)`, is $2,629,185.82 over 95,958 trips; `finance.mart_daily_zone_revenue` agrees to the cent ($2,629,185.82 over 95,958) and the semantic metric `billable_revenue` returns $2,629,185.819998. The walk's nine `component_amount` lines sum to $2,641,448.07, and the `c_residual` line alone is −$20,376.50. The airport fee total is $12,262.25 over 7,007 trips — January $3,997.00 over 2,284 trips, February $3,550.75 over 2,029, March $4,714.50 over 2,694 — and it is exactly the excess.

## Root-cause analysis

**Blast radius.** Every consumer of a trip total's decomposition.

| Surface | Rows / groups affected | Change |
| --- | --- | --- |
| `finance.mart_revenue_component_bridge`.`c_residual` | 9 of 44 Q1 groups; the walk total | −$12,262.25 on the walk; the `c_residual` line moves from −$20,376.50 to −$32,638.75 |
| `core.fct_trip`.`fare_residual` | 7,007 billable trips carry a fee; 97,184 trips in window | the column's value on every fee-carrying trip |
| `core.fct_trip`.`has_unexplained_residual` path (`int_trip_fare_components`) | 5,942 trips become balanced, 530 become unbalanced | verdict flips on 6,472 trips |
| `ops.mart_trip_quality_scorecard`.`unbalanced_total_count` | 3 months | 9,420→7,612 (Jan), 9,489→7,950 (Feb), 12,960→10,895 (Mar) |
| Semantic metric `fare_residual_total` (`SUM(trips.fare_residual)`) | any query over it | falls by the fee total |

No column is added, removed, renamed or retyped, so no contract version moves: the shape is unchanged and the values are corrected. `clean_trip_count` and `clean_rate` do not move — `is_clean_trip` does not read the residual. Nothing is deleted, so ADR 0004's "flag, never delete" holds without amendment; the residual is not one of its twelve named verdicts.

**Root cause.** `fare_residual` in `transformation/macros/finance.sql` subtracts every modelled component except the airport fee:

```
total_amount - fare_amount - tip_amount - tolls_amount - total_surcharges
```

`total_surcharges` expands to `extra + mta_tax + improvement_surcharge + congestion_surcharge` and the airport fee is not among them. `int_trip_fare_components` publishes that residual, `fct_trip.fare_residual` carries it, and `mart_revenue_component_bridge` unpivots it as `c_residual` beside `c_airport_fee`. On any trip whose `total_amount` already includes the fee, the fee is therefore counted twice: once as its own component and once inside the residual. [`code-inspection`: `transformation/macros/finance.sql:12-38`, `transformation/models/intermediate/int_trip_fare_components.sql:23`, `transformation/models/marts/finance/mart_revenue_component_bridge.sql:20,38-44`]

The reproduction confirms the shape of it, one per-trip class at a time on the billable Q1 population. [`sql-probe`: residual recomputed per trip from the seven explicit components]

| Class | Trips | Fee | Residual as built | Residual minus fee | Reading |
| --- | --- | --- | --- | --- | --- |
| No fee | 88,951 | $0.00 | −$28,685.25 | −$28,685.25 | untouched by the fix |
| Fee inside the total | 5,765 | $10,088.75 | +$10,088.75 | $0.00 | the double count: residual equals the fee exactly |
| Fee outside the total | 530 | $927.50 | $0.00 | −$927.50 | total genuinely omits the fee; −$1.75 each is honest |
| Genuine residual | 712 | $1,246.00 | −$1,780.00 | −$3,026.00 | total omits fee *and* congestion ($2.50 each); −$4.25 is honest |

The three classes are disjoint and exhaustive; 5,765 + 530 + 712 = 7,007, the fee-carrying trips. The walk at its own grain (month × service type × pickup borough) has 44 groups in Q1, of which 35 balance and 9 differ by exactly their airport-fee amount; neither side has a group the other lacks (44 baseline, 44 walk, 0 missing, 0 extra). The finding's per-class trip counts (5,765 / 530 / 712) reproduce exactly.

**The finding's target figure is wrong, and the correction is a real one.** It states the Q1 genuine residual would be −$20,376.50 once the double count is removed. −$20,376.50 is the residual *as built*; subtracting the fee lowers it further to −$32,638.75, and the two differ by exactly the $12,262.25 fee total (−20,376.50 − 12,262.25 = −32,638.75). Read as an identity this is forced: the walk balances only if `sum(components) = sum(total_amount)`, and since `sum(components)` falls by the fee when `c_residual` does, and `sum(total_amount)` is fixed at billable revenue, the residual must absorb the whole fee. A per-trip recomputation confirms it: the residual after subtracting the fee is −$32,638.75 on the billable population and −$32,648.75 across all 97,184 in-window trips. This is not a defect in the proposed fix; it is a correction to the figure the finding offered as the target.

**Why no test caught it.** No test asserts the walk closes against `total_amount`, either per group on the bridge or per trip on the fact. `fct_trip.fare_residual` carries no test at all. A wrong residual is invisible to a `not_null` on a column that is never null.

**Runtime plane.** `audit_runs` holds one run (dlt `tlc`, 2026-11-24, `git_sha` `1184020d…`, completed); there is no `target/run_results.json` and no Elementary schema, so dbt run and test history is unavailable and no green build can be cited as evidence of correctness. The defect needs none: it is a static arithmetic omission that the live-state probes confirm directly. [`runtime-audit`: `list_runs`; gap recorded, confidence unchanged because the probes are direct]

**Live state.** Bronze carries `Airport_fee DOUBLE` on `yellow_tripdata`; `stg_tlc__yellow_tripdata` and `stg_tlc__yellow_trip_extras` both surface it, green never carries one, and `airport_fee_status` is `present` on 86,848 billable yellow trips (`missing` 7,333, `not_applicable` 1,777 green). The fee is a real populated component, not a null-handling artefact. [`schema-diff`, `sql-probe`]

**Checks run.**

| Check | Outcome |
| --- | --- |
| The finding's reproduction query, as written | 44 groups, 35 balanced, 9 off by exactly the fee: reproduces |
| Same query after subtracting the fee from the residual in SQL | 0 rows; max per-group gap 0.0: would confirm the fix |
| Per-trip residual classes | 5,765 / 530 / 712 fee trips, summing to 7,007: reproduces the finding's classes |
| Walk nine-line sum vs `sum(total_amount)` at the grain | $2,641,448.07 vs $2,629,185.82: reproduces the +$12,262.25 |
| Billable revenue, three independent routes | `fct_trip`, `mart_daily_zone_revenue` and semantic `billable_revenue` all $2,629,185.82: agree |
| Per-trip residual recomputation after the fix | −$32,638.75, not the −$20,376.50 the finding names |

**Confidence.** High. The arithmetic omission is read directly in the macro, the per-trip classes are disjoint and exhaustive, and the Q1 walk closes exactly once the fee leaves the residual. Not checked: whether any consumer outside this repository reads `fare_residual` (none is listed in the repository).

## Decision

`code-change`. Class: failing or missing dbt test. Sandbox verification: re-run the affected models and tests, then reconcile the walk against billable revenue.

- **Data-loss check.** The fix changes an arithmetic expression; it adds no filter, join or deduplication and removes no row. Passes.
- **Decisions check.** No accepted ADR is contradicted. ADR 0004 governs flagging rather than deleting and names twelve verdicts, none of them the residual; ADR 0003 governs billable filtering and is untouched. The residual's meaning in `CONTEXT.md` ("what is left of a trip's total after every modelled fare component") is what the fix makes true rather than changes. Passes.

**Proposed change.**

1. `transformation/macros/finance.sql`: `fare_residual` subtracts `coalesce({{ alias }}.airport_fee, 0)`, so the fee stops landing in the residual as well as in its own component. `total_surcharges` and its `surcharge_columns()` list stay as they are: the airport fee is a separate fleet-specific column, not one of the four pass-throughs the surcharge total names, and adding it there would move `mart_daily_zone_revenue.surcharge_revenue`, `agg_trip_zone_daypart_dow.surcharge_revenue` and `int_shift_economics.surcharge_collected`, three published numbers this defect does not concern.
2. `transformation/models/docs.md`: the `fare_residual` doc block lists airport fee among the components it subtracts.
3. `finance.mart_revenue_component_bridge`'s published description and the `component_name` property keep naming the residual as the part of the total no other component explains; no contract column moves, so the version stays.
4. `transformation/tests/assert_revenue_bridge_balances.sql` (new singular test): fails first, returning every walk grain whose nine lines do not sum to `total_amount` within a cent. This is the durable half of the fix — the reason nothing caught the defect.
5. `test-map.json`: register the new test under `finance`.

## Approvals
