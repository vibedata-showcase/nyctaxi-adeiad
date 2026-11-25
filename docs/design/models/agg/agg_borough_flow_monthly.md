---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Borough-to-borough traffic and revenue, monthly, with each origin borough's crossing share. The zone dimension joined twice, once per role, rolled up to borough.

## Grain

One row per (trip month, origin borough group, destination borough group), over the full cross product of the window's months and the nine borough groups — not only the pairs that carried a trip. The alternative, emitting only pairs with traffic, was rejected because a pair with no billable trip in a month would then be indistinguishable from a pair the report omitted, and a borough's row set would change shape month by month (requirement `R-01`, user answer "Full grid, zero rows included").

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer, "agg (the folder's current schema)" — the folder's `+schema` in `dbt_project.yml`.

## Decisions

- `D-01` Built from `fct_trip` with `dim_zone` joined twice, on the pickup and dropoff surrogate keys, rolled up by `dim_zone.borough_name`. The published zone-pair matrix is not the input: it is truncated by ADR 0017's floor, so its totals are a subset of the fact and a rollup of it would undercount exactly the thin cross-borough pairs this surface exists to show. Source: `R-03`, `R-05`, user answer "No floor on this table".
- `D-02` Nine borough groups: the eight `borough_name` values `dim_zone` carries, plus an `unresolved` member for a trip whose zone key matches no `dim_zone` row (a null-safe `coalesce`, not an inner join), so no trip leaves the table unexplained. Source: `R-05`, user answer "Eight boroughs plus 'unresolved' (243 rows)", [ADR 0015](../../adr/0015-unmatched-dimension-keys-stay-null.md).
- `D-03` Billable trips only, inside the reporting window, per ADR 0003: a non-billable trip is not traffic anyone paid for. Source: `R-02`, [ADR 0003](../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-04` No minimum-traffic floor at this grain; every pair that carries a billable trip is published however thin. The floor is a rule about the zone-pair surface and would remove the small cross-borough pairs the crossing question is made of. Source: `R-03`, [ADR 0018](../../adr/0018-a-borough-grain-flow-carries-no-traffic-floor.md).
- `D-05` Revenue is the summed trip total per pair, the same measure `agg_od_flow_matrix` and `mart_daily_zone_revenue` report, so the city's revenue figure is comparable with the revenue surfaces the business already reads. Source: `R-02`.
- `D-06` Trips are attributed through each trip's own zone surrogate, the version resolved as of the trip's pickup date, not the zone's current version, so a zone re-designation does not reassign history. Source: [ADR 0009](../../adr/0009-type-2-only-where-the-source-versions-history.md), `R-02`.
- `D-07` The crossing share is computed over trips whose destination resolves to a borough: numerator the trips whose destination borough group differs from the origin's, denominator those same resolved-destination trips, with the denominator and the excluded unresolved-destination count carried on the row. A trip ending in a zone the TLC cannot place is not evidence of crossing either way, so counting it as crossing or as staying would both be invented. Source: `R-04`, user answer "Resolved ends only".
- `D-08` The share is null for a row whose origin does not resolve to a borough: a zone the source cannot place is not "the borough they started in", so no crossing can be attributed to it. The counts on that row are still published. Source: `R-04`, user answer "Resolved ends only".
- `D-09` `EWR` is a resolved borough group, so a trip between it and a New York borough is a crossing. It is a real `dim_zone` borough in the `Out of State` region, not an unresolved zone. Source: `R-05`, repository (`core.dim_zone`).
- `D-10` The crossing count, the resolved-destination count, the unresolved-destination count and the share are per (month, origin borough) and are therefore repeated on every destination row of that origin. They must never be summed across destination rows; the trip and revenue columns are the only pair-level measures. Source: `R-04`.
- `D-11` `is_cross_borough` states, per row, whether the two borough groups differ, mirroring `is_intra_borough` on the zone-pair matrix, so a consumer filters crossing traffic without comparing two strings. Source: `R-04`, request ("trips that leave the borough they started in").
- `D-12` Each role carries a boolean saying the group is unresolved, rather than leaving a consumer to recognise the values `Unknown` and `N/A` by name. A rollup that must exclude unresolved zones can then filter a column instead of matching strings. Source: `R-05`, [ADR 0012](../../adr/0012-unresolved-zones-are-retained-and-flagged.md).
- `D-13` Materialised as a table in the `agg` layer, the layer's default, since it is a gold aggregate read repeatedly and not a view over a large fact. Source: repository (`dbt_project.yml` `marts.agg`).

## Rejected

- Building on `agg_od_flow_matrix` — its ADR 0017 floor makes it a strict subset of the fact, so a borough rollup over it would not reconcile to the quiet trips the question is about.
- Applying a 25-trip floor per pair per month — see ADR 0018.
- Emitting only the pairs that carried a trip — the grid would change shape between months and an absent pair would read as a missing report.
- A second table at (month, origin borough) grain for the share — one surface was asked for, and the repeated at-level columns keep the share beside the flows it describes.
- Recognising unresolved groups by their value names instead of flags — see `D-12`.

## Consumers

None in this repo.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets: []
logical_sources:
  added: [LTS10_borough_flow_monthly]
  changed: []
  retired: []
metrics: []
concepts: []
mappings: []
```

The relation is a rollup of the trips star's own rows over the whole billable population, so it becomes a further aggregate logical source on the `trips` dataset in the trips document, at the month level of `date` and the borough level of `zone` in both roles. No metric is added: the two pair-level measures are the existing `trip_count` and `billable_revenue`. No concept is reached, because the aggregate carries no key of the Trip concept and no new ontology object is introduced.

## History

- 2026-11-25 — new-intent-ef17c719 — design record written — D-01, D-02, D-03, D-04, D-05, D-06, D-07, D-08, D-09, D-10, D-11, D-12, D-13 — terms: added Borough flow, Crossing share
