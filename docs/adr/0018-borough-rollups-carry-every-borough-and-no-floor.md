---
status: decided
date: 2026-11-25
---

# A borough rollup reports every borough the zone master names, with no trip floor, and its cross-borough share is per origin borough

A borough-level rollup of trips is a whole-network answer, so it is not narrowed the way the published zone-pair matrix is. It reports every borough group the zone master names — the five NYC boroughs, EWR and the two unresolved groups — keeps every billable trip, and publishes a pair as soon as it carries one. The cross-borough share of an origin borough-month is its trips that end in a different borough over all its trips that month; a trip that starts and ends in the same borough group, an unresolved one included, did not cross a borough line.

ADR 0017's 25-trip floor is a rule about which zone pairs may be called a published flow, and it stays scoped to that surface. Applying it here would change the denominator of the share as well as the numerator, so the share would describe the pairs that survived the floor rather than the borough's traffic: measured over Q1 2024 it lowers the cross-borough share of every month, by 0.22 points in January (12.79% to 12.57%). The zone master's unresolved groups are kept here for the reason ADR 0012 gives, that a borough rollup reports them unless its consumer filters; they carry 360 Q1 billable origins and 902 destinations.

## Considered options

- **Apply the 25-trip floor per borough pair** — rejected: it narrows the denominator too, so boroughs whose crossings are thin report a share of their traffic that is not their traffic.
- **Report the five NYC boroughs only** — rejected: it drops trips to and from Newark and the trips whose zone no borough resolves, and makes the five shares a share of a filtered network.
- **A single cross-borough share for the whole network per month** — rejected: it hides that the outer boroughs and Manhattan differ by an order of magnitude.
- **Every borough group, no floor, share per origin borough** — chosen.

## Consequences

- Summing the pair rows of a month reproduces the month's billable trips, unresolved groups included.
- A borough pair with no traffic in a month is absent rather than published as zero, so a reader counts crossings that happened.
- The share repeated on each of an origin borough's rows is one number: it is a property of the origin borough-month, not of the pair.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
