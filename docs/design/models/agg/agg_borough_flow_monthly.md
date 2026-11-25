---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Monthly borough-to-borough flow: one row per month, origin borough and destination borough, built from `fct_trip` with `dim_zone` joined twice — once in each role — and rolled up from the zone to the borough level.

## Grain

One row per (month, origin borough, destination borough) that carries at least one billable trip in the reporting window. The month is the trip's pickup month. Alternatives considered: a complete 8 × 8 grid per month with zero rows for pairs that carry no traffic (rejected by the user, because a reader wants the crossings that happened, not 64 cells of which 22–24 are empty), and the zone-pair grain of `agg_od_flow_matrix` rolled up here (rejected under `D-06`).

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer at the design stop; the folder's `+schema` in `dbt_project.yml`.

## Decisions

- `D-01` **Kind `model`; materialisation `table` in `agg`, relation `agg.agg_borough_flow_monthly`.** A boundary aggregate that reports a period and two roles is a consumption surface, and the folder's default materialisation is `table`; incremental adds a unique key and a late-arriving-trip hazard for a table small enough to rebuild whole. Source: `dbt_project.yml`; `dbt-models` B15.
- `D-02` **Population: billable trips inside the reporting window, with both zone keys resolved.** ADR 0003 puts a revenue-and-flow mart's filter at `fct_trip.is_billable` inside the window, and the two inner as-of joins to `dim_zone` drop a trip whose zone key is null (ADR 0015), which the profile shows is no trip in the window. Source: R-03; ADR 0003; ADR 0015.
- `D-03` **No trip floor.** A pair is published as soon as it carries one billable trip; ADR 0017's floor stays scoped to the zone-pair matrix. Source: R-07; ADR 0018.
- `D-04` **Both borough roles keep every borough group, unresolved ones included.** `dim_zone.borough_name` is carried through as-is, so `Unknown`, `N/A` and `EWR` are ordinary members of each role rather than filtered or remapped. Source: R-06; ADR 0012; ADR 0018.
- `D-05` **`trip_month` is the pickup month, cast to `DATE`.** `date_trunc('month', …)` returns a timestamp even over a date column, so the model casts it; the Ossie documents and the contracts in this Domain treat a month key as a date. Source: R-01; R-08; the VD-7689 date-type convention.
- `D-06` **Built from `fct_trip`, not from `agg_od_flow_matrix`.** The matrix publishes the zone-pair grain but a floored population, so rolling it up would inherit the floor, make the trips a subset of the network and change the share's denominator as well as its numerator. Source: R-07; ADR 0017; ADR 0018.
- `D-07` **Columns: `trip_month`, `origin_borough`, `dest_borough`, `trip_count`, `total_revenue`, `cross_borough_trip_count`, `cross_borough_share`.** `cross_borough_trip_count` is the row's trips when the two boroughs differ and zero when they do not; the share is a rate, and ADR 0016 requires a rate to be rebuilt from summed numerators and denominators rather than carried as an average of lower-level rates. It also lets a reader recompute the share from the table. Source: R-03; R-04; R-05; ADR 0016.
- `D-08` **The share is a window ratio over the origin borough-month.** `cross_borough_share` is the origin borough's `cross_borough_trip_count` summed over the month divided, through `safe_divide`, by its `trip_count` summed over the month, partitioned by month and origin borough; it therefore repeats on each of that borough's rows and is null only when the borough has no trips, which cannot happen on a row that exists. Source: R-05; ADR 0016; ADR 0018.
- `D-09` **Keys are the borough names the zone master carries; no surrogate, no zone key.** A borough has no dimension of its own and a zone key would reintroduce the zone grain; a zone re-designation under a borough name does not split a row. Source: `dim_zone.borough_name`; `agg_od_flow_matrix` D-3.
- `D-10` **Contract and properties follow the boundary layer.** The model carries `contract: {enforced: true}` with every column typed and described, and its ODCS contract is authored alongside it at `contracts/agg/agg_borough_flow_monthly.odcs.yaml`; the `contracts` module of `repo-map.json` puts every gold relation under contract. Source: R-09; `repo-map.json`; `dbt-models` B6.
- `D-11` **Semantic layer: one aggregate logical source on the `trips` star, and no new metric.** `LTS10_borough_flow_monthly` is an aggregate source under the `trips` dataset, grouped at the month level of the Time hierarchy and at the borough level of both zone roles, and it supplies the existing `billable_trip_count` and `billable_revenue` metrics because its population is exactly theirs. `cross_borough_trip_count` and `cross_borough_share` are refused on that source with a `note`: both compare the origin borough with the destination borough of the same row, and no expression over the fact's declared fields can compare two roles of the same dimension, so neither is expressible as a star metric. A consumer that needs the share reads this table. Source: R-05; ADR 0016; `modeling-rules` S3c and the refusal rule.
- `D-12` **Ontology: no mapping added.** The relation's keys are a month and two borough names; it carries no identity column of a concept (`Trip`, `Zone` and their keys are not its keys), so it populates no concept of its own. Source: `semantic-model` step 9.

## Rejected

- **Rolling `agg_od_flow_matrix` up to the borough grain** — its 25-trip floor would narrow both the trips and the share's denominator (ADR 0017, ADR 0018).
- **A complete 8 × 8 grid per month** — 22–24 of the 64 cells carry no trips, and a zero row reads as a measured crossing.
- **The share computed per pair (`cross_borough_trip_count / trip_count`)** — that column is 1 or 0 on every row and answers nothing the user asked.
- **Publishing an `origin_trip_count` repeated on each row** — a repeated total fans out the moment anyone sums it; the window ratio keeps the denominator out of the published columns.
- **A surrogate borough key or a new borough dimension** — a borough is a name on the zone master; a key would have to be invented here and would drift from the Ossie level.

## Consumers

- A city-facing report and the Mobility Planning Lead's ad-hoc analysis of borough crossings: trips and revenue per origin and destination borough per month, and each borough's cross-borough share.
- The semantic layer: `LTS10_borough_flow_monthly` on the `nyc_taxi_analytics` document supplies `billable_trip_count` and `billable_revenue`; its cross-borough columns are read from the table, not through a metric.
- No dbt model, test or contract in the repository reads it; nothing downstream changes.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml:
      datasets: {}
      metrics: {}
      logical_sources:
        added:
          - LTS10_borough_flow_monthly
      concepts: {}
      mappings: {}
```

The star is not new: the relation rolls up the existing `trips` star at its own month and borough levels, so it joins that document as one aggregate logical source rather than a second document. Its `cross_borough_trip_count` and `cross_borough_share` columns carry no metric, because a share of one role of a dimension over another role of the same dimension is not expressible over the fact's declared fields; the source's `note` records that refusal, as `LTS1_detail`'s note already does for its refused columns.

## History

- 2026-11-25 — RR_Intent — initial design — D-01-D-12 — terms: none new (Cross-borough share was added with the requirement)
