---
artifacts: [agg_trip_zone_daily]
---

# agg_trip_zone_daily

Daily zone demand with period-over-period context. The window functions are the point: a raw count answers "how many", the lag and rolling average answer "is that normal".

## Grain

One row per pickup date, pickup location and the zone attributes carried beside them (`zone_name`, `borough_name`, `reporting_region`). The billable measures are added at this grain, not a finer one: a billable-only table would be a second model at the row grain the finance report already reads, which is the duplication this change exists to remove.

## Schema

- `transformation/models/marts/agg`: `agg` (default). Source: user answer, 2026-11-24.

## Decisions

- `D-01` Add the billable measures and `reporting_region` as new columns at the existing grain, and change no existing column. The operations aggregate keeps its all-trip `trip_count` and `total_revenue` and everything else it publishes, so its other readers see the same values. Source: R-05, R-06, user answer "No. Add new columns only."
- `D-02` Compute the billable measures in the same scan that computes the all-trip measures, as conditional aggregates over `fct_trip.is_billable` (`count(*) filter (where f.is_billable)`, `sum(...) filter (where f.is_billable)`), never by a second read of `fct_trip` and never by filtering the CTE. One scan means the billable and all-trip figures on a row cannot come from different populations, and the billable verdict stays the single one `int_trip_quality_flags` computes. Source: R-05; `transformation/models/intermediate/int_trip_quality_flags.sql`.
- `D-03` A zone-day with traffic but no billable trip carries `billable_trip_count` 0 and NULL in each of `billable_revenue`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue` and `billable_toll_revenue`. `sum` over an empty set already returns NULL, so no `coalesce` is written: the absence of billable revenue stays distinguishable from a billable trip that genuinely earned nothing. Source: R-07, user answer.
- `D-04` The five window columns stay computed over the same daily CTE from the same all-trip `trip_count` and `total_revenue`, in the same window frame. The billable columns enter no window function, so every period-over-period figure keeps the value it has today. Source: R-06.
- `D-05` `reporting_region` joins the `group by` beside the zone attributes already grouped on, read from the `dim_zone` row the model already joins on `zone_key`. It is a carried attribute, not a new join, and the as-of resolution stays the one the rest of the row uses. Source: R-05, user answer.
- `D-06` Keep the model's materialisation (`table`) and its enforced contract, and declare each new column with its type there, so the relation's shape is checked at build rather than discovered by a consumer. Source: R-05; `transformation/models/marts/agg/_agg.yml`.

## Rejected

- A second, billable-only aggregate beside this one — two models at one grain is the duplication the request exists to remove, and two builds drift.
- Filtering the CTE to billable trips — it would destroy the all-trip columns this model publishes for the operations readers.

## Logical Model

```yaml
documents:
  logical-model/nyc_taxi_analytics.ossie.yaml:
    datasets: {}
    logical_sources:
      LTS2_zone_day_agg: changed
    metrics: {}
ontology:
  documents:
    ontology/nyc_taxi.ontology.yaml: {}
    ontology/nyc_taxi_analytics.mapping.yaml: {}
  concepts: {}
  mappings: {}
```

`LTS2_zone_day_agg` changes because the two billable measures join its `column_map`: `billable_trip_count` and `billable_revenue` already exist in the document (both aggregate over `fct_trip` with the billable filter), so no metric is added, and its `note` loses the refusal of them. Its `content_filter` already excludes rows with a null pickup zone key, and a zone-day whose billable measures are null sums to zero in the aggregate, which is what the detail side computes. `reporting_region` stays unbound: it is an attribute of the Geography `zone` level the source already claims, reached through the zone relationship, and binding it would declare no metric. The ontology's mapping is expressed over the trips document and reaches no column this change adds, so no concept or mapping moves.

## Consumers

- `finance.mart_daily_zone_revenue` (this intent).
- The semantic layer's `LTS2_zone_day_agg`, and through it `assert_semantic_content_holds` and `assert_semantic_levels_hold`.
- `contracts/agg/agg_trip_zone_daily.odcs.yaml`, which the built relation must match.
- Operations readers of the all-trip figures, inside and outside this repository.

## History

- 2026-11-24 — ss-zone-revenue — design record written; billable measures and `reporting_region` added at the existing grain so the finance report can be built from this model — D-01 … D-06 — terms: none new
