---
status: decided
date: 2026-11-25
---

# The 25-trip floor governs zone pairs, not borough pairs

ADR 0017 publishes an origin-destination pair only when it carries at least 25 billable trips, because the 265 × 265 zone cross product is mostly ones and twos and publishing it invites reading noise as a route. That reason does not carry to a borough pair: a borough pair aggregates the zones on each side, and the floor would withhold 66 of the 122 populated pair-months in Q1 2024 — 54% of the matrix — which together hold 253 of 95,958 billable trips. A borough flow matrix therefore publishes every pair-month that has at least one billable trip, and its totals reconcile with `fct_trip`'s billable totals.

## Considered options

- **Apply the 25-trip floor at borough grain too** — rejected: it blanks half the matrix, and the population a share of crossings is computed over would then be a filtered one that the published rows could not be reconciled against.
- **Publish the floor's population and mark it** — rejected: a mark answers "is this cell thin", which the published trip count already answers directly.
- **No floor at borough grain** — chosen, by the Mobility Planning Lead's answer to the requirement.

## Consequences

- The borough matrix and `agg_od_flow_matrix` are different populations and must not be compared: the first covers every billable trip in the window, the second only zone pairs at or above the floor and only trips both of whose zones resolve.
- A pair-month with a single trip appears. It is a real trip, and the trip count is published beside the revenue so the reader sees the size rather than having to infer it.
- Changing this rule changes a published population, so it is a decision to record, not a threshold to tune.

## Affected designs

None yet: the design record for the borough flow model is written at the design stage of the same intent.
