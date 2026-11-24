---
status: decided
date: 2026-10-14
---

# The tip rate is measured only over payment methods that record tips

The measurable tip rate is the tip as a share of the fare, and it exists only for payment methods that record tips (the payment method master flags them). For every other method it is null, not zero, because an unrecorded tip is unmeasured rather than absent. Aggregates publish the share of trips for which it is measurable beside the rate.

## Considered options

- **A blended rate over all trips** — rejected: it falls in proportion to how much of a zone's traffic pays another way, which reads as a finding about the zone and is an artefact of the instrument.
- **Exclude non-recording trips from the data** — rejected: they are real trips.
- **Null where unmeasured, share published** — chosen.

## Consequences

- Averages of the rate ignore nulls by design; a count of measurable trips accompanies them.
- Tip totals are structurally understated and are not reported as a tip rate.

## Affected designs

- [`models/core/fct_trip.md`](../design/models/core/fct_trip.md)
- [`models/intermediate/int_trip_fare_components.md`](../design/models/intermediate/int_trip_fare_components.md)
