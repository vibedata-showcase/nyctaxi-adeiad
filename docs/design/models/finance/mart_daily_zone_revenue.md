---
artifacts: [mart_daily_zone_revenue]
---

# mart_daily_zone_revenue

Daily revenue by pickup zone, read from the operations aggregate rather than recomputed from the trip fact.

## Grain

One row per pickup zone and trip date. Unchanged: `pickup_location_id` is `dim_zone.zone_natural_key` and `trip_date` is the pickup date ([ADR 0018](../../../adr/0018-zone-day-billable-measures-are-computed-once-in-the-aggregate.md)).

## Schema

- `transformation/models/marts/finance/`: `finance` (default). Source: user answer at the design stop; unchanged from `+schema: finance` in `dbt_project.yml`.

## Decisions

- `D-01` Read `agg.agg_trip_zone_daily` and republish its billable measures under the report's column names: `trip_count` ← `billable_trip_count`, `total_revenue` ← `billable_total_revenue`, `fare_revenue` ← `billable_fare_revenue`, `tip_revenue` ← `billable_tip_revenue`, `surcharge_revenue` ← `billable_surcharge_revenue`, `toll_revenue` ← `billable_toll_revenue`. The model computes no aggregate and applies no billable filter of its own; it no longer applies the billable rule itself, which [ADR 0018](../../../adr/0018-zone-day-billable-measures-are-computed-once-in-the-aggregate.md) moves into the aggregate. Source: R-01, R-05, answer on the route.
- `D-02` The published column names, order and types do not change, so the eleven columns Finance reads are exactly the ones it reads today. Source: R-02, [ADR 0018](../../../adr/0018-zone-day-billable-measures-are-computed-once-in-the-aggregate.md).
- `D-03` `reporting_region` comes from `dim_zone`, joined on `zone_natural_key` with the half-open validity interval on the trip date, never on the natural key alone: `dim_zone` is Type 2 and the bare key multiplies rows for the zones that carry more than one version ([ADR 0009](../../../adr/0009-type-2-only-where-the-source-versions-history.md)). `borough` and `zone_name` come from the aggregate, which already carries the zone's attributes as of the trip. Source: R-02, [ADR 0009](../../../adr/0009-type-2-only-where-the-source-versions-history.md); measurements in `docs/verify/2026-11-25-rr-intent2-04937342.md`.
- `D-04` A zone-day with no billable trip is published with `trip_count` 0 and every revenue measure 0, which widens the report by exactly those zone-days and leaves every existing row's value, and the four acceptance totals, unchanged. The aggregate states the same absence as a null measure with a 0 count; the mart's published columns are `not_null` under its enforced contract, so the report states it as zero. Source: answer on the population ("Emit them with zero trips and zero revenue"), R-02, R-03.
- `D-05` The reporting window is not re-applied here: the aggregate already applies `in_report_window` to the pickup timestamp, and a second window predicate over an already-windowed relation is the duplicated rule this change removes. Source: R-01, R-05.
- `D-06` The model stays a `table` in schema `finance`, so the swap is a rebuild under the existing `marts` config, not a change of materialisation. Source: `dbt_project.yml`.

## Rejected

- Applying the rule in silver: the excluded rows would be invisible to quality work.
- **Keeping the aggregation in the mart and documenting that agg differs** — it leaves the two builds the request removes.
- **Reading the aggregate and keeping a `billable_trip_count > 0` filter** — it would hold the report at its current row count, but the user asked for the zero-billable zone-days to appear.
- **Joining `dim_zone` on `zone_natural_key` alone for `reporting_region`** — it multiplies rows for zones with more than one version.
- **Taking `reporting_region` from the aggregate instead** — the aggregate does not carry it, and adding it solely for this mart would widen a published relation for a report-only need.

## Consumers

- Finance's daily zone revenue report, which reads this relation every morning. Not declared as a dbt exposure in this repository.
- Logical source `LTS7_daily_zone_revenue` in `logical-model/nyc_taxi_analytics.ossie.yaml`, which binds `billable_trip_count` to `trip_count` and `billable_revenue` to `total_revenue`.
- `assert_semantic_content_holds` and `assert_semantic_levels_hold`.
- ODCS contract `contracts/finance/mart_daily_zone_revenue.odcs.yaml`.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets: {}
metrics:
  added: []
  changed: []
  retired: []
logical_sources:
  added: []
  changed:
    - LTS7_daily_zone_revenue
  retired: []
```

`LTS7_daily_zone_revenue` keeps its bindings — `billable_trip_count` to `trip_count` and `billable_revenue` to `total_revenue` — and its `content_filter` is unchanged, `... AND is_billable AND pickup_zone_key IS NOT NULL`. What changes is only where the filter bites: the mart inherits it from the aggregate instead of applying it, so the filter still describes this source's content and the generated binding test still holds. Its `note` refusal of `trip_count` ("the mart applies `f.is_billable`") is reworded at authoring time to say the mart inherits the billable count, since the fact it states is unchanged. Source: R-06, [ADR 0018](../../../adr/0018-zone-day-billable-measures-are-computed-once-in-the-aggregate.md).

The ontology is untouched: no concept reaches this relation, and the measures it republishes are the same billable measures already mapped through the star dataset. Source: `ontology/nyc_taxi_analytics.mapping.yaml`.

## History

- 2026-11-25 — RR_Intent2 — the mart becomes a projection of the operations aggregate, and the billable rule moves upstream of it — D-01, D-02, D-03, D-04, D-05, D-06 — terms: none new
- 2026-10-14 — trip-fact — design record written; audience wording removed from the model description — D-01
