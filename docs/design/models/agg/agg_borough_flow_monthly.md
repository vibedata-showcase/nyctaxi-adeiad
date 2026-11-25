---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Monthly borough-to-borough movement: one row per month × origin borough × destination borough over the five NYC boroughs, with billable trips, their revenue, and the origin borough's outbound cross-borough share.

## Grain

One row per (pickup month, origin borough, destination borough). The month is the pickup month, which is the only date the star reports on (`CONTEXT.md` **Date**). The alternatives were zone grain (already published as `agg_od_flow_matrix`, and under a floor that would hide the answer) and borough-of-origin only (`mart_daily_zone_revenue`'s grain, which carries no destination and so cannot answer "from each borough to each borough").

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer at the design stage; the folder's `+schema` already resolves to `agg`.

## Decisions

- `D-01` One new boundary model, `agg_borough_flow_monthly`, in `models/marts/agg/`, materialised `table` like every mart in the folder. Materialisation is the folder's `marts` default, not a per-model override. Source: R-01; `dbt_project.yml`.
- `D-02` Built from `core.fct_trip` with `core.dim_zone` joined twice, once in the origin role and once in the destination role, on the as-of surrogate keys the fact already carries. No published model serves this grain, so nothing is rebuilt from a layer below the star. Source: R-01, R-02; `agg_od_flow_matrix.sql` is the same pattern at zone grain.
- `D-03` Population: billable trips whose pickup zone and dropoff zone are both in an NYC borough. The five boroughs are selected by `dim_zone.is_nyc`, not by a hard-coded name list, so a master-data change to the borough set moves the grid rather than leaving a stale literal. `is_unresolved_zone` is redundant against `is_nyc` and is not used, to keep one rule in one place. Source: user answer; R-03; ADR 0012.
- `D-04` Revenue is `sum(total_amount)` over the cell's billable trips, including no-charge and dispute payments. Reason: ADR 0003 makes the billable rule the rule for revenue and flow marts, and ADR 0013 leaves whether those payments count to each metric. The alternative, payment-method-recognised revenue, was put to the user and declined. Source: user answer; R-02; ADR 0003; ADR 0013.
- `D-05` The grid is a left join from a 3 × 5 × 5 spine, so all 75 cells exist and a cell with no trips carries 0 trips and 0 revenue rather than a null or an absent row. No `HAVING` floor. Source: user answer; R-05; ADR 0018.
- `D-06` The share is `cross_borough_trip_count / origin_trip_count` of the same month, computed once over all of an origin's trips and published on every row of that origin month. Its numerator and denominator are published as their own columns so the ratio can be checked and so no consumer has to infer what it was taken over. Source: user answer; R-04.
- `D-07` The table is a `semantic_exclusions` entry in `repo-map.json`, not an aggregate logical source. Two reasons, both fatal to a binding: its population (both endpoints in an NYC borough) is not a predicate the `trips` dataset's fields can state, because borough membership lives in `dim_zone` and no fact column carries it, so no `content_filter` could declare the subset; and `outbound_cross_borough_share` divides by its origin month's trips, so it is not additive across rows. The star answers the same question through its detail source today, which the Verification's `## Discovery` records. Source: user answer; R-06.
- `D-08` No ontology mapping. The table reaches Zone and Trip, both already mapped from the `nyc_taxi_trips` document; it introduces no concept and no new identity. Source: R-06; `ontology/nyc_taxi_analytics.mapping.yaml`.
- `D-09` The relation carries an enforced dbt contract and an ODCS contract at `contracts/agg/agg_borough_flow_monthly.odcs.yaml`, because `repo-map.json` `contracts` puts every gold relation under contract. Source: R-06; `repo-map.json` `contracts`.
- `D-10` Column set: `trip_month`, `trip_month_start_date`, `origin_borough`, `destination_borough`, `is_cross_borough`, `trip_count`, `total_revenue`, `origin_trip_count`, `cross_borough_trip_count`, `outbound_cross_borough_share`. `is_cross_borough` is derived from the two borough names, so a consumer can filter without string comparison. Source: R-02, R-04, R-05.
- `D-12` `D-10` names two month columns, `trip_month` and `trip_month_start_date`, which would hold the same value: the month has one key, its first day. The published set is nine columns, with `trip_month` alone, typed `DATE` and equal to the first day of the pickup month. It is `DATE` rather than the `TIMESTAMP` the older finance marts carry, because a month is a date and a timestamp invites an accidental time comparison; the `agg` folder's other monthly models set the precedent for the month grain, and a consumer joins it to `dim_date.month_start_date`. Source: R-01; `dim_date.sql` `month_start_date` is the month level's key.
- `D-11` Tests: `unique` and `not_null` on the composite grain through a surrogate-free uniqueness test, `not_null` on both boroughs and on the three measure columns, an accepted-values test on `origin_borough`/`destination_borough` against the borough master, and one singular test that each month's cells sum to the independently counted trips of that month's population. Source: R-05, R-07.

## Logical Model

The relation is added to `repo-map.json` `semantic_exclusions` and to no Ossie document, so no document changes and no ontology document changes.

```yaml
# logical-model/nyc_taxi_analytics.ossie.yaml and logical-model/nyc_taxi_fleet.ossie.yaml: read, unchanged.
datasets: []
metrics: []
logical_sources: []
ontology:
  documents: []
  concepts: []
  mappings: []
```

## Rejected

- **Reusing `agg_od_flow_matrix` at zone grain** — its 25-trip floor (ADR 0017) drops exactly the thin borough pairs the question is about, and its grain is finer than asked, so a consumer would re-derive the rollup and the share per report.
- **Rebuilding on `mart_daily_zone_revenue`** — it carries no destination borough, so it cannot produce a matrix at any cost.
- **A dbt `schema` config on the model** — the folder's `+schema` owns this; a per-model override lets the model drift from its folder.
- **Filtering the five boroughs by a hard-coded name list** — a literal list goes stale the moment master data changes the borough set, and it duplicates a rule `dim_zone.is_nyc` already carries.
- **Publishing the share as a metric on the star** — the star cannot reach it: the denominator is a total across a dimension the numerator's row cannot see, which the compiler refuses by design.

## Consumers

- Leila Haddad, Mobility Planning Lead, answering the city's cross-borough question; anyone reporting monthly borough-to-borough movement.
- No repository artifact reads this relation: it is a new leaf in the graph, and nothing downstream of it exists.

## History

- 2026-11-25 — new-intent-5af98744 — created with the model, its population, its share and its exclusion route — D-01–D-11 — terms: added cross-borough trip
- 2026-11-25 — new-intent-5af98744 — amended before planning: the month is one column, `trip_month` as a DATE on the first day, because `D-10` named a duplicate — D-12 — terms: none new
