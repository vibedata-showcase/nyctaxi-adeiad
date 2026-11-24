---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Borough-to-borough flow for each month of the reporting window: the same zone dimension joined twice, once in each role, rolled from zone pairs up to borough pairs.

## Grain

One row per (month, origin borough, destination borough), the month being `month_start_date`. The grid is complete: every borough the zone lookup holds is an origin and a destination in every month of the window, and a pair-month with no billable trip is a row of zero trips and zero revenue (ADR 0018).

Rejected alternatives: one row per (month, origin borough) with a wide set of destination columns, which makes a new borough a schema change and defeats any query that does not know the full borough list; and one row per observed pair only, which cannot be told apart from a pair nobody checked and breaks the share's arithmetic.

## Schema

- `transformation/models/marts/agg/`: `agg` (`default`). Source: user answer at design; the folder's existing `+schema` in `dbt_project.yml`.

## Decisions

- `D-01` **Built from `fct_trip` and `dim_zone`, not from `agg_od_flow_matrix`.** The zone-pair matrix removes the thin pairs (ADR 0017) and carries the zone grain, so neither the borough cells nor the share's denominator survives it. This is the only published model at a coarser grain than the request, and reusing it would have required a different population. Source: R-01, R-06; ADR 0017; playbook `transformation` (`Reuse`).
- `D-02` **Billable, in-window trips only, through `fct_trip`.** A billable trip is one with a positive total (ADR 0003), and a revenue or flow mart applies the rule; the window comes from the `in_report_window` macro so it moves with the reporting window and never with a copy of the dates. Source: R-03; ADR 0003.
- `D-03` **Both zone roles come from `dim_zone` at the trip's own version.** The join is on the trip's resolved `pickup_zone_key` / `dropoff_zone_key`, not the zone's current version, so a re-designation does not move history (ADR 0009); a borough is read off the version in force on the trip's date. Source: ADR 0009; `fct_trip`'s role-playing keys.
- `D-04` **The borough axis is the eight values the zone lookup holds, and the unresolved group is flagged rather than disguised.** N/A and Unknown are real dimension rows (ADR 0012) and appear as origins and destinations like any other, so their traffic is visible rather than dropped; but each row also carries `origin_is_unresolved` and `dest_is_unresolved`, read from `dim_zone.is_unresolved_zone`, so a reader can tell the unplaced group apart from a borough instead of having to know its names. That is the flag-on-the-row, filter-in-the-consumer treatment ADR 0004 gives a quality verdict, and it is what makes the null share defensible: the cells are published, and the flag says why they are not part of a borough-to-borough rate. Source: R-02, R-05; ADR 0012; ADR 0004; user answer ("add flag columns (an unresolved origin flag and an unresolved destination flag)").
- `D-05` **The cross-borough share is a ratio of sums with a null on an empty or unresolved origin.** `cross_borough_share_pct` is `100 * cross_borough_trip_count / resolved_trip_count` through `safe_divide` (ADR 0016), so an unresolved origin, and any origin-month the data leaves empty, carries null rather than a measured zero. A trip counts as crossing only when both ends resolve to a borough and the two differ (ADR 0019). The basis counts beside that null follow `D-11`, not a zero. Source: R-04; ADR 0016; ADR 0019.
- `D-06` **The share's numerator and denominator ride on the row.** `cross_borough_trip_count` and `resolved_trip_count` are published beside the share so a reader can recompute it and see the basis, per the answer that rejected a bare percentage; both are origin-month values repeated across that origin's destination rows, described as such and never summed. Source: R-04; user answer ("the count of resolved-destination trips is published beside it").
- `D-07` **`is_cross_borough` marks the cell.** True when the row's origin and destination are both resolved and differ, following `agg_od_flow_matrix`'s `is_intra_borough`; it lets a consumer separate the diagonal and the unresolved cells from the crossings without re-deriving ADR 0019. Source: ADR 0019; `agg_od_flow_matrix`.
- `D-08` **A materialised table with an enforced contract**, like every other boundary model in the `agg` folder, and every output expression cast to its declared type because DuckDB does not coerce to a contract (dialect card, `## Type fidelity`). Source: repository `transformation/models/marts/agg/_agg.yml`; `duckdb_local` dialect card.
- `D-09` **The month axis comes from `dim_date`, not from the trips.** A month with no billable trip still publishes its grid, which a month axis taken from the fact could not. Source: R-02; `dim_zone`, `dim_date`.
- `D-10` **Output columns, fixed by this record.** `month_start_date` DATE, `month_name` VARCHAR, `calendar_year` INTEGER, `origin_borough` VARCHAR, `origin_is_unresolved` BOOLEAN, `dest_borough` VARCHAR, `dest_is_unresolved` BOOLEAN, `is_cross_borough` BOOLEAN, `trip_count` BIGINT, `total_revenue` DOUBLE, `resolved_trip_count` BIGINT, `cross_borough_trip_count` BIGINT, `cross_borough_share_pct` DOUBLE. Source: R-01 to R-07; user answer on the flags.
- `D-11` **`resolved_trip_count` is computed for every origin, unresolved ones included; `cross_borough_trip_count` stays zero on an unresolved origin — supersedes the "empty origin" wording of `D-05` and the population `D-06` left implicit.** The two counts follow different rules, because they answer different questions. `resolved_trip_count` is a basis count: the origin's trips whose *destination* resolves to a borough, which an unresolved pickup satisfies normally, so it is computed for every origin and publishable beside the null share as ADR 0019 states ("the count of its resolved-destination trips is published beside it as the basis"). `cross_borough_trip_count` is a crossing count, and ADR 0019 says a trip from N/A or Unknown neither is in-borough nor counts as leaving its borough, so an unresolved origin's value is `0` by definition and is not a measurement of its destinations. `D-05` had read an unresolved origin as an origin with no resolved-destination trip, leaving both counts at zero; that premise is false of the data. The share stays null on those rows because an unresolved origin has no borough to leave (`D-05`, ADR 0019); what changes is that the basis printed beside it is the real one rather than a zero reading as "nothing to measure". Source: R-04; ADR 0019; user answer ("publish the real resolved_trip_count on an unresolved origin, but keep cross_borough_trip_count at 0 there … add a test for both"); the Verification's `## Findings` row, which records the measurement.

