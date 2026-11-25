---
artifacts: [agg_trip_zone_daily]
---

# agg_trip_zone_daily

## Grain

One row per pickup date × pickup zone, unchanged. `reporting_region` joins the select
list without widening it: it is functionally dependent on the zone version in force on
the pickup date, which is already part of the row's identity (Verification D6).

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer, 2026-11-25.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets:
  trips: changed
metrics: {}
logical_sources:
  LTS2_zone_day_agg: changed
```

`LTS2_zone_day_agg` gains `billable_trip_count` and `billable_revenue` in its
`column_map`, bound to the metrics of those names that the document already defines,
following the pattern `LTS3_zone_daypart_dow` uses for its own `billable_trip_count`.
`billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue` and
`billable_toll_revenue` stay unbound: no metric for them is declared, the same reason
`LTS7_daily_zone_revenue` refuses the report's four component measures today. No
metric, concept or mapping is added, so this carries no design decision. The ontology
mappings under `ontology/` map concepts onto the document's logical fields, and no
logical field is added or renamed by this binding, so no ontology document changes.

## Decisions

- `D-01` Publish the billable measures beside the existing all-trips ones rather than redefining `trip_count` and `total_revenue` as billable. Operations reads this relation and its figures must not move (R-07); a redefinition would silently restate 7,997 published rows and the refund population would disappear from the only daily zone relation in `agg`. Source: user answer (additive), R-02, R-07.
- `D-02` The new measures are named `billable_trip_count`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue`, `billable_total_revenue`. The `billable_` prefix is what distinguishes them from the all-trips `trip_count`/`total_revenue` on the same row, and it matches the prefix `agg_trip_zone_daypart_dow` already uses for its billable count, so a reader who knows one agg model reads the other. Source: R-02, repository (`agg_trip_zone_daypart_dow`).
- `D-03` The billable measures are computed as `count(*) filter (where f.is_billable)` and `sum(<measure>) filter (where f.is_billable)`, over the same window and the same single scan as the existing aggregates, not as a second grouped subquery joined back. One scan keeps the row's all-trips and billable figures provably from the same population, and a join-back would be a place for the two halves to drift. Source: R-02, ADR 0003.
- `D-04` `reporting_region` is carried from the zone version in force on the pickup date, by adding it to the existing group by, not by a second join in the consuming report. It is functionally dependent on `(pickup_date, pickup_location_id)` (Verification D6), so it adds no row, and putting it here is what lets the report drop its `dim_zone` join (R-01). Source: R-01, R-03.
- `D-05` The model's existing columns, tests, contract shape and materialisation are untouched; this is an additive change, so the ODCS version moves minor. Source: R-07, `.agents/skills/data-contract` version rule (added properties are minor).

## Rejected

- **Redefine `trip_count`/`total_revenue` as billable** — would restate Operations' published daily figures and remove the refund rows from `agg`; the user chose the additive form.
- **A separate `agg_trip_zone_daily_billable` relation** — two relations in `agg` answering "daily by zone" is the duplication the request exists to remove.
- **Have the report join `dim_zone` for `reporting_region`** — keeps a `dim_zone` dependency in the report and splits the zone label across two sources of truth (R-01).
- **Compute the billable half in a joined subquery** — a second scan and a join-back, with no benefit over a filter aggregate in the same pass.

## Consumers

- `finance.mart_daily_zone_revenue` (new consumer: the daily zone revenue report).
- `transformation/tests/assert_semantic_content_holds.sql` and
  `assert_semantic_levels_hold.sql` (generated; regenerated when the logical source changes).
- The semantic layer's `LTS2_zone_day_agg` logical source, and anything reading the agg
  through the canonical model.
- Operations, reading the existing all-trips columns (outside this repository).

## History

- 2026-11-25 — jl2 — added billable measures and `reporting_region` so the finance daily zone revenue report can read this relation as its only source — D-01, D-02, D-03, D-04, D-05 — terms: none new (the billable population is already defined as **Billable trip** in `CONTEXT.md`)
