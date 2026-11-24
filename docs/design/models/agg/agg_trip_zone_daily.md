---
artifacts: [agg_trip_zone_daily]
---

# agg_trip_zone_daily

The Domain's single zone × day build. It carries the all-trips measures Operations
reads and, beside them, the billable measures a revenue report needs, so
`finance.mart_daily_zone_revenue` can select its numbers from here instead of
aggregating `fct_trip` a second time.

## Grain

One row per pickup zone and pickup date.

## Decisions

- `D-01` This model is the one build of the zone-day grain, and `finance.mart_daily_zone_revenue` selects from it rather than aggregating `fct_trip` itself. The shared decision, and why the duplication is worth removing, is [`trips/one-zone-day-build.md`](../../trips/one-zone-day-build.md). Source: docs/requirement/2026-11-24-daily-zone-revenue-from-operations-figures-c61d6ba4.md R-01, user answer on the single source.
- `D-02` The billable measures are added beside the all-trips ones; `trip_count`, `total_revenue`, `total_miles` and `attributed_driver_count` keep counting every in-window trip. The all-trips population is what this model already publishes, and a measure with its own population belongs in its own column, not in a redefinition of a published one. Source: docs/requirement/2026-11-24-daily-zone-revenue-from-operations-figures-c61d6ba4.md R-04, R-05.
- `D-03` The billable measures are `billable_trip_count`, `billable_revenue` and the four component sums `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue`, each `filter (where f.is_billable)` in the same aggregation pass as the all-trips measures. The revenue report publishes the four components separately, and `R-01` requires it to be a selection from here, so they are summed here rather than twice. Source: docs/requirement/2026-11-24-daily-zone-revenue-from-operations-figures-c61d6ba4.md R-01, R-07.
- `D-04` The billable predicate and the reporting window are evaluated here, once, and a surface on this grain selects the result. The rule itself is unchanged ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)); where it is evaluated is [ADR 0018](../../../adr/0018-the-billable-rule-is-evaluated-once-in-the-zone-day-build.md). `is_billable` is still computed once, in `int_trip_quality_flags`, and read from `fct_trip`. Source: [ADR 0018](../../../adr/0018-the-billable-rule-is-evaluated-once-in-the-zone-day-build.md).
- `D-05` A zone-day with trips but no billable trip carries 0 in the billable count and 0 in every billable sum, never null. Because a billable trip has a positive total by definition, 0 means "no billable trips" without ambiguity, and every row of the all-trips population stays in the model. Source: docs/requirement/2026-11-24-daily-zone-revenue-from-operations-figures-c61d6ba4.md R-06, user answer.
- `D-06` `reporting_region` is added, carrying the zone's region from the `dim_zone` row this model already joins. It costs no second join and cannot change the row count, and it keeps the revenue report a selection from one relation instead of a selection plus a re-join of the dimension. Source: docs/requirement/2026-11-24-daily-zone-revenue-from-operations-figures-c61d6ba4.md R-01, R-07.
- `D-07` The window and derived columns (`prev_day_trip_count`, `same_day_last_week_trip_count`, `trip_count_7d_avg`, `revenue_28d_rolling`, `revenue_rank_that_day`) stay computed over `trip_count` and `total_revenue`, the all-trips measures, and are not recomputed over the billable ones. Redefining them would change numbers Operations reads, and nothing in the request asks for it. Source: docs/requirement/2026-11-24-daily-zone-revenue-from-operations-figures-c61d6ba4.md R-04.
- `D-08` Materialisation stays `table`, and the enforced contract gains the new columns. The contract version moves a minor step, because columns are added and none is removed, renamed or retyped. Source: repository convention (`repo-map.json`: this relation is on the contract boundary), [ADR 0018](../../../adr/0018-the-billable-rule-is-evaluated-once-in-the-zone-day-build.md).

## Rejected

- Retiring this model in favour of the report — rejected: it would drop the all-trips measures and the period-over-period columns, which are published and read by Operations.
- Renaming `trip_count`/`total_revenue` to make the all-trips meaning explicit — rejected: it is a breaking change for this relation's consumers, for no gain the descriptions do not already give.
- Casting the money columns to `DECIMAL(18,2)` so sums are exact — rejected: it retypes published columns, and exact decimal arithmetic still does not reproduce the stored `DOUBLE` values bit for bit.

## Consumers

Depended on by: `mart_daily_zone_revenue`, and the two semantic-layer hold tests `assert_semantic_content_holds` and `assert_semantic_levels_hold`. The semantic layer binds this relation as logical source `LTS2_zone_day_agg` in `logical-model/nyc_taxi_analytics.ossie.yaml`, which maps its `trip_count`.

## History

- 2026-11-24 — new-intent-c61d6ba4 — design record written; the model became the Domain's single zone-day build and gained the billable measures and `reporting_region` — D-01 to D-08
