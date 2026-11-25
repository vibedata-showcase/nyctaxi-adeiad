---
status: decided
date: 2026-11-25
---

# The daily zone revenue report publishes the billable population, carried beside the all-trip figures in `agg_trip_zone_daily`

`agg_trip_zone_daily` gains billable measures beside the all-trip ones it already publishes: a billable trip count and billable fare, tip, surcharge, toll and total revenue. Its existing `trip_count` and `total_revenue` keep their present meaning, every in-window trip. `mart_daily_zone_revenue` is built from `agg_trip_zone_daily` rather than from `fct_trip`, and keeps publishing only the billable population: a zone-day with no billable trip does not appear in the report.

Two published relations therefore change their meaning and their dependencies, which is hard to reverse; and the arrangement is surprising without context, because one aggregate now carries two populations of the same measure. The trade-off is between one revenue source and the contract of an aggregate that other consumers already read.

## Considered options

- **Add billable measures beside the all-trip ones** — chosen: every existing consumer of `agg_trip_zone_daily` reads the same numbers it read before, and the report reproduces its billable figures from the aggregate.
- **Redefine the existing `trip_count` and `total_revenue` as billable-only** — rejected: it moves the aggregate's published numbers for every consumer and breaks its contract, to answer a question about one report.
- **Build the report from `agg_trip_zone_daypart_dow`** — rejected: that aggregate carries no toll revenue and no billable-restricted component sums, so the report's fare, tip, surcharge and toll revenue cannot be reproduced from it.
- **Emit a zero row for a zone-day with no billable trip** — rejected: it grows the report's row set without changing any total, so the report would change shape to say nothing new.

## Consequences

- `agg_trip_zone_daily` carries two populations of the same measure, told apart by column name, never by which is summed. `trip_count` and `total_revenue` count every trip in the window; the billable columns count only billable trips ([ADR 0003](0003-billable-trip-definition-and-where-it-applies.md)).
- `agg_trip_zone_daily` joins the set of gold marts that apply the billable rule, for its billable measures only, and its contract version moves at the minor level for the added columns.
- `mart_daily_zone_revenue` reads one revenue source, `agg_trip_zone_daily`, and none of its published columns or values change.
- A zone-day whose only trips are non-billable stays absent from the report, so the report's row count is below the aggregate's and the aggregate is the surface that shows such a day.
- A later revenue mart built on `agg_trip_zone_daily` must choose explicitly between the two populations; summing both in one query double-counts.

## Affected designs

- [`models/agg/agg_trip_zone_daily.md`](../design/models/agg/agg_trip_zone_daily.md)
- [`models/finance/mart_daily_zone_revenue.md`](../design/models/finance/mart_daily_zone_revenue.md)
