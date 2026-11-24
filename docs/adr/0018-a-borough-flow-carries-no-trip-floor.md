---
status: decided
date: 2026-11-24
---

# A borough flow carries no trip floor

The origin-destination matrix publishes a zone pair only at 25 billable trips (ADR 0017). A table that reports flows between boroughs, by month, publishes every pair with at least one billable trip. The floor is a property of the zone-pair surface, not of every flow surface: it exists so a reader does not mistake two trips in a 265 × 265 cross product for a corridor, and at borough grain the pairs are few and each one names a real jurisdiction the city asks about.

The alternative — applying the floor at the new grain — was rejected on two grounds. It would hide most of the table: of the 104 populated borough-pair-month cells, 51 hold fewer than 25 billable trips, together 179 trips and 13,058.48 of revenue. And it would break the closure that makes the table usable: a per-origin-borough total that silently omits thin destinations cannot be reconciled to the borough's traffic, so the share of trips leaving a borough could not be recomputed from the table or trusted against the star.

The user's answer is the source: "The totals must equal billable revenue, so every billable trip counts." The consequence is deliberate — a borough-pair-month cell may be a single trip, and the table says so by publishing the count rather than a floor.

## Considered options

- **Apply ADR 0017's 25-trip floor to each borough × month cell** — rejected: it removes 51 of 104 populated cells and 179 trips, and it breaks every origin borough's monthly total, so the cross-borough share is computed on a population a reader cannot reconstruct.
- **Apply a lower floor, such as 10 trips** — rejected: the same objection at a smaller scale, and the number would be a constant tuned per surface rather than a rule.
- **Publish every pair with at least one billable trip** — chosen: the table stays whole, its totals close to `fct_trip`, and the thin cells are visible as thin rather than absent.
- **Publish the full borough cross product with zero rows** — rejected: a zero and an absent month would then be indistinguishable, and no other mart emits empty pairs.

## Consequences

- ADR 0017 keeps applying to `agg_od_flow_matrix` and is not changed by this decision; a consumer asking for zone-pair corridors reads that surface, and a consumer asking for borough traffic reads this one.
- The two surfaces do not agree cell for cell: summing the matrix over a borough pair gives the pairs above the floor only, so a borough total from the matrix is short. A borough total comes from the star or from this table.
- A cell's trip count is a fact to be shown, never a threshold to suppress.
- The table's population is the whole billable population of the reporting window, so its totals are checkable against `fct_trip` and its shape is guarded by that check.

## Affected designs
