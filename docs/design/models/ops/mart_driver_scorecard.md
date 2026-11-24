---
artifacts: [mart_driver_scorecard]
---

# mart_driver_scorecard

Driver performance for the reporting window, ranked within garage and fleet-wide.

## Grain

One row per driver.

## Decisions

- `D-01` Rank on revenue per online hour, not gross revenue: gross rewards whoever worked the most hours, which is a roster fact ([ADR 0010](../../../adr/0010-driver-ranking-and-utilisation-definitions.md)). Source: docs/requirement/2026-08-29-driver-status-occupancy-and-utilisation.md R-05, [ADR 0010](../../../adr/0010-driver-ranking-and-utilisation-definitions.md).
- `D-02` Flag drivers below a minimum number of online hours with `is_below_ranking_floor`, so a rank built on a few shifts is visible as noise ([ADR 0010](../../../adr/0010-driver-ranking-and-utilisation-definitions.md)). Source: docs/requirement/2026-08-29-driver-status-occupancy-and-utilisation.md R-05, [ADR 0010](../../../adr/0010-driver-ranking-and-utilisation-definitions.md).
- `D-03` Every rate is a ratio of summed numerators and denominators, null when the denominator is zero ([ADR 0019](../../../adr/0019-every-published-rate-is-a-ratio-of-summed-numerators-and-denominators.md)). Source: [ADR 0019](../../../adr/0019-every-published-rate-is-a-ratio-of-summed-numerators-and-denominators.md).

## Rejected

- Ranking on gross revenue.
- Ranking on revenue per trip.

## Consumers

None in this repo.

## History

- - 2026-10-14 — status-occupancy — design record written — D-01, D-02, D-03
