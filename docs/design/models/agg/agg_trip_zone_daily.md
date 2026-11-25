---
artifacts: [agg_trip_zone_daily]
---

# agg_trip_zone_daily

Daily zone demand with period-over-period context, one row per pickup zone and trip date, built from `fct_trip` with `dim_zone` joined as of the pickup date.

## Grain

One row per pickup zone and trip date, over the reporting window. The grain is unchanged by this intent.

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer, accepting the folder's current `+schema` in `dbt_project.yml`.

## Decisions

- `D-01` Carry the billable population beside the all-trip figures: `billable_trip_count`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue` and `billable_total_revenue`, each `filter (where f.is_billable)` over the same group by that already produces the row. `trip_count` and `total_revenue` keep counting every in-window trip, so no existing consumer of this relation reads a different number and the added properties move the contract at the minor level only ([ADR 0018](../../../adr/0018-the-daily-zone-revenue-report-publishes-the-billable-population.md)). The billable measure applies the rule of [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md). Source: docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-4-667f7960.md R-01 and R-05, user answer.
- `D-02` The six new columns are named `billable_<measure>`, matching `billable_trip_count` on `agg_trip_zone_daypart_dow`, and sit after the existing columns so every published column keeps its position. A reader tells the two populations apart by name, never by which relation they came from. Source: convention, `transformation/models/marts/agg/agg_trip_zone_daypart_dow.sql`.
- `D-03` A zone-day whose only in-window trips are non-billable stays in this relation with a zero `billable_trip_count`, because the row exists for its all-trip figures and its window statistics. Dropping it would change the existing columns' population, which R-05 forbids. Source: docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-4-667f7960.md R-05.
- `D-04` `reporting_region` is not added to this relation. The one consumer that needs it carries the date and joins the dimension half-open, and adding a seventh published column is a change to a boundary relation the Requirement did not ask for ([ADR 0009](../../../adr/0009-type-2-only-where-the-source-versions-history.md)). Source: docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-4-667f7960.md, `## Design pending`.
- `D-05` This relation joins the marts that apply the billable rule, for its billable columns only ([ADR 0018](../../../adr/0018-the-daily-zone-revenue-report-publishes-the-billable-population.md)). [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md) enumerates those marts and names only `agg_od_flow_matrix` among the aggregates, so that sentence is amended through `domain-modeling` in the same change that ships this, not by this record. Source: docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-4-667f7960.md, flagged in the requirement stop.

## Logical Model

The six new columns need no new binding: `billable_trip_count` and `billable_revenue` are already served at exactly this grain by the report's own logical source, `LTS7_daily_zone_revenue`, so binding them here too would offer one metric twice at one grain and leave the compiler choosing arbitrarily. The rolling and lag columns stay refused for the reason the source's note already gives: their windows count rows, not days, so a zone-day with no trips stretches them.

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets: []
metrics: []
logical_sources:
  - name: LTS2_zone_day_agg
    change: changed
ontology_documents: []
concepts: []
mappings: []
```

`LTS2_zone_day_agg` changes only in its `note`, which records why the six new columns are not bound. `trips` as a dataset, every metric, every concept and every mapping stay as they are.

## Rejected

- Redefining `trip_count` and `total_revenue` as billable-only: it moves every existing consumer's numbers and breaks the published contract, to answer a question about one report.
- Adding `reporting_region` here so the report reads one relation: it is a published-column addition this Requirement does not cover, and the dimension's `reporting_region` is already correct at this grain under a half-open as-of join.
- Dropping the zero-billable zone-days so this relation matches the report row for row: it would change the existing all-trip columns' population and hide the rows the aggregate exists to show.

## Consumers

`finance.mart_daily_zone_revenue`, and the logical source `LTS2_zone_day_agg` of `trips` in [`logical-model/nyc_taxi_analytics.ossie.yaml`](../../../logical-model/nyc_taxi_analytics.ossie.yaml), which binds `trip_count`. The semantic-content and semantic-level tests read it. Nothing else in the repository selects from it.

## History

- 2026-11-25 — zone-revenue-report-from-operations-figures-4 — design record written; billable measures added beside the all-trip ones so the daily zone revenue report reads its figures from here — D-01, D-02, D-03, D-04 — terms: none new
