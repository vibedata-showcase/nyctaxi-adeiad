---
kinds: [transformation]
---

# Requirement: Borough-to-borough trips and revenue, Q1 2024

## Ask

Leila Haddad, Mobility Planning Lead, asked for the city's question: how much of our traffic crosses borough lines. For each month of Q1 2024 she needs the trips and the revenue from each borough to each borough, and the share of trips that leave the borough they started in. The consumer is a borough-level answer to the city, not a zone-level corridor report; the existing zone-pair matrix does not serve it (see the reuse row below).

## Requirements

- [ ] `R-01` A published relation reports, for each calendar month of Q1 2024 and each (origin borough, destination borough) pair, a trip count and a revenue figure — accept when the built relation carries the columns `month`/`month_start_date`, `origin_borough`, `destination_borough`, a trip count and a revenue measure, and the selection's `dbt build` passes — source: request
- [ ] `R-02` Revenue per pair equals the recognised revenue of that pair's billable trips in the month — accept when an independent recomputation from `core.fct_trip` joined twice to `core.dim_zone` and once to `core.dim_payment_method` matches the published revenue to the cent on every row, and `revenue_trip_count` matches its trip count — source: request, ADR 0003, ADR 0013, answer
- [ ] `R-03` Each origin borough and month carries the share of its published trips that leave the origin borough — accept when, for every origin-month in the relation, the published `cross_borough_trip_count` divided by `origin_month_trip_count` equals the published share to within 1e-9, and both counts recompute independently from `core.fct_trip` — source: request, answer (ADR 0019)
- [ ] `R-04` The relation covers exactly the three Q1 2024 months and no other period — accept when a query returns three distinct months, 2024-01-01, 2024-02-01 and 2024-03-01, and no row falls outside 2024-01-01 to 2024-03-31 — source: request
- [ ] `R-05` The relation publishes exactly the borough pairs that clear the floor: both ends a New York City borough and at least 25 billable trips in that month — accept when an independent query over `core.fct_trip` joined twice to `core.dim_zone` returns 39 rows, 94,624 trips and 2,494,501.46 recognised revenue for Q1 2024, the relation returns the same row count and the same sums, and no published row carries fewer than 25 trips — source: request, answer (ADR 0018)
- [ ] `R-06` A trip whose destination borough is unresolved (Unknown, N/A) or outside the city (EWR) is excluded from the published surface and nowhere else: nothing is removed upstream — accept when the relation carries no row with an unresolved or out-of-city destination borough, while `core.fct_trip` still carries those trips in the same window — source: `CONTEXT.md` (Unresolved zone), ADR 0012, answer (ADR 0018)
- [ ] `R-07` The relation is a boundary (gold) dbt model with its properties entry, an enforced contract and tests on its keys, so a consumer reads it as a published surface — accept when the model carries a properties file entry with `contract: enforced`, a uniqueness test on the month/origin/destination grain, and `not_null` on the key columns — source: `.agents/skills/data-contract`, `.agents/skills/dbt-models`

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain of the new mart | One row per (calendar month, origin borough, destination borough) | request |
| Origin and destination | The borough of the pickup zone and the borough of the dropoff zone, from `dim_zone.borough_name` resolved as of the trip's pickup date | request; `transformation/models/marts/core/fct_trip.sql` |
| Period boundary | A calendar month, expressed through `dim_date.month_start_date`; Q1 2024 is 2024-01-01 to 2024-03-31, which is exactly the reporting window `report_start`/`report_end` | request; `transformation/dbt_project.yml` |
| Edge periods | `not applicable`: no month is cut short — the data covers every day of January (31), February (29) and March (31), 2024-01-01 to 2024-03-31, so no incomplete-period mark is needed | repository (query over `core.fct_trip`) |
| Billable filter | Both trips and revenue count billable trips only, inside the reporting window: "A trip is **billable** when its total amount is positive. … Gold marts that report revenue or flows apply it, inside the reporting window" | ADR 0003 |
| Trips count | Count of billable trips for the pair-month | ADR 0003; request |
| Revenue measure | Recognised revenue: `sum(total_amount)` over billable trips whose payment method has `counts_as_revenue` true; a billable trip with a null payment-method key keeps its row and adds no revenue | user answer, ADR 0013 |
| Trips counted by the cross-borough share | Over the published pairs of the origin borough and month: trips to a different New York City borough divided by all trips in those pairs | user answer (ADR 0019) |
| Pair population | Both ends a New York City borough, at least 25 billable trips in that month; no zero-filled rows | user answer (ADR 0018) |
| Coverage of the revenue measure | The trip count is published beside revenue, and no billable trip has a null `total_amount` in the window, so the count is the measure's coverage | playbook default; repository (query: 0 nulls over 95,958 billable trips) |
| Reuse | Built from `fct_trip` with `dim_zone` joined twice, not from `agg_od_flow_matrix`: "Summing `billable_revenue` or `billable_trip_count` through this source undercounts the network … A question about the whole network is answered from the detail source." The city's question is about the whole network | ADR 0017 |
| Unmatched and null keys | Every row is kept: the zone joins are left joins, so a trip whose borough cannot be resolved still counts, and unresolved zones form their own group rather than being dropped: "No mart excludes them on its own; a borough rollup includes an unresolved group unless its consumer filters." | ADR 0012; ADR 0015 |
| Extended scope | `not applicable`: no schedule and no new source; the intent delivers no logical-model, ontology or contract artifact beyond the mart's own enforced dbt contract | `.agents/skills/../_shared/playbooks/kinds/transformation.md` |

## Out of scope

- `agg_od_flow_matrix` and its 25-trip floor (ADR 0017) are not changed; this relation neither replaces nor re-points it.
- `core.fct_trip`, `core.dim_zone`, `finance.mart_daily_zone_revenue` and `finance.mart_monthly_service_summary` are not modified.
- No new ingestion, no new dlt source and no orchestration item.
- Zone-level or corridor-level reporting beyond the borough pair; no airport/zone splits.

## Open questions

1. **Coverage of the revenue measure among published trips** — recognised revenue leaves some billable trips without a value: those on no-charge, dispute, unknown or voided payments, and those whose payment-method key is null. The design publishes `revenue_trip_count` beside `revenue` so the gap is visible (98.56% of published trips carry recognised revenue). If the Mobility Planning Lead would rather see recognised revenue *and* the billable total side by side, that is a new column and a new decision. Holds no requirement; the design record's `D-04` settles the published shape until the user says otherwise.

The three population and measure questions are settled: recognised revenue, the share over published pairs, both ends a New York City borough at 25 billable trips a month (ADR 0018, ADR 0019).

## Approvals

- 2026-11-25T06:23:02Z — requirement approved — "Please write the design records and the Plan. Stop when the Plan is written. Do not start the build yet." — 728c64a
