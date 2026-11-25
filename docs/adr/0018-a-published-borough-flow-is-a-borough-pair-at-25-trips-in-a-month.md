---
status: decided
date: 2026-11-25
---

# A published borough flow is one New York City borough to another at 25 billable trips in a month

The borough flow surface publishes a pair only when both ends resolve to a New York City borough and the pair carries at least 25 billable trips in that month. The floor is measured per pair and per month, not over the reporting window: a borough pair that clears it in January and falls below it in February is published in January and not in February, because the table answers a monthly question.

Both ends being a New York City borough is what makes the pair a borough flow. The borough master carries two more borough labels — the out-of-state airport EWR and the two unresolved labels — and a trip ending in one of those has left the city's borough system rather than travelled between two of its boroughs. Excluding them is the consumer filter ADR 0012 allows a borough rollup to apply; it is not a change to how unresolved zones are retained upstream, which stays as ADR 0012 records.

The consequence is bounded and deliberate. The surface's trip counts and revenue are a subset of the star's billable metrics over the same window, short by every pair under the floor and by every pair with an end outside the five boroughs. A question about the whole network is answered from the detail source, as ADR 0017 already says of the zone-pair matrix.

## Considered options

- **No floor** — rejected: the coarser grain does not make every pair meaningful, and the thin pairs are concentrated in exactly the origin boroughs a cross-borough question is about, so publishing them alongside a share computed from them would mix settled and unsettled numbers in one table.
- **The floor over the whole reporting window** — rejected: the table is monthly, so a pair published by a quarterly total would carry a month whose own count is noise.
- **Both ends a New York City borough** — chosen: it is what the word borough means in this Domain, and it keeps the share's numerator and denominator inside one population.
- **Every destination label published, the share narrowed to New York City boroughs anyway** — rejected: the table would then hold rows the share was defined to exclude, and no reader could tell which rows the share spoke for.
- **A zero-filled borough grid** — rejected: a month and a pair with no trips is a fact about the trips, not a row, and a zero would have to be distinguished from a pair that was filtered out.

## Consequences

- A pair appears and disappears between months. That is accepted: the surface answers which borough flows exist in a month, not which trips happened.
- The floor is one number in one place, in the mart's SQL. Changing it changes the published population and the share with it, so it is a decision to record rather than a constant to tune.
- Every origin borough with no published pair — because its whole month falls under the floor — has no row and no share. The surface's absence is the statement.
- A consumer that wants the whole network's billable trips uses `fct_trip`, not this surface.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
