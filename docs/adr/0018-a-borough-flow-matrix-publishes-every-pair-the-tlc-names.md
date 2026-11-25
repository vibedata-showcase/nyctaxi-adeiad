---
status: decided
date: 2026-11-25
---

# A borough flow matrix publishes every pair the TLC names a borough, with no trip floor

The borough-level flow matrix reports every ordered pair of the TLC's own borough groups, in every month of the window, with no minimum trip count. ADR 0017's 25-trip floor stays with the zone-pair matrix it was reasoned for: it answers "which corridors exist" out of a 265 × 265 cross product that is mostly ones and twos. At borough grain the same floor would delete most of the surface — 66 of the 122 observed borough pair-months carry fewer than 25 billable trips — and a caller asking how much traffic crosses a borough line expects the whole matrix, small cells included, because the small cells are what the share is computed from.

The published groups are the eight names the zone lookup carries, not the five city boroughs. EWR is out of state and two labels ("Unknown", "N/A") place no zone in a borough at all; all three are real traffic and appear as their own origin and destination groups, so summing the matrix reproduces the billable trips in the reporting window instead of quietly dropping them. A filter on the NYC flag is the consumer's, not the mart's (ADR 0012).

The population is billable trips inside the reporting window, per ADR 0003 — this is a flow mart.

## Considered options

- **Apply the 25-trip floor per pair-month** — rejected: it empties most of the matrix and makes the crossing share unreproducible from the published rows.
- **Publish the five city boroughs only** — rejected: EWR and the unresolved groups hold real trips, so the matrix would not reconcile to the trip fact, and a borough rollup that silently drops them repeats the mistake ADR 0012 refuses.
- **Fold EWR and the unresolved groups into one "other" group** — rejected: EWR is a named airport travellers actually go to, and merging it with a group that means "the lookup could not place this zone" would make the destination unreadable.
- **Every group, no floor, billable only** — chosen.

## Consequences

- The matrix has a row for every month × origin group × destination group, with zero-trip cells kept, so a missing row never has to be told apart from a zero.
- `sum(trip_count)` over the matrix equals the billable trips picked up in the reporting window; ADR 0017's partiality does not apply here.
- A consumer wanting city boroughs only filters the NYC flag; a consumer wanting the TLC's grouping as published reads it as it stands.
- The table is a matrix, not a star member: the pickup and dropoff groups are the same dimension in two roles, as in `agg_od_flow_matrix`.
