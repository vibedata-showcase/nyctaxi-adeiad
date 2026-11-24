---
kinds: [transformation]
---

# Requirement: SS · borough flow

## Ask

Leila Haddad, Mobility Planning Lead, was asked by the city how much of our traffic crosses borough lines. She needs, for each month of Q1 2024, the trips and the revenue from each borough to each borough, and the share of trips that leave the borough they started in. The consumer is mobility planning and the city's reporting; the artifact is a new boundary table in `agg`.

## Requirements

- [ ] `R-01` One row per month, origin borough and destination borough for Q1 2024, over the five city boroughs plus one `unresolved` group on both sides — accept when the built relation returns exactly 108 rows (6 × 6 members × 3 months), one per month × origin × destination, with no duplicate key and no month outside 2024-01 / 2024-02 / 2024-03 — source: request; answers to the unresolved-group and EWR questions
- [ ] `R-02` Every combination in that row and column set is present, so a pair with no trips carries 0 rather than being absent — accept when 15 of the 108 rows carry `trip_count` 0 and 93 carry at least one trip, and every one of the 108 keys is present — source: answer to the matrix-shape question
- [ ] `R-03` Each row carries the trips and the revenue for that pair: `trip_count` as billable trips and `revenue` as the summed total amount, per ADR 0003 — accept when, over the whole relation, `sum(trip_count)` = 95,723 and `round(sum(revenue), 2)` = 2,599,668.55, recomputed independently from `core.fct_trip` restricted to the same population, and no row has a null `revenue` — source: `docs/adr/0003-billable-trip-definition-and-where-it-applies.md`
- [ ] `R-04` Each row whose origin is a city borough carries that borough's share of its trips that left it in that month, as a ratio of summed trips (ADR 0016), repeated on every destination row of that origin and month — accept when the share takes exactly one value per (month, city-borough origin) across that origin's six rows, is null on all 18 rows of the `unresolved` origin and on no city-borough row (every city borough reached a resolved destination in every month), and reproduces 5.30% for Manhattan in January, 58.88% for Bronx in January and 70.52% for Queens in January — source: `docs/adr/0016-rates-are-rebuilt-from-summed-numerators-and-denominators.md`; answer to the share-population question
- [ ] `R-05` The share's numerator and denominator are published beside it, so a reader can see what it divides — accept when each row carries the count of the origin's cross-borough trips and the count of the origin's trips to a resolved destination for that month, and the share equals one over the other — source: `docs/adr/0016-rates-are-rebuilt-from-summed-numerators-and-denominators.md`
- [ ] `R-06` A trip whose destination is an unresolved zone is neither cross-borough nor in-borough, and is reported in the `unresolved` group — accept when the quarter's cross-borough rows sum to 11,249 and its in-borough rows to 83,474, the two disjoint, and the 1,000 billable trips touching an unresolved zone sit only in rows with `unresolved` as origin or destination — source: answer to the share-population question; `docs/adr/0012-unresolved-zones-are-retained-and-flagged.md`
- [ ] `R-07` EWR is left out of the table on both sides, and no trip touching it is counted — accept when no row has EWR as origin or destination and the relation's `sum(trip_count)` is short of the window's 95,958 billable trips by exactly the 235 that touch EWR — source: answer to the EWR question
- [ ] `R-08` No 25-trip floor is applied — accept when the thinnest populated rows survive (for example Bronx → Brooklyn in January with 11 trips) and no `having` clause or threshold removes a pair — source: answer to the floor question; `docs/adr/0018-borough-flows-publish-every-pair-with-unresolved-in-its-own-group.md`
- [ ] `R-09` The table is a boundary relation with its properties entry, data tests, ODCS contract and semantic-layer mapping, and its docs state the rule it follows — accept when the build and its data tests pass in the sandbox, the contract check passes, the semantic-model validation passes, and every count, share and exclusion claimed in the description matches the built relation — source: `repo-map.json` layer roles; `docs/adr/0018-borough-flows-publish-every-pair-with-unresolved-in-its-own-group.md`

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain of the new agg model | One row per month × origin borough × destination borough | request |
| Period boundary | Calendar months January, February and March 2024, from `pickup_datetime` inside the reporting window (`report_start` 2024-01-01, `report_end` 2024-04-01) | request; `transformation/dbt_project.yml` |
| Edge periods | `not applicable`: every day of all three months is present in the window (31, 29 and 31 day-distinct dates), so no month is cut short | derived, `core.fct_trip` |
| Population | Billable trips inside the reporting window, per ADR 0003: "A trip is **billable** when its total amount is positive… Gold marts that report revenue or flows apply it, inside the reporting window" | `docs/adr/0003-billable-trip-definition-and-where-it-applies.md` |
| `trip_count` definition | Billable trips, counted once per trip at the pair its origin and destination boroughs name | request; ADR 0003 |
| Revenue definition | Billable revenue: the summed `total_amount` of those trips, the canonical `billable_revenue` measure | `logical-model/nyc_taxi_analytics.ossie.yaml` |
| Revenue NULL handling | `not applicable`: `total_amount` is never null in the window (0 of 95,958 billable trips), and a pair with no trips carries 0 | derived, `core.fct_trip` |
| Empty pairs | Emitted with `trip_count` 0 and `revenue` 0 rather than omitted: "Full cross product, zero-trip pairs carry 0" | answer to the matrix-shape question |
| Share shape | Carried on each row of its origin's month, with its numerator and denominator beside it | answer to the share-shape question |
| Share definition | The origin borough's cross-borough trips over its trips to a resolved destination, as summed trips rather than an average of pairs | answer to the share-population question; ADR 0016 |
| Cross-borough definition | Starts in one city borough and ends in another; a trip to an unresolved destination is neither | answer to the share-population question; `docs/adr/0018-borough-flows-publish-every-pair-with-unresolved-in-its-own-group.md` |
| Unresolved members | One `unresolved` group covering both the "Unknown" and "N/A" zones, on both sides | answer to the unresolved-group question; ADR 0012 |
| EWR | Excluded from the table on both sides; not one of the city's boroughs | answer to the EWR question; ADR 0018 |
| Published-pair threshold | None: ADR 0017's 25-trip floor stays with the zone-grain matrix and does not apply at borough grain | answer to the floor question; ADR 0018 |
| Coverage of the revenue measure | `not applicable` as a count-beside-measure question: `trip_count` already stands beside `revenue` on every row, and revenue is present whenever a trip is | derived; `core.fct_trip` |
| Reuse | Build on `fct_trip` with `dim_zone` joined twice, not on `agg_od_flow_matrix`: rolling that model up would inherit its 25-trip floor and contradict R-08, and it carries no unresolved or EWR-free population | derived; `transformation/models/marts/agg/agg_od_flow_matrix.sql` |
| Unmatched and null keys | Keep every row: a null zone key groups as `unresolved` rather than dropping the trip. No row in this window is affected (0 null zone keys), and the left join keeps it true if one appears | `docs/adr/0015-unmatched-dimension-keys-stay-null.md`; ADR 0012 |
| Zone version | Each trip reads the zone version in force on its pickup date, through its own zone surrogate key; the borough is not taken from the zone's current version | request; `CONTEXT.md`; ADR 0009 |
| Extended scope | `not applicable`: no schedule is requested, so `kinds:` stays `[transformation]` | playbook |

## Out of scope

- `agg_od_flow_matrix` and its 25-trip floor: unchanged, still the zone-grain matrix under ADR 0017.
- `fct_trip`, `dim_zone` and every other published model: read only, no column added, removed or retyped.
- The reporting window in `dbt_project.yml`: unchanged.
- No zone-grain, daypart, service-type or payment-method split of the flows.
- No schedule or orchestration item.

## Open questions

None. Three things the answers do not settle are recorded for design, not for you:

- the model's name and relation name in `agg`, and its materialisation;
- whether the share is stored as a percentage or a fraction, and the column names;
- whether the two counts beside the share are exposed as columns or only implied by the rows. R-05 asks for them, so design records them.

## Approvals
- 2026-11-24T14:13:23Z — requirement approved — "Approve the Requirement and start the design" — d97f630
- 2026-11-24T14:22:01Z — design approved — "Approve the design but do not plan yet" — 54198a5
- 2026-11-24T14:53:19Z — ship approved — "Approve shipping an intent PR" — e213fb9
