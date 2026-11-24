---
status: decided
date: 2026-11-24
---

# The revenue walk decomposes the total it reports

A revenue walk is a decomposition: its components are disjoint parts of one total, and summed over any group of trips they equal that group's total. The walk at `finance.mart_revenue_component_bridge` therefore publishes `total_amount` as the sum of its nine component rows, and each component — `airport_fee` among them — is subtracted from the residual rather than being left inside it.

Before this, `fare_residual` was the total minus fare, tip, tolls and the four surcharges in `surcharge_columns()`, with `airport_fee` not among them, so the fee stayed in the residual. The bridge then published `c_airport_fee` as its own component on top of that residual, and the fee appeared twice. The walk read higher than billable revenue by the whole fee, which is a decomposition that does not decompose.

The rule this fixes is not that the fee must be a component: it is that the walk and the total it publishes must agree. `c_airport_fee` stays a component because finance reads the fee as its own line, and the residual stops absorbing it so the line is counted once.

## Considered options

- **Leave `airport_fee` in the residual and drop `c_airport_fee` from the walk** — rejected: it balances the walk by removing a line finance reads. The fee is a real, separately-rated charge and belongs in the decomposition as its own component.
- **Keep both and state that the walk totals higher than revenue** — rejected: the walk exists to decompose the total, and a published surface whose components do not sum to its own `total_amount` column is a trap for every consumer that runs `sum(component_amount)`. A rule that the total is approximate cannot be stated honestly in a column called `total_amount`.
- **Add `airport_fee` to `surcharge_columns()`** — rejected: that macro is the surcharge set, and its sum is published in its own right as `total_surcharges` (`fct_trip.total_surcharges`, and `surcharge_revenue` in `mart_daily_zone_revenue` and `agg_trip_zone_daypart_dow`). Folding the airport fee in would move those numbers, change what "surcharge" means in the glossary, and put the fee in `fct_shift.surcharge_collected` beside its existing `airport_fee_collected`. The fee is not a surcharge for this purpose: it is a separately-rated access charge the TLC reports in its own column.
- **Subtract the fee from the residual while leaving `surcharge_columns()` alone** — chosen: the residual is what the total does not explain, so any component the walk publishes must be excluded from it. The residual is the only term that has to change, and nothing that reports the surcharge set moves.

## Consequences

- `fare_residual` means "the total minus every component the walk publishes", `airport_fee` included. Its published definition and the `fare_residual_total` metric move with it.
- `has_unexplained_residual` and `mart_trip_quality_scorecard.unbalanced_total_count` change population: trips whose whole imbalance was the fee stop counting as unexplained, and trips whose total excludes the fee start. Both are the correct verdicts; the scorecard's count on any given window moves when the residual's definition moves.
- A future component added to the walk must be subtracted from the residual in the same change, or the walk double-counts again. The test that asserts the walk sums to the total per group is what holds this: it fails on any new component that is not excluded.
- The walk's total and `billable_revenue` agree by construction on the same population, so a difference between them is a defect in one of them, not a coverage difference to explain.

## Affected designs

- [`models/intermediate/int_trip_fare_components.md`](../design/models/intermediate/int_trip_fare_components.md)
- [`models/core/fct_trip.md`](../design/models/core/fct_trip.md)
- [`models/finance/mart_revenue_component_bridge.md`](../design/models/finance/mart_revenue_component_bridge.md)
