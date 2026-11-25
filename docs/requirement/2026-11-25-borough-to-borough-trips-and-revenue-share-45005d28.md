---
kinds: [transformation]
---

# Requirement: Borough-to-borough trips and revenue share

## Ask

Leila Haddad, Mobility Planning Lead, for a question the city put to her:

> "The city asked how much of our traffic crosses borough lines. For each month of Q1 2024, I need the trips and the revenue from each borough to each borough, and the share of trips that leave the borough they started in."

She will read the result as a table per month: one row per origin borough and destination borough, and beside each borough the share of its traffic that crosses a borough line.

## Requirements

- [ ] `R-01` A new boundary table publishes, for each month of Q1 2024, every origin-borough × destination-borough pair with at least 25 billable trips in that month — accept when the built relation carries exactly 56 pair rows over the reporting window (18 in January, 19 in February, 19 in March), every pair row has `trip_count >= 25`, and the smallest pair has 26 — source: request; user answer on the floor
- [ ] `R-02` Each pair row's revenue is the sum of the trip totals over its billable trips, counting no-charge and dispute payments — accept when the pair rows' revenue sums to 2,609,219.76 and `fct_trip`'s Q1 billable revenue (2,629,185.82) exceeds it by exactly 19,966.06, the revenue of the 66 pairs the floor removes — source: user answer on the revenue population; ADR 0003
- [ ] `R-03` Every row carries its origin borough-month's crossing share: all of that borough's billable departures as the denominator and every crossing billable trip as the numerator, whether or not the pair is published — accept when the recomputed shares are Bronx 59.26% / 65.06% / 50.99%, Brooklyn 37.54% / 40.68% / 43.36%, Manhattan 6.01% / 5.78% / 5.97%, Queens 71.54% / 73.10% / 73.96% for January / February / March, the numerators sum to 12,214 and the denominators to 95,958 — source: user answers on the share's basis and numerator
- [ ] `R-04` An origin borough-month with no qualifying pair still carries a row reading its crossing share, with zero trips and zero revenue — accept when the relation carries exactly 9 such rows, one each for EWR, N/A and Staten Island in every month, and EWR reads 0.00%, N/A 30.77%, Staten Island 45.45% in January — source: user answer on boroughs with no qualifying pair
- [ ] `R-05` The grain is one row per month, origin borough and destination borough — accept when a uniqueness test over those three columns passes and the relation has exactly 65 rows (56 pair rows plus 9 no-pair rows) — source: request; user answers
- [ ] `R-06` Unresolved zones stay in the rollup as their own borough groups, not filtered or remapped — accept when every origin and destination borough value is one of the 8 borough names on `dim_zone`, and the 14 published pair rows touching N/A or Unknown keep their trips and revenue — source: ADR 0012
- [ ] `R-07` Every Q1 2024 billable trip is accounted for — accept when the pair rows' 95,705 trips plus the 253 trips of the floored-out pairs equal `fct_trip`'s 95,958, and 2,609,219.76 plus 19,966.06 equals 2,629,185.82 — source: ADR 0017's recorded partiality, recomputed for this surface
- [ ] `R-08` The table reports exactly three calendar months, none of them cut short — accept when the relation's months are 2024-01, 2024-02 and 2024-03 and `fct_trip` holds trips on all 31, 29 and 31 calendar days of them — source: derived from `fct_trip` (`min(pickup_datetime)` 2024-01-01 00:05:25, `max` 2024-03-31 23:56:17)

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain | One row per calendar month × origin borough × destination borough, plus one row per origin borough-month that has no qualifying pair | user answer; request |
| Edge periods | Not applicable: the data window covers all three Q1 2024 months whole (trips on all 31, 29 and 31 calendar days), so no month is cut short and no completeness mark is needed | derived from `fct_trip` |
| Population — billable only | "A new revenue or flow mart applies the rule" — billable trips only, inside the reporting window | ADR 0003 |
| Population — floor of a published borough pair | At least 25 billable trips in that month; the same floor ADR 0017 sets for a zone pair, applied to a borough pair at month grain | user answer |
| Population — revenue | Sum of `total_amount` over the pair's billable trips, including no-charge and dispute payments; those payments are not excluded from billable revenue | user answer; ADR 0013 |
| Population — crossing share numerator | Every crossing billable trip of the borough-month, including trips whose pair falls under the floor (12,214 against the 12,023 inside published pairs) | user answer |
| Population — crossing share denominator | Every billable trip departing the borough in that month (95,958 over the quarter) | user answer |
| Metric — zero denominator | Null, never zero, through `safe_divide`; with a row published per origin borough-month the denominator is positive on every row | ADR 0016 |
| Coverage | The pair's trip count is published beside its revenue, and every billable trip carries a total (0 null and 0 zero among the 95,958), so the count is the coverage | playbook default |
| Reuse | No published model serves origin-borough × destination-borough (`agg_od_flow_matrix` stops at zone pairs, `agg_trip_zone_daily` and `agg_trip_zone_daypart_dow` carry no destination borough), so build from `fct_trip` with `dim_zone` joined twice, as `agg_od_flow_matrix` does | repository |
| Unmatched and null keys | Keep every row: no trip has a null zone key (0 pickup, 0 dropoff), and unresolved zones remain their own borough groups rather than being dropped, remapped or filtered | ADR 0012; derived from `fct_trip` |
| Extended scope | Not applicable: no schedule is requested. This new boundary relation's semantic-model, ontology and data-contract work is carried by the design records and Plan tasks, not by another kind | playbook |

## Out of scope

- `agg_od_flow_matrix` and ADR 0017's floor for zone pairs: unchanged. This intent adds a borough-grain surface and does not alter, retune or retire the zone-pair matrix.
- Every other published model (`fct_trip`, `mart_daily_zone_revenue`, `mart_monthly_service_summary`, `agg_trip_zone_daily`, `agg_trip_zone_daypart_dow`, the ops marts): unchanged.
- No ingestion, no new source, no schedule, and no change to the `report_start` / `report_end` reporting window.
- Months outside Q1 2024.

## Open questions

None. How the no-pair origin borough-month is represented (a null destination borough or a second relation) and the column names are design questions, recorded as pending for design.

## Approvals
- 2026-11-25T03:53:35Z — requirement approved — "Approve — continue to design" — ad6ef77
- 2026-11-25T04:17:34Z — design approved — "Approve — continue to plan" — 980930d
- 2026-11-25T06:04:33Z — ship approved — "Approve — open the pull request" — 175df0d
