---
artifacts: [agg_borough_flow_matrix]
---

# agg_borough_flow_matrix

Borough-to-borough flow, one row per month and origin-destination borough pair, with each city borough's share of its trips that left it. The same `dim_zone` joined twice, as in `agg_od_flow_matrix`, but rolled to the borough level and over a population ADR 0018 defines: five city boroughs plus one `unresolved` group on each side, EWR out, every pair published, no threshold.

## Grain

One row per (month, origin borough, destination borough) for the months of the reporting window: `month_start_date` × `origin_borough` × `destination_borough`. Alternatives: one row per origin and month with the destinations pivot-widened (rejected: a column per pair changes shape whenever a borough appears or disappears, and a reader cannot filter or join on a pair), and one row per origin and month only (rejected: it cannot carry the pair's own trips and revenue, which the request asks for). Source: R-01.

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer, batched schema question.

## Decisions

- `D-01` New model `agg_borough_flow_matrix` in `transformation/models/marts/agg/`, materialised as a table, `access: public` with `contract: {enforced: true}` like every other model in that folder. No existing model is extended or restructured: the requested grain does not exist, and rolling `agg_od_flow_matrix` up would inherit its 25-trip floor and contradict R-08. Source: R-01, R-09.
- `D-02` Built from `fct_trip` with `dim_zone` joined twice on `pickup_zone_key` and `dropoff_zone_key`. Each trip reads the borough of the zone version resolved as of its own pickup date, because the fact already stores that version's surrogate key; the join never uses the zone's current version, so a TLC re-designation does not reassign history ([ADR 0009](../../../adr/0009-type-2-only-where-the-source-versions-history.md)). Source: R-06, ADR 0009.
- `D-03` Population: billable trips inside the reporting window (`in_report_window('f.pickup_datetime')` and `f.is_billable`), the same predicate the other revenue and flow marts apply ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: R-03.
- `D-04` Members: five city boroughs plus one `unresolved` group on each side. A zone is `unresolved` when `dim_zone.is_unresolved_zone` is true — the flag, never the literal labels, so both the `Unknown` and the `N/A` zone fall into the one group their flag already marks ([ADR 0012](../../../adr/0012-unresolved-zones-are-retained-and-flagged.md), [ADR 0018](../../../adr/0018-borough-flows-publish-every-pair-with-unresolved-in-its-own-group.md)). Source: R-06, answer to the unresolved-group question.
- `D-05` EWR is out of the table on both sides: not a member of the spine, and a trip with EWR as origin or destination is excluded before aggregating. `dim_zone.is_nyc` decides membership rather than a literal name, so EWR drops out as the non-New-York borough it is. Source: R-07, ADR 0018.
- `D-06` The spine is every month of the window crossed with every member on each side, left-joined to the trips, so a pair with no trips carries `trip_count` 0 and `revenue` 0 instead of being absent. The month list comes from `dim_date` inside the reporting window and the member list from `dim_zone`, so a re-designated borough or a moved window changes the row set without a code change — the 108 rows R-01 accepts are today's count, not a constant. Source: R-02, ADR 0018.
- `D-07` `trip_count` counts billable trips at their pair and `revenue` sums their `total_amount`; `trip_count` is named without a `billable_` prefix for the same reason `agg_od_flow_matrix` names it that way — the whole population is billable and the description says so. Source: R-03.
- `D-08` `flow_class` states what a pair is in one column: `cross_borough` when both sides are city boroughs and they differ, `in_borough` when the same city borough is on both sides, `unresolved` when either side is the unresolved group. One column rather than two flags, because the three values are exclusive and a reader filtering for crossing traffic must not have to combine two booleans. Source: R-06, ADR 0018.
- `D-09` The leaving share is the origin borough's cross-borough trips over its trips whose destination borough is known, computed at the (month, origin) level and carried on every destination row of that origin. Published as `origin_cross_borough_trips` / `origin_trips_to_known_destination` beside `cross_borough_share`, a ratio of sums computed through `safe_divide`, so the numerator and denominator are on the row and the share is rebuilt rather than averaged ([ADR 0016](../../../adr/0016-rates-are-rebuilt-from-summed-numerators-and-denominators.md)). Source: R-04, R-05.
- `D-10` `cross_borough_share` is a fraction in [0, 1], matching the other share columns in the repository (`component_share`, `tip_measurable_share`), not a percentage. Source: R-04, convention.
- `D-11` All three share columns are null on the `unresolved` origin's rows. A trip starting in a zone TLC cannot place has no borough to leave, so there is no numerator, no denominator and no share: null reads as "not applicable", where 0 would read as a measured zero ([ADR 0016](../../../adr/0016-rates-are-rebuilt-from-summed-numerators-and-denominators.md) on a zero denominator giving null, [ADR 0018](../../../adr/0018-borough-flows-publish-every-pair-with-unresolved-in-its-own-group.md)). Source: R-04, ADR 0018.
- `D-12` Month is `month_start_date`, a `DATE` at the first of the month, the month key `dim_date` already uses and the `agg` layer's monthly models already carry; not a `TIMESTAMP` and not the finance marts' `trip_month`, because this table lives in `agg` and a reader joins it to the calendar. Source: R-01, existing model.
- `D-13` An enforced ODCS contract at `contracts/agg/agg_borough_flow_matrix.odcs.yaml`, `status: proposed` while the relation does not exist and `active` in the task that builds it. Source: R-09.
- `D-14` Excluded from the semantic layer: a `semantic_exclusions` entry in `repo-map.json` with the reason, and no Ossie document change. Three things make this table no honest star member. Its `trip_count` and `revenue` are a narrower population than the star's `billable_trip_count` and `billable_revenue` — EWR dropped on both sides — so binding the canonical names here would make one metric name mean two populations. Its borough columns carry `unresolved`, which is no member of the `borough` level, so a join at that level drops the row (the same departure `agg_weather_demand_daily` records in its `note`). And its share is a repeated per-origin value, which the semantic layer refuses as a precomputed rate on any source. Source: R-09, convention (`semantic-model` routing a bespoke table).
- `D-15` No threshold of any kind is applied: no `having` clause, no cut-off on trips or revenue, so a pair that carried a single trip is published. ADR 0017's 25-trip floor governs the zone-grain matrix only and does not reach this relation ([ADR 0018](../../../adr/0018-borough-flows-publish-every-pair-with-unresolved-in-its-own-group.md)). Source: R-08, answer to the floor question.

## Logical Model

No document changes. The relation is excluded from the semantic layer per `D-14`: `repo-map.json` `semantic_exclusions` gains one entry naming `agg_borough_flow_matrix` and the reason above, and `logical-model/` is untouched.

```yaml
documents: []
datasets: []
metrics: []
logical_sources: []
```

## Rejected

- **Roll `agg_od_flow_matrix` up to the borough level** — its `having count(*) >= 25` floor (ADR 0017) would silently drop thin borough corridors, contradicting R-08, and it carries no unresolved group and no EWR exclusion.
- **Answer from the star's detail source only, with no table** — the canonical model already groups `fct_trip` by the pickup and drop-off borough in one query (recorded under `## Discovery`), but it leaves `Unknown` and `N/A` as two members, keeps EWR, emits no zero rows and carries no share; the four things the request needs are exactly what a published table fixes.
- **One row per origin and month with a column per destination** — the shape changes whenever a borough appears, and no consumer can filter or join on a pair.
- **A percentage in a `pct` column** — the repository's other share columns are fractions, and mixing the two invites a 100× error.
- **Zero for the unresolved origin's share** — reads as "no trip left", when the truth is that the group is no borough to leave.

## Consumers

None inside the repository: no model reads it, and no contract, Ossie document or ontology entry binds it. Outside, Mobility Planning's borough-flow reporting for the city, as an ad-hoc consumer of the published relation.

## History

- 2026-11-24 — ss-borough-flow-b2fa6d9e — design record written — D-01 … D-14 — terms: none new (Cross-borough trip and EWR were added with the Requirement)
