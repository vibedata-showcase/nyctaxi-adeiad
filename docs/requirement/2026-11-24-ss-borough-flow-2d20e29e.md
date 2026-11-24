---
kinds: [transformation]
---

# Requirement: SS · borough flow

## Ask

Leila Haddad, Mobility Planning Lead: "The city asked how much of our traffic crosses borough lines. For each month of Q1 2024, I need the trips and the revenue from each borough to each borough, and the share of trips that leave the borough they started in."

The consumer is Mobility Planning, answering a city request; the answer is a borough-by-borough matrix per month, read directly and through the semantic layer.

## Requirements

- [ ] `R-01` A new boundary table publishes one row per month × origin borough × destination borough for the billable trips of the reporting window (Q1 2024) — accept when a dbt test proves `(month, origin_borough, destination_borough)` unique and the relation returns the 24 populated (month, origin borough) groups over 3 months — source: request; `dbt_project.yml` `report_start`/`report_end`
- [ ] `R-02` Each pair row carries its trip count and its revenue — accept when a singular test recomputes the month totals from `core.fct_trip` and `core.dim_zone` and finds trips 29,985 / 30,017 / 35,956 and revenue 816,057.76 / 813,885.68 / 999,242.38 for January, February and March 2024 — source: request; answer (billable total amount)
- [ ] `R-03` The cross-borough share is published per origin borough per month, as the borough's trips that end in a different borough over all its trips, with numerator and denominator beside it — accept when a singular test recomputes the share from the published numerator and denominator with no row disagreeing, and an independent recomputation reproduces January 2024 Manhattan 6.01% and Queens 71.54% — source: answer (per origin borough); `docs/adr/0019-the-cross-borough-share-is-per-origin-borough.md`
- [ ] `R-04` No trip floor applies: every borough pair carrying a billable trip in the month is published, small pairs included — accept when the relation holds at least one row below 25 trips in each of the three months (22 / 21 / 23 such pairs observed) and its SQL carries no `HAVING` clause — source: answer; `docs/adr/0018-a-borough-flow-surface-has-no-trip-floor.md`
- [ ] `R-05` Every billable trip in the reporting window is counted exactly once, and unresolved boroughs form their own group rather than being dropped — accept when the month sums of the pair trip counts equal the star's billable trips per month (95,958 over the window) and the relation contains `Unknown`, `N/A` and `EWR` rows — source: answer; `docs/adr/0012-unresolved-zones-are-retained-and-flagged.md`
- [ ] `R-06` The table ships as a published boundary relation: dbt properties with an enforced contract, its design record, its Ossie document mapping and its ODCS contract — accept when the data and unit tests on the selection pass, the contract is `active` and `odcs check` passes, and the semantic-model and ontology gates report green — source: repository `repo-map.json` `layers.agg`, `artifact_paths`

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain of `agg_borough_flow_monthly` | One row per month × origin borough × destination borough | request ("each month", "from each borough to each borough"); borough is the zone dimension's attribute (`core.dim_zone.borough_name`) |
| Edge periods | Not applicable: no month is cut short — all 31, 29 and 31 days of January, February and March 2024 carry trips, so no incomplete-period mark applies anywhere | computed from `core.dim_date` and `core.fct_trip` |
| Population | Billable trips only, inside the reporting window: a revenue and flow mart applies the billable rule | `docs/adr/0003-billable-trip-definition-and-where-it-applies.md` |
| Revenue definition | `sum(total_amount)` of billable trips, including no-charge and dispute payments (January 2024: 9,454.34 of 816,057.76 across 421 trips) | user answer; `docs/adr/0013-no-charge-and-dispute-payments-are-not-excluded-by-the-billable-rule.md` leaves it to the metric |
| Cross-borough share basis | Per origin borough per month, numerator and denominator published beside it; not additive across boroughs | user answer; `docs/adr/0019-the-cross-borough-share-is-per-origin-borough.md` |
| NULLs entering the revenue aggregate | None: `total_amount` is non-null and positive on all 95,958 billable trips of the window, so `trip_count` is also the count of rows carrying revenue and serves as the coverage denominator; no separate coverage column | computed from `core.fct_trip` |
| Empty borough pairs | Omitted: a pair with no billable trip in a month has no row, and no zero rows are emitted | user answer |
| Thin-pair floor | None: ADR 0017's 25-trip floor applies to zone pairs, not to a borough surface | user answer; `docs/adr/0018-a-borough-flow-surface-has-no-trip-floor.md` |
| Reuse | Built from `core.fct_trip` joined twice to `core.dim_zone`; `agg.agg_od_flow_matrix` cannot be reused, because its floor drops 27,445 of the window's 95,958 billable trips (68,513 published) and a share over the residue would misstate crossings | derived from the floor answer; `docs/adr/0017-published-flows-have-a-25-trip-floor.md` |
| Unmatched and null keys | Left joins keep every trip; a trip whose zone key is null groups under a null borough instead of disappearing. No such row exists in Q1 2024 (0 null pickup and 0 null dropoff zone keys), so the choice is inert today and closure holds either way | `docs/adr/0015-unmatched-dimension-keys-stay-null.md`; playbook default (keep every row) |
| Deliverable kind | `model`: one new boundary dbt model in `transformation/models/marts/agg/` | request; `repo-map.json` `layers.agg` |

## Out of scope

- `core.fct_trip`, `agg.agg_od_flow_matrix`, `finance.mart_daily_zone_revenue` and every other published model: none is changed.
- Zone-pair grain, and the 25-trip floor of ADR 0017, which stays as it is.
- A schedule: no orchestration item is added by this intent.
- Borough-level attributes beyond the borough name (region, `is_nyc` flags) are not published on this surface.

## Open questions

None.

## Approvals
- 2026-11-24T15:18:45Z — requirement approved — "approve_stop" — 56cb6b7
