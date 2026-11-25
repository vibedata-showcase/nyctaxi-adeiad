---
status: decided
date: 2026-11-25
---

# A borough flow mart publishes every pair and counts every other borough as crossing

A mart that rolls trips up to borough asks a different question from the zone-level origin-destination matrix, so two of that matrix's properties do not carry over.

**No floor.** ADR 0017 publishes a zone pair only at 25 billable trips. That floor exists because the 265 × 265 zone cross product is mostly ones and twos, and publishing it invites reading noise as a route. A borough rollup has no such problem: it is a fixed handful of groups, and its thin cells are the cross-borough flows the question is about. So a borough flow mart publishes every pair that carries at least one billable trip, and its trip and revenue totals close exactly to the star's.

**Every different borough crosses.** A trip is cross-borough when its destination borough name differs from its origin borough name. The unresolved `Unknown` and `N/A` groups and the out-of-state `EWR` group are borough groups in their own right under ADR 0012, so a trip from Manhattan to `Unknown` counts as leaving Manhattan, and a trip from `Unknown` to `Unknown` does not. A cross-borough share is the origin borough's cross-borough trips over all its trips in the period, a ratio of sums per ADR 0016, never the mean of its per-pair shares.

## Considered options

- **Reuse ADR 0017's floor at borough grain** — rejected: the floor guards against a sparse cross product that a borough rollup does not have, and it would drop exactly the small cross-borough flows the rollup is asked about while breaking closure to the star.
- **Exclude `EWR` and the unresolved groups from the rollup** — rejected: ADR 0012 retains them, and a Manhattan trip ending in a zone the lookup cannot place did leave Manhattan.
- **Count only destination boroughs that are New York City boroughs as crossing** — rejected: it would make a trip to Newark an intra-borough trip, which it plainly is not.
- **A revenue share instead of a trip share** — rejected: the question is about traffic, and revenue weights a few long airport trips over many short local ones.
- **Publish every pair, count every different borough** — chosen.

## Consequences

- A borough flow mart's per-month totals equal the star's billable totals; nothing is dropped, so a consumer can reconcile it against `fct_trip` without knowing about a floor.
- The share's denominator is the origin borough's own traffic, so shares are comparable across boroughs of very different size, and the intra-borough row is the complement rather than a separate measure.
- A future mart that wants the floored view at borough grain states that itself; this ADR does not make a floor wrong, it says the floor is a property of the zone-pair surface.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
