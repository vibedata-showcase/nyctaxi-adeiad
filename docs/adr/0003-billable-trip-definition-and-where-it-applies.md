---
status: decided
date: 2026-10-14
---

# A billable trip is one with a positive total, applied where revenue and flows are reported

A trip is **billable** when its total amount is positive. The warehouse computes the verdict once, in `int_trip_quality_flags`, and `fct_trip` keeps every trip and exposes it as `is_billable`. Gold marts that report revenue or flows apply it, inside the reporting window: `agg_trip_zone_daily`, `mart_monthly_service_summary`, `mart_revenue_component_bridge` and `agg_od_flow_matrix`. `mart_daily_zone_revenue` reports revenue yet does not apply it itself: it reads `agg_trip_zone_daily`, which applies the rule once for both, so the two builds cannot disagree. Marts that profile quality or banding report billable and non-billable counts side by side instead of filtering (`agg_trip_zone_daypart_dow`, `agg_trip_band_profile`, `mart_trip_quality_scorecard`), and the fleet-operations marts do not use the rule at all.

This supersedes ADR 0002, which said every gold mart applies the rule. The models do not, and could not: a quality mart needs the rows the rule excludes, and a shift mart measures time, not billing.

The decision stands as written; its enumerated list of applying relations was corrected on 2026-11-25, when `mart_daily_zone_revenue` began reading `agg_trip_zone_daily`. The billable definition, the population and the reporting window are unchanged by that correction.

## Considered options

- **Filter in silver** — rejected: the excluded rows (refunds, voids, meter errors) would be invisible to quality work.
- **Every gold mart applies it** (the statement in ADR 0002) — rejected: it contradicts the marts that must see non-billable trips, and the fleet-operations marts that do not measure billing.
- **Flag once, apply where revenue or flows are reported** — chosen: one definition, and each mart states whether it filters.
- **Apply it again in each revenue mart, including one that reads an aggregate which already applied it** — rejected: the two builds are paid for twice and can disagree, which is what moving the application into `agg_trip_zone_daily` removes; a mart reading a billable-only aggregate cannot re-check the per-trip verdict at all.

## Consequences

- Revenue and flow marts have fewer rows than `fct_trip`, always.
- The rule uses only the total amount. It does not exclude any payment method (see ADR 0013).
- Changing the reporting window restates every mart that applies the rule.
- A new revenue or flow mart applies the rule; a new quality or fleet-operations mart does not unless a requirement says so.
- The rule is applied once per path, not once per mart: a mart reading an aggregate that already applied it inherits the result instead of repeating the filter.

## Affected designs

- [`models/core/fct_trip.md`](../design/models/core/fct_trip.md)
- [`models/intermediate/int_trip_quality_flags.md`](../design/models/intermediate/int_trip_quality_flags.md)
- [`models/finance/mart_daily_zone_revenue.md`](../design/models/finance/mart_daily_zone_revenue.md)
- [`models/agg/agg_trip_zone_daily.md`](../design/models/agg/agg_trip_zone_daily.md)
- [`models/agg/agg_od_flow_matrix.md`](../design/models/agg/agg_od_flow_matrix.md)
