---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Monthly origin-borough to destination-borough flow, with the share of each origin borough's traffic that leaves it. Built from `fct_trip` with `dim_zone` joined twice, once in each role, as `agg_od_flow_matrix` does at zone grain.

## Grain

One row per (calendar month, origin borough, destination borough) pair that clears the floor below, and one row per origin borough-month that clears no pair, in which `dest_borough` is null.

The alternative of a second relation for the no-pair borough-months was rejected: the crossing share belongs to the borough-month, not to a pair, and splitting it out would put the answer the city asked for in a table nobody joins.

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer at the design stop; `+schema: agg` in `dbt_project.yml` is unchanged.

## Decisions

- `D-01` A pair is published only at 25 billable trips in its month (ADR 0018). The floor is ADR 0017's, at the borough grain and the month, because the surface is published monthly and a pair below the floor reads as a corridor. Source: R-01, user answer at requirement; [ADR 0018](../../../adr/0018-published-borough-pairs-have-a-monthly-25-trip-floor.md).
- `D-02` Billable trips only, inside the reporting window, through the shared `in_report_window` macro on `pickup_datetime`. Source: R-02, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-03` Revenue is `sum(total_amount)` over the pair's billable trips and counts no-charge and dispute payments, exactly as `mart_daily_zone_revenue` and `agg_od_flow_matrix` do. Source: R-02, user answer at requirement; [ADR 0013](../../../adr/0013-no-charge-and-dispute-payments-are-not-excluded-by-the-billable-rule.md).
- `D-04` The crossing share's numerator and denominator both come from the origin borough-month's full billable population, not from the published pairs, and the three share columns repeat on every row of that borough-month (ADR 0019). Source: R-03, user answers at requirement; [ADR 0019](../../../adr/0019-crossing-share-covers-a-boroughs-whole-traffic.md).
- `D-05` An origin borough-month with no qualifying pair is published with a null `dest_borough` and a zero `trip_count` and `total_revenue`, so its crossing share is never lost to the floor. Source: R-04, user answer at requirement.
- `D-06` Unresolved zones stay in the rollup as their own `N/A` and `Unknown` borough groups: the model filters neither the zone nor the trip, as no other mart does. Source: R-06, [ADR 0012](../../../adr/0012-unresolved-zones-are-retained-and-flagged.md).
- `D-07` The share is a ratio of counted trips computed through `safe_divide`, so a zero denominator yields null rather than zero. The pair rows' own rate is not published: `trip_count` and `total_revenue` are sums a higher level can total, and any ratio built from them belongs to its reader. Source: R-03, [ADR 0016](../../../adr/0016-rates-are-rebuilt-from-summed-numerators-and-denominators.md).
- `D-08` The month is `date_trunc('month', pickup_datetime)`, carried as a DATE holding the month's first day, the key `mart_monthly_service_summary` and `dim_date`'s `month_start_date` already use. Source: R-05, existing models.
- `D-09` The relation is excluded from the semantic model (`semantic_exclusions` in `repo-map.json`), as `agg_od_flow_matrix` is: the `HAVING` floor is a group-level cut, and the no-pair rows stack a second grain in the same relation, so no logical source answers from it honestly. Its SQL and its description state both. Source: R-01, R-04, [ADR 0018](../../../adr/0018-published-borough-pairs-have-a-monthly-25-trip-floor.md), `semantic-model` routing rule.
- `D-10` The relation carries a contract at `contracts/agg/agg_borough_flow_monthly.odcs.yaml`, `status: proposed` until the model is built and `active` after, with `contract: {enforced: true}` in its properties file: every gold relation is on the contract boundary the Domain declares. Source: repository convention, `repo-map.json` `artifact_paths.data_contract`.
- `D-11` Materialised as a table in `agg`, the folder's default, with no audit columns: nothing in the requirement asks for them. Source: repository convention; R-01 to R-08.

## Rejected

- Rolling `agg_od_flow_matrix` up by borough — it inherits a zone-pair floor that keeps 71.4% of billable trips, so the borough rollup would lose traffic the share is defined over (ADR 0018).
- A second relation for the borough-month shares — splits the answer across two tables (see `## Grain`).
- Publishing the share over the floored pairs only — it understates every borough and has no row for the three boroughs that clear no pair in January (ADR 0019).
- Carrying `is_intra_borough` — the share columns already answer the crossing question, and no requirement asks for the flag.

## Logical Model

```yaml
documents: []
datasets: []
metrics: []
logical_sources: []
```

No document under `logical-model/` is touched: `D-09` excludes the relation instead, and the exclusion is recorded in `repo-map.json`'s `semantic_exclusions` rather than in a document. No concept is added or reached, so `ontology/` is unchanged.

## Consumers

- The Mobility Planning Lead's monthly borough report, and the city question it answers; nothing in the repository depends on it.
- No existing model, test, contract or Ossie document reads it, so nothing downstream changes.

## History

- 2026-11-25 — borough-to-borough trips and revenue share — design record written — D-01 to D-11 — terms: added Borough pair, Crossing share (ADR 0018, ADR 0019)
