---
kinds: [transformation]
---

# Requirement: R9 · borough flow

## Ask

Leila Haddad, Mobility Planning Lead, for the city: "The city asked how much of our traffic crosses borough lines. For each month of Q1 2024, I need the trips and the revenue from each borough to each borough, and the share of trips that leave the borough they started in."

Mobility Planning consumes the result to answer the city, as a new gold (boundary) table over the trip star, scoped by the reporting window.

## Requirements

- [ ] `R-01` One row per (month, origin group, destination group) for every month of the reporting window and every group in the zone dimension, where the groups are the six boroughs plus one `unresolved` group that absorbs `Unknown`, `N/A` and any zone-less trip; zero-trip pairs included — accept when the table has no duplicate on that triple and its row count equals 3 × 7² = 147 for Q1 2024 as read on 2026-11-24 — source: request; full-grid answer; design-stop answer that `Unknown` and `N/A` are not boroughs
- [ ] `R-02` `trip_count` is the count of billable trips picked up in the origin group that month and dropped in the destination group, inside the reporting window — accept when, for each month, the table's sum of `trip_count` equals that month's billable trip count in `core.fct_trip` (Q1 2024 total 95,958 as read on 2026-11-24) and each row's count matches a direct group-by from `fct_trip` — source: ADR 0003; answer that every billable trip counts
- [ ] `R-03` `total_revenue` is `sum(total_amount)` over the same trips — accept when, for each month, the table's sum of `total_revenue` equals `sum(total_amount)` over that month's billable trips in `core.fct_trip` — source: `mart_daily_zone_revenue` and `agg_od_flow_matrix`, the existing revenue measure
- [ ] `R-04` A row whose origin and destination are both boroughs carries that row's share of its origin borough's billable pickups whose destination is also a borough that month, so the borough-destination rows of one (month, origin borough) sum to 1; a row touching the `unresolved` group carries a null share; an `is_intra_borough` flag marks origin = destination — accept when borough-to-borough shares per (month, origin borough) sum to 1 within floating-point tolerance, every row touching `unresolved` carries a null share, and the complement of the intra-borough row equals the leaving-borough share computed directly from `fct_trip` over borough-to-borough trips — source: user answer (row share plus flag); design-stop answer (unresolved is outside the share)
- [ ] `R-05` No trip floor: every pair is published, including pairs with no billable trips, which appear with 0 trips and 0 revenue — accept when the built relation contains no volume threshold and every zero-trip pair required by R-01 is present with zero trips and zero revenue — source: user answer; ADR 0018
- [ ] `R-06` Every group is kept: the six boroughs including the out-of-state `EWR`, and one `unresolved` group holding the `Unknown` and `N/A` zones and any zone-less trip, all carrying their trips and revenue — accept when each appears as its own origin and destination group, `Unknown` and `N/A` appear nowhere else, and `EWR` appears as its own group — source: ADR 0012; design-stop answer (one unresolved group); unmatched/null default (keep every row)
- [ ] `R-07` The table is published as a gold (boundary) relation that meets the repo's boundary obligations: enforced dbt contract with documented columns, a uniqueness test on the grain, an ODCS contract that passes `odcs.py check`, and an entry in the semantic layer's canonical documents — accept when those checks pass on the built relation — source: `repo-map.json` (the `contracts` module, which puts every gold relation under contract, and the `boundary` layer role)
- [ ] `R-08` No published relation changes: `fct_trip`, `dim_zone`, `agg_od_flow_matrix` and every existing mart keep their rows, columns and values — accept when no existing model's SQL or properties change and `agg_od_flow_matrix` still reports its floored population — source: request is to add a table; ADR 0017

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain | one row per (month, origin group, destination group), the groups being the six boroughs plus one `unresolved` group | request; design-stop answer |
| Period boundary | the reporting window's calendar months on pickup date (`in_report_window(pickup_datetime)`), currently 2024-01-01 to 2024-04-01 | request ("each month of Q1 2024"); ADR 0003's reporting-window rule; `dbt_project.yml` vars |
| Population | billable trips only | ADR 0003: "A trip is **billable** when its total amount is positive. … Gold marts that report revenue or flows apply it, inside the reporting window"; and "A new revenue or flow mart applies the rule" |
| Revenue measure | `sum(total_amount)` over the row's trips | existing revenue marts (`mart_daily_zone_revenue`, `agg_od_flow_matrix`) |
| Share shape | each borough-to-borough row carries trip_count ÷ the origin borough's billable pickups to borough destinations that month, plus `is_intra_borough`; a row touching `unresolved` carries a null share | user answers (row share plus flag; unresolved outside the share) |
| Share arithmetic | the share is a ratio of summed trip counts, never an average of pair shares, and a zero denominator gives null | ADR 0016: "Every rate … is computed as a sum of numerators over a sum of denominators, through the `safe_divide` macro, which returns null when the denominator is zero. Such a rate is never the average of lower-level rates." |
| Quality verdicts | no quality verdict is filtered; a billable trip flagged implausibly short, fast or zero-distance stays in its flow | ADR 0004: "A consumer decides which verdicts to exclude, and says so"; this table excludes none beyond the billable rule |
| Empty pairs | full grid: a pair with no billable trips is published with 0 trips and 0 revenue | user answer |
| Trip floor | none at borough grain; ADR 0017's 25-trip floor remains a zone-pair rule | user answer; ADR 0018 |
| Reuse | build from `fct_trip` with `dim_zone` joined twice, not from `agg_od_flow_matrix` | repository: the zone matrix is floored onto zone pairs (ADR 0017), so it cannot reproduce totals or shares |
| Unmatched and null keys | keep every group; `Unknown`, `N/A` and any zone-less trip form one `unresolved` group, kept in the totals and outside the share | ADR 0012 (unresolved zones are real rows, kept and flagged; "a borough rollup includes an unresolved group"); ADR 0015 (a null key stays null and its trip stays); design-stop answer |
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
- 2026-11-24T10:18:21Z — requirement approved — "Approve and stop here" — 1d8bcd0
