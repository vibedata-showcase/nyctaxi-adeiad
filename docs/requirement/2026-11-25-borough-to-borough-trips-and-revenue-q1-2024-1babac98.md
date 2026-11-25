---
kinds: [transformation]
---

# Requirement: Borough-to-borough trips and revenue, Q1 2024

## Ask

Leila Haddad, Mobility Planning Lead, asked for the city's question: how much of our traffic crosses borough lines. For each month of Q1 2024 she needs the trips and the revenue from each borough to each borough, and the share of trips that leave the borough they started in. The consumer is a borough-level answer to the city, not a zone-level corridor report; the existing zone-pair matrix does not serve it (see the reuse row below).

## Requirements

- [ ] `R-01` A published relation reports, for each calendar month of Q1 2024 and each (origin borough, destination borough) pair, a trip count and a revenue figure — accept when the built relation carries the columns `month`/`month_start_date`, `origin_borough`, `destination_borough`, a trip count and a revenue measure, and the selection's `dbt build` passes — source: request
- [ ] `R-02` Revenue per pair equals the sum of the chosen revenue measure over that pair's billable trips in the month — accept when an independent recomputation from `core.fct_trip` joined twice to `core.dim_zone` matches the published revenue to the cent on every row — source: request, ADR 0003
- [ ] `R-03` Each origin borough and month carries the share of its trips that leave the origin borough — accept when, for every origin-month in the relation, cross-borough trips divided by all trips from that origin equals the published share to within 1e-9, recomputed independently — source: request
- [ ] `R-04` The relation covers exactly the three Q1 2024 months and no other period — accept when a query returns three distinct months, 2024-01-01, 2024-02-01 and 2024-03-01, and no row falls outside 2024-01-01 to 2024-03-31 — source: request
- [ ] `R-05` Every billable trip picked up in Q1 2024 is counted in the relation's trip counts when the population decision keeps every pair — accept when the sum of the trip count over the relation equals the independently queried billable trip count for the window (95,958 at the current build) — source: request, ADR 0012, ADR 0015; depends on the open population question
- [ ] `R-06` Trips that end in a zone whose borough the source cannot resolve (Unknown, N/A) are not silently dropped from the relation — accept when the relation carries rows for those destination borough labels, per whatever the open share question decides — source: `CONTEXT.md` (Unresolved zone), ADR 0012
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
| Revenue measure | **OPEN** — billable `sum(total_amount)` (2,629,185.82 for Q1, as `agg_od_flow_matrix` publishes) or recognised revenue (`counts_as_revenue` payment methods only, 2,594,324.30): a 1.33% difference. Asked; unanswered | open question |
| Trips counted by the cross-borough share | **OPEN** — any different borough label (Manhattan January 6.01%), resolved destinations only (5.55%) or NYC boroughs only excluding EWR (5.30%). Asked; unanswered | open question |
| Pair population | **OPEN** — every pair with trips and no floor (122 pair-months; total reconciles), the 25-trip floor of ADR 0017 (56 pair-months, 253 trips dropped, whole origins such as Staten Island vanish) or a zero-filled 8 × 8 grid (192 rows). Asked; unanswered | open question |
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

1. **Revenue measure** — billable `total_amount` (matches `agg_od_flow_matrix`) or recognised revenue (`counts_as_revenue` only)? Difference over Q1: 1.33%. Holds the revenue column's definition and `R-02`'s acceptance value.
2. **What the cross-borough share counts** — any different borough label (6.01% for Manhattan January; unresolved destinations such as Unknown/N/A count as a different borough, so every trip has a destination and destination shares sum to 100%), resolved destinations only (5.55%; trips ending in Unknown/N/A leave both numerator and denominator), or NYC boroughs only excluding EWR (5.30%). Holds `R-03` and `R-06`.
3. **Pairs published** — every pair with trips (122 pair-months, no floor, totals reconcile), the 25-trip floor (56 pair-months, 253 trips dropped, EWR / N/A / Staten Island origins disappear entirely), or a zero-filled 8 × 8 grid (192 rows, 0 trips and 0 revenue for empty pairs)? Holds `R-05` and the row count.

Three questions were put to the user in one round and timed out unanswered; each is recorded here rather than decided, per the grilling rule that an unresolved branch is never a guess.

## Approvals

