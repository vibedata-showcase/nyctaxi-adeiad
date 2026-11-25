---
artifacts: [mart_daily_zone_revenue]
---

# mart_daily_zone_revenue

## Grain

One row per pickup zone and trip date, unchanged (`trip_date` × `pickup_location_id`).

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets:
  trips: changed
metrics: {}
logical_sources:
  LTS7_daily_zone_revenue: changed
```

`LTS7_daily_zone_revenue` keeps the same three-column `column_map`; what changes is its
`note`, which records that the model now reaches `agg.agg_trip_zone_daily` rather than
`fct_trip`, so the refusals it lists for the all-trips `trip_count` stay true and the
population it describes is unchanged. Its `content_filter` is expressed over the detail
dataset's logical fields and needs no edit. No metric, concept or mapping is added, so
no ontology document changes: the mappings under `ontology/` reach the document's
logical fields, and none of those is added or renamed.

## Decisions

- `D-01` Apply the billable rule and the reporting window here, in gold, and nowhere upstream, so quality work can still see the rows this excludes ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: docs/requirement/2026-08-29-the-trip-fact.md R-03, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-02` The report reads `agg.agg_trip_zone_daily` as its only upstream relation, and no longer `ref('fct_trip')` or `ref('dim_zone')`. One daily-by-zone rollup in the warehouse instead of two builds of the same figures is the point of the request; the agg now publishes every column the report needs. Source: R-01, user request.
- `D-03` The report keeps applying the billable rule itself, on the agg's `billable_trip_count > 0` rather than on `fct_trip.is_billable`. ADR 0003 puts the rule on this mart, and keeping the filter here means the report's population is stated in the report's own SQL rather than inherited implicitly from a column name; it is also what keeps the 36 all-refund zone-days out of the report (R-08). Source: R-04, R-08, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-04` The eleven published columns keep their names, types and order; the five revenue measures and `trip_count` are re-pointed at the agg's `billable_*` columns, and `borough`/`zone_name`/`reporting_region` at the agg's zone labels. The agg's labels equal `dim_zone`'s at this grain (Verification D6), so dropping the `dim_zone` join changes no value (R-05). Source: R-03, R-04, R-05.
- `D-05` The report keeps its `relationships` test to `dim_zone.zone_natural_key` even though it no longer joins `dim_zone`. The test asserts that every published zone is a real dimension member, which is a property of the report's output, not of its lineage; removing it would drop the only check that the agg's zone set stays inside the dimension. Source: R-09, repository (`_finance.yml`).
- `D-06` `trip_count`'s description becomes "Billable trips." The current text, "Trips, billable or not", describes the opposite of what the column holds, since the mart filters on `is_billable`; the logical model already reads it correctly (Verification D9). Source: R-10.
- `D-07` The published shape is unchanged, so the ODCS contract version moves patch only (a prose correction), not minor or major. Source: R-04, `.agents/skills/data-contract` version rule.

## Rejected

- **Keep `ref('fct_trip')` alongside the agg** — two builds of the same figures, which is exactly the duplication the request removes.
- **Have the report read the agg's all-trips `trip_count`/`total_revenue`** — would restate every number in the report (R-05, R-06).
- **Move the billable filter into the agg only, and have the report read `billable_trip_count` with no filter** — the report would then have to filter on a nullable measure to exclude all-refund zone-days, which states the population less clearly than filtering on the count; and ADR 0003 puts the rule on this mart.
- **Join `dim_zone` for the labels** — unnecessary once the agg carries them, and it would keep a second source of truth for zone labels (R-01).

## Consumers

- The finance team's daily zone revenue report (outside this repository).
- `transformation/tests/assert_semantic_content_holds.sql` and
  `assert_semantic_levels_hold.sql` (generated; regenerated when the logical source changes).
- The semantic layer's `LTS7_daily_zone_revenue` logical source.

## History

- 2026-10-14 — trip-fact — design record written; audience wording removed from the model description — D-01
- 2026-11-25 — jl2 — report re-pointed from `fct_trip`/`dim_zone` to `agg.agg_trip_zone_daily`, published shape unchanged — D-02, D-03, D-04, D-05, D-06, D-07 — terms: none new
