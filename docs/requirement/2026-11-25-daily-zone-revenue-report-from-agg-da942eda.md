---
kinds: [transformation]
---

# Requirement: Daily zone revenue report from agg

## Ask

Ravi Menon, who owns the finance reports, asks that the daily zone revenue report be built from the operations figures in the `agg` schema, "so that there is one source", on the stated premise that "we pay for two builds that should give the same answers". No number in the report may change.

Finance reads `finance.mart_daily_zone_revenue` every morning. Operations keeps `agg.agg_trip_zone_daily` in the `agg` schema. The request's acceptance check is Q1 2024: 95,958 trips and 2,629,185.82 revenue in total, and 4,120 trips and 337,711.05 revenue for JFK Airport.

**The premise does not hold today, and the check confirms it.** Measured on the Domain's DuckDB:

| Relation | Q1 2024 trips | Q1 2024 revenue | JFK trips | JFK revenue |
| --- | --- | --- | --- | --- |
| `finance.mart_daily_zone_revenue` | 95,958 | 2,629,185.82 | 4,120 | 337,711.05 |
| `agg.agg_trip_zone_daily` | 97,184 | 2,597,120.92 | 4,261 | 329,766.06 |

The reported figures match the finance report exactly and differ from agg, because the report filters to billable trips ([ADR 0003](../adr/0003-billable-trip-definition-and-where-it-applies.md)) while `agg_trip_zone_daily` counts every trip. `agg_trip_zone_daily` also publishes only `total_revenue`, where the report publishes four further revenue components and `reporting_region`.

The user resolved the conflict by choosing to **extend `agg_trip_zone_daily` additively** with billable-only measures and `reporting_region`, then build the report on it: one build serves both, Operations' existing all-trip figures are untouched, and every number in Finance's report is preserved.

## Requirements

