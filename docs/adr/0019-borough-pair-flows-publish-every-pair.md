---
status: decided
date: 2026-11-25
---

# A borough-to-borough matrix publishes every pair that carries traffic

ADR 0017 makes a published origin-destination flow a zone pair with at least 25 billable trips in the reporting window. That floor governs `agg_od_flow_matrix`, whose grain is the zone pair, where the 265 × 265 cross product is mostly pairs travelled a handful of times. It does not extend to a matrix at the borough-pair-and-month grain, and this ADR records the Mobility Planning Lead's answer that such a matrix publishes every pair that carries billable traffic.

The floor does not scale down to the coarser grain. Applying it at borough-pair-and-month grain would remove 66 of the 122 populated cells and 253 of the 95,958 billable trips in Q1 2024 — over half the cells for a fraction of a percent of the traffic — and it would break the crossing share, whose denominator is every trip that departed a borough, published cell or not.

ADR 0017 is unchanged and still governs `agg_od_flow_matrix`. The two surfaces are not interchangeable in either direction: summing this matrix reproduces the star's billable trip count and billable revenue over the reporting window, and summing the zone-pair matrix deliberately does not.

## Considered options

- **Apply ADR 0017's floor to borough pairs as well** — rejected: it costs most of the cells, distorts the share, and the noise the floor exists to suppress is a property of zone pairs, not of eight boroughs.
- **Publish no matrix and let each consumer group the fact** — rejected: the crossing definition, the split by month and the population would then be re-derived per consumer and disagree.
- **Publish every pair that carries traffic, with ADR 0017 untouched** — chosen.

## Consequences

- A thin borough pair appears as a row with a single trip. A reader must not treat every published row as a route; the granularity, not a floor, is what makes this surface readable.
- A borough pair with no billable trip in a month has no row, so a pivot over the matrix shows a gap rather than a zero.
- Changing this population changes what the matrix and its derived share report, so it is a decision to record rather than a constant to tune quietly.
