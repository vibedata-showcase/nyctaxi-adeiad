---
artifacts: [agg_trip_zone_daily]
---

# agg_trip_zone_daily

Daily zone demand, with period-over-period context. Extended by this intent to carry the billable-only measures a revenue report needs, so the billable rule is computed in one place.

## Grain

One row per pickup zone and trip date, holding every in-window zone-day including those whose trips are all non-billable. Unchanged by this intent: the extension adds columns, never rows.

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer (application-owner accepted the folder's current schema).

## Decisions

- `D-01` Add the billable-only measures as new columns beside the existing whole-population ones, rather than redefining `trip_count` and `total_revenue` to count billable trips. `trip_count` and `total_revenue` are published as population-wide, an active ODCS contract and a semantic-layer source (`LTS2_zone_day_agg`) already bind them, and other fleet and demand consumers read them; redefining either would change their answers silently. Source: R-06, R-07.
- `D-02` Carry the billable measures as `billable_trip_count`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue` and `billable_total_revenue`, each computed with `filter (where f.is_billable)` before aggregation. The names follow `agg_trip_zone_daypart_dow`'s existing `billable_trip_count`, and the prefix states the population so a reader cannot mistake it for the population-wide column beside it. Source: R-06, R-09; `agg_trip_zone_daypart_dow`.
- `D-03` Add `reporting_region` to the select list and the `group by`. It is functionally dependent on the zone, so it splits no row and the grain is unchanged; it is added here because the revenue report publishes it and must read no other relation (R-01). Source: R-06, R-05.
- `D-04` Apply the billable rule here, once, with the reporting window — this relation becomes the one place on the report's path where the rule runs. The predicate is evaluated per trip inside the aggregate, not on the aggregate's rows, which is why the counts and sums reproduce the per-trip filter exactly. Source: R-09, user answer on ADR 0003.
- `D-05` Keep the inner join to `dim_zone` on `zone_key`, and keep keeping every in-window zone-day. The join resolves the zone version in force on the trip's date; switching it to the natural key would merge a zone's versions and change which row a trip lands in. Source: R-08, ADR 0009, ADR 0015.
- `D-06` Publish the billable measures unfiltered, so a zone-day with no billable trip carries zeros rather than disappearing, and leave the decision to omit such a row to the consumer that wants that population. Omitting here would break the relation's population commitment and its coverage test, and the revenue report applies its own requirement instead. Source: R-08, user answer on the report's population.

## Logical Model

The Domain has `logical-model/`, and this intent changes a boundary model it binds.

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets:
  agg_trip_zone_daily: changed
metrics:
  billable_trip_count: {}
  billable_revenue: {}
logical_sources:
  LTS2_zone_day_agg: changed
```

`LTS2_zone_day_agg` gains `billable_trip_count` and `billable_revenue` in its `column_map`, mapping to the new columns, and its `note` drops the refusal of billable measures it currently records. Both metrics already exist in the document, so none is added. `trip_count` stays mapped to `trip_count`, which keeps its population-wide meaning (D-01).

## Rejected

- Redefining `trip_count` and `total_revenue` to count billable trips — it would satisfy the revenue report with no new columns, but silently change the answer for every other consumer of this boundary relation and contradict the active contract and the semantic source that describe them as population-wide.
- Building the billable measures in the finance mart from `core.fct_trip` — that is the second build the request removes.
- Dropping zero-billable zone-days here, so the aggregate's rows equal the report's — it would break the grain commitment and the coverage test, and the aggregate's other consumers would lose rows.

## Consumers

- `finance.mart_daily_zone_revenue` (this intent re-sources it from here).
- `transformation/tests/assert_semantic_content_holds.sql`, `assert_semantic_levels_hold.sql` (generated from the semantic model).
- `logical-model/nyc_taxi_analytics.ossie.yaml` — `LTS2_zone_day_agg`.
- `contracts/agg/agg_trip_zone_daily.odcs.yaml`, which must gain the new columns.
- Outside the repository: the operations team's own daily figures by zone, the reason this relation exists and the reason the request names it as the one source.

## History

- 2026-11-25 — lfq-2 — design record written; billable-only measures and `reporting_region` added so a revenue report can read this relation as its one source — D-01, D-02, D-03, D-04, D-05, D-06 — terms: none new