- [ ] `R-01` `agg_trip_zone_daily` publishes billable-only revenue measures and `reporting_region` beside its existing all-trip measures — accept when the built relation carries `billable_trip_count`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue`, `billable_total_revenue` and `reporting_region`, and its row count is unchanged at 7,997 — source: user answer (`opt-0`), verified baseline row count
- [ ] `R-02` `mart_daily_zone_revenue` reads `agg_trip_zone_daily` and nothing else — accept when the compiled model references no other dbt model or source — source: request ("one source"), user answer (`opt-0`)
- [ ] `R-03` The report's published shape is unchanged: the same 11 columns, in the same names and logical types, at the same grain — accept when a column-by-column comparison of the rebuilt relation against the pre-change relation reports no added, removed or retyped column — source: request ("no number … may change"), existing `mart_daily_zone_revenue` properties and contract
- [ ] `R-04` Every value in the report is unchanged: the same 7,961 `(trip_date, pickup_location_id)` rows, none added and none removed, with `trip_count` and all five revenue columns **exactly** equal to the pre-change values — accept when a full outer join of the rebuilt and pre-change relations reports 0 added rows, 0 removed rows and 0 rows differing in any of the six measures under `IS DISTINCT FROM`. Exact equality is required, not a tolerance: agg and the report group by the identical keys, so each measure is the same sum over the same rows and no re-aggregation or reordering occurs. An independent same-grain recomputation against today's relation already returns 0 differences in all six measures — source: request ("No number in our report may change"); measured recomputation
- [ ] `R-05` The acceptance check passes on the rebuilt report — accept when the rebuilt report returns 95,958 trips and 2,629,185.82 revenue for Q1 2024, and 4,120 trips and 337,711.05 revenue for JFK Airport — source: request (Ravi Menon's check figures)
- [ ] `R-06` Zone-days with no billable trip are omitted from the report, as they are today — accept when the rebuilt report has 7,961 rows, 0 rows with `trip_count = 0`, and `agg_trip_zone_daily` still holds its 36 such zone-days — source: user answer (`opt-0`), measured baseline
- [ ] `R-07` `agg_trip_zone_daily`'s existing all-trip columns keep their values and meaning — accept when `trip_count`, `total_revenue`, `total_miles`, `attributed_driver_count`, `pickup_date_key`, `pickup_date`, `pickup_location_id`, `zone_name`, `borough_name` and the five window columns match the pre-change relation for all 7,997 rows — source: `agg_trip_zone_daily`'s published contract and its consumers
- [ ] `R-08` The two relations' contracts follow the change — accept when `agg_trip_zone_daily`'s ODCS contract moves by a minor version for the added columns and passes `check`/`diff`, and `mart_daily_zone_revenue`'s contract keeps its shape and version — source: `.agents/skills/data-contract` version rule (added properties: minor; shape unchanged: none)
- [ ] `R-09` Descriptions the change makes false are corrected — accept when the report's `trip_count` description states it is the billable count (it currently reads "Trips, billable or not" while the model filters `is_billable`), and `_finance.yml`'s "the billable rule is applied here and nowhere upstream" no longer claims the rule is absent upstream — source: `transformation/models/marts/finance/mart_daily_zone_revenue.sql`, `transformation/models/marts/finance/_finance.yml`, `logical-model/nyc_taxi_analytics.ossie.yaml` LTS7 note

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Sourcing: one build or two | Extend `agg_trip_zone_daily` additively with billable-only measures and `reporting_region`; build the report on it | user answer (`opt-0`); required because agg's all-trip measures give 97,184 / 2,597,120.92 and cannot preserve the check figures |
| Grain of `mart_daily_zone_revenue` | One row per pickup zone and trip date (unchanged) | existing model and its design record |
| Grain of `agg_trip_zone_daily` | `pickup_date` × `pickup_location_id` (unchanged; 7,997 rows, 7,997 distinct) | existing model, `logical-model/` LTS2 content grain |
| Edge periods | Not applicable: the Q1 window is fully covered — all 91 days of 2024-01-01..2024-03-31 are present and 2024-01-01, 2024-02-29 and 2024-03-31 each carry all 24 hours, so no period is cut short | measured on `core.fct_trip` |
| Population of the report's measures | Billable trips only, inside the reporting window: "A trip is **billable** when its total amount is positive … Gold marts that report revenue or flows apply it, inside the reporting window" | [ADR 0003](../adr/0003-billable-trip-definition-and-where-it-applies.md); [CONTEXT.md](../../CONTEXT.md) "Billable trip" |
| Population of agg's new measures | The same billable rule, applied to the new `billable_*` columns only; agg's existing all-trip columns keep their all-trip population. ADR 0003 does not name `agg_trip_zone_daily` in either of its lists, so this requirement is what places the new columns under the rule | user answer (`opt-0`); [ADR 0003](../adr/0003-billable-trip-definition-and-where-it-applies.md) "Consequences": "A new revenue or flow mart applies the rule" |
| Precedent in `agg` for the new columns | `billable_trip_count` beside an all-trip `trip_count` already exists in `agg_trip_zone_daypart_dow` (5,424 of its 5,458 rows carry billable trips). Billable **revenue** columns are new to the `agg` layer: the only billable revenue today is `mart_daily_zone_revenue`, which produces it by filtering rather than by parallel columns. There is therefore no in-layer precedent for the new revenue columns, so `R-04`'s exactness is proven by measurement, not assumed | measured on `agg.agg_trip_zone_daypart_dow` and the finance marts |
| NULLs in the measures | Not applicable as an aggregate choice: none of the five revenue measures is null on any of the 95,958 billable Q1 trips (0 nulls in each) | measured on `core.fct_trip`; default does not arise |
| A zone-day with no billable trip | Omitted from the report; retained in `agg_trip_zone_daily` with `billable_trip_count = 0` | user answer (`opt-0`) |
| Coverage beside the billable measures | Publish `billable_trip_count` beside the billable revenue columns, because 36 of agg's 7,997 rows carry no billable trip | playbook default (Coverage); measured baseline |
| Reuse | Build on the published `agg_trip_zone_daily` rather than rebuilding from `fct_trip` | playbook default (Reuse); request |
| Unmatched and null keys | Keep every row: the rebuilt report performs no join, taking zone attributes from agg; agg's existing inner join to `dim_zone` is unchanged. No billable Q1 trip has a null `pickup_zone_key` (0) | playbook default; measured on `core.fct_trip` |
| Zone attributes across SCD2 versions | Grouping by `reporting_region` does not change agg's row count: each `zone_natural_key` has exactly one `zone_name`, `borough_name` and `reporting_region` across its versions | measured on `core.dim_zone` (0 zones vary) |
| `agg_trip_zone_daily` contract version | Minor bump (added properties) | `.agents/skills/data-contract` "Added: minor" |
| `mart_daily_zone_revenue` contract version | Unchanged; no property added, removed or retyped | `.agents/skills/data-contract` |
| ADR 0003's list of revenue marts | Requires amendment: ADR 0003 enumerates four marts that apply the billable rule, and `agg_trip_zone_daily` will now publish billable-measured revenue columns. The rule itself is honoured, not contradicted | [ADR 0003](../adr/0003-billable-trip-definition-and-where-it-applies.md); user answer (`opt-0`) |
| Extended scope | Not a question: the contract and `logical-model/` deliverables stay in `transformation` | `.agents/skills` — `transformation` playbook |

## Out of scope

- `agg_od_flow_matrix`, `agg_trip_zone_daypart_dow`, `agg_trip_band_profile`, `agg_weather_demand_daily` and every other `agg` relation: untouched.
- `mart_monthly_service_summary` and `mart_revenue_component_bridge`: untouched.
- `core.fct_trip`, `core.dim_zone`, the intermediate models, the macros and the reporting window (`report_start` / `report_end`): untouched.
- The ingestion pipelines, the orchestration scripts and the simulated sources: untouched.
- ADR 0003's own text: amended only if the user approves this requirement; not written at this stage.

## Open questions

None. Both branches that change rows or values were put to the user and answered: the sourcing conflict (`opt-0`) and the treatment of zone-days with no billable trip (`opt-0`).

## Approvals
- 2026-11-25T07:20:56Z — requirement approved — "Approve, continue to design" — 99e40b7
