---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Borough-to-borough flow, one row per month and borough pair, built from `fct_trip` with `dim_zone` joined twice — once in each role. Answers how much traffic crosses a borough line and what it carried.

## Grain

One row per calendar month, origin borough and destination borough, for the reporting window. The month key is `month_start_date`, the first day of the month cast to `DATE`, the same shape as `dim_date.month_start_date`, so the month level joins on the value rather than being re-derived per consumer.

Alternatives: zone-pair grain (what `agg_od_flow_matrix` already publishes) would make the crossing share a computation every consumer repeats; day grain would leave the monthly rollup to each report and let two reports disagree about which days a month has.

## Schema

- `transformation/models/marts/agg`: `agg` (default — the folder's `+schema`, accepted). Source: user answer, this intent's schema question.

## Decisions

- `D-01` A new boundary model `agg_borough_flow_monthly` in `agg`, materialized as a table, reading `fct_trip` and `dim_zone` twice. It is a new relation beside `agg_od_flow_matrix`, never a change to it: the two answer different questions at different grains. Source: `R-01`, `R-09`, `.agents/skills/dbt-models/SKILL.md` (`agg_` = aggregates built from facts).
- `D-02` One row per month × origin borough × destination borough, as `month_start_date`, `origin_borough` and `destination_borough`; the month is the calendar month of `pickup_date`, written as `month_start_date` (`DATE`). Source: `R-01`, `core.dim_date`.
- `D-03` The population is `fct_trip.is_billable` inside the reporting window, inner joined to both zone roles. A billable trip whose pickup or dropoff zone key is null is therefore outside the relation, and the count of those trips is published per month beside the flow (`D-09`) rather than dropped silently. The two measures are `billable_trip_count` and `billable_revenue`. Source: `R-02`, `R-07`, ADR 0003, ADR 0015.
- `D-04` The borough axis is `dim_zone.borough_name` exactly as the dimension carries it, on both roles: the unresolved groups and `EWR` are members. Crossing is plain equality on that name. Source: `R-04`, ADR 0018, ADR 0012.
- `D-05` No floor. Every borough pair that carries billable traffic in a month is published, which is what ADR 0019 decides and what keeps the share's denominator the whole departing population. ADR 0017 is untouched and still governs `agg_od_flow_matrix`. Source: `R-05`, ADR 0019.
- `D-06` A pair with no billable trip in the month has no row: the relation is a group-by result with no spine and no zero filling. Source: `R-06`.
- `D-07` The crossing share is stored per row but rebuilt as a ratio of sums, with its numerator and denominator beside it: `origin_month_trip_count`, `origin_month_crossing_trip_count` and `origin_month_crossing_share`, all three repeated on every row of that origin borough and month. ADR 0016 forbids averaging a lower-level rate and requires a new aggregate to carry the summed numerators and denominators; repeating them keeps the share and its parts on the same row a reader sees. They are not additive across rows. Source: `R-03`, ADR 0016.
- `D-08` `is_cross_borough` states the definition on every row as `origin_borough <> destination_borough`, so a reader can filter or audit the crossing set without re-deriving the rule from prose. Source: `R-03`, `R-04`, ADR 0018.
- `D-09` `month_unplaced_billable_trip_count` is the month's billable trips that no zone version places, repeated on every row of that month, and 0 rather than null when a month has none, so the coverage reads as a measured zero. It comes from `fct_trip` alone, since the inner join to both zone roles is what excludes those trips. It is not additive across rows. Source: `R-07`.
- `D-10` The relation is contracted: the ODCS contract is authored first and `active` once built, and its dbt keys, types and descriptions come from `odcs.py generate`, never by hand, with `contract: {enforced: true}` and `access: protected` on the model. Source: `R-08`, `.agents/skills/data-contract/SKILL.md`.
- `D-11` In the semantic layer it is an aggregate logical source on the `nyc_taxi_analytics` document — the trips star's own rows rolled up at month × origin borough × destination borough — so no new document and no new star. `billable_trip_count` and `billable_revenue` bind to it; the stored share and the three repeated columns are refused in the source's note, because a precomputed rate is refused on every source and a repeated level value is not a column this grain can supply additively. Source: `R-08`, `.agents/skills/semantic-model/SKILL.md` (routing a boundary relation; precomputed rates refused).
- `D-12` No ontology change: the source carries the Trip and Zone concepts already mapped on this document, and no concept is added, retired or re-identified. The reference gate is re-run because the document moved. Source: `R-08`, `.agents/skills/ontology/SKILL.md`.
- `D-13` Materialisation `table` (the gold default), no incremental logic and no audit columns; nothing schedules it. Source: `.agents/skills/dbt-models/SKILL.md` (B12, B15), `R-01`.

## Rejected

- **Publish it through `semantic_exclusions` with no contract.** The relation is the star's rows rolled up with no `HAVING` and no lossy join, so an aggregate source is the honest route; excluding it would leave the domain's one borough-flow answer unqueryable through the semantic layer.
- **A second relation for the coverage gap.** One repeated column on the month carries the unplaced count and keeps the deliverable to one boundary relation; a companion model would owe its own contract, document source and design record for a count the Verification measures in one query.
- **A sentinel borough such as `(no zone)` on both axes.** ADR 0015 rejects placeholder members, and `D-03` keeps the trip visible through the published count instead.
- **A window function over `agg_od_flow_matrix`.** That mart keeps only pairs at or above the 25-trip floor (ADR 0017), so its totals are a filtered subset and cannot yield the network share (ADR 0019).
- **Averaging zone-pair shares up to the borough.** The mean of ratios is not the ratio asked for (ADR 0016).

## Consumers

Mobility Planning, through the semantic layer (`billable_trip_count` and `billable_revenue` grouped by month, origin borough and destination borough) and by reading the relation directly for the share and its coverage columns. Nothing else in the repository reads it; no published model changes.

## Logical Model

```yaml
logical_model:
  documents:
    - logical-model/nyc_taxi_analytics.ossie.yaml
  datasets: []
  metrics: []
  logical_sources:
    - name: LTS10_borough_flow_monthly
      status: added
ontology:
  documents: []
  concepts: []
  mappings: []
```

The source sits on the `trips` star of the existing document at its own grain, so no dataset, metric or document is added. Its `content_grain` is month, origin borough and destination borough; its `content_levels` claim the month level of `trips_to_date` and the borough level of both zone roles; its `content_filter` states the billable filter, the literal reporting-window bounds and both zone keys `IS NOT NULL`, from the inner joins. The note names the three refusals: `origin_month_crossing_share` (a precomputed rate), and `origin_month_trip_count`, `origin_month_crossing_trip_count` and `month_unplaced_billable_trip_count` (level values repeated below the grain, which no aggregation of this source can supply).

## History

- 2026-11-25 — mich — design record written — `D-01`–`D-13` — terms: none new (the Crossing-borough trip term landed with the Requirement)
