---
status: decided
date: 2026-11-24
---

# A cross-borough trip ends in a resolved borough other than the one it started in

A trip crosses a borough line when both ends resolve to a borough and the two boroughs differ. Three consequences follow from what the TLC zone lookup actually contains:

- **EWR is a borough.** The lookup lists Newark Airport as its own borough, so a trip between EWR and any New York borough crosses a line, and EWR's own share counts those crossings.
- **N/A and Unknown are not boroughs.** They are the unresolved zones ADR 0012 keeps as real, flagged rows. A trip to or from one of them is neither in-borough nor cross-borough, so it never counts as leaving its borough and never sits in the denominator of the share. The table still publishes those cells with their trips and revenue, so the traffic is visible; only the share treats it as unplaced.
- **The share and the published cells agree.** Because the unresolved groups are excluded from the share's numerator and denominator alike, an origin's resolved diagonal plus its off-diagonal resolved cells reproduce the share's denominator exactly.

An origin that is itself unresolved has no borough to leave, so its share is null rather than zero, and the count of its resolved-destination trips is published beside it as the basis. Zero would read as "nothing crossed", which is false for most of those trips.

## Considered options

- **Count any differing destination borough as a crossing** — rejected: it makes N/A and Unknown destinations crossings, inflating Manhattan's January share from 5.45% to 5.86% on the same denominator, on values nobody could place in a borough.
- **Drop the unresolved groups from the table entirely** — rejected: ADR 0012 retains them, and the trips are real even where their location is not.
- **A zero share for an unresolved origin** — rejected: it asserts no crossings where most of that traffic ended in a real borough.
- **Resolved-borough ends, differing, with a null share on an unresolved origin** — chosen.

## Consequences

- The share is a ratio over resolved-destination trips, not over all of a borough's trips; the basis count is published alongside so a reader can tell the two apart.
- Every consumer computing "share of trips leaving a borough" from this table gets the same definition, because it is a published column rather than a formula every report re-derives.
- A change to which borough values the zone lookup calls resolved changes the share and is a change to this definition, not a threshold to tune.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
