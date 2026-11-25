---
kinds: [transformation]
---

# Requirement: Zone revenue report from operations figures 4

## Ask

Ravi Menon, who owns the finance reports, asked: Finance reads the daily zone revenue report every morning, and Operations keeps its own daily figures by zone in the `agg` schema, so two builds pay for answers that should be the same. Build the report from the operations figures so there is one source, and change no number in the report. Acceptance is Finance's own check on Q1 2024: 95,958 trips and 2,629,185.82 revenue in total, and 4,120 trips and 337,711.05 revenue for JFK Airport.

The report is `finance.mart_daily_zone_revenue`, read every morning by Finance. The operations figures are `agg.agg_trip_zone_daily`, one row per pickup zone and trip date.

The two do not agree today, and the reason is the population, not the grain. The report applies the billable rule ([ADR 0003](../../docs/adr/0003-billable-trip-definition-and-where-it-applies.md)); the aggregate counts every trip in the window:

| Source | Q1 trips | Q1 revenue | JFK trips | JFK revenue |
| --- | --- | --- | --- | --- |
| `finance.mart_daily_zone_revenue` | 95,958 | 2,629,185.82 | 4,120 | 337,711.05 |
| `agg.agg_trip_zone_daily` | 97,184 | 2,597,120.92 | 4,261 | 329,766.06 |

The aggregate carries no billable measure at all, so it cannot answer the report's question as it stands.

## Requirements

- [ ] `R-01` `agg.agg_trip_zone_daily` carries the billable population beside the all-trip figures it already publishes: a billable trip count and billable fare, tip, surcharge, toll and total revenue — accept when the six columns exist on the built relation, the six equal a recomputation from `core.fct_trip` filtered by `is_billable` and the reporting window on every one of its rows, and its existing `trip_count` and `total_revenue` still total 97,184 and 2,597,120.92 — source: user answer (billable population carried additively)
- [ ] `R-02` `mart_daily_zone_revenue` is built from `agg.agg_trip_zone_daily` and from no other revenue source — accept when the compiled model reads `agg_trip_zone_daily` for every measure it publishes and `core.fct_trip` appears nowhere in its compiled SQL — source: request
- [ ] `R-03` No number in the report changes — accept when the rebuilt report returns 95,958 trips and 2,629,185.82 revenue for Q1 2024, 4,120 trips and 337,711.05 revenue for JFK Airport (zone 132), and every one of its rows matches the pre-change report cell for cell on `trip_count`, `fare_revenue`, `tip_revenue`, `surcharge_revenue`, `toll_revenue` and `total_revenue` — source: request (Finance's acceptance check)
- [ ] `R-04` The report keeps its shape — accept when the rebuilt report has 7,961 rows, 261 pickup zones and 91 trip dates, the same set of `(trip_date, pickup_location_id)` pairs as before, and its distinct `zone_name`, `borough` and `reporting_region` values are unchanged — source: user answer (zone-days with no billable trip stay omitted)
- [ ] `R-05` No other consumer of the operations figures sees a changed number — accept when `agg.agg_trip_zone_daily` keeps all 14 of its existing columns with their current types and meanings, and every existing test on it that passes at the baseline still passes — source: user answer (billable population carried additively)
- [ ] `R-06` The change carries its contracts and documentation — accept when `agg_trip_zone_daily`'s contract moves at the minor level for the six added properties and passes its check, `mart_daily_zone_revenue`'s contract still describes the relation it builds, the semantic model's binding of both relations still holds, and no description states a meaning the built relation contradicts — source: repository (`contracts/agg/agg_trip_zone_daily.odcs.yaml`, `contracts/finance/mart_daily_zone_revenue.odcs.yaml`, `logical-model/nyc_taxi_analytics.ossie.yaml`)

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain of the report | One row per pickup zone and trip date, the grain `agg_trip_zone_daily` already carries — zone natural key and `pickup_date`, inside the reporting window `report_start` 2024-01-01 to `report_end` 2024-04-01 | request; existing `agg_trip_zone_daily`; `transformation/dbt_project.yml` |
| Edge periods | not applicable: the report is daily, not a rollup to a period, and the window it reads is whole — `fct_trip` spans exactly 2024-01-01 to 2024-03-31, so no day of the window is cut short by the loaded data | queried: `core.fct_trip` min/max `pickup_datetime` |
| Population of the report | Billable trips only, inside the reporting window ([ADR 0003](../../docs/adr/0003-billable-trip-definition-and-where-it-applies.md), [ADR 0018](../../docs/adr/0018-the-daily-zone-revenue-report-publishes-the-billable-population.md)) | ADR 0003; request (numbers must not change) |
| How the billable population is carried | Additive billable measures on `agg.agg_trip_zone_daily`, beside its existing all-trip ones; its `trip_count` and `total_revenue` keep their all-trip meaning ([ADR 0018](../../docs/adr/0018-the-daily-zone-revenue-report-publishes-the-billable-population.md)) | user answer |
| Zone-days with no qualifying rows | Omitted from the report, never emitted as zero rows: a zone-day appears only when it carries at least one billable trip. 36 zone-days of the aggregate carry only non-billable trips, so the report has 7,961 rows against the aggregate's 7,997 | user answer |
| NULLs in the reported measures | None to handle: `total_amount`, `fare_amount`, `tip_amount`, `total_surcharges` and `tolls_amount` are non-null on all 97,184 in-window trips, so the billable sums carry no null and behave identically whichever way a null would be treated | queried: `core.fct_trip` over the window |
| Coverage | Publish the count beside the measures: the report already carries `trip_count` on every row, and it becomes the billable count, which is the count of rows that carry the revenue | playbook default |
| Reuse | Build on the published aggregate rather than the fact: `agg_trip_zone_daily` already serves exactly the report's grain, which is the source the request names | request; existing `agg_trip_zone_daily` |
| Unmatched and null keys | Keep every row: no key is dropped today — `fct_trip` has no null `pickup_zone_key` in the window, the aggregate has no null `pickup_location_id`, `zone_name` or `borough_name`, and the report's 7,961 rows have no null `reporting_region`. The dimension attributes the report shows are identical between the as-of and current zone versions on every zone in the window | queried: `core.fct_trip`, `agg.agg_trip_zone_daily`, `core.dim_zone` |
| Extended scope | Not a question: no schedule changes, so `orchestration` is not in `kinds:`. The contract and semantic-model updates stay inside `transformation` | playbook |

## Design pending

Recorded for `designing`, never asked here:

- The report publishes `reporting_region`, which `agg_trip_zone_daily` does not carry. Whether to add it to the aggregate, so the report reads one relation, or to keep the join to `core.dim_zone` for it. The values are identical either way on the current data.
- Whether `agg_trip_zone_daily` keeps one row per zone-day for a day with no trips at all — today it emits a row only for a zone-day that has trips, and the report must keep omitting the zero-billable ones.
- Materialisation and the placement of the six new columns in the aggregate's contract and properties file.

## Out of scope

- `finance.mart_monthly_service_summary` and `finance.mart_revenue_component_bridge` keep reading `fct_trip`; the request names the daily zone report only.
- `agg.agg_trip_zone_daypart_dow` and every other aggregate in the `agg` schema stay as they are; the request names `agg_trip_zone_daily` as the operations figure.
- `core.fct_trip`, `core.dim_zone` and every model upstream of the aggregate: no column, filter or value changes there.
- The report's own published shape: no column is added, removed, renamed or retyped, so its contract does not move major.

## Open questions

None: both material branches were answered before drafting.

## Approvals

