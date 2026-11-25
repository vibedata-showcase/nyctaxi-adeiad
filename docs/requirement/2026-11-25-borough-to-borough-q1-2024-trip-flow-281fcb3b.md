---
kinds: [transformation]
---

# Requirement: Borough-to-borough Q1 2024 trip flow

## Ask

Leila Haddad, Mobility Planning Lead, for a question the city asked: *"how much of our traffic crosses borough lines. For each month of Q1 2024, I need the trips and the revenue from each borough to each borough, and the share of trips that leave the borough they started in."*

Consumed by Mobility Planning and, through them, the city. The result is a queryable table in the warehouse, not a written report.

## Requirements

- [ ] `R-01` A boundary relation publishes, for each month of Q1 2024 and each ordered (origin borough, destination borough) pair that carried trips, the number of trips and the revenue — accept when the relation exists in the `agg` schema and a row per month-pair carries both measures — source: request
- [ ] `R-02` The same relation publishes, for each (month, origin borough), the share of that borough's trips whose destination borough differs from the origin borough — accept when the share is recomputed independently from `core.fct_trip` for every origin-month and matches the published value — source: request, and the share answer below
- [ ] `R-03` The grain is one row per (month, origin borough, destination borough) and is unique — accept when a `group by` over those three columns returns the same row count as the relation and no duplicate group exists — source: derived from the request's "from each borough to each borough"
- [ ] `R-04` The population is every billable trip picked up in the reporting window, resolved to a borough on both ends, with no minimum-volume floor — accept when the relation's `sum(trip_count)` equals 95,958 and `sum(revenue)` equals 2,629,185.82 — source: ADR 0003, and the floor and population answers below
- [ ] `R-05` Revenue is billable revenue: the sum of `total_amount` over billable trips, counting every payment method including no-charge and dispute, and including the trips that carry no payment method at all — accept when the Q1 total equals 2,629,185.82 and the recognised-revenue variant (2,594,324.30) does not appear — source: the revenue answer below, ADR 0013
- [ ] `R-06` Month totals in the relation reconcile to the fact — accept when January reads 29,985 trips / 816,057.76, February 30,017 / 813,885.68 and March 35,956 / 999,242.38 — source: query against `core.fct_trip`
- [ ] `R-07` The relation is documented as a gold relation of this Domain — accept when its properties file, its ODCS contract under `contracts/agg/` and its design record under `docs/design/models/agg/` exist and agree with the built relation, and the semantic-layer document names it — source: repo-map.json `layers.agg` role `boundary` and `notes_for_agents`; ADR-0225 as repo-map records it

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain | One row per (month, origin borough, destination borough) that carried at least one billable trip; the month is the calendar month, `date_trunc('month', pickup_datetime)` | request ("each month of Q1 2024", "from each borough to each borough"); `mart_monthly_service_summary` and `agg_driver_monthly` set the calendar-month precedent |
| Edge periods | Not applicable: Q1 2024 is not cut short. The reporting window runs 2024-01-01 to 2024-04-01 exclusive and the data covers every day — January 31, February 29, March 31 distinct pickup dates. No period is marked incomplete | user decision, on this evidence |
| Borough population | All eight borough values the zone lookup holds, each as its own row group: Bronx, Brooklyn, Manhattan, Queens, Staten Island, EWR, plus the two unresolved groups `N/A` and `Unknown`. Nothing is filtered or remapped | user decision; ADR 0012 says a borough rollup includes an unresolved group unless its consumer filters, and this one does not |
| Minimum-volume floor | None. Every borough pair that carried a trip is published. ADR 0017's 25-trip floor is scoped to the zone-pair surface `agg_od_flow_matrix`, not to this one | user decision |
| Revenue measure | Billable revenue — `sum(total_amount)` over billable trips, all payment methods counted, including the 1,287 no-charge and dispute trips (31,310.45) and the 106 billable trips that carry no payment method (3,551.07). The recognised-revenue variant would be 2,594,324.30 | user decision; ADR 0013 leaves the choice to the metric, and this matches both revenue and flow surfaces (`agg_od_flow_matrix`, `mart_daily_zone_revenue`) |
| Leaving-share definition | For an origin borough and month, the trips whose destination borough differs from the origin borough, over all that borough's trips. A trip to an unresolved destination counts as leaving | user decision |
| Empty pairs | A borough pair with no trips in a month is not emitted; no zero rows are generated, so the relation is not a filled 8 × 8 grid | user decision; matches every existing `agg` mart, none of which cross-joins to a grid |
| Coverage | Not a partial measure: `total_amount` is non-null and positive on every billable trip (0 nulls, 0 non-positive in the window), so `trip_count` is both the row count and the carrier count of the revenue measure | repository, verified against `core.fct_trip` |
| Reuse | New relation built from `fct_trip` joined to `dim_zone` twice, not rolled up from `agg_od_flow_matrix`. Rolling up the published matrix would inherit its 25-trip floor and undercount 253 trips, which the floor answer excludes | user decision on the floor, against ADR 0017's population |
| Unmatched and null keys | Every trip is kept: the pickup and dropoff zone keys are non-null on all 97,184 fact rows, and `dim_zone` has 272 distinct `zone_key` values over 272 rows, so neither inner join drops or duplicates a row | repository, verified against `core.fct_trip` and `core.dim_zone`; ADR 0012 and ADR 0015 |
| Extended scope | No schedule is requested, so no `orchestration` kind is added. The contract and semantic-layer document stay inside `transformation` | request |
| Model name and materialisation | Pending design | design question, never asked at intent |

## Out of scope

- No published model is rewritten. `agg_od_flow_matrix` keeps its zone-pair grain and its 25-trip floor (ADR 0017) and is not touched.
- No ingestion, no new source, no change to `fct_trip`, `dim_zone` or any intermediate model.
- No written report, chart or dashboard: the deliverable is the table.
- No schedule or orchestration item.
- The share is per origin borough-month, not per zone and not city-wide.

## Open questions

- None open. Two writes are held rather than unanswered, blocked by the instruction to draft the Requirement and stop: a `CONTEXT.md` entry for the cross-borough share term, and an ADR recording that a published borough-level flow matrix carries no minimum-volume floor while ADR 0017's floor governs the zone-pair matrix. Both are pending writes for the next stage, not open business questions.
- Design holds the model name, its materialisation and how the origin-month share is carried on a table whose grain is finer than the share (repeated across the origin's rows, or once per origin-month), a shape that changes what a naive `sum` of that column would mean.

## Approvals
