---
status: decided
date: 2026-11-24
---

# A borough flow is published without a trip floor; the 25-trip floor stays a zone-pair rule

A flow reported between boroughs is published for every borough pair in each month, including a pair with no billable trips, and carries no trip floor. ADR 0017's 25-trip floor remains a rule about zone pairs on the zone-level origin-destination matrix. The floor answers a noise problem the borough grain does not have — it exists because the 265 × 265 zone cross-product is mostly ones and twos — and applying it at borough grain would also break the surface's arithmetic: the consumer needs each month's trips and revenue to reconcile to the billable population, and a floor removes rows whose trips are still in that population.

## Considered options

- **Apply the same 25-trip floor at borough grain** — rejected: the noise the floor answers at zone grain does not arise across a borough cross-product, and the floor would drop pairs that carry real traffic from the small boroughs, leaving their leaving-borough shares measured over a partial set of destinations.
- **Relax the floor on the zone matrix too** — rejected: the 265 × 265 zone cross-product still needs it for the reason ADR 0017 gives.
- **A different floor at borough grain** — rejected: an arbitrary second threshold with no separate noise problem to answer.
- **No floor at borough grain, with the floor kept as a zone-pair rule** — chosen.

## Consequences

- A month's trips and revenue on the borough surface sum to that month's billable trip count and billable total amount; the zone-level matrix stays a subset of them (ADR 0017).
- The two surfaces have different populations and are not interchangeable. A question about the whole network is answered from the borough surface or the star, never by summing published zone flows.
- A borough pair with no billable trips is published with zero trips and zero revenue, not omitted.
- Changing the floor still means editing the zone matrix in one place; it does not touch the borough surface.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