## Rejected

- **Reusing `agg_od_flow_matrix`** — its 25-trip floor and zone grain remove both the cells and the denominator this table must publish (ADR 0017).
- **A floor of its own at borough grain** — ADR 0018 records why the floor does not transfer and what it would break.
- **A cross-borough share counting an unresolved destination as a crossing** — ADR 0019 records the inflation it causes and why an unplaceable destination is not a borough left.
- **A wide one-row-per-origin table with a column per destination** — a new borough becomes a schema change, and a consumer cannot filter a destination it does not know.
- **Publishing the share rounded to a fixed number of decimals** — the rounding belongs to the reader; a stored rounded rate cannot be re-aggregated.

## Consumers

- Mobility Planning (Leila Haddad) and the city, reading the table directly for the Q1 2024 borough-flow question.
- The semantic layer: `agg_borough_flow_monthly` is a new aggregate logical source of the trips document, so the two additive measures are answerable through the canonical model. No dbt model reads it, and no existing published model changes.

## Logical Model

```yaml
documents:
  - document: logical-model/nyc_taxi_analytics.ossie.yaml
    datasets:
      added: []
      changed: []
      retired: []
    metrics:
      added: []
      changed: []
      retired: []
    logical_sources:
      added: [LTS10_borough_flow_month]
      changed: []
      retired: []
ontology:
  documents:
    - document: ontology/nyc_taxi_analytics.mapping.yaml
      concepts:
        added: []
        changed: []
        retired: []
      mappings:
        added: []
        changed: []
        retired: []
```

Routing and its reasons, for the reviewer:

- The table is the star's rows rolled up, so it is an aggregate logical source of the trips document rather than a new star: its two measures are `billable_trip_count` and `billable_revenue` over a population that restates `trips.is_billable` in its `content_filter`, as `mart_daily_zone_revenue` does.
- The zero cells are no obstacle to the binding. The generated content test compares the source and the detail with `coalesce(…, 0)`, so a published zero against a detail with no such row passes; the whole table sums to the fact.
- `cross_borough_share_pct`, `cross_borough_trip_count` and `resolved_trip_count` are **refused** on the source in its `note`: a precomputed rate column is refused on every source, and the share's denominator is an origin-level total over a filtered population (resolved destinations only) that no declared metric restates — declaring one would be a repeated total, which is exactly the denominator-of-a-share case the rules refuse. The share stays answerable in SQL and is published on the table; it is not a canonical metric.
- No ontology change: the table carries no concept the ontology does not already have, and the mapping's `Trip` and `Zone` referents are expressions over the trips and zone datasets, which this table does not alter.

## History

- 2026-11-24 — BB · borough flow — design record written — D-01 to D-10 — terms: added Borough flow, Cross-borough trip
- 2026-11-24 — BB · borough flow — D-04 amended to flag the unresolved group on each axis; D-10 fixes the output columns — D-04, D-10
- 2026-11-24 — BB · borough flow — verification returned the basis counts: D-11 publishes the real `resolved_trip_count` on an unresolved origin and keeps `cross_borough_trip_count` at `0` there, correcting D-05's premise; a test covers both — D-05, D-11 — terms: none new
