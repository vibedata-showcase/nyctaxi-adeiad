---
artifacts: [agg_driver_daily]
---

# agg_driver_daily

The base of the driver pyramid.

## Grain

One row per driver and shift date.

## Decisions

- `D-01` Carry the summed numerators and denominators with each rate, and compute a rate as a ratio of sums, never as the average of shift rates ([ADR 0019](../../../adr/0019-every-published-rate-is-a-ratio-of-summed-numerators-and-denominators.md)). Source: docs/requirement/2026-08-29-driver-status-occupancy-and-utilisation.md R-04, [ADR 0019](../../../adr/0019-every-published-rate-is-a-ratio-of-summed-numerators-and-denominators.md).
- `D-02` Build the level above (`agg_driver_monthly`) from this model rather than from shifts again, so the levels cannot disagree. Source: docs/requirement/2026-08-29-driver-status-occupancy-and-utilisation.md R-04.

## Rejected

- Averaging shift-level rates: the mean of two ratios is not the ratio anyone asked for.

## Consumers

Depended on by: `agg_driver_monthly`, `mart_driver_scorecard`.

## History

- - 2026-10-14 — status-occupancy — design record written — D-01, D-02
