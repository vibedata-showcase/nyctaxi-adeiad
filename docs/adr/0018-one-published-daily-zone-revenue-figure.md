---
status: decided
date: 2026-11-25
---

# One published daily zone revenue figure, and it is the billable one

The warehouse publishes two relations at or near daily zone grain: `finance.mart_daily_zone_revenue` and `agg.agg_trip_zone_daily`. Both are built from `fct_trip` and `dim_zone`; neither reads the fleet operator's source. They differ because the mart applies the billable rule ([ADR 0003](0003-billable-trip-definition-and-where-it-applies.md)) and the aggregate does not, and because the mart carries the four revenue components and `reporting_region` while the aggregate carries rolling-window context instead.

Finance reads the mart every morning and its figures are a standing check. The aggregate's figures cannot satisfy that check, because it aggregates every trip. Keeping both means paying for two builds that must agree and do not, and leaving a reader to discover which one the revenue number means. So the mart stays and the aggregate is retired.

This is hard to reverse in the way that matters: consumers outside the repository read the aggregate, and once it is gone they cannot be given back the same relation without re-authoring it. It is surprising without context, because the two relations look like duplicates and a reader would expect the aggregate to be the cheaper one to keep. The trade-off is real: retiring either side loses something.

## Considered options

- **Retire `agg.agg_trip_zone_daily`, keep the mart** — chosen. The mart is the relation finance reports from, its figures are the standing acceptance check, and it applies the billable rule the Domain requires of revenue reporting. What is lost with the aggregate is its rolling-window context, which no semantic metric binds and which the request did not ask for.
- **Retire the mart, keep the aggregate** — rejected. It changes every number finance reports and fails the check the request set as its acceptance condition.
- **Add billable measures and the four revenue components to the aggregate, then build the mart from it** — rejected. It satisfies both stated constraints on paper, but it makes the aggregate the single build while still publishing two relations at the same grain, and it puts a billable-filtered measure beside an all-trip measure in one relation, which is exactly the conflation [ADR 0003](0003-billable-trip-definition-and-where-it-applies.md) removed from silver.
- **Keep both and reconcile them in a test** — rejected. A passing reconciliation test does not merge two published answers to one question; it only proves they currently agree, which they do not.

## Consequences

- `finance.mart_daily_zone_revenue` is the only published daily zone revenue relation, and it always applies the billable rule and the reporting window.
- A request for all-trip daily zone counts, or for rolling-window context by zone and day, has no published relation; such a request is a new relation, not a second copy of this one.
- A later request to retire the mart itself would leave the Domain with no daily zone revenue figure at all.
- The semantic layer binds `trip_count` to this relation through the detail source; the aggregate source it used to route through is withdrawn.

## Affected designs

- [`models/finance/mart_daily_zone_revenue.md`](../design/models/finance/mart_daily_zone_revenue.md)
- [`models/agg/agg_trip_zone_daily.md`](../design/models/agg/agg_trip_zone_daily.md)
