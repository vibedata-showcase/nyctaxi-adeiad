---
status: decided
date: 2026-11-25
---

# A trip crosses a borough line when its destination borough differs from its origin borough

Every trip carries an origin borough and a destination borough, including the zones the TLC cannot place (`Unknown`, `N/A`) and the one zone outside the city (`EWR`). A trip is cross-borough when the two names differ, so a Manhattan trip that ends in an unplaceable zone crosses, and a trip whose two ends both read `N/A` does not. The question the city asked — how much traffic leaves the borough it started in — is answered over all traffic, so no trip is left outside the numerator or the denominator. The consequence is that a borough flow matrix in which every trip lands in exactly one cell reproduces the crossing share as one minus the same-borough share, and a reader can recompute the share from the table without knowing which borough names are "real".

## Considered options

- **Only a different NYC borough counts as crossing**, with unresolved and out-of-city destinations held as a residual — rejected: 1,137 of the 95,958 billable Q1 2024 trips end in an unplaceable zone or at Newark, and holding them out stops the published rows from reproducing the share. Over the same Q1 window it moves the Manhattan share from 5.92% to 5.30% and the Queens share from 72.92% to 72.01%.
- **Drop the trips whose destination is unresolved** — rejected: they happened, and ADR 0012 keeps them and flags them rather than removing them.
- **Any differing destination borough** — chosen, by the Mobility Planning Lead's answer to the requirement.

## Consequences

- Every borough name the zone lookup carries is a group in a borough flow matrix: the five NYC boroughs, `EWR`, `Unknown` and `N/A`. No row is filtered on the unresolved flag.
- The unresolved groups are read as their own origins and destinations, never folded into a city total.
- A share of crossings computed as one minus the same-borough share agrees with the published share, and a test can assert that equality.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
