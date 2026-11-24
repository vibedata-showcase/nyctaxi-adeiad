---
artifacts: [mart_daily_zone_revenue]
---

# mart_daily_zone_revenue

Daily revenue by pickup zone, read from the single daily-by-zone build.

## Grain

One row per pickup zone and trip date (`trip_date`, `pickup_location_id`); unchanged by this intent.

## Schema

- `transformation/models/marts/finance`: `finance` (default). Source: user answer.

## Decisions

- `D-01` Apply the billable rule and the reporting window here, in gold, and nowhere upstream, so quality work can still see the rows this excludes ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: docs/requirement/2026-08-29-the-trip-fact.md R-03, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-02` The report reads `agg_trip_zone_daily`'s billable measures and keeps the zone-days that carry at least one billable trip (`billable_trip_count > 0`); the reporting window and the billable filter belong to that model, so the report neither repeats them nor aggregates `fct_trip`. Supersedes the "nowhere upstream" clause of `D-01`: the exclusion still happens in gold, never in silver, so quality work still sees every trip. Source: R-01, R-02, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md), [ADR 0018](../../../adr/0018-daily-zone-revenue-covers-every-billable-trip.md), user answer.
- `D-03` The six measures are renamed from the aggregate's billable measures, not recomputed: `trip_count` from `billable_trip_count`, and `fare_revenue`, `tip_revenue`, `surcharge_revenue`, `toll_revenue` and `total_revenue` from the matching `billable_*_revenue`. Source: R-01, R-03.
- `D-04` The zone attributes (`borough`, `zone_name`, `reporting_region`) come from `dim_zone` joined as of the pickup date on the zone's natural key, `pickup_date >= valid_from_date and pickup_date < valid_to_date`, never on the natural key alone, so a zone with more than one version cannot multiply a row ([ADR 0009](../../../adr/0009-type-2-only-where-the-source-versions-history.md)). Source: R-03, [ADR 0009](../../../adr/0009-type-2-only-where-the-source-versions-history.md).
- `D-05` The published shape is unchanged: the same eleven columns with the same types, the same grain and key, contract still enforced, so the contract carries no delta and no consumer sees a change. Source: R-04.

## Rejected

- Applying the rule in silver: the excluded rows would be invisible to quality work.
- Keeping the aggregation here and reading the aggregate only for its all-trip figures: two builds of one grouping.
- Joining `dim_zone` on the natural key alone: it multiplies rows for the zones with more than one version (ADR 0009).
- Computing the zone attributes on the aggregate: a dimension attribute added to a published boundary model for one consumer's convenience.

## Consumers

- The morning report the finance team reads.
- The semantic layer binds `billable_trip_count` and `billable_revenue` to this relation (logical source LTS7) and publishes them; the binding is unchanged by this intent.
- The ODCS contract `contracts/finance/mart_daily_zone_revenue.odcs.yaml`, unchanged by this intent.
- No dbt model depends on it in this repository.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets: []
metrics: []
logical_sources: []
ontology: []
```

The report's binding keeps its columns, metrics and content filter: the relation's shape and values do not move, so the document does not move and no concept is re-reached.

## History

- 2026-10-14 — trip-fact — design record written; audience wording removed from the model description — D-01 — terms: none new
- 2026-11-24 — r9-zone-revenue — report rebuilt from the daily-by-zone aggregate, measures renamed, zone attributes joined as of the pickup date — D-02, D-03, D-04, D-05 — terms: none new
