---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Monthly borough-to-borough flow: billable trips and their revenue for every origin borough and destination borough in each month of the reporting window, with each origin borough's cross-borough trips and share carried on its rows.

## Grain

One row per (trip month, origin borough, destination borough) that holds at least one billable trip inside the reporting window. The month is the calendar month of the trip's pickup date, as a `DATE` at its first day.

Alternatives: the complete borough cross product with zero rows, so every cell exists whether or not it has traffic — rejected by the user's answer, because the published trip count already tells a thin cell from a missing one, and no other mart emits empty pairs.

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer, schema question of this intent, 2026-11-25.

## Decisions

- `D-01` Group by `trip_month` = `cast(date_trunc('month', f.pickup_date) as date)`, on the day the trip started (`CONTEXT.md`, Date). dbt's `date_trunc` over a `DATE` yields a timestamp, and the warehouse builds date columns as `DATE`; a month is therefore stored as its first day as a `DATE`, the type `dim_date.month_start_date` already carries. Source: R-01, `transformation/models/marts/core/dim_date.sql`.
- `D-02` The billable rule applies: rows are `fct_trip` trips with `is_billable` inside the reporting window, so the table's population closes against the fact's billable population. Source: R-02, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-03` No minimum-trip floor at this grain: every pair-month with a billable trip is published. Source: R-05, [ADR 0019](../../../adr/0019-the-25-trip-floor-governs-zone-pairs-not-borough-pairs.md).
- `D-04` Both boroughs are read from `dim_zone` through the trip's own zone surrogate keys (`pickup_zone_key`, `dropoff_zone_key`), so each trip keeps the zone version in force on its pickup date rather than the zone's current version. Source: R-01, [ADR 0009](../../../adr/0009-type-2-only-where-the-source-versions-history.md).
- `D-05` Every borough name the zone lookup carries is a group, the unplaceable ones (`Unknown`, `N/A`) and the out-of-city `EWR` included: no row is filtered on `is_unresolved_zone` and no name is remapped. Source: R-04, [ADR 0012](../../../adr/0012-unresolved-zones-are-retained-and-flagged.md), [ADR 0018](../../../adr/0018-a-trip-crosses-a-borough-line-when-its-destination-borough-differs.md).
- `D-06` Both zone joins are `LEFT` and a null borough is grouped under the sentinel `unresolved` rather than dropping the trip, following the convention `agg_weather_demand_daily` already sets: an unmatched zone key is a real trip (ADR 0015) that no borough rollup may lose. Source: R-02, [ADR 0015](../../../adr/0015-unmatched-dimension-keys-stay-null.md).
- `D-07` A trip is cross-borough when `origin_borough` and `dest_borough` differ as names, compared with `IS DISTINCT FROM` so a trip whose two boroughs are both null-derived compares as one row and never as an unknown. Source: R-04, [ADR 0018](../../../adr/0018-a-trip-crosses-a-borough-line-when-its-destination-borough-differs.md).
- `D-08` `cross_borough_trip_count` and `cross_borough_share` are properties of an origin borough and a month, so every row of that origin-month carries the same value, computed with a window over `(trip_month, origin_borough)`: the share's denominator is all of that origin's published trips in the month, the numerator its cross-borough trips. Summing either column across destinations double-counts and the column descriptions say so. Source: R-03, [ADR 0018](../../../adr/0018-a-trip-crosses-a-borough-line-when-its-destination-borough-differs.md).
- `D-09` The share is a ratio of one trip count to another, computed with the `safe_divide` macro so a zero denominator yields null instead of a division error, and published as a `DOUBLE` between 0 and 1 like the repository's other share columns. Source: R-03, `transformation/models/marts/agg/agg_trip_zone_daypart_dow.sql`.
- `D-10` A `table` in the `agg` schema with `contract: {enforced: true}` in its properties file, matching every other model in the folder; the column types the properties file declares are the ones the SQL casts to. No model in this repository sets `access:`, so none is added here. Source: R-06, `transformation/models/marts/agg/_agg.yml`.
- `D-11` The semantic layer routes the table as an aggregate logical source on the `trips` document (`LTS10_borough_flow_monthly`, `priority_group: 0`), binding `billable_trip_count` and `billable_revenue` with a `content_filter` for the billable rule and the reporting window. `cross_borough_trip_count` and `cross_borough_share` are not bound: they repeat the origin borough's total on every destination row, so a consumer grouping at any destination level would double-count them, and the compiler refuses the repeated-total escape a share's denominator needs; the source `note` says so. Source: R-06, S3c of the plugin's semantic modelling rules; the compiler's own answer at the Requirement's Verification.
- `D-12` The trip count column is named `billable_trip_count`, not `trip_count`. The semantic layer resolves a bound metric's description by physical column name, and the `trips` document already carries a `trip_count` field meaning "trips, billable or not": a column of that name holding billable trips only would publish a false description over it. The name states the population the column counts, and matches the metric it binds. Source: R-02, `logical-model/nyc_taxi_analytics.ossie.yaml` (`trips` field `trip_count`).

## Rejected

- The full borough cross product with zero-row cells: it would emit 192 rows for Q1 where 122 carry traffic, and an absent pair-month would stop being distinguishable from a pair-month the model lost.
- A 25-trip floor copied from `agg_od_flow_matrix`: it would withhold most of the matrix and make the share a filtered figure (ADR 0019).
- Counting only resolved NYC destinations as crossings: it would leave 1,137 Q1 trips outside both the numerator and the denominator (ADR 0018).
- Building on `agg_od_flow_matrix`: its zone-pair grain is below this one and its floor removes population, so a rollup of it cannot close against `fct_trip`.

## Consumers

Mobility Planning reporting to the city: the monthly borough matrix and each borough's crossing share. No dbt model reads it. The canonical model binds `billable_trip_count` and `billable_revenue` to it through a new aggregate logical source on the `trips` document; the two origin-level columns stay unbound because they repeat across destination rows.

## Logical Model

```yaml
documents:
  - path: logical-model/nyc_taxi_analytics.ossie.yaml
    datasets: {}
    metrics: {}
    logical_sources:
      LTS10_borough_flow_monthly: added
ontology:
  documents: []
  concepts: {}
  mappings: {}
```

The `trips` dataset entry itself does not change: the new aggregate logical source binds the two metrics that dataset already declares (`billable_trip_count`, `billable_revenue`), and no field is added to `trips`. No concept is added, retired or re-identified, so no ontology mapping moves.

## History

- 2026-11-25 — trips-and-revenue-by-borough — design record written — D-01 … D-10 — terms: none new (`Cross-borough trip` was added to `CONTEXT.md` with the Requirement)
