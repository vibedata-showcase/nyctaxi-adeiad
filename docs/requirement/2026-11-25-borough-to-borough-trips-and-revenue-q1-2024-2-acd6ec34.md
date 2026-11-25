---
kinds: [transformation]
---

# Requirement: Borough-to-borough trips and revenue, Q1 2024

## Ask

Leila Haddad, Mobility Planning Lead, is answering a question from the city: how much of the city's taxi traffic crosses borough lines. For each month of Q1 2024 she needs, for every borough, the trips and the revenue from that borough to each destination borough, and the share of that borough's trips that leave the borough they started in. She consumes it as a published table in this project; the figures go to the city.

## Requirements

- [ ] `R-01` A new boundary table in the `agg` layer carries one row per (month, origin borough, destination borough), built from `fct_trip` with `dim_zone` joined twice — accept when the built relation has one row per month/origin/destination triple with no duplicate grain and its row set equals an independent recomputation from `fct_trip` and `core.dim_zone` — source: request
- [ ] `R-02` Trips and revenue are measured on billable trips only, revenue as the sum of `total_amount` — accept when every row's trips and revenue equal a recomputation filtered on `is_billable`, and the sum of a month's rows for one origin borough equals that borough's billable trip count and billable revenue for the month from `fct_trip` — source: user answer; ADR 0003
- [ ] `R-03` Every observed borough pair is published, with no minimum-trip floor — accept when the row count equals the number of (month, origin, destination) groups carrying at least one billable trip (122 for Q1 2024 at the time of writing) and no such group is missing — source: user answer; ADR 0018
- [ ] `R-04` A pair with no billable trips is omitted rather than published as a zero row — accept when no row in the relation has zero trips and the row count is below the dense 8 × 8 × 3 = 192 — source: user answer
- [ ] `R-05` Each row carries the share of its origin borough's trips for that month that left that borough, and the cross-borough trip count the share is computed from, so the share reconciles against the rows — accept when the outbound trip count for an origin-month equals the sum of trips over that origin-month's rows whose destination differs, and the share equals that count divided by the origin-month total within 0.01 percentage point of an independent recomputation — source: request; user answer
- [ ] `R-06` A destination borough that differs from the origin counts as leaving, including the unresolved groups and the out-of-state one, which appear as destination rows of their own — accept when the unresolved (`Unknown`, `N/A`) and `EWR` destinations are present as destination rows and Manhattan's January 2024 share is 6.01% from an independent recomputation, not 5.53% — source: user answer; ADR 0019; ADR 0012
- [ ] `R-07` Months are calendar months of the trip's pickup date and cover January, February and March 2024, each published once — accept when the relation holds exactly three distinct months, the first 2024-01-01 and the last 2024-03-01, and each month's totals reconcile to the same predicate on `fct_trip.pickup_datetime` — source: request; `CONTEXT.md` "Date"
- [ ] `R-08` The published relation states what it means: column descriptions, its grain, and the population rules it applies, all checked against the built data — accept when every number, rule and date in the properties file, design record and any ADR written for it agrees with the built relation — source: repository convention

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain | One row per (calendar month, origin borough, destination borough) | user answer; `R-01` |
| Edge periods | No month is cut short: trips cover 2024-01-01 to 2024-03-31, all 91 days, so no incomplete mark is published | derived from `fct_trip` (min/max pickup date, 91 distinct dates) |
| Population: which trips | Billable trips only, `fct_trip.is_billable` | user answer (95,958 billable of 97,184 picked up in Q1 2024) |
| Population: revenue | `sum(total_amount)` over billable trips | request; ADR 0003 |
| Population: NULL in the revenue aggregate | `total_amount` is present on every billable trip in Q1 2024, so no null handling changes a figure | derived from `fct_trip` (0 null totals, 0 zero totals on billable trips) |
| Population: a pair with no qualifying trips | Omitted, not emitted as zero | user answer |
| Coverage | `trip_count` is published on every row, so the measure's coverage reads beside the revenue | playbook default |
| Floor | No minimum-trip floor at borough grain | user answer; ADR 0018 |
| Share scope | Every destination group that differs from the origin counts as leaving, unresolved and out-of-state included | user answer; ADR 0019 |
| Reuse | Build from `fct_trip` + `dim_zone`, not from `agg_od_flow_matrix`: its 25-trip zone-pair floor would drop rows this surface must publish | derived from `agg_od_flow_matrix.sql` and ADR 0017, given the floor answer |
| Unmatched and null keys | Keep every row: both zone keys resolve on every Q1 trip (0 null pickup key, 0 null dropoff key, no unmatched `dim_zone` join) | derived from `fct_trip` and `dim_zone` |
| Extended scope | No schedule, no new source, no zone-level detail | playbook default |

Design questions left for the design stop: the model's name and folder, its materialisation, and whether it is one model or a model over an intermediate.

## Out of scope

- `agg_od_flow_matrix`, its 25-trip floor (ADR 0017) and its zone-pair grain: unchanged.
- `mart_daily_zone_revenue` and every other published mart: not rewritten.
- `fct_trip`, `dim_zone` and the silver layers: read, not changed.
- Zone-to-zone detail, and any period outside January–March 2024.
- Revenue restricted to `counts_as_revenue` payment methods (ADR 0013): the request asks for revenue as the billable total.
- A schedule or orchestration item.

## Open questions

None: the four business branches that changed rows or values were settled before writing.

## Approvals

- 2026-11-25T03:49:46Z — requirement approved — "design" — 4b5dcff
- 2026-11-25T03:58:31Z — design approved — "stop" — 0b5fbbc
