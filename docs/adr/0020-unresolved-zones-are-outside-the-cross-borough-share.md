---
status: decided
date: 2026-11-24
---

# Unresolved zones are outside the cross-borough share but inside its totals

`Unknown` and `N/A` are not boroughs. They are the zone dimension's marker for a zone that cannot be placed in a borough at all (ADR 0012), so they are no member of the borough level and a trip that touches one has no borough at one end. A share that asks "how much of this borough's traffic leaves it" therefore cannot take them: a trip ending in an unresolved zone did not arrive in another borough, and a trip starting in an unresolved zone is not one borough's traffic.

The borough flow mart publishes those trips as their own rows — the unresolved-to-unresolved pair and every pair touching an unresolved end — outside the share, and inside every total. Their rows carry a null `cross_borough_share`; they contribute nothing to any borough's `cross_borough_billable_trip_count`; and they are still counted in the relation's month sums of `trip_count` and `billable_revenue`, which therefore equal the star's billable trips and billable revenue exactly.

The denominator of a borough's share is every billable trip picked up in that borough, including the ones set down in an unresolved zone. Excluding those from the denominator too would hide the borough's real traffic from the only number the borough is asked about, and would make the share disagree with the trips published on the same rows. The numerator is the narrower term: it needs an arrived-in-another-borough trip, and an unresolved destination is not one.

## Considered options

- **Count an unresolved destination as leaving the borough** — rejected: it treats a missing borough as a different borough, which is exactly the relabelling ADR 0012 forbids, and it inflates the share (January 2024 Manhattan 6.01% instead of 5.53%, Queens 71.54% instead of 68.19%).
- **Drop unresolved trips from the mart entirely** — rejected: it loses the closure with the star, so the totals would no longer equal billable trips and revenue.
- **Exclude them from the denominator as well as the numerator** — rejected: a borough's own traffic would shrink by ~3.3% in Queens and the share would no longer be a property of the borough's traffic.
- **Keep their rows, publish a null share, and keep them in the totals** — chosen.

## Consequences

- The relation's month sums equal `fct_trip`'s billable trips and billable revenue exactly; that closure is a testable property and is tested.
- A share column summed or averaged across all rows is wrong: unresolved rows are null, and a consumer must filter on a resolved origin borough to read it.
- A pair with an unresolved end appears in the matrix like any other pair, so a reader sees those trips rather than wondering where they went.
- `EWR` is unaffected: it is a real zone with a real borough on the dimension, so it is a borough member and takes part in the share like the five NYC boroughs, even though it is outside the city.
- ADR 0012 is unchanged: nothing is dropped, remapped or relabelled. This ADR only states which rows a share may read.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
