---
artifacts: [agg_trip_zone_daily, mart_daily_zone_revenue]
---

# One zone-day build

Finance's daily zone revenue report and Operations' daily zone figures are the same
answer at the same grain — one row per pickup zone and pickup date — and were built
twice, each aggregating `fct_trip` itself. This records the decision that they are
built once, so the two cannot disagree.

## Grain

One row per pickup zone and pickup date. Both relations already had it; the
consolidation does not change it.

## Decisions

- `D-01` One build owns the grain: `agg_trip_zone_daily` aggregates `fct_trip` and
  `mart_daily_zone_revenue` is a selection from it, so no second aggregation of the
  same rows exists. Two builds of one answer are a standing invitation to disagree,
  and the disagreement surfaces in a finance report nobody can reconcile.
- `D-02` The build carries both populations: its original all-trips measures, and
  the billable measures a revenue report needs beside them. Dropping the all-trips
  measures to make the table purely billable would remove what Operations reads;
  keeping only all-trips measures leaves the report re-deriving the billable rule,
  which is the duplication being removed.
- `D-03` The billable rule is applied once, in this build, and reports on the grain
  select its measures rather than filtering again
  ([ADR 0018](../../adr/0018-the-billable-rule-is-applied-once-in-the-zone-day-build.md)).
  The rule itself is unchanged and still
  [ADR 0003](../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-04` A report on this grain keeps its own column names and its own meaning for
  them, even where they differ from the build's. `mart_daily_zone_revenue.trip_count`
  is billable trips and `agg_trip_zone_daily.trip_count` is all trips; both
  descriptions say so, and neither is renamed to match the other.

## Rejected

- Retiring one of the two relations — rejected: the build carries period-over-period
  columns and all-trips measures the report does not, and the report is a published
  name its consumers read.
- Making the report the only build and having Operations read it — rejected: same
  reason in the other direction, and it would publish Operations' surface under
  Finance's name.
- Having the report select the build's billable measures and still filter
  `is_billable` or the window itself — rejected: a second application point drifts
  from the first the moment either changes, which is what this decision prevents.

## Consumers

`mart_daily_zone_revenue` depends on `agg_trip_zone_daily`. Both are read by the
semantic-layer hold tests `assert_semantic_content_holds` and
`assert_semantic_levels_hold`.

## History

- 2026-11-24 — new-intent-c61d6ba4 — the two zone-day builds consolidated onto one — D-01 to D-04
