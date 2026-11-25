---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Monthly borough-to-borough flow with each origin borough's cross-borough share, built from `fct_trip` with `dim_zone` joined twice — once as the origin, once as the destination.

## Grain

One row per (month, origin borough, destination borough) carrying at least one billable trip in the month. A month is a calendar month from `dim_date.month_start_date`, not a truncated timestamp.

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: `repo-map.json` `layers.agg`; the folder's declared schema.

## Decisions

- `D-01` Built from `fct_trip` with `dim_zone` joined twice, not from `agg_od_flow_matrix`. The OD matrix is one row per zone pair for the whole reporting window — coarser than a month and floored at 25 trips — so it carries neither this grain nor the full population. Source: R-01, R-02; `docs/design/models/agg/agg_od_flow_matrix.md`.
- `D-02` No 25-trip floor. Every borough pair with at least one billable trip is published. ADR 0017's floor is a property of the 265-zone grain, not of flow publishing; the boundary is recorded in ADR 0018. Source: R-01; user answer 2026-11-25.
- `D-03` Billable trips inside the reporting window only, the rule every revenue and flow mart applies. Source: R-02; ADR 0003.
- `D-04` `total_revenue` is `sum(total_amount)`, so no-charge and dispute trips count, matching `mart_daily_zone_revenue` and the finance marts. Source: R-03; ADR 0013; user answer 2026-11-25.
- `D-05` `trips_with_revenue` is published beside the revenue as the coverage count the Coverage default requires. Every billable trip in Q1 carries a total, so it equals `trip_count` today; it is published so a future null total shows as reduced coverage rather than as silently smaller revenue. Source: R-03; playbook default (Coverage).
- `D-06` The share is per origin borough per month: of the borough's trips, the share that ended in a different borough. It is a property of the origin, so the boroughs' shares do not sum to one, and the value is repeated on every row of that origin and month. Source: R-04; request.
- `D-07` The share's denominator is the origin's trips whose destination borough is resolved. A trip ending in "Unknown" or "N/A" (ADR 0012) is published as its own row but is not evidence of crossing a borough line, so it leaves the denominator and `origin_unresolved_trip_count` publishes the count left out. Source: R-04; user answer 2026-11-25.
- `D-08` An unresolved origin — "Unknown", "N/A", or a null borough — carries a null share, not a computed one. Every destination differs from "Unknown", so a computed share would read 100% by construction and say nothing about traffic. Source: R-04; ADR 0012.
- `D-09` Both zone joins and the date join are LEFT joins: a trip whose key finds no dimension row keeps its row with a null borough rather than vanishing, and a null borough counts as unresolved. Source: R-02; ADR 0015.
- `D-10` Zero-activity pairs are omitted: no row is emitted for a pair with no billable trip in the month. Source: R-01; user answer 2026-11-25.
- `D-11` The two zone roles are carried as `origin_borough` and `dest_borough` columns, not as surrogate keys, so a pair keeps its identity across a zone re-designation — the same reasoning as the OD matrix's natural-key decision. Source: `docs/design/models/agg/agg_od_flow_matrix.md` D-03.

## Logical Model

```yaml
documents:
  - nyc_taxi_analytics.ossie.yaml
datasets:
  - trips: changed
logical_sources:
  - LTS10_borough_flow_month: added
metrics: []
```

The relation is registered as a `priority_group: 0` aggregate source of the `trips` star, grouping by the month level through `trips_to_date` and by the borough level through each zone role. `billable_trip_count` and `billable_revenue` bind; the repeated origin totals, the precomputed share and the row-level flags are refused in the source's `note`. No metric is added and no concept is declared: the table carries the trips the star carries, rolled up, and no new business object.

## Rejected

- **Applying ADR 0017's 25-trip floor at borough grain** — withholds real borough-level traffic (99 / 55 / 99 trips a month) and moves the share, for a noise problem that does not exist at 8 members. Recorded as ADR 0018.
- **A quarter-level floor** — a January figure would depend on March volume.
- **Counting unresolved destinations in the share** — makes "Unknown" an origin read 100% cross-borough by construction.
- **Excluding unresolved boroughs from the table** — hides traffic that happened (ADR 0012).
- **A dense borough × borough grid with zero rows** — invents zeros and triples the row count.
- **Rebuilding from `agg_od_flow_matrix`** — wrong grain and a floored population.

## Consumers

- Mobility Planning, answering the city's question on cross-borough traffic, and anyone asking how much traffic leaves the borough it starts in.
- The semantic layer's `trips` star reaches it as the month × origin borough × destination borough aggregate source.

## History

- 2026-11-25 — JL — created with the relation — D-01 to D-11 — terms: added Cross-borough trip, Cross-borough share
