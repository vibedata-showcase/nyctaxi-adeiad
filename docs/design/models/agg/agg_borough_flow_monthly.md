---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Monthly borough-to-borough flow with the share of an origin borough's trips that crosses a borough line.

## Grain

One row per (calendar month, origin borough, destination borough) that carried at least one billable trip. `trip_month` is the first day of the month of the trip's pickup date.

## Schema

- `transformation/models/marts/agg/` → `agg` (default). Source: user answer, this intent.

## Decisions

- `D-01` Build from `fct_trip` with `dim_zone` joined twice, once per role, rather than from an existing aggregate. `agg_od_flow_matrix` is a zone pair with no month and a 25-trip floor (ADR 0017) that this surface must not apply, and `mart_daily_zone_revenue` has no destination borough, so neither carries this grain. Source: R-01, R-03; ADR 0018.
- `D-02` Both joins are `left`, so a trip whose zone key resolves to nothing stays in the table as a null borough rather than disappearing from the population. No trip loses its row to a join. Source: R-01; playbook default (keep every row).
- `D-03` Count and sum billable trips only, `total_amount` summed, inside the reporting window. A non-billable trip is not traffic anyone paid for, and this surface reports both trips and revenue, so one population serves both. Source: R-02, user answer; [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-04` Publish every observed pair and no minimum-trip floor. The floor in [ADR 0017](../../../adr/0017-published-flows-have-a-25-trip-floor.md) governs the zone-pair matrix; at borough grain it would remove destination rows and leave the share computed over a trimmed population. Source: R-03, user answer; [ADR 0018](../../../adr/0018-borough-level-flows-are-published-without-a-floor.md).
- `D-05` Omit a pair that carried no billable trip, rather than emitting a zero row, so `trip_count` is never zero and the table has no rows nothing happened on. Source: R-04, user answer.
- `D-06` A destination borough that differs from the origin counts as leaving, unresolved and out-of-state groups included, and they appear as destination rows of their own. Source: R-06, user answer; [ADR 0019](../../../adr/0019-a-destination-with-no-borough-counts-as-leaving.md).
- `D-07` Carry the share's numerator and denominator on every row, beside the share: `origin_trip_count` (the origin borough's billable trips that month) and `cross_borough_trip_count` (those of them that left), with `cross_borough_share = cross_borough_trip_count / origin_trip_count` and `is_cross_borough` beside them. A reader can add the rows back to the denominator, and the rate is a ratio of two stated counts rather than a number nothing explains ([ADR 0016](../../../adr/0016-rates-are-rebuilt-from-summed-numerators-and-denominators.md)). Source: R-05, R-06; convention.
- `D-08` Both repeated columns belong to the origin-month, not the row: a destination row carries its origin's whole-month counts, so the two are not additive across destination rows and the properties file says so on each. Source: R-05; convention.
- `D-09` `access: public` with `contract: {enforced: true}`, materialised as a table in the `agg` folder, which is what the folder already resolves to for the other marts there. Source: convention, `dbt_project.yml`.
- `D-10` The table is described from its own SQL: the floor's absence, the share's population and the unresolved destinations each stated where a reader meets them, and no number in a description that the data would change. Source: R-08.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets: []
metrics: []
logical_sources:
  - added: LTS10_borough_flow_month
```

The table is the trips star rolled up by two borough roles, which is one aggregate logical source on the document that already owns the trips star: `billable_trip_count` and `billable_revenue` bind to it unchanged, because its population is the same billable in-window population with no floor. The share and its two repeated counts stay refused in that source's `note`: they compare the two zone roles against each other, and no metric expression over the fact's fields can state that comparison, while the two repeated counts are not additive across destination rows. No new metric and no new dataset, so nothing here is a design decision beyond where the source sits. No ontology change: no concept, identity or mapping moves.

## Rejected

- Building on `agg_od_flow_matrix` — its 25-trip floor and its zone grain would drop rows this surface publishes.
- Building on `mart_daily_zone_revenue` — it has no destination borough; adding one there would re-grain a published mart the request did not name.
- Applying ADR 0017's floor at borough grain — it removes destination rows and distorts the share.
- Mapping `Unknown`, `N/A` and `EWR` out of the crossing count — the share would move with how well the TLC placed zones rather than with the traffic.
- A precomputed share with no counts beside it — a reader could neither check it nor see what it was measured over.

## Consumers

None yet: a new relation. The semantic layer's trips document gains an aggregate logical source over it; nothing else in the repository reads it.

## History

- 2026-11-25 — borough-to-borough Q1 2024 flows — design record written — D-01…D-10 — terms: added Cross-borough share; sharpened Published flow
