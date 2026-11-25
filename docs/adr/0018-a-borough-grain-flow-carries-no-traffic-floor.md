---
status: decided
date: 2026-11-25
---

# A borough-grain flow is published without a traffic floor

ADR 0017 puts a 25-billable-trip floor on a published origin-destination flow, and that rule is about the zone-pair matrix: at 265 × 265 the cross product is mostly ones and twos, and a published pair invites reading noise as a route. The borough-to-borough surface is deliberately published with no floor. It answers how much traffic crosses a borough line, and a floor applied per pair per month would remove exactly the thin cross-borough pairs that answer is made of: at borough grain the floor would cut thousands of trips the city's question counts, and it would turn a share of the borough's traffic into a share of whatever survived the cut. The surface therefore publishes every pair that carries a billable trip, however small, and the totals of its trip and revenue columns reconcile to the fact rather than to a filtered subset.

## Considered options

- **Apply ADR 0017's floor per pair per month** — rejected: it removes the small cross-borough pairs the surface exists to show, and it makes the crossing share a share of published traffic rather than of the borough's traffic.
- **Apply a floor and publish nothing below it** — rejected for the same reason, at any threshold: the question is about the whole population, and a threshold on this surface would state a business rule the question does not have.
- **Publish every pair, with the floor left where it was decided** — chosen: ADR 0017 keeps its stated scope, the zone-pair matrix, and each surface answers the question it was built for.

## Consequences

- The two surfaces are not interchangeable. A zone-pair matrix totals a subset of the fact; this surface totals all of it. Summing one to check the other is a defect, not a reconciliation.
- ADR 0017's floor stays one number in one place, and it stays a rule about the zone-pair matrix.
- A new flow surface at any grain has to say which of the two it is: a filtered published-flow surface or a whole-population rollup. Silence is not an answer.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
