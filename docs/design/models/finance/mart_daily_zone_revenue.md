---
artifacts: [mart_daily_zone_revenue]
---

# mart_daily_zone_revenue

Daily revenue by pickup zone.

## Grain

One row per pickup zone and trip date. Unchanged: the report keeps exactly the rows it publishes today.

## Schema

- `transformation/models/marts/finance`: `finance` (default). Source: user answer, 2026-11-24.

## Decisions

- `D-01` Apply the billable rule and the reporting window here, in gold, and nowhere upstream, so quality work can still see the rows this excludes ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: docs/requirement/2026-08-29-the-trip-fact.md R-03, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-02` Read `agg_trip_zone_daily` instead of `fct_trip` joined to `dim_zone`: the report's measures, zone attributes and trip date all come from that one relation. The zone attributes it needs are already carried on the aggregate, as of the trip's own date, so the report takes them rather than re-deriving them, and the duplicate build the request complains about ends. Source: R-01, request.
- `D-03` Read the billable measures, not the all-trip ones: `trip_count` from `billable_trip_count`, `total_revenue` from `billable_revenue`, `fare_revenue` from `billable_fare_revenue`, `tip_revenue` from `billable_tip_revenue`, `surcharge_revenue` from `billable_surcharge_revenue`, `toll_revenue` from `billable_toll_revenue`. The column names the report publishes do not move. Source: R-02, R-04.
- `D-04` Select the zone-days that carry a billable trip (`billable_trip_count > 0`) and no others. That predicate, not a filter on the trips, is the report's whole population control now: the billable rule itself is applied upstream in `agg_trip_zone_daily` (its `D-02`), and this is what keeps the excluded zone-days out of the publication. A zone-day with no billable trip would otherwise publish 0 trips and null revenue, which the report has never shown. Source: R-08, user answer.
- `D-05` Supersedes `D-01`'s placement clause: the billable rule is now applied in `agg_trip_zone_daily`, and this mart publishes the billable population that aggregate computes, its own `where` keeping out the zone-days that carry no billable trip. The mart's description and its SQL header say that, instead of "applied here and nowhere upstream". [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md) is not amended and stays as it is; the ADR's statement that the revenue marts apply the rule, and this record, are reconciled by this decision. Source: R-09, user answer "No. Add new columns only. ADR 0003 stays as it is."
- `D-06` The report's published shape is unchanged: the same eleven columns, names, types and order, the enforced contract, and the existing `not_null` and `relationships` tests. The change is upstream of it, not in it. Source: R-04.
- `D-07` `pickup_location_id` keeps its `relationships` test against `dim_zone.zone_natural_key`. The aggregate carries the zone's natural key, and the dimension is still the member list a consumer joins for anything the report does not carry. Source: R-04, R-10.

## Rejected

- Applying the rule in silver: the excluded rows would be invisible to quality work.
- Rebuilding the mart from `fct_trip` and keeping the aggregate for the operations readers: that is the two-builds arrangement the request asks to end.
- Publishing the aggregate's all-trip figures and calling the difference a definition change: the finance numbers would move, which the request forbids.

## Consumers

- The finance team's daily zone revenue reading, outside this repository and not represented in it by a model.
- The semantic layer's `LTS7_daily_zone_revenue`, and through it `assert_semantic_content_holds` and `assert_semantic_levels_hold`.
- `contracts/finance/mart_daily_zone_revenue.odcs.yaml`.

## History

- - 2026-10-14 — trip-fact — design record written; audience wording removed from the model description — D-01
- - 2026-11-24 — ss-zone-revenue — the report is built from `agg_trip_zone_daily`, reading its billable measures, with the same columns, rows and values — D-02 … D-07 — terms: none new
