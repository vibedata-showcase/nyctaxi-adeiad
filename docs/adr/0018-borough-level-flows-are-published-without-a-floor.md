---
status: decided
date: 2026-11-25
---

# A borough-level flow is published for every observed pair, with no minimum-trip floor

The floor in ADR 0017 is a rule about zone pairs in the origin-destination matrix, not about every flow surface. A borough-to-borough flow is published for every pair that carries at least one billable trip in its month, so the surface shows where a borough's traffic goes without dropping a destination because it is thin.

At borough grain the floor does not do the work it does for zones. There are a handful of borough pairs per month and most of them carry very few trips, so a floor removes whole destination rows while leaving the origin borough's outbound share computed over a trimmed population: the share then answers "how much of the traffic that stayed in the published set crosses", which is not the question the surface exists for. The floor's reason — a 265 × 265 cross product that is mostly noise — has no analogue at this grain.

## Considered options

- **Apply the 25-trip floor** — rejected: it drops most cells, and the outbound share would be measured over the surviving cells rather than over the borough's traffic.
- **Publish every pair but compute the outbound share from all billable trips** — rejected: a reader cannot reconcile rows that sum to less than the share's denominator, and the published rows would silently disagree with the share they sit beside.
- **Publish every observed pair, share from the same population** — chosen: rows sum to the borough's traffic, and the share is the sum of the rows whose destination differs.

## Consequences

- The number of rows per origin borough varies with the traffic it really has, and a single trip to Staten Island is a row.
- ADR 0017 still governs `agg_od_flow_matrix`; a change to that floor does not reach this surface, and this decision does not reach that one.
- A question about flows still needs the zone-pair matrix, because this surface has no zone detail.
- The rule lives in the model that publishes the surface, so a later floor there is a decision to record, not a constant to tune.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
