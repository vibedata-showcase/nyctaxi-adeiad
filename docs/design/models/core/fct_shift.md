---
artifacts: [fct_shift]
---

# fct_shift

The bridge between the operational world (occupancy, leases) and the revenue world (trips).

## Grain

One row per driver sign-on (`shift_id`).

## Decisions

- `D-01` Online time runs to the shift's effective end, so an unclosed shift keeps the time it was worked. Source: docs/requirement/2026-08-29-driver-status-occupancy-and-utilisation.md R-02.
- `D-02` `occupancy_rate` is on-trip time over online time, from summed numerators and denominators, null when online time is zero ([ADR 0019](../../../adr/0019-every-published-rate-is-a-ratio-of-summed-numerators-and-denominators.md)). Source: docs/requirement/2026-08-29-driver-status-occupancy-and-utilisation.md R-04, [ADR 0019](../../../adr/0019-every-published-rate-is-a-ratio-of-summed-numerators-and-denominators.md).
- `D-03` `revenue_per_online_hour` is gross revenue over online hours, the ranking basis ([ADR 0010](../../../adr/0010-driver-ranking-and-utilisation-definitions.md)). Source: docs/requirement/2026-08-29-driver-status-occupancy-and-utilisation.md R-05, [ADR 0010](../../../adr/0010-driver-ranking-and-utilisation-definitions.md).

## Rejected

- Treating a null shift end as a zero-length shift.

## Consumers

Depended on by: `agg_driver_daily`, `agg_driver_monthly`, `agg_garage_monthly`, `agg_vehicle_daily`, `agg_vehicle_monthly`, `mart_driver_scorecard`, `mart_vehicle_utilisation`.

## Semantic Model

```yaml
metrics:
  - shift_count
  - online_hours
  - occupancy_rate
  - revenue_per_online_hour
```

## History

- - 2026-10-14 — status-occupancy — design record written — D-01, D-02, D-03
