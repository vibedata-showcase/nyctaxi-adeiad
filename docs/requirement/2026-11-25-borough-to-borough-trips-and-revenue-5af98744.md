---
kinds: [transformation]
---

# Requirement: Borough-to-borough trips and revenue

## Ask

Leila Haddad, Mobility Planning Lead: *"The city asked how much of our traffic crosses borough lines. For each month of Q1 2024, I need the trips and the revenue from each borough to each borough, and the share of trips that leave the borough they started in."*

She and anyone answering a city question about cross-borough movement consume the result. It is a new table in the Domain's `agg` layer, published under contract and in the semantic model so it can be queried by name.

## Requirements

- [ ] `R-01` A new boundary model publishes one row per month of Q1 2024 × origin borough × destination borough over the five NYC boroughs, 75 rows, with every one of the 25 cells present in each month — accept when `select trip_month, count(*) from agg.agg_borough_flow_monthly group by 1` returns 25 for each of the three months and Q1's three monthly trip totals sum to 94,723 — source: request; ADR 0018
- [ ] `R-02` Each cell carries the billable trips between its two boroughs and their total revenue — accept when the January Manhattan→Manhattan cell is 24,995 trips and 515,753.34 revenue, and the three months' revenue sums to 2,533,885.02 — source: request, ADR 0003; figures recomputed from `core.fct_trip` in this intent
- [ ] `R-03` The table's population is trips whose pickup and dropoff zones are both in an NYC borough: trips touching an unresolved zone (`Unknown`, `N/A`) and trips touching EWR are outside the published grid and outside every share and total it carries — accept when the three monthly trip totals are 29,568 / 29,650 / 35,505 (against 29,985 / 30,017 / 35,956 over every billable trip) — source: user answer; ADR 0012; figures recomputed in this intent
- [ ] `R-04` Every row of an origin borough's month carries that borough's outbound cross-borough share, with the trip count it is computed over published beside it — accept when, for each of the three months, the share recomputed independently as the sum of that origin's cross-borough cells over that origin's total trips equals the published value to 1e-9, and January reads Manhattan 5.30%, Queens 70.52%, Brooklyn 37.18%, Bronx 58.88%, Staten Island 40.00% — source: user answer; figures recomputed in this intent
- [ ] `R-05` A cell with no trips in a month carries zero trips and zero revenue, never a null, and no cell is suppressed for being thin — accept when no row of the table holds a null trip count or null revenue, and the January grid holds 22 cells with trips and 3 with none — source: user answer; ADR 0018
- [ ] `R-06` The relation is registered in the semantic model and the ontology, and carries an enforced dbt contract and an ODCS contract at the Domain's contract path — accept when `ossie.py validate`, `coverage`, `suppliers` and `notes` pass with the new relation named, `odcs.py check` passes, and a `validating-semantic-model` and a `validating-data-contract` report both pass — source: repository (`repo-map.json` `contracts`, `logical-model/`, `ontology/`); `test-map.json` selectors
- [ ] `R-07` The model's grain, its zero cells and its share are protected by tests — accept when the agg data-test selection passes at the built commit, including a grain-uniqueness test over (month, origin borough, destination borough) and a singular test that each month's cells sum to the independently counted trips — source: repository convention for `transformation/models/marts/agg/`

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain of `agg_borough_flow_monthly` | One row per month × origin borough × destination borough | request ("from each borough to each borough", "for each month") |
| Period boundary | Calendar month, Q1 2024 = the reporting window's three months; the month is the pickup month | request; `dbt_project.yml` `report_start`/`report_end` |
| Edge periods | Not applicable: no period is cut short. The data spans 2024-01-01 to 2024-03-31, the reporting window is 2024-01-01 to 2024-04-01, and all 91 days carry trips | `core.fct_trip` recomputed in this intent |
| Which places are boroughs | The five NYC boroughs only; unresolved zones and EWR are outside the grid | user answer |
| Revenue definition | `total_amount` over billable trips, all payment methods, including no-charge and dispute payments | user answer; ADR 0003; ADR 0013 |
| Population of a cell | Billable trips (positive total) only | request "revenue"; ADR 0003 |
| NULLs and empty cells | A cell with no trips carries 0 trips and 0 revenue; no nulls, no `HAVING` floor | user answer; ADR 0018 |
| A period with no qualifying rows | Not applicable: every month has trips, and the zero-fill rule covers an absent cell | ADR 0018; data recomputed in this intent |
| Coverage of the revenue measure | Complete by construction: every counted trip is billable, and a billable trip has a positive total, so no counted trip lacks the measure. `trip_count` is published beside revenue | ADR 0003; `core.fct_trip` recomputed in this intent |
| Share scope | Per origin borough per month, outbound: that origin's cross-borough trips over that origin's total trips | user answer |
| Reuse | Built from `core.fct_trip` with `core.dim_zone` joined twice. No published model serves this grain: `agg_od_flow_matrix` is zone-grain under ADR 0017's floor and `mart_daily_zone_revenue` carries no destination | repository; ADR 0017 |
| Unmatched and null keys | No row is dropped: every trip has a resolvable pickup and dropoff zone key (0 nulls in Q1), and the borough grid is a left join so a cell with no trips survives | `core.fct_trip` recomputed in this intent |
| Extended scope | Not a question: no schedule, and the contract, semantic-model and ontology deliverables stay inside `transformation` | transformation playbook |

## Out of scope

- Any change to `agg_od_flow_matrix`, its 25-trip floor (ADR 0017) or its published columns.
- Any change to `core.fct_trip`, `core.dim_zone`, `mart_daily_zone_revenue` or any other published model this intent does not name.
- Zone-grain or neighbourhood-grain flows, and any period other than Q1 2024's three months.
- A schedule or orchestration item for the new model.
- Revenue recognised through the payment-method master (ADR 0013), which the user declined in favour of billable revenue.

## Open questions

None.

## Approvals
- 2026-11-25T01:44:18Z — requirement approved — "Approve and continue" — 5397a0d
