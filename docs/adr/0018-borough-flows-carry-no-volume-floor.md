---
status: decided
date: 2026-11-24
---

# The borough flow table publishes every borough pair, with no volume floor

`agg_borough_flow_monthly` publishes all origin borough × destination borough cells for every month, including a pair-month where no trip ran, which appears as a row of zero trips and zero revenue. It does not carry ADR 0017's 25-trip floor.

The floor in ADR 0017 answers a different question. It keeps the 265 × 265 zone-pair matrix free of pairs that hold ones and twos, where a "route" cannot be told apart from noise. At borough grain the cells are few and each stands for a whole borough, so a thin cell is a finding about the city's traffic rather than noise in a matrix, and it is exactly what the question asks for. Applying the floor here would also break the table's own arithmetic: an origin borough's cross-borough share needs every destination cell, so dropping the thin ones would make the published rows stop adding up to the published share.

The rejection is deliberate and recorded, because the same word ("a published flow") carries a floor in one surface and none in the other: on this surface, published means every borough pair, not every pair above a threshold.

## Considered options

- **Apply ADR 0017's 25-trip floor at borough grain** — rejected: it drops real borough pairs from a population whose question is precisely which pairs carry traffic, and it removes denominator rows the share needs.
- **Publish only pairs with traffic, no explicit zeros** — rejected: an absent row cannot be told apart from a pair nobody checked, and the share can no longer be verified by adding up the table's own rows.
- **Publish the full grid with zero rows and no floor** — chosen.

## Consequences

- `sum(trip_count)` over the whole table equals the billable trips in the reporting window, so the table can be reconciled against `fct_trip` directly.
- Summing a single origin's rows reproduces that borough's trips. For the share, an origin's resolved diagonal plus its off-diagonal resolved cells reproduce the denominator, and on a resolved origin the off-diagonal resolved cells alone are the numerator, so the rate is reconstructable from the published rows. An unresolved origin has no resolved diagonal, so its off-diagonal resolved cells equal its denominator while its numerator stays zero (ADR 0019).
- A consumer wanting the "which corridors exist" question still reads `agg_od_flow_matrix` under ADR 0017; the two surfaces answer different questions and are not interchangeable.
- A new mart that publishes flows must state which of the two populations it publishes.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
