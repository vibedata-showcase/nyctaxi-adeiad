---
artifacts: [mart_daily_zone_revenue]
---

# mart_daily_zone_revenue

Daily revenue by pickup zone, read every morning by Finance, built from the operations figures in `agg_trip_zone_daily`.

## Grain

One row per pickup zone and trip date. Unchanged: the report keeps omitting a zone-day with no billable trip, so its grain is the zone-day population that carries a billable trip.

## Schema

- `transformation/models/marts/finance/`: `finance` (default). Source: user answer, accepting the folder's current `+schema` in `dbt_project.yml`.

## Decisions

- `D-01` Apply the billable rule and the reporting window here, in gold, and nowhere upstream, so quality work can still see the rows this excludes ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: docs/requirement/2026-08-29-the-trip-fact.md R-03, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-02` Read the measures from `agg_trip_zone_daily`'s billable columns rather than from `fct_trip`, so one build answers the daily zone question for both Finance and Operations ([ADR 0018](../../../adr/0018-the-daily-zone-revenue-report-publishes-the-billable-population.md)). The billable filter moves upstream into the aggregate; the report selects the billable columns it maps onto its published ones. Source: docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-4-667f7960.md R-02.
- `D-03` Filter `billable_trip_count > 0`, so a zone-day with no billable trip is absent rather than published as a zero row. This is what keeps the report at its present 7,961 rows against the aggregate's 7,997 and keeps every committed value unchanged. Source: docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-4-667f7960.md R-04, user answer.
- `D-04` Take `reporting_region` from `dim_zone` through a half-open as-of join on the natural key and `trip_date`, not through the current version. The aggregate carries no region, and an unfiltered natural-key join multiplies rows for the zones the dimension versions ([ADR 0009](../../../adr/0009-type-2-only-where-the-source-versions-history.md)). Source: docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-4-667f7960.md `## Design pending`, [ADR 0009](../../../adr/0009-type-2-only-where-the-source-versions-history.md).
- `D-05` `trip_count` is the billable trip count and its description says so. The model has always filtered on `is_billable`, so the existing text "Trips, billable or not." contradicted the SQL; this intent corrects the text, not the value. Source: docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-4-667f7960.md R-06.
- `D-06` The published shape does not move: the same eleven columns, types, order and values, so the contract keeps its version and only its prose changes. Source: docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-4-667f7960.md R-03, R-06.
- `D-07` `trip_count`'s description is a `{{ doc(...) }}` pointer, not plain text. `odcs.py generate` owns a contracted relation's descriptions and resolves `trip_count` by column name to the all-trip `trip_count` metric, so any plain text here is replaced by `Trips, billable or not.` — the opposite of what the model does. `generate` leaves a `doc()` pointer alone, which is the documented route for a column whose meaning the document's same-named metric states wrongly. Source: docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-4-667f7960.md R-06, `.agents/skills/data-contract/SKILL.md` (a `{{ doc() }}` pointer is left alone).

## Logical Model

The report keeps its published columns and its logical source, `LTS7_daily_zone_revenue`, which goes on binding `billable_trip_count` to `trip_count` and `billable_revenue` to `total_revenue`. Only that source's `content_filter` changes, to the population the rebuilt model reads, and its `note` loses the refusals that no longer apply. No dataset, metric, concept or mapping is added or retired.

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets: []
metrics: []
logical_sources:
  - name: LTS7_daily_zone_revenue
    change: changed
ontology_documents: []
concepts: []
mappings: []
```

## Rejected

- Keeping the `fct_trip` build and reading the aggregate as a cross-check: the request is one source, not two builds that agree.
- Publishing zero rows for the 36 zero-billable zone-days: it grows the report's row set without changing a total, so the report changes shape to say nothing new.
- Joining `dim_zone` on the natural key without the date: it returns 8,220 rows for 7,997 aggregate rows, because seven zones carry two versions.
- Adding `reporting_region` to the aggregate instead: a published-column addition the Requirement does not cover.

## Consumers

Finance reads it every morning. In this repository, the logical source `LTS7_daily_zone_revenue` of `trips` in [`logical-model/nyc_taxi_analytics.ossie.yaml`](../../../logical-model/nyc_taxi_analytics.ossie.yaml) binds `billable_trip_count` and `billable_revenue` to it, and the semantic-content and semantic-level tests read it.

## History

- - 2026-10-14 — trip-fact — design record written; audience wording removed from the model description — D-01
- - 2026-11-25 — zone-revenue-report-from-operations-figures-4 — rebuilt from `agg_trip_zone_daily`'s billable measures, region taken through an as-of join, `trip_count` description corrected — D-02, D-03, D-04, D-05, D-06, D-07 — terms: none new
