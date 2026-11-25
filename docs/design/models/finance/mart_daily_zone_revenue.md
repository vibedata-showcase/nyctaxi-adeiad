---
artifacts: [mart_daily_zone_revenue]
---

# mart_daily_zone_revenue

Daily revenue by pickup zone.

## Grain

One row per pickup zone and trip date.

## Schema

- `transformation/models/marts/finance`: `finance` (default). Source: user answer at design, batched schema question.

## Decisions

- `D-01` Apply the billable rule and the reporting window here, in gold, and nowhere upstream, so quality work can still see the rows this excludes ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: docs/requirement/2026-08-29-the-trip-fact.md R-03, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-02` Supersedes `D-01`: the billable rule and the reporting window are applied once, in `agg_trip_zone_daily`, and this mart selects the billable measures from it. Both are still applied in gold, so [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md) holds; what changes is which gold relation computes them. Running them in both places is the second build this change removes. Source: docs/requirement/2026-11-25-tarun-ex2-5f307739.md R-01 and R-02.
- `D-03` The mart publishes exactly the eleven columns it publishes today, six of them picked from the ops relation under a new name (`trip_count` from `billable_trip_count`, `total_revenue` from `billable_total_revenue`, and the four components from their `billable_` columns) so no consumer's query changes. Source: requirement R-04 and R-05.
- `D-04` The mart keeps one row per zone-day **that has a billable trip**, `where billable_trip_count > 0`, because that is the report's population today and its row count must not move. It does not re-apply `is_billable`: the trip-level flag is not on the source relation, and the billable measures beside it already carry the rule's effect. A zero-billable zone-day is present in the source with zeros and is excluded here, which is the only filter this mart applies. Source: requirement R-05 and R-06.
- `D-05` No property of the mart's contract is added, removed or retyped, and no prose changes: `trip_count` is a star member, so its description is the Ossie field's `billable_trip_count` — "Trips whose total amount is positive." — which `generate` writes into `_finance.yml`; a hand-written description there makes `check` report `generated/stale`. The contract stays at 1.0.1. Source: requirement R-07; `data-contract` skill, "Prose is authored or absent; a star member's column descriptions belong to the Ossie field".

## Rejected

- Applying the rule in silver: the excluded rows would be invisible to quality work.
- Filtering `is_billable` in this mart after reading the ops relation: the trip-level flag is not on the ops relation, so the filter would test a column that does not exist. The rule is applied upstream, once, and this mart selects only the zone-days that have a billable trip (`D-04`).

## Consumers

- The finance team reading the morning report.
- The canonical model's logical source `LTS7_daily_zone_revenue`, and the two generated singular tests that hold its binding (`assert_semantic_content_holds`, `assert_semantic_levels_hold`).

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets: {}
metrics: {}
logical_sources:
  LTS7_daily_zone_revenue: changed
```

Its `content_filter` records "the mart applies `is_billable`", which becomes false: the filter moves to `LTS2_zone_day_agg`. Its `column_map` is unchanged, and no metric, dataset or level moves.

## History

- 2026-10-14 — trip-fact — design record written; audience wording removed from the model description — D-01
- 2026-11-25 — tarun-ex2 — record read and superseded: the mart now selects the billable measures from `agg_trip_zone_daily` — D-02 to D-05 — terms: none new

