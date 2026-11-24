---
artifacts: [mart_daily_zone_revenue]
---

# mart_daily_zone_revenue

Daily revenue by pickup zone, as the finance report publishes it. It no longer
aggregates `fct_trip` itself: it selects its numbers from the Domain's single
zone × day build, so the report and Operations' daily zone figures cannot disagree.

## Grain

One row per pickup zone and trip date.

## Decisions

- `D-01` Apply the billable rule and the reporting window in gold, and nowhere upstream, so quality work can still see the rows this excludes ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: docs/requirement/2026-08-29-the-trip-fact.md R-03, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-02` Read `agg.agg_trip_zone_daily` and project its measures instead of aggregating `fct_trip` here. The report keeps its grain, its columns and its values; only its source changes. The shared decision is [`trips/one-zone-day-build.md`](../../trips/one-zone-day-build.md), and the rule is still applied in gold, as `D-01` states — now in the build this report reads. Source: docs/requirement/2026-11-24-daily-zone-revenue-from-operations-figures-c61d6ba4.md R-01, R-07, user answer on the single source.
- `D-03` Evaluate neither the billable predicate nor the reporting window here. Both are evaluated once in the build ([ADR 0018](../../../adr/0018-the-billable-rule-is-evaluated-once-in-the-zone-day-build.md)); a predicate added back here would be the second evaluation point this change removes, even where it happens to return the same rows. The report selects the zone-days its billable measures cover with `where billable_trip_count > 0`, a test on a published measure rather than a re-application of `is_billable`, which is why the report has fewer rows than the build. Source: [ADR 0018](../../../adr/0018-the-billable-rule-is-evaluated-once-in-the-zone-day-build.md).
- `D-04` Keep the report's column names and types exactly as published: `trip_date`, `pickup_location_id`, `borough`, `zone_name`, `reporting_region`, `trip_count`, `fare_revenue`, `tip_revenue`, `surcharge_revenue`, `toll_revenue`, `total_revenue`. Renaming them to the build's names was rejected: consumers read these names. Source: docs/requirement/2026-11-24-daily-zone-revenue-from-operations-figures-c61d6ba4.md R-02, R-07.
- `D-05` `trip_count` on this report continues to mean billable trips and reads the build's `billable_trip_count`; the build's own `trip_count` counts every trip and is not what this column publishes. Source: docs/requirement/2026-11-24-daily-zone-revenue-from-operations-figures-c61d6ba4.md R-02, existing column description.
- `D-06` Materialisation stays `table` and the enforced contract keeps its columns and types, so no consumer sees a contract change; the ODCS contract moves a patch version, because no property or promise changes. Source: docs/requirement/2026-11-24-daily-zone-revenue-from-operations-figures-c61d6ba4.md R-08, repository convention.

## Rejected

- Keeping this model's own aggregation for the fare-component columns while reading the build for the totals — rejected: the report would still read `fct_trip`, and the one-source claim would be untrue.
- Retiring the report in favour of consumers reading the build directly — rejected: the report's name, grain and columns are a published promise, and its consumers are not being migrated.

## Consumers

None in this repo. The semantic layer binds this relation as logical source `LTS7_daily_zone_revenue` in `logical-model/nyc_taxi_analytics.ossie.yaml`, for the `billable_trip_count` and `billable_revenue` metrics.

## History

- 2026-10-14 — trip-fact — design record written; audience wording removed from the model description — D-01
- 2026-11-24 — new-intent-c61d6ba4 — report now selects from `agg_trip_zone_daily` instead of aggregating `fct_trip`; columns, grain and values unchanged — D-02 to D-06
