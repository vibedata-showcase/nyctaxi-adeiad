---
artifacts: [agg_trip_zone_daily]
---

# agg_trip_zone_daily

Daily zone demand, one row per pickup zone and trip date, with period-over-period context. The operations-side daily zone figure the finance report is built from.

## Grain

One row per (pickup zone, pickup date) inside the reporting window, over every in-window trip — the grain it publishes today. The billable measures this intent adds are computed within that same row, so the grain does not move and the existing columns keep their values.

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer.

## Decisions

- `D-01` The table publishes billable measures beside the all-trip measures it already publishes: `billable_trip_count`, `billable_revenue`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue` and `billable_toll_revenue`, each an aggregate filtered on `f.is_billable` (a count or a sum of the same column the all-trip measure sums). The billable rule therefore runs here and not downstream, because an aggregate of whole totals cannot have the rule subtracted from it (a non-billable trip carries a negative total, so billable revenue is not `total_revenue` minus anything recoverable). Source: R-02, R-05; [ADR 0018](../../adr/0018-the-billable-rule-moves-into-the-operations-daily-zone-aggregate.md).
- `D-02` The existing columns keep their names, types, grain and values, and no existing column is retyped or removed: `trip_count` and `total_revenue` stay the all-trip figures, so the demand and quality work that reads them is unaffected. A consumer that needs billable figures reads the new columns. Source: R-02, R-05.
- `D-03` The table also publishes `reporting_region`, taken from `dim_zone` in the same join that already supplies `zone_name` and `borough_name`. Re-joining the zone dimension downstream is not an option: 7 zone natural keys carry two SCD2 versions, so a natural-key join to `dim_zone` returns two rows for those zone-days and would double their revenue. All versions of a zone agree on name, borough and reporting region in every row of this relation, so carrying the column here relabels nothing. Source: R-02; Verification `## Discovery`.
- `D-04` Rows are emitted for every zone-day with at least one in-window trip, including a zone-day whose trips are all non-billable; those carry a billable trip count of zero and a billable revenue of zero. The rows stay because the table answers demand, not only revenue. The report filters them out; see `mart_daily_zone_revenue` `D-03`. Source: user answer; R-05.
- `D-05` The moving-window columns (`prev_day_trip_count`, `same_day_last_week_trip_count`, `trip_count_7d_avg`, `revenue_28d_rolling`, `revenue_rank_that_day`) keep their current definition over all trips. No billable counterpart is added: a billable rolling window is a metric the request did not ask for, and the semantic model refuses to bind these columns for reasons it records. Source: R-02; R-05.
- `D-06` The new measures use `sum(...)` with no `coalesce`, the same aggregation the report applied before this change, so the arithmetic is identical. A `coalesce` would be a silent difference if a null fare ever appeared; none exists in the window, and the report's own `not_null` test on `total_revenue` guards the outcome. Source: R-05; Verification `## Discovery`.
- `D-07` Supersedes `D-06`: the billable sums are wrapped in `coalesce(..., 0)`. `D-06` assumed every zone-day has a billable trip, and the first build disproved it — a zone-day whose trips are all non-billable has no row for the filtered sum to add up, so the sum is NULL rather than zero, and `D-04` says such a row carries a billable revenue of zero. The two decisions conflicted and `D-04` is the one that states the row's meaning. The change cannot move a published number: the report filters those rows out, and no other row's sum is touched, because a group with at least one billable trip has at least one non-null summand. Source: R-02, R-05; Verification `## Discovery`; the first Task 1 build.

## Rejected

- Filtering the table to billable trips — it would drop the trips quality and demand work needs (the thing ADR 0003 exists to prevent) and would change the values of columns it already publishes.
- Publishing only a billable total and deriving the components downstream — the components cannot be derived from it, and the report publishes all four.
- Re-joining `dim_zone` in the report for `zone_name`, `borough_name` and `reporting_region` — the natural-key join fans out across SCD2 versions.
- Adding billable counterparts for the rolling and lag columns — not requested, and the semantic model already refuses them for the all-trip versions.

## Consumers

- `finance.mart_daily_zone_revenue` — the finance daily zone revenue report, which this intent rebuilds on this table.
- The canonical model's `LTS2_zone_day_agg` logical source and `assert_semantic_content_holds` / `assert_semantic_levels_hold`.
- `contracts/agg/agg_trip_zone_daily.odcs.yaml`.
- Ad-hoc analysis of daily zone demand; no other model in the repository reads it.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets: []
metrics: []
logical_sources:
  - name: LTS2_zone_day_agg
    change: changed
concepts: []
mappings: []
```

`LTS2_zone_day_agg` gains no new column binding. The billable columns are not bound: binding them would move canonical billable questions at day and zone grain off `LTS1_detail` and onto this table, which is a metric decision the request did not ask for and no measurement yet shows to be equivalent under arbitrary filters. Its `note` is rewritten, because it currently explains that the report's own `trip_count` is the billable one while this table's is unfiltered — that stops being true when this intent lands. Source: R-02.

## History

- 2026-11-25 — zone-revenue-report-from-operations-figures-2 — design record written; billable measures and `reporting_region` added, existing columns held still — D-01, D-02, D-03, D-04, D-05, D-06 — terms: none new
