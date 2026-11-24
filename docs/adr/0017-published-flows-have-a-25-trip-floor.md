---
status: decided
date: 2026-10-22
---

# A published origin-destination flow is a zone pair with at least 25 billable trips

The origin-destination matrix publishes a pair only when it carries at least 25 billable trips in the reporting window. Below that, the pair is not a route anyone travels; publishing it invites reading noise as a flow, and the full 265 × 265 cross product is mostly ones and twos. The floor is a business rule about what may be called a published flow, not a data-quality verdict: nothing is removed from `fct_trip`, and the pair is simply not published at this surface.

The consequence is deliberate and bounded. `agg_od_flow_matrix` answers "which flows exist and how big are they" for flows that qualify; its `trip_count` and `total_revenue` are therefore a **subset** of the star's `billable_trip_count` and `billable_revenue`, short by every pair under the floor and by every pair whose trips resolve to no zone. Consumers reading the OD surface get the published population; consumers summing the star's billable metrics over the whole network get the warehouse population. The two are not interchangeable and the semantic model says so on the source.

## Considered options

- **Publish every pair** — rejected: the matrix becomes mostly noise, and a reader cannot tell a real corridor from a rounding of two trips.
- **Publish no matrix, query `fct_trip` on demand** — rejected: every consumer then rewrites the same group-by and the same judgement about thin pairs, and they will disagree.
- **Truncate at a floor, and bind the star metrics to it** — chosen, with the partiality recorded on the source and here.
- **Truncate at a floor and expose scoped metrics only** (`od_pair_billable_trip_count`) — rejected: the floor is a property of the published surface, so a second metric name would imply a second measure rather than the same measure over a narrower population.

## Consequences

- Summing `billable_revenue` or `billable_trip_count` through this source undercounts the network; that is the recorded intent, not a defect. A question about the whole network is answered from the detail source.
- The threshold is one number in one place (`agg_od_flow_matrix.sql`). Changing it changes the published population, so it changes what the OD surface reports, and it is a decision to record rather than a constant to tune quietly.
- A pair that crosses the floor between two runs appears or disappears from the surface. That is accepted: the surface answers "which flows exist now", not "which trips happened".
- The model's logical source cites this ADR in its `note`, so a reviewer can tell the partiality apart from a broken mapping.

## Affected designs

- [`models/agg/agg_od_flow_matrix.md`](../design/models/agg/agg_od_flow_matrix.md)
- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
