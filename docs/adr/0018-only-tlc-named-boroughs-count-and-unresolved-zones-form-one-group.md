---
status: decided
date: 2026-11-24
---

# Only the boroughs the TLC names count; its Unknown and N/A zones are reported as one Unresolved group

A borough rollup built from the zone dimension meets eight borough labels, not five: the five the TLC names for New York City, `EWR`, and the two its unresolved zones carry, `Unknown` and `N/A` (ADR 0012). `EWR` is a borough because the TLC lists it as one. `Unknown` and `N/A` are not boroughs: they are the absence of one, so a rollup merges them into a single `Unresolved` group, and a trip that touches that group is counted as neither in-borough nor cross-borough.

The crossing share follows from that: a trip leaves its borough only when both of its ends resolve to a named borough and those boroughs differ. The unresolved group is still published, so the trips remain visible, but it stands outside the in-borough and cross-borough counts rather than being assigned to either. Anything else would report a trip to a zone nobody could place as a trip across a borough line.

Source: the Mobility Planning Lead's answer to the requirement for a monthly borough-to-borough flow table, 2026-11-24.

## Considered options

- **Treat `Unknown` and `N/A` as boroughs and count their trips in the shares** — rejected: it invents a borough, and a trip to an unplaced zone then reads as a trip across a line.
- **Drop the trips that touch an unresolved zone** — rejected: the trips happened, and ADR 0012 keeps them.
- **Report every unresolved label separately** — rejected: two labels are one gap in the zone master, and splitting it makes the gap look like a destination of its own.
- **One `Unresolved` group outside the borough counts, in the table** — chosen, with `EWR` kept as a borough because the TLC names it one.

## Consequences

- A borough crossing share has a narrower denominator than the period's total trips: every trip that touches an unresolved zone at either end is outside it.
- A rollup that publishes the unresolved group therefore publishes trips its shares do not cover, and has to say so on the relation.
- `EWR` remains a distinct origin and destination, so a trip between Queens and `EWR` is a crossing; a trip between two zones the TLC cannot place is not.
- Any future borough rollup that counts crossings inherits this definition rather than deciding it again.
