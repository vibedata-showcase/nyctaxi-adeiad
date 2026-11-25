---
status: decided
date: 2026-11-25
---

# The 25-trip floor governs zone-grain flows, not borough-grain ones

ADR 0017 publishes an origin-destination flow only at 25 billable trips, and gives its reason: the full 265 × 265 zone cross product "is mostly ones and twos", so publishing it "invites reading noise as a flow". That reason is a property of the zone grain, not of flow publishing in general. At borough grain the observed population is 40 to 42 pairs a month, and applying the floor withholds 99 / 55 / 99 billable trips across January, February and March 2024 while moving the cross-borough share from 12.79% / 12.15% / 13.16% to 12.57% / 12.05% / 12.99% — a change to the answer the city asked for, bought for nothing.

So `agg_borough_flow_monthly` publishes every borough pair that carries at least one billable trip in the month, and its share covers every trip the borough sent out whose destination borough is resolved. `agg_od_flow_matrix` keeps the floor unchanged. The line between them is the grain: a pair drawn from 265 zones is mostly incidental co-occurrence, and a pair drawn from 8 boroughs is a route.

The figures above compare the floor's effect on one denominator — every destination counted, including unresolved boroughs — and are not the published share. `agg_borough_flow_monthly` excludes unresolved destinations from its denominator by its own decision, so its published all-borough share is lower again.

The decision is recorded rather than left implicit because the floor is one number in one model (ADR 0017's own consequence list says changing it "is a decision to record rather than a constant to tune quietly"), and because a reader comparing the two flow surfaces would otherwise not know why one is floored and the other is not.

## Considered options

- **Apply the floor at borough grain too** — rejected: it removes real borough-level traffic from a borough-level question, and the noise it guards against does not exist at 8 members.
- **Apply the floor once at quarter level** — rejected: a January figure would then depend on March volume, and the request is for each month.
- **No floor at borough grain, floor unchanged at zone grain** — chosen.
- **Withdraw ADR 0017 entirely** — rejected: the zone matrix's own problem is real and unresolved by this change.

## Consequences

- `agg_borough_flow_monthly` may publish a borough pair that a reader would call thin; its `trip_count` is there to tell them so.
- The two flow surfaces answer different questions and are not comparable pair by pair. `agg_borough_flow_monthly` totals reconcile to the star's billable count; `agg_od_flow_matrix` remains a subset of it.
- A future flow table at a third grain decides its own floor against this ADR's line: the grain's member count, not the word "flow", decides.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
- [`models/agg/agg_od_flow_matrix.md`](../design/models/agg/agg_od_flow_matrix.md)
- [`0017-published-flows-have-a-25-trip-floor.md`](./0017-published-flows-have-a-25-trip-floor.md)
