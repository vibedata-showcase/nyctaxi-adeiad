---
kinds: [transformation]
---

# Requirement: R9 · borough flow

## Ask

Leila Haddad, Mobility Planning Lead, for the city: "The city asked how much of our traffic crosses borough lines. For each month of Q1 2024, I need the trips and the revenue from each borough to each borough, and the share of trips that leave the borough they started in."

Mobility Planning consumes the result to answer the city, as a new gold (boundary) table over the trip star, scoped by the reporting window.

## Requirements

- [ ] `R-01` One row per (month, origin borough, destination borough) for every month of the reporting window and every borough the zone dimension carries, zero-trip pairs included — accept when the table has no duplicate on that triple and its row count equals (months in the window) × (distinct boroughs in `core.dim_zone`) squared, which is 3 × 8² = 192 for Q1 2024 as read on 2026-11-24 — source: request; full-grid answer
- [ ] `R-02` `trip_count` is the count of billable trips picked up in the origin borough that month and dropped in the destination borough, inside the reporting window — accept when, for each month, the table's sum of `trip_count` equals that month's billable trip count in `core.fct_trip` (Q1 2024 total 95,958 as read on 2026-11-24) and each row's count matches a direct group-by from `fct_trip` — source: ADR 0003; answer that every billable trip counts
- [ ] `R-03` `total_revenue` is `sum(total_amount)` over the same trips — accept when, for each month, the table's sum of `total_revenue` equals `sum(total_amount)` over that month's billable trips in `core.fct_trip` — source: `mart_daily_zone_revenue` and `agg_od_flow_matrix`, the existing revenue measure
- [ ] `R-04` Each row carries that row's share of its origin borough's billable pickups that month, so the rows of one (month, origin borough) sum to 1, and an `is_intra_borough` flag marks origin = destination — accept when shares per (month, origin borough) sum to 1 within floating-point tolerance and the complement of the intra-borough row equals the leaving-borough share computed directly from `fct_trip` — source: user answer (row share plus flag)
- [ ] `R-05` No trip floor: every borough pair is published, including pairs with no billable trips, which appear with 0 trips and 0 revenue — accept when the built relation contains no volume threshold and every zero-trip pair required by R-01 is present with zero trips and zero revenue — source: user answer; ADR 0018
- [ ] `R-06` Every borough group is kept — including the unresolved `Unknown` and `N/A` and the out-of-state `EWR` — accept when each appears as its own origin and destination group carrying its trips and revenue — source: ADR 0012; unmatched/null default (keep every row)
- [ ] `R-07` The table is published as a gold (boundary) relation that meets the repo's boundary obligations: enforced dbt contract with documented columns, a uniqueness test on the grain, an ODCS contract that passes `odcs.py check`, and an entry in the semantic layer's canonical documents — accept when those checks pass on the built relation — source: `repo-map.json` (the `contracts` module, which puts every gold relation under contract, and the `boundary` layer role)
- [ ] `R-08` No published relation changes: `fct_trip`, `dim_zone`, `agg_od_flow_matrix` and every existing mart keep their rows, columns and values — accept when no existing model's SQL or properties change and `agg_od_flow_matrix` still reports its floored population — source: request is to add a table; ADR 0017

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain | one row per (month, origin borough, destination borough) | request |
| Period boundary | the reporting window's calendar months on pickup date (`in_report_window(pickup_datetime)`), currently 2024-01-01 to 2024-04-01 | request ("each month of Q1 2024"); ADR 0003's reporting-window rule; `dbt_project.yml` vars |
| Population | billable trips only | ADR 0003: "A trip is **billable** when its total amount is positive. … Gold marts that report revenue or flows apply it, inside the reporting window"; and "A new revenue or flow mart applies the rule" |
| Revenue measure | `sum(total_amount)` over the row's trips | existing revenue marts (`mart_daily_zone_revenue`, `agg_od_flow_matrix`) |
| Share shape | each row carries trip_count ÷ all billable pickups in its origin borough that month, plus `is_intra_borough`; the leaving share is the complement of the intra-borough row | user answer |
| Empty pairs | full grid: a pair with no billable trips is published with 0 trips and 0 revenue | user answer |
| Trip floor | none at borough grain; ADR 0017's 25-trip floor remains a zone-pair rule | user answer; ADR 0018 |
| Reuse | build from `fct_trip` with `dim_zone` joined twice, not from `agg_od_flow_matrix` | repository: the zone matrix is floored onto zone pairs (ADR 0017), so it cannot reproduce borough totals or shares |
| Unmatched and null keys | keep every borough group, including `Unknown`, `N/A` and `EWR`; none is dropped or merged | ADR 0012: "a borough rollup includes an unresolved group unless its consumer filters"; playbook default (keep every row) |
| Coverage | the trip count stands beside revenue as the count of rows that carry it | playbook default |
| Edge periods | not applicable: the data covers all three months whole (31, 29 and 31 distinct pickup dates, 2024-01-01 to 2024-03-31) | data check on `core.fct_trip` |
| Materialisation, model name, layer folder | pending for design | design question, never asked at intent |

## Out of scope

- Any change to `fct_trip`, `dim_zone`, `agg_od_flow_matrix`, the finance, ops and other agg marts, or their contracts.
- The reporting window itself: the table follows it and does not change it.
- Months outside Q1 2024, and non-billable trips.
- Zone-level or corridor-level flows, and any quality or fleet-operations measure.

## Open questions

None.

## Approvals
