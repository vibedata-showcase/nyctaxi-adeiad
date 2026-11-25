---
status: decided
date: 2026-11-25
---

# A borough-to-borough matrix publishes every pair, with no trip floor

The 25-billable-trip floor of ADR 0017 is a property of the zone-grain origin-destination matrix and does not extend to a borough-grain matrix. A borough matrix publishes all 25 origin-destination cells of the five NYC boroughs for every month, including the cells with no trips, and it publishes no cell below the floor on the grounds of being thin.

The floor was decided for a 265 × 265 zone cross product whose thin pairs are mostly ones and twos; a borough pair is a coarse, stable geography, and the pair a floor would hide is the one a planner most needs to see. Staten Island's outbound movement *is* the few-trips case, and hiding it would report the borough as having no cross-borough traffic. Nine of January's 25 borough cells carry fewer than 25 trips, so a floor here would publish 13 cells and read as a complete grid with holes.

The grid is also what makes the origin share answerable. A share of trip that leaves its origin borough needs every destination of that origin in the denominator, and a zero cell is a real zero — no trip was taken — not an unknown. The alternative that publishes only observed pairs would leave a reader unable to tell an unpublished pair from one with no traffic.

## Considered options

- **Apply the ADR 0017 floor to borough pairs** — rejected: it hides Staten Island's outbound flow entirely and narrows the origin share's denominator to whichever pairs survived.
- **Publish observed pairs only, no zero cells** — rejected: the grid has holes, and an absent cell cannot be told apart from a suppressed one.
- **Publish every pair, zero-filled, and publish the origin denominator beside the share** — chosen. The denominator is what a reader needs to judge a share built on a handful of trips, and it costs one column.

## Consequences

- A zero-trip cell carries zero trips and zero revenue, never a null: the zero is known, not missing.
- A cell's share of its origin can rest on very few trips; the origin month's trip count is published on every row of that origin so the reader can judge it, and no minimum is imposed.
- The floor in `agg_od_flow_matrix.sql` stays where it is. A future flow surface decides its own population and records it, as this one does.
- Summing a month's cells gives that month's total for the five boroughs, which the zone matrix cannot do because of its floor.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
