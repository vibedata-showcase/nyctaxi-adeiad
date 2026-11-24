---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Borough-to-borough flow by month: for every month of the reporting window and every pair of groups in the zone dimension (the six boroughs plus one `unresolved` group), the billable trips, their total amount, and the pair's share of its origin borough's pickups.

## Grain

One row per (month, origin borough, destination borough), covering every month in the reporting window crossed with every group the zone dimension yields — the six boroughs and one `unresolved` group holding `Unknown`, `N/A` and any zone-less trip — zero-trip pairs included. Alternatives: observed pairs only — rejected, because a pair missing from the table cannot be told from a pair that carried no traffic, and the request is "from each borough to each borough"; the zone-pair grain of `agg_od_flow_matrix` — rejected, because the question is about crossings between boroughs, not corridors; `Unknown` and `N/A` as boroughs of their own — rejected at the design stop, because an unresolved zone is a zone the TLC lists but cannot place in a borough.

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer.

## Decisions

- `D-01` New model `agg_borough_flow_monthly.sql` in the `agg` layer, materialised as a table, `access: public` with `contract: { enforced: true }`. Gold aggregates built from facts live in `agg` and `agg_od_flow_matrix` is the flowing precedent; the folder's table materialisation suits a window-bounded aggregate rebuilt each run, and `access: public` states that a consumer outside the repository reads it. Source: R-07; repository convention.
- `D-02` Built from `fct_trip` with `dim_zone` joined twice on the surrogate `zone_key`, once per role. `agg_od_flow_matrix` is not reused: its 25-trip floor and zone grain cannot reproduce borough totals or the shares R-02 and R-03 reconcile. `agg_trip_zone_daily` carries no destination borough. Source: R-02, R-03; ADR 0017.
- `D-03` Population is billable trips inside the reporting window: `in_report_window(f.pickup_datetime)` and `f.is_billable`. A gold mart that reports revenue or flows applies the billable rule (ADR 0003), and reconciliation across every billable trip is the population's definition. Source: R-02, R-03; ADR 0018.
- `D-04` Measures are `count(*)` as `trip_count` and `sum(f.total_amount)` as `total_revenue`, the pair `agg_od_flow_matrix` and `mart_daily_zone_revenue` already publish. Source: R-03; repository.
- `D-05` The grid is the cross join of the window's months with the distinct borough groups, left joined to the observed pairs. The months come from `dim_date`, filtered by `in_report_window` on `calendar_date` and reduced to distinct `month_start_date`; the groups come from `dim_zone` with `Unknown` and `N/A` mapped to `'unresolved'` and one row added for it if no zone yields it. Neither spine is a literal list, so both follow the window and the dimension. No volume threshold filters a pair: every pair is published, and a zero-trip pair carries 0 trips and 0 revenue. Source: R-01, R-05; ADR 0012; ADR 0018.
- `D-06` `is_intra_borough` is `origin_borough = dest_borough`, keeping the diagonal pair visible rather than folded away; the `unresolved`-to-`unresolved` row is therefore intra-group. Source: R-04.
- `D-07` `share_of_origin_borough_trips` is the row's `trip_count` over the origin borough's `trip_count` to borough destinations that month, taken with a window over the joined grid, so zero-trip pairs stay in the denominator. A row touching `unresolved` on either side is null, as is a borough origin with no borough-destination trip; both go through `safe_divide`. Source: R-04; ADR 0016; design-stop answer that unresolved is outside the share.
- `D-08` Both zone joins are left joins and a missing borough becomes `'unresolved'`, mirroring `agg_weather_demand_daily`, so a trip whose zone key is null stays in the totals as an unresolved trip rather than disappearing. No placeholder borough is invented and no trip is dropped. Source: ADR 0015; ADR 0012; R-02.
- `D-09` `Unknown`, `N/A` and any zone-less trip collapse into one `unresolved` group; the six boroughs, `EWR` among them, keep their own groups. Nothing is filtered, so the unresolved trips stay in the totals and outside the share. Source: R-06; ADR 0012; design-stop answer.
- `D-10` The relation publishes an ODCS contract at `contracts/agg/agg_borough_flow_monthly.odcs.yaml`, set active when the relation exists, and carries a `unique` test on the grain triple, `not_null` on the grain, the measures and the flag, a singular test that each month's `trip_count` and `total_revenue` reconcile to `fct_trip`'s billable population, and a singular test that borough-to-borough shares sum to 1 per (month, origin borough) while rows touching `unresolved` are null. Source: R-07, R-02, R-04; `repo-map.json` contract boundary.
- `D-11` Canonical mapping is a new logical source `LTS10_borough_flow_monthly` on the `trips` dataset of `logical-model/nyc_taxi_analytics.ossie.yaml`, priority group 0, binding `billable_trip_count` to `trip_count` and `billable_revenue` to `total_revenue` at (month, origin borough, destination borough), with the window-and-billable content filter. The detail source can answer the same question at its own cost; the aggregate is the exact-grain route. `share_of_origin_borough_trips` is refused in the source `note` for want of a declared metric: it is a ratio at the table's own grain, null on unresolved rows, not an additive measure. Source: R-07; semantic-model skill.
- `D-12` No existing model is edited: the change is the new model, its properties entry, its contract and the canonical document entry, so `fct_trip`, `dim_zone`, `agg_od_flow_matrix` and every mart keep their SQL, properties and values. Source: R-08.
- `D-13` The share is a rate, so it is rebuilt from summed trip counts through `safe_divide` and never as an average of pair shares, with a null where the denominator is zero. Source: ADR 0016.
- `D-14` No quality verdict filters a trip: a billable trip flagged implausibly short, fast, zero-distance or unresolved stays in its flow. The only exclusion is the billable rule, and this record states it. Source: ADR 0004; R-02.
- `D-15` `LTS10_borough_flow_monthly` claims the month content level and binds `billable_trip_count` to `trip_count` and `billable_revenue` to `total_revenue` there; the origin and destination borough roles stay in the source's grain and its `physical_joins` but declare no level. The `unresolved` group is no member of the Geography level, and no row predicate can state the sentinel away because the table genuinely holds those rows, so a borough-level binding cannot hold: the generated `assert_semantic_content_holds` rejected all 148 unresolved bindings. Borough-grain questions are the detail source's. Supersedes the (month, origin borough, destination borough) clause of `D-11`. Source: R-07; `semantic-model` S3b and S5a; Verification discovery.

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
- Publishing `Unknown` and `N/A` as boroughs of their own — an unresolved zone cannot be placed in a borough, and the answer at the design stop is one unresolved group.
- Counting unresolved destinations inside a borough's share — rejected at the design stop: a row touching `unresolved` is outside the share.
- A share denominator that excludes the intra-borough row — the leaving share is then no share of the borough's trips.
- A literal month or borough list in the SQL — it drifts from the window and from the dimension.

## Consumers

- Mobility Planning, outside the repository, answering the city's question about traffic crossing borough lines.
- The semantic layer, through `LTS10_borough_flow_monthly` in `logical-model/nyc_taxi_analytics.ossie.yaml`.
- No repository model reads it yet.

## History

- 2026-11-24 — R9 borough flow — created — D-01 to D-12 — terms: none new (Borough flow and Leaving-borough share landed with the Requirement).
- 2026-11-24 — R9 borough flow — amended at the design stop: one `unresolved` group outside the share, and the ADR 0004 and ADR 0016 decisions added — D-05, D-07, D-08, D-09, D-10, D-11, D-13, D-14 — terms: none new.
- 2026-11-24 — R9 borough flow — `D-11`'s semantic binding amended at execution: the month level only, because the `unresolved` group is no Geography member — D-15 — terms: none new.
