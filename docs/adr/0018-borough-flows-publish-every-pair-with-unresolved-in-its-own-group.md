---
status: decided
date: 2026-11-24
---

# The borough flow surface publishes every city borough pair, monthly, with unresolved trips in their own group

A borough-to-borough surface reports the city's five boroughs plus one `unresolved` group on both sides, one row per month and per origin-destination pair, and it publishes every combination in that row and column set — a pair with no trips keeps its row carrying zero, so a missing row never has to be read as "no trips". The population is billable trips in the reporting window (ADR 0003), attributed through each trip's own zone version; a trip counts at the pair its origin and destination boroughs name.

Two members are not city boroughs and are handled differently, both on Mobility Planning's instruction.

`unresolved` covers the zones the TLC cannot place in a borough (ADR 0012). It is a row and a column of its own, so those trips stay visible and a rollup closes. It is **not** a borough for the purpose of crossing: a trip whose destination is unresolved neither stayed in the origin's borough nor left it, so it is excluded from both the numerator and the denominator of a borough's share of trips that leave. Counting such a trip as leaving would report the city's traffic as more cross-borough than anyone can evidence, on the strength of a zone the source could not place.

`EWR` — Newark airport, a borough value in the zone lookup with `is_nyc` false — is not a New York City borough and is left out of the surface altogether, on both sides. A trip to Newark is not traffic crossing a line between two city boroughs, and the city's question is about its own boroughs.

ADR 0017's 25-trip floor is **not** applied here; it stays the rule for the zone-grain origin-destination matrix. The floor was decided against a 265 × 265 cross product that is mostly ones and twos, and at borough grain the same floor would delete 43 of the 93 month-pairs that carried any billable trip in Q1 2024 — including city corridors of a dozen trips, such as Bronx to Brooklyn at 11 trips in January — and would leave a borough's share of leaving trips without the population it divides by. A published borough pair therefore means something different from a published flow: the flow floor still governs the zone matrix.

## Considered options

- **Apply the 25-trip floor per month at borough grain** — rejected: it hides thin but real corridors, and the leaving share needs every trip from a borough to a resolved destination.
- **Publish only pairs that carried trips** — rejected: a reader cannot tell an absent pair from an unpublishable one.
- **Count a trip to an unresolved zone as leaving** — rejected by the business: Unknown and N/A are not boroughs, so such a trip neither stays nor leaves.
- **Keep the two unresolved labels as two members** — rejected: one group, so a consumer reads a single unresolved row and column.
- **Include EWR as a borough** — rejected: it is out of state and outside the question.
- **Five city boroughs, one unresolved group, every pair, no floor** — chosen.

## Consequences

- Summing `trip_count` over the surface gives the billable trips in the window that touch neither EWR, not the whole network; a question about the network reads the trip fact.
- The leaving share is one value per origin borough per month, repeated on each of that origin's destination rows. Summing or averaging it across rows is meaningless, and a consumer that wants it once takes any one row of the origin's month.
- A share is null, never zero, when a borough sent no trip to a resolved destination in the month: an empty denominator is not a measured zero (ADR 0016). The `unresolved` group carries no share at all, for the same reason it is no borough: a trip starting in a zone TLC cannot place leaves no borough to measure against.
- A consumer that wants the unresolved group out filters it; the surface keeps it, per ADR 0012.

## Affected designs

- [`models/agg/agg_borough_flow_matrix.md`](../design/models/agg/agg_borough_flow_matrix.md)
