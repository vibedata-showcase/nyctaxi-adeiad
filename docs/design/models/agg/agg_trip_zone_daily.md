---
artifacts: [agg_trip_zone_daily]
---

# agg_trip_zone_daily

Retired. Daily zone demand with period-over-period context, withdrawn so the Domain publishes one daily zone figure rather than two.

## Decisions

- `D-01` Retire this relation rather than keep it beside `finance.mart_daily_zone_revenue`. Both were built from `fct_trip` and `dim_zone`; this one aggregated every trip and the mart applies the billable rule ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)), so the two published different answers to one question ([ADR 0018](../../../adr/0018-one-published-daily-zone-revenue-figure.md)). Source: user answer to the requirement's opening question, docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-3-ac8b102d.md R-02.
- `D-02` The retirement removes the model SQL, its `_agg.yml` properties entry, its contract at `contracts/agg/agg_trip_zone_daily.odcs.yaml`, and its semantic source `LTS2_zone_day_agg` with the two `physical_joins` and the `physical_tables` entry that name it, in one change. A contract for a relation that no longer exists is a promise the warehouse cannot keep. Source: R-02, R-06, `data-contract` skill step 4.
- `D-03` The seven columns only this relation carried are dropped with it, and no semantic metric is lost: the Ossie document bound only `trip_count` from this relation. Source: R-06, `logical-model/nyc_taxi_analytics.ossie.yaml` (`LTS2_zone_day_agg` note).
- `D-04` The nine design records that list this relation in their `## Consumers` line have it removed in the same change, so no record claims a dependent that no longer exists. Those lines are hand-kept, not generated, so they do not update themselves. Source: R-07.

## Rejected

- Keeping the relation as a view over `mart_daily_zone_revenue`: it would still publish a second daily zone relation with a different population, which is the duplication being removed.
- Keeping it for its rolling-window context: no semantic metric binds those columns, and no model `ref()`s the relation, so nothing in the repository reads them.

## Consumers

None: it is retired, so nothing may depend on it.

## Logical Model

`logical-model/nyc_taxi_analytics.ossie.yaml` (`nyc_taxi_trips`):

```yaml
datasets: {}
metrics: {}
logical_sources:
  LTS2_zone_day_agg: retired
```

The `physical_tables` entry and the two `physical_joins` naming the relation (`agg_trip_zone_daily_to_dim_date`, `agg_trip_zone_daily_to_Pickup_Zone`) go with the source. No metric is retired: `trip_count` stays bound through `LTS1_detail` and `LTS7_daily_zone_revenue`, and the other columns this relation carried had no metric declared. `ontology/` is untouched: no concept or mapping names the relation.

## History

- 2026-11-25 — zone-revenue-report-from-operations-figures-3 — record written as the relation is retired — D-01, D-02, D-03 — terms: none new
