---
kinds: [transformation]
---

# Requirement: Daily zone revenue from operations figures

## Ask

Ravi Menon, who owns the finance reports, reports that Finance reads a daily zone
revenue report every morning while Operations keeps its own daily figures by zone,
so the business pays for two builds that should give the same answers. He asks for
the finance report to be built from the operations figures, "so that there is one
source", with no number in the report changing. His acceptance check is Q1 2024:
9,604,511 trips and 263,480,834.99 revenue in total, and 416,460 trips and
33,881,378.28 revenue for JFK Airport.

Consumers: Finance (the morning report), and Operations (the zone×day build this
work consolidates onto).

### What the Domain's data shows

Read from the Domain warehouse at `1184020`, before any change:

| Relation | Grain | Population | Q1 trips | Q1 revenue | JFK trips | JFK revenue |
| --- | --- | --- | --- | --- | --- | --- |
| `finance.mart_daily_zone_revenue` | zone × day | billable, in window | 9,604,511 | 263,480,834.99 | 416,460 | 33,881,378.28 |
| `agg.agg_trip_zone_daily` | zone × day | all trips, in window | 9,722,336 | 260,487,920.62 | 429,806 | 33,140,983.67 |
| `ops_raw.trip_assignment` | trip | fleet-attributed only | 457,991 | 12,639,955.27 | 20,713 | 1,679,105.07 |

Ravi's four figures are exactly today's finance mart. The two relations are not two
builds of one answer: `agg_trip_zone_daily` counts every in-window trip and carries
no billable revenue at all, while the mart is billable-only under ADR 0003. The
operator's `trip_assignment` records cover 463,848 trips — the 4.8% of trips
Harbour Point ran — so building from them literally would drop 95% of the report.
Each of the three is a different population, and the request as written (one
source, no number changed) is satisfiable only by making one build carry both.

## Requirements

- [ ] `R-01` `agg.agg_trip_zone_daily` is the single zone×day build: `finance.mart_daily_zone_revenue` selects from it instead of from `fct_trip`, and neither relation is rebuilt from `fct_trip` for the same grain — accept when `mart_daily_zone_revenue`'s compiled SQL references `agg_trip_zone_daily` and no longer `fct_trip`, and both relations compile and build — source: request ("build our report from the operations figures, so that there is one source"), user answer on the source

- [ ] `R-02` Every number in `finance.mart_daily_zone_revenue` is unchanged: same grain (zone × day), same rows, same column set and types, and identical values — accept when, over the same window, the rebuilt relation returns exactly 20,770 rows with no duplicate (zone, day), joined against today's relation at `1184020` with zero rows on either side, zero differing `trip_count` and text values, and zero differing money values **rounded to the cent** (the precision the report publishes; DuckDB's parallel float sums are not reproducible to the last bit, so bit equality is not an available acceptance) — source: request ("No number in our report may change"), user answer on precision

- [ ] `R-03` Ravi's acceptance check passes on the rebuilt report: Q1 2024 totals and JFK Airport totals are exactly 9,604,511 trips, 263,480,834.99 revenue, 416,460 trips and 33,881,378.28 revenue — accept when a query over the rebuilt `mart_daily_zone_revenue` returns those four figures to the cent — source: request (acceptance check)

- [ ] `R-04` The agg's existing published numbers are unchanged: its all-trips `trip_count`, `total_revenue`, `total_miles` and `attributed_driver_count` keep their current values, and its window and derived columns (`prev_day_trip_count`, `same_day_last_week_trip_count`, `trip_count_7d_avg`, `revenue_28d_rolling`, `revenue_rank_that_day`) are unaffected — accept when the rebuilt `agg_trip_zone_daily` matches today's at `1184020` on those columns row for row, with the same 20,771 rows and 9,722,336 trip_count and 260,487,920.62 total_revenue — source: request scope, playbook `Reuse` (never rewrite a published model the request did not name silently)

- [ ] `R-05` `agg.agg_trip_zone_daily` publishes billable measures beside its all-trips ones, so the finance report can be built from it without re-deriving the rule: a count of billable trips and the revenue they carry — accept when the rebuilt relation carries both columns for every row, and summing the billable count and revenue over the window returns 9,604,511 and 263,480,834.99, with the rows excluded by the billable rule visible in the all-trips columns — source: request, [ADR 0003](../../adr/0003-billable-trip-definition-and-where-it-applies.md) (the rule stays in gold and is applied once)

