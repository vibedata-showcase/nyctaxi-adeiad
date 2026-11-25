---
kinds: [transformation]
---

# Requirement: Borough-to-borough trips and revenue, Q1 2024 3

## Ask

Leila Haddad (Mobility Planning Lead): the city asked how much of our traffic
crosses borough lines. For each month of Q1 2024 she needs the trips and the
revenue from each borough to each borough, and the share of trips that leave
the borough they started in.

The consumer is the Mobility Planning team, reporting to the city. The answer
becomes a new gold table in this project.

## Requirements

- [ ] `R-01` One row per calendar month of Q1 2024 × origin borough × destination borough — accept when a grain test on (`trip_month`, `origin_borough`, `dest_borough`) returns no duplicate — source: request
- [ ] `R-02` Each row carries the trip count for its borough pair and month — accept when the per-month sum of the trip column equals `fct_trip`'s billable trip count in the window (29,985 / 30,017 / 35,956 for 2024-01 / 02 / 03) — source: request
- [ ] `R-03` Each row carries the revenue for its borough pair and month — accept when the per-month sum of the revenue column equals the star's billable `total_amount` (816,057.76 / 813,885.68 / 999,242.38) — source: request
- [ ] `R-04` The table carries the cross-borough share of the origin borough for that month, defined as trips ending outside the origin borough over all billable trips starting in it; how the value is carried per row follows open question 4 — accept when the share recomputed from the table's own rows for one origin and month matches the published value for that origin and month — source: request
- [ ] `R-05` Unresolved zones (`Unknown`, `N/A`) and `EWR` stay in the rollup as borough groups of their own rather than being dropped, and a trip landing in one of them from another borough counts as leaving — accept when the table's borough groups are exactly the 8 on `dim_zone` across the quarter and the totals still close to `R-02` and `R-03` — source: request; `docs/adr/0012-unresolved-zones-are-retained-and-flagged.md`
- [ ] `R-06` The table is published at the gold boundary as a dbt model with its properties entry, its tests, an ODCS contract and its Ossie document, because a boundary relation owes all of them — accept when `dbt build` and its tests pass in the sandbox and the contract and semantic-model gates pass — source: `repo-map.json` `layers` (`boundary` role), `AGENTS.md`

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain of the new mart | One row per (trip month, origin borough, destination borough) | request: "for each month of Q1 2024 … from each borough to each borough" |
| Period boundary | Calendar months; Q1 2024 is `pickup_datetime` inside the reporting window (`2024-01-01` to `2024-04-01`) | `transformation/dbt_project.yml` vars; `docs/adr/0003-billable-trip-definition-and-where-it-applies.md` |
| Edge periods | Not applicable: every one of the three months is whole in the data (31 / 29 / 31 days carrying billable trips, 2024-01-01 to 2024-03-31), so no month is cut short and none needs an incomplete mark | measured on `core.fct_trip` for the window |
| Which trips count | Billable trips only: "A new revenue or flow mart applies the rule; a new quality or fleet-operations mart does not unless a requirement says so." | `docs/adr/0003-billable-trip-definition-and-where-it-applies.md` (quoted) |
| What "revenue" means in the revenue column | **Open** — proposed: gross billable `total_amount`, as `mart_daily_zone_revenue` and `agg_od_flow_matrix` do. The alternative is recognised revenue (`counts_as_revenue`, ADR 0013), which excludes 1,287 billable no-charge and dispute trips and is $31,310.45 smaller over the quarter | open question 1 |
| Whether a floor applies to published borough pairs | **Open** — proposed: publish every borough pair, because ADR 0017's 25-trip floor is about zone pairs on the OD matrix. Measured at month × borough-pair grain, the floor would keep 56 of the 122 observed rows and drop 253 of the window's 95,958 billable trips (0.3%), almost all of them small cross-borough flows | open question 2 |
| A month × borough pair with no billable trips | **Open** — proposed: omit it and publish observed pairs only, as `agg_od_flow_matrix` and `mart_daily_zone_revenue` do; the alternative is a zero-filled 8 × 8 grid per month | open question 3 |
| Coverage of the revenue measure | `trip_count` is published beside the revenue column, and every billable trip carries a `total_amount` (0 nulls among the window's billable trips), so the pair of columns is self-describing | playbook default; measured on `core.fct_trip` |
| Cross-borough share, per row | **Open** — proposed: one value per origin borough per month, repeated on each of that origin's rows (including its intra-borough row), so a single figure answers the city's question; the alternative is each row's own share of its origin's trips | open question 4 |
| Whether an unresolved or out-of-city destination counts as leaving | Yes: a trip from Manhattan to `Unknown`, `N/A` or `EWR` is cross-borough, because the destination borough name differs from the origin's and ADR 0012 keeps those groups in a borough rollup rather than excluding them | `docs/adr/0012-unresolved-zones-are-retained-and-flagged.md`; request |
| Reuse | Built from `fct_trip` joined to `dim_zone` twice, as `agg_od_flow_matrix` is. The published OD matrix cannot be built on: it has no month column (it totals the whole window) and applies ADR 0017's floor, covering 68,513 of the window's 95,958 billable trips | `transformation/models/marts/agg/agg_od_flow_matrix.sql`; measured on `agg.agg_od_flow_matrix` |
| Unmatched and null keys | Every row kept: no billable trip in the window has a null pickup or dropoff zone key, so the `dim_zone` joins drop nothing; the totals are tested against `fct_trip` for that reason | playbook default; measured on `core.fct_trip` |
| Extended scope | No schedule is asked for, so no `orchestration` kind. The new gold relation's Ossie document, ontology mapping and data contract stay in `transformation` | playbook |

## Out of scope

- `agg.agg_od_flow_matrix`, `finance.mart_daily_zone_revenue`, `finance.mart_monthly_service_summary` and every other published model: not changed, not rebuilt from, not restructured.
- Zone-pair grain, daypart grain and borough × service-type breakdowns.
- Filtering `EWR`, the unresolved zones or any payment method out of the rollup.
- A schedule or any other orchestration item.

## Open questions

1. **What "revenue" means.** Gross billable `total_amount` (matches the existing revenue marts and closes to the star, $2,625,634.75 for the quarter) or recognised revenue excluding no-charge and dispute payments (ADR 0013's `counts_as_revenue`: 1,287 billable trips, $31,310.45 lower). Holds `R-03` and the revenue column.
2. **Whether ADR 0017's 25-trip floor applies to borough pairs.** Publishing every pair keeps the table equal to the network totals. Applying the floor at this grain would keep 56 of the 122 observed month × pair rows and drop 253 of 95,958 billable trips (0.3%) — small in volume, but it removes precisely the thin cross-borough flows the city's question is about, and every share's denominator then no longer matches the star. Holds `R-02`, `R-03` and `R-04`.
3. **Whether a month × borough pair with no trips is emitted as zero or omitted.** Holds `R-01`'s row count (122 observed rows versus 192 zero-filled ones for Q1 2024).
4. **How the cross-borough share is carried.** One value per origin borough per month repeated on all of that origin's rows, or each row's own share of its origin's month trips (whose intra-borough row alone equals the stay-at-home share). Holds `R-04`'s column shape.

These follow approval: "cross-borough trip" is new Domain vocabulary, and the share's definition may clear the ADR bar. Both land through `domain-modeling` once questions 1–4 are answered.

## Approvals
