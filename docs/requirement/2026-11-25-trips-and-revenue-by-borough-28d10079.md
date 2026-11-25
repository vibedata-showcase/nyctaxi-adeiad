---
kinds: [transformation]
---

# Requirement: Trips and revenue by borough

## Ask

The Mobility Planning Lead asked: "The city asked how much of our traffic crosses borough lines. For each month of Q1 2024, I need the trips and the revenue from each borough to each borough, and the share of trips that leave the borough they started in." The consumer is Mobility Planning reporting to the city; the result is a new published table in the `agg` boundary layer.

## Requirements

- [ ] `R-01` One row per month of Q1 2024 × origin borough × destination borough, carrying the trip count and the revenue of that cell — accept when the built relation has one row per observed (month, origin borough, destination borough) with no duplicate grain and no null in any of the three key columns; the Q1 build holds 122 rows (40 in January, 40 in February, 42 in March) — source: request
- [ ] `R-02` The population is billable trips picked up inside the reporting window, and every one of them lands in exactly one cell — accept when `sum(trip_count)` equals `fct_trip`'s billable count for the window (95,958) and `sum(total_revenue)` equals its billable total amount to the cent (2,629,185.82, both sides rounded to 2 decimals) — source: `docs/adr/0003-billable-trip-definition-and-where-it-applies.md`
- [ ] `R-03` Each origin borough in each month carries its cross-borough trip count and its share of trips that leave the borough, over all of that origin's trips in the month — accept when an independent recomputation from `fct_trip` matches, and the share equals cross-borough trips ÷ the origin's trips in the month at cent precision; Q1: 12,214 cross-borough trips of 95,958 — source: request
- [ ] `R-04` A trip crosses when its destination borough name differs from its origin borough name, and the zones the lookup cannot place (`Unknown`, `N/A`) and the out-of-city zone (`EWR`) appear as their own groups, neither filtered nor remapped — accept when the relation carries all eight borough names as origins and as destinations, no row is filtered on `is_unresolved_zone`, and the unresolved groups' trips are included in the totals of R-02 (Q1: 360 of 95,958 trips start in an unplaceable borough; 1,137 end in one or in EWR) — source: `docs/adr/0018-a-trip-crosses-a-borough-line-when-its-destination-borough-differs.md`
- [ ] `R-05` Every borough pair-month with at least one billable trip is published; no minimum-trip floor applies at borough grain — accept when the minimum published `trip_count` is 1 and the 66 pair-months holding fewer than 25 billable trips are present (253 trips in total) — source: `docs/adr/0019-the-25-trip-floor-governs-zone-pairs-not-borough-pairs.md`
- [ ] `R-06` The table is a boundary relation: its columns, types, grain and quality rules are published as a data contract, and the model's properties file enforces them — accept when `odcs.py check` passes for the relation and a `contract: {enforced: true}` entry names every published column — source: `repo-map.json` (`modules.contracts`: a boundary relation owes a contract; `artifact_paths.data_contract`)

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain (month × origin borough × destination borough) | One row per month of the reporting window, origin borough and destination borough; the month is `date_trunc('month', pickup_date)`, the day the trip started (`CONTEXT.md`, Date) | request; `CONTEXT.md` |
| Month boundary | Calendar month, as the request says "each month of Q1 2024"; no week or fiscal convention applies | request; `docs/adr/0014-weeks-start-on-monday.md` (weeks only) |
| Edge periods | `not applicable`: the loaded and reporting window is exactly 2024-01-01 to 2024-03-31, 91 days with at least one trip each, so no Q1 month is cut short | repository: `dbt_project.yml` `report_start`/`report_end`; `fct_trip` day coverage |
| Population — which trips | Billable only. ADR 0003: "Gold marts that report revenue or flows apply it, inside the reporting window" | `docs/adr/0003-billable-trip-definition-and-where-it-applies.md` |
| Population — trip floor | No floor. ADR 0019: "A borough flow matrix therefore publishes every pair-month that has at least one billable trip" | `docs/adr/0019-the-25-trip-floor-governs-zone-pairs-not-borough-pairs.md` |
| `trip_count` definition | `count(*)` of the cell's billable trips in the month | `docs/adr/0003-billable-trip-definition-and-where-it-applies.md`; request ("the trips") |
| `total_revenue` definition | `sum(total_amount)` over the cell's billable trips, the same measure `agg_od_flow_matrix` and the finance marts publish | `docs/adr/0003-billable-trip-definition-and-where-it-applies.md`; `transformation/models/marts/finance/mart_daily_zone_revenue.sql` |
| `cross_borough_trip_count` definition | Trips whose destination borough name differs from their origin borough name, including unplaceable and out-of-city destinations. ADR 0018: "A trip is cross-borough when the two names differ" | `docs/adr/0018-a-trip-crosses-a-borough-line-when-its-destination-borough-differs.md` |
| `cross_borough_share` definition and denominator | Cross-borough trips ÷ all of that origin borough's trips in the month, so the denominator includes trips ending in an unplaceable or out-of-city borough. ADR 0018: "a borough flow matrix in which every trip lands in exactly one cell reproduces the crossing share as one minus the same-borough share" | `docs/adr/0018-a-trip-crosses-a-borough-line-when-its-destination-borough-differs.md` |
| Share scale | A double ratio in 0–1, not a percentage, matching the existing share columns (`tip_measurable_share`, `occupancy_rate`) | existing models |
| Coverage of `total_revenue` | Complete, no separate count needed: every billable trip in the window has a non-null, non-zero `total_amount` (0 nulls, 0 zeros), so `trip_count` is the count of rows carrying the measure | repository: `fct_trip` in the window|
| NULLs in an aggregate over a nullable measure | `not applicable` to revenue, which is present on every published row (row above); a NULL origin or destination zone key would keep its trip — no such key exists in the window (0 of 95,958) but the model must not drop one that appears later | `docs/adr/0015-unmatched-dimension-keys-stay-null.md`; `docs/adr/0012-unresolved-zones-are-retained-and-flagged.md` |
| A borough pair with no trips in a month | Omitted, not emitted as zero: only pair-months with at least one billable trip have a row | user answer (observed cells only) |
| Reuse | No published model serves this grain: `agg_od_flow_matrix` is zone-pair grain under the 25-trip floor (ADR 0017/0019) and `mart_monthly_service_summary` is month × service type × payment method. The new relation is built from `fct_trip` with `dim_zone` joined twice, as `agg_od_flow_matrix` does | repository: `transformation/models/marts/agg/agg_od_flow_matrix.sql`, `transformation/models/marts/finance/mart_monthly_service_summary.sql` |
| Unmatched and null keys | Keep every row: an origin or destination zone key that matches no `dim_zone` version keeps its trip in the population rather than dropping it | `docs/adr/0015-unmatched-dimension-keys-stay-null.md` |
| Extended scope | A schedule is not part of this intent; no `orchestration` kind | transformation playbook |

## Out of scope

- Any change to `fct_trip`, `dim_zone` or the existing `agg` and `finance` marts, including `agg_od_flow_matrix`: its population and its 25-trip floor stay as they are (ADR 0017).
- Loading, resampling or altering the reporting window: Q1 2024 is what the data covers.
- Borough-pair measures beyond trips and revenue (distance, duration, fares, tips) — the request names trips and revenue plus the crossing share.
- Any schedule or automation around the new model.

## Open questions

None. Two decisions were taken by the Mobility Planning Lead: no minimum-trip floor at borough grain, and any differing destination borough counts as crossing. A third — empty cells omitted rather than emitted as zero — was answered with observed cells only.

## Approvals