- [ ] `R-06` A zone-day with trips but no billable trips publishes zero, not null, for both billable measures; because a billable trip always has a positive total, zero unambiguously means "no billable trips" — accept when the one such row in the window (2024-02-12, zone 175) reads 0 and 0, and no billable measure is null anywhere in the relation — source: user answer

- [ ] `R-07` The fare-component revenue the finance report carries (fare, tip, surcharge, toll, total) stays on the report at the same values, sourced from the consolidated build rather than re-aggregated in the mart — accept when those five columns match today's mart value for value, and the mart contains no aggregation of its own over `fct_trip` — source: request ("no number may change"), `R-01`

- [ ] `R-08` The relation's enforced dbt contract, its ODCS contract, the semantic-layer binding and the ontology mapping all still describe what is built, and no consumer of either relation is left reading a stale definition — accept when `dbt build` passes with the enforced contract, `odcs.py check` passes, `validating-semantic-model` and `validating-ontology` report no finding for the affected documents, and every design record naming either model states the new lineage — source: repository conventions

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Which build is the single source | `agg.agg_trip_zone_daily`, extended with billable measures; `finance.mart_daily_zone_revenue` becomes a selection from it | user answer |
| Grain of the consolidated build | One row per pickup zone and trip date (unchanged on both sides) | existing models, `agg_trip_zone_daily` and `mart_daily_zone_revenue` |
| Edge periods | Not applicable: the consolidated build is at day grain and the data covers every day of Q1 2024 (91 distinct pickup dates, 2024-01-01 to 2024-03-31), so no period is cut short by the window | data (query over `core.fct_trip`) |
| Population of the all-trips measures | Every in-window trip, resolved zone, as today | existing model `agg_trip_zone_daily` |
| Population of the billable measures | Billable trips in the reporting window, selected on `fct_trip.is_billable` | [ADR 0003](../../adr/0003-billable-trip-definition-and-where-it-applies.md): "Gold marts that report revenue or flows apply it, inside the reporting window" |
| Billable measures on a zone-day with no billable trips | 0 for both the count and the sum | user answer |
| Coverage of the billable measures | Not applicable: a billable trip's total is positive by definition, so the measure is present on every row it counts and no coverage column is owed; the all-trips `trip_count` is published beside it | [ADR 0003](../../adr/0003-billable-trip-definition-and-where-it-applies.md), data (0 null totals or components among in-window billable trips) |
| Null components in the billable sums | Not applicable: no in-window billable trip has a null fare, tip, surcharge or toll amount, and the sums match today's mart exactly | data (query over `core.fct_trip`) |
| Unmatched and null zone keys | Every row kept; the build joins `dim_zone` as it does today, and no in-window trip has a null or unmatched pickup zone key, so the join drops nothing | existing model `agg_trip_zone_daily`, data (0 null, 0 unmatched) |
| Reuse | Build on `agg.agg_trip_zone_daily` and make the mart read it; do not rebuild either from `fct_trip` twice | playbook default `Reuse`, user answer |
| What "no number changes" means for a float measure | Equal to the cent; bit-for-bit equality is not achievable because DuckDB's parallel float sums vary in the last bits on recomputation, including when the agg's own stored columns are recomputed from `fct_trip` | user answer |
| Extended scope | No schedule, no contract removal, no new source | playbook `Extended scope` |

## Out of scope

- `ops_raw.trip_assignment` and every model built from it. It stays the operator's
  own record of the 4.8% of trips Harbour Point ran, and is not the population of a
  city-wide revenue report.
- `finance.mart_monthly_service_summary`, `finance.mart_revenue_component_bridge`,
  `agg.agg_trip_zone_daypart_dow` and every other published relation the request
  did not name. They keep their current definitions and numbers.
- The billable rule itself (ADR 0003), the reporting window (ADR 0003), the zone
  versioning rule (ADR 0009) and the 25-trip floor (ADR 0017): no definition changes.
- Replacing or retiring the mart. Finance keeps the report at the same name and grain.

## Open questions

None.

## Approvals

- 2026-11-24T03:27:10Z — requirement approved — "approve and continue to design" — 05d1c09
