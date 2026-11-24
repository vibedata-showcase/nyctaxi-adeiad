---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Borough-to-borough flow by month: for every month of the reporting window and every pair of boroughs in the zone dimension, the billable trips, their total amount, and the pair's share of its origin borough's pickups.

## Grain

One row per (month, origin borough, destination borough), covering every month in the reporting window crossed with every borough in `dim_zone`, zero-trip pairs included. Alternatives: observed pairs only — rejected, because a pair missing from the table cannot be told from a pair that carried no traffic, and the request is "from each borough to each borough"; the zone-pair grain of `agg_od_flow_matrix` — rejected, because the question is about crossings between boroughs, not corridors.

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer.

## Decisions

- `D-01` New model `agg_borough_flow_monthly.sql` in the `agg` layer, materialised as a table, `access: public` with `contract: { enforced: true }`. Gold aggregates built from facts live in `agg` and `agg_od_flow_matrix` is the flowing precedent; the folder's table materialisation suits a window-bounded aggregate rebuilt each run, and `access: public` states that a consumer outside the repository reads it. Source: R-07; repository convention.
- `D-02` Built from `fct_trip` with `dim_zone` joined twice on the surrogate `zone_key`, once per role. `agg_od_flow_matrix` is not reused: its 25-trip floor and zone grain cannot reproduce borough totals or the shares R-02 and R-03 reconcile. `agg_trip_zone_daily` carries no destination borough. Source: R-02, R-03; ADR 0017.
- `D-03` Population is billable trips inside the reporting window: `in_report_window(f.pickup_datetime)` and `f.is_billable`. A gold mart that reports revenue or flows applies the billable rule (ADR 0003), and reconciliation across every billable trip is the population's definition. Source: R-02, R-03; ADR 0018.
- `D-04` Measures are `count(*)` as `trip_count` and `sum(f.total_amount)` as `total_revenue`, the pair `agg_od_flow_matrix` and `mart_daily_zone_revenue` already publish. Source: R-03; repository.
- `D-05` The grid is the cross join of the window's months with the distinct `borough_name` values in `dim_zone`, left joined to the observed pairs. The months come from `dim_date`, filtered by `in_report_window` on `calendar_date` and reduced to distinct `month_start_date`, so neither spine is a literal list and both follow the window and the dimension. Source: R-01, R-05; ADR 0018.
- `D-06` `is_intra_borough` is `origin_borough = dest_borough`, keeping the diagonal pair visible rather than folded away. Source: R-04.
- `D-07` `share_of_origin_borough_trips` is `trip_count` over the sum of `trip_count` for the row's (month, origin borough), taken with a window over the joined grid so zero-trip pairs stay in the denominator. It is null through `safe_divide` when an origin borough has no billable pickup that month. Source: R-04; the `safe_divide` convention that a zero denominator yields null.
- `D-08` A trip whose pickup or dropoff zone key is null has no borough, so both joins are inner and a singular test asserts no billable in-window trip carries a null zone key: R-02 then fails loudly instead of the totals shrinking silently. No placeholder borough is invented. Source: ADR 0015; R-02.
- `D-09` Unresolved zones keep their own borough groups (`Unknown`, `N/A`), and `EWR` keeps its out-of-state group; nothing is filtered or remapped, so the rollup reports them. Source: R-06; ADR 0012.
- `D-10` The relation publishes an ODCS contract at `contracts/agg/agg_borough_flow_monthly.odcs.yaml`, set active when the relation exists, and carries a `unique` test on the grain triple, `not_null` on the grain, the measures and the flag, plus a singular test for the billable reconciliation and the null-key guard. Source: R-07, R-02; `repo-map.json` contract boundary.
- `D-11` Canonical mapping is a new logical source `LTS10_borough_flow_monthly` on the `trips` dataset of `logical-model/nyc_taxi_analytics.ossie.yaml`, priority group 0, binding `billable_trip_count` to `trip_count` and `billable_revenue` to `total_revenue` at (month, origin borough, destination borough), with the window-and-billable content filter. The detail source can answer the same question at its own cost; the aggregate is the exact-grain route. `share_of_origin_borough_trips` is refused in the source `note` for want of a declared metric: it is a ratio at the table's own grain, not an additive measure. Source: R-07; semantic-model skill.
- `D-12` No existing model is edited: the change is the new model, its properties entry, its contract and the canonical document entry, so `fct_trip`, `dim_zone`, `agg_od_flow_matrix` and every mart keep their SQL, properties and values. Source: R-08.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets:
  - name: trips
    change: changed
metrics: []
logical_sources:
  - name: LTS10_borough_flow_monthly
    change: added
ontology:
  documents:
    - ontology/nyc_taxi.ontology.yaml
  concepts: []
  mappings: []
```

No metric is added: `billable_trip_count` and `billable_revenue` already measure what the table aggregates. No concept is added, retired or re-identified: the existing Trip, Zone and Date mappings already carry the keys this source groups on.

## Rejected

- Building on `agg_od_flow_matrix` — its floor and zone grain make the borough totals and shares unreconcilable (ADR 0017).
- Publishing observed pairs only — an absent pair and a zero-traffic pair would look the same.
- Applying the 25-trip floor at borough grain — rejected by the Requirement and ADR 0018.
- A share denominator that excludes the intra-borough row — the leaving share is then no share of all pickups, which is what R-04 measures.
- A literal month or borough list in the SQL — it drifts from the window and from the dimension.

## Consumers

- Mobility Planning, outside the repository, answering the city's question about traffic crossing borough lines.
- The semantic layer, through `LTS10_borough_flow_monthly` in `logical-model/nyc_taxi_analytics.ossie.yaml`.
- No repository model reads it yet.

## History

- 2026-11-24 — R9 borough flow — created — D-01 to D-12 — terms: none new (Borough flow and Leaving-borough share landed with the Requirement).
