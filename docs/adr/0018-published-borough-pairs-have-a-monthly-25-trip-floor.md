---
status: decided
date: 2026-11-25
---

# A published borough pair carries at least 25 billable trips a month

The borough-to-borough surface publishes an origin-borough × destination-borough pair only when it carries at least 25 billable trips in that calendar month. The floor is ADR 0017's rule applied at a new grain, on the Mobility Planning Lead's instruction: a borough pair is a coarser unit than a zone pair, but a pair of 3 trips still reads as a corridor when printed as a row, and the surface is meant to answer which borough pairs carry traffic. The unit is the month, not the reporting window, because the surface is published per month and a pair that qualifies over the quarter but not in February would otherwise appear in a month where it carries almost nothing.

Measured over Q1 2024, the floor keeps 56 of 122 (month, origin borough, destination borough) combinations and 95,705 of 95,958 billable trips; 253 trips and 19,966.06 of revenue are in the 66 pairs it removes. The partiality is not confined to thin pairs: the Bronx's January share of trips leaving the borough reads 49.4% over the published rows, where all of its billable traffic gives 59.3%. The surface therefore publishes the crossing share beside the pairs from a wider population, which ADR 0019 decides.

## Considered options

- **No floor, publish every borough pair that has trips** — rejected by the requirement's owner: with 8 borough groups the cross product is small, but it still prints pairs of one and two trips as if they were routes.
- **ADR 0017's floor over the whole reporting window rather than the month** — rejected: it keeps 22 pairs, drops 139 trips, and leaves a pair published in a month where it is below 25 trips, which is the case the floor exists to prevent.
- **No borough surface, query the zone pairs on demand** — rejected: a consumer would roll `agg_od_flow_matrix` up by borough and inherit a zone-pair floor that, at the reporting-window grain, keeps only 71.4% of billable trips, so the borough rollup would lose 28.6% of the traffic it was meant to count.
- **Floor at 25 billable trips per month, with the crossing share published from the full population** — chosen.

## Consequences

- Summing this surface's `trip_count` or revenue undercuts the network; a question about all billable traffic is answered from `fct_trip`.
- An origin borough-month whose every pair falls under the floor has no pair row; the surface still publishes that borough-month's crossing share, so the share is never lost to the floor.
- Changing the threshold changes the published population at both grains, and is a decision to record rather than a constant to tune.
- A pair that crosses the floor between two runs appears or disappears; the surface answers which borough pairs carry traffic now, not which trips happened.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
