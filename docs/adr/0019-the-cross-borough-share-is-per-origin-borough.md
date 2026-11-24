---
status: decided
date: 2026-11-24
---

# The cross-borough share is per origin borough, over trips whose destination is located

"Share of trips that leave the borough they started in" is read as one share per origin borough per month: the trips from that borough that end in a different borough, divided by that borough's trips whose destination lies in a borough. Both counts are published beside the share, so a reader can rebuild the number and see how much traffic the base excludes.

Two narrower readings were rejected. A network-wide share answers the city's headline but not "whose traffic leaves", which is what a planning lead asks borough by borough. A share over every trip from the borough counts trips to an unplaced destination as leaving, which contradicts ADR 0012: an unresolved zone is a real zone that belongs to no borough, so a trip to it is neither in-borough nor cross-borough.

A trip whose pickup or dropoff zone is unresolved is therefore in the table, in one unresolved group, and in neither count of the share. That keeps the share honest about what it measures and keeps the table's totals equal to the billable population (ADR 0018): the excluded trips appear in the matrix rows rather than vanishing.

Newark Airport is a borough for this purpose, so a trip between Manhattan and Newark crosses. The user's answer is the source for both readings: "share of that borough's own trips", base "only trips with a located destination", and "Unknown and N/A are not boroughs. Do not count their trips as in-borough or cross-borough. Keep these trips in a separate unresolved group (ADR 0012)."

## Considered options

- **One network-wide share per month** — rejected: it answers how much of all traffic crosses, not which borough's traffic drains away.
- **Share over all trips from the borough, unresolved destinations counted as leaving** — rejected: it calls a trip to an unplaced zone a crossing, so the share would move with the source's geocoding quality rather than with where people travel.
- **Share over all trips from the borough, unresolved destinations in the denominator only** — rejected: an unresolved destination then depresses every borough's share for a reason that is not a flow.
- **Share over trips with a located destination, unresolved trips reported separately** — chosen.

## Consequences

- A row carries the share of its origin borough and month, so all rows of one origin borough in one month carry the same share; the share is a property of that borough-month, not of the cell.
- A trip with an unresolved pickup or dropoff zone counts in the table's trip and revenue totals and in no share count. A consumer that recomputes the share must exclude those rows.
- Adding a borough value to the master data changes the base of the share for the boroughs it borders, and is a change to this definition's population rather than a data refresh.
- A future surface that reports a different base, such as a share restricted to New York City boroughs, is a different measure and needs its own name.

## Affected designs
