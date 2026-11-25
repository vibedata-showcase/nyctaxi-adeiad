---
status: decided
date: 2026-11-25
---

# The cross-borough share is measured over the published pairs, not over all the borough's trips

The share of trips that leave the borough they started in is computed over the borough flows the surface publishes: the trips going to a different borough divided by all the trips in that origin borough's published pairs for the month.

This makes the column internally consistent — a reader can add the table's own rows and arrive at the denominator — at the cost of a share that differs from one computed over every trip the borough generated. The difference is largest exactly where it is most visible: an origin borough whose cross-borough destinations fall under the floor loses them from the numerator while keeping its own intra-borough pair in the denominator, so its share reads low.

That bias is accepted, not overlooked. The alternative — a denominator over all the origin's trips — leaves the table showing rows that do not add up to the share beside them, and a reader with no way to see why. A number that reconciles with the table it sits in is worth more here than a number that matches the city's own count, and the whole-network figure remains available from `fct_trip`.

## Considered options

- **Over all the origin borough's billable trips to New York City boroughs** — rejected: it is the more faithful answer to "how much of our traffic crosses borough lines", but the table's own rows then sum to less than the share's denominator and nothing on the surface says so.
- **Over the published pairs** — chosen: the share reconciles with the rows it is published beside.
- **A share over the published pairs and a second over all trips, side by side** — rejected: two columns with the same name and different populations invite the reader to pick the flattering one.

## Consequences

- The share is a property of the published surface, not of the borough's traffic. It is stated as such on the column and on the surface.
- A month whose origin borough has one published pair carries a share of zero or one, and that is a real reading of a thin surface, not a defect.
- Changing the floor in ADR 0018 restates every share.
- A consumer asking what fraction of a borough's traffic leaves it, over all its trips, queries `fct_trip` and computes it there.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
