---
status: decided
date: 2026-11-25
---

# A borough-level flow publishes the full borough cross product, with no trip floor

A rollup of flows to borough grain publishes every origin borough against every destination borough for each period, with zero trips and zero revenue where no trip ran, and it applies no trip floor. The 25-trip floor of ADR 0017 is a rule about zone pairs: it exists because the 265 × 265 zone cross product is mostly ones and twos, and that reasoning does not survive at eight borough groups, where each of the 64 cells per period is a corridor a reader can name. At borough grain the floor does the opposite of its purpose — most cells fall under it while holding under half a percent of the trips, so it hides the shape of the traffic it was meant to clarify, and it leaves a crossing share computed over a partial population.

The full cross product is the user's answer, cited as the source of this decision: it is a definition of what the published surface reports, so it is a decision to record rather than a query parameter to tune.

## Considered options

- **Every borough pair that carries at least one billable trip** — rejected: a pair with no trip then has no row, so a reader cannot tell an empty corridor from a missing one, and the 64 cells do not line up between periods.
- **The 25-trip floor of ADR 0017, per period** — rejected for borough grain: it removes most cells for a negligible share of trips, removes whole directions, and makes the crossing share a share of an unpublished subset.
- **The full cross product with zero-filled cells** — chosen: the surface answers the city's question directly, and an empty corridor is stated as empty.

## Consequences

- A zero row is not a measurement of zero demand; it means the pair carried no billable trip in that period, and consumers read it with the trip count beside it.
- ADR 0017 still governs the zone-pair matrix: this decision narrows where the floor applies and does not supersede it. Summing across destination boroughs here therefore closes to the star's billable counts, while summing the zone matrix does not.
- The full cross product costs nothing to publish at this grain: eight borough groups by three periods is 192 rows.
- The borough set is whatever the zone dimension holds, including the unresolved groups ADR 0012 keeps, so the number of cells follows that dimension rather than a list fixed in code.
