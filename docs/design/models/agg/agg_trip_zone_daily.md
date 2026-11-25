---
artifacts: [agg_trip_zone_daily]
---

# agg_trip_zone_daily

Daily zone demand with period-over-period context, and the one place the billable zone-day measures are computed.

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer at the design stop; unchanged from `+schema: agg` in `dbt_project.yml`.

## Decisions

- `D-01` Publish the billable zone-day measures beside the existing unfiltered ones: `billable_trip_count`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue` and `billable_total_revenue`. The existing `trip_count` and `total_revenue` keep counting every in-window trip, so the operations figures do not move ([ADR 0018](../../../adr/0018-zone-day-billable-measures-are-computed-once-in-the-aggregate.md)). Source: R-01, R-04, answer on the route ("Add billable measures to agg; finance mart becomes a projection").
- `D-02` The billable measures are `filter (where f.is_billable)` over the same aggregate and the same reporting window as the unfiltered ones, so both populations come from one scan and one `group by`. The verdict itself stays in `int_trip_quality_flags` and is only read here ([ADR 0018](../../../adr/0018-zone-day-billable-measures-are-computed-once-in-the-aggregate.md)). Source: R-05, answer on the route.
- `D-03` The billable measures are named for their population (`billable_…`), never left as a second unnamed `trip_count`, because a reader who sums the wrong column gets a different and plausible number. `trip_count` and `total_revenue` keep their names and meaning. Source: R-06, [ADR 0018](../../../adr/0018-zone-day-billable-measures-are-computed-once-in-the-aggregate.md).
- `D-04` A zone-day whose trips are all non-billable still carries a row, with `billable_trip_count` 0 and every billable revenue measure null. Null rather than 0 states "nothing to sum"; the count beside it states how many trips the measure covers. Source: R-02 acceptance, answer on the population ("Emit them with zero trips and zero revenue" is the mart's rule; the aggregate states absence as null), playbook default on Coverage.
- `D-05` The six new columns are added by `+on_schema_change: append_new_columns`-equivalent behaviour of a table materialisation rebuilt whole; the model stays `table`, as `marts.agg` sets, so nothing about the window functions or the grain changes. Source: `dbt_project.yml`, R-04.

## Rejected

- **Making `trip_count` and `total_revenue` billable-only** — it would change the operation's published numbers, which R-04 forbids.
- **A second aggregate model for the billable figures** — it would be the second build the request removes.
- **Coalescing the billable revenue measures to 0 in the aggregate** — it would hide the difference between "no billable trip" and "billable trips that summed to zero", and the count already answers the population question.

## Consumers

- `finance.mart_daily_zone_revenue`, which reads the billable measures and publishes them under the report's column names.
- `assert_semantic_content_holds` and `assert_semantic_levels_hold`, through logical source `LTS2_zone_day_agg`, which binds `trip_count` to this relation. That binding is unaffected: `trip_count` keeps its meaning.
- Operations' own daily zone figures, from the unfiltered columns.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets: {}
metrics:
  added:
    - billable_fare_revenue
    - billable_tip_revenue
    - billable_surcharge_revenue
    - billable_toll_revenue
  changed: []
  retired: []
logical_sources:
  added: []
  changed:
    - LTS2_zone_day_agg
  retired: []
```

`LTS2_zone_day_agg` gains `billable_trip_count` and `billable_revenue` in its `column_map`, pointing at the new columns of the same names and at `billable_total_revenue`. Its `content_filter` stays unfiltered, as `LTS3_zone_daypart_dow` already does: the billable metrics' own aggregations carry the filter (`SUM(CASE WHEN trips.is_billable THEN 1 ELSE 0 END)`), so the source does not add a second one. The four component measures have no metric today and each takes one whose aggregation is `SUM(...) filter (where is_billable)`. Source: R-05, R-06, [ADR 0018](../../../adr/0018-zone-day-billable-measures-are-computed-once-in-the-aggregate.md).

The ontology is untouched: its `Trip` concept reaches the star dataset `trips`, and neither this relation nor these measures is a concept or a mapped dataset. Source: `ontology/nyc_taxi_analytics.mapping.yaml`.

## History

- 2026-11-25 — RR_Intent2 — design record written; billable measures added beside the unfiltered ones — D-01, D-02, D-03, D-04, D-05 — terms: none new
