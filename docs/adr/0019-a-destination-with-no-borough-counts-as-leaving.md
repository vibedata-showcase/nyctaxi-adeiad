---
status: decided
date: 2026-11-25
---

# A trip to a borough the TLC cannot resolve, or to one out of state, counts as leaving the borough it started in

A cross-borough share counts a trip as leaving when its destination borough differs from its origin borough, and a destination whose borough is unresolved or outside the city is a different borough for this purpose. The trips are real and their destinations are known to be somewhere other than the zone they started in, so treating them as not leaving understates exactly the traffic the measure is about.

ADR 0012 keeps unresolved zones and their trips, and a borough rollup shows the unresolved group as a group of its own; this decision reads the same groups as destinations rather than excluding them. The alternative makes the share depend on how often the TLC could not place a zone, which is a property of the reference data, not of the traffic.

## Considered options

- **Count only resolved NYC boroughs as a different borough** — rejected: a trip ending in an unplaced or out-of-state zone then counts as staying, so the share moves with the quality of the zone lookup.
- **Drop trips that touch an unresolved zone** — rejected: ADR 0012 keeps them, and the destinations are genuinely elsewhere.
- **Every different borough group counts, unresolved and out-of-state included** — chosen.

## Consequences

- The unresolved and out-of-state groups appear as destination rows and are counted as crossings, so their volume is visible rather than implied.
- A reader who wants crossings between the five named NYC boroughs filters the destination rows; the published share is the unfiltered one.
- The share's denominator is every billable trip from the origin borough, so its rows sum to it.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
