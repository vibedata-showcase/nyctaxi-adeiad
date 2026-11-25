---
status: decided
date: 2026-11-25
---

# The crossing share is measured over trips whose destination borough the lookup can name

A borough's crossing share is the billable trips that ended in another borough divided by its billable trips that ended in a borough the lookup can name — the out-of-state airport counts, the two labels that place no zone in a borough do not. A trip whose dropoff zone the lookup places in no borough is in neither the numerator nor the denominator: the data cannot say whether it crossed a line, and counting it as a crossing overstates the share while counting it as a stay understates it. Counting it as a stay also makes a borough's share fall as its destination resolution gets worse, which reads as a finding about travel rather than about the lookup.

The measure is undefined, and null, for an origin group with no trip whose destination borough the lookup names: a share of nothing is not a share, and 0% or 100% there would be an invented value. In the Q1 2024 window every group has some resolvable destination, so no share is null today; that is a property of the data in the window, not a rule that a group always has one. When a group's only destinations are the unplaceable ones, its share is null rather than a fabricated percentage.

The threshold-free structure is deliberate: the share is computed from the same month × origin × destination counts the matrix publishes, so it can be re-derived from the table and a reader can see which cells produced it.

The answer was given by the Mobility Planning Lead's request as settled in this intent, between the three treatments of the unresolved destination the repository left open.

## Considered options

- **All trips, unresolved destination counts as leaving** — rejected: it credits a crossing to a trip the data cannot place, and the share rises with lookup failure.
- **All trips, unresolved destination counts as staying** — rejected: it credits a stay the data cannot place, and biases the share downward.
- **Resolvable destinations only** — chosen: the denominator states its own population, and no unresolved trip is silently assigned a side.

## Consequences

- The share's denominator is smaller than the origin group's trip count; both are published beside it, so the gap is visible rather than inferred.
- A reader summing the matrix's rows for one origin will not get the denominator from the crossing row alone; the denominator column is the authority.
- A group with no resolvable destination carries a null share, never 0 and never 1.
- The same rule applies to any future mart that splits a measure by whether a trip stayed in or left a place the lookup might not name.
