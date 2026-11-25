---
status: decided
date: 2026-10-14
---

# A billable trip is one with a positive total, applied where revenue and flows are reported

A trip is **billable** when its total amount is positive. The warehouse computes the verdict once, in `int_trip_quality_flags`, and `fct_trip` keeps every trip and exposes it as `is_billable`. Gold marts that report revenue or flows apply it, inside the reporting window: `mart_monthly_service_summary`, `mart_revenue_component_bridge` and `agg_od_flow_matrix`, and `agg_trip_zone_daily` applies it to its `billable_*` measures. Marts that profile quality or banding report billable and non-billable counts side by side instead of filtering (`agg_trip_zone_daypart_dow`, `agg_trip_band_profile`, `mart_trip_quality_scorecard`), and the fleet-operations marts do not use the rule at all.

Applying the rule to a measure is not the same as reducing a relation to billable trips. `agg_trip_zone_daily` publishes both populations side by side — all-trip `trip_count` and `total_revenue` beside `billable_trip_count` and the `billable_*` revenue columns — because Operations reads its all-trip figures and Finance reads its billable-only ones, and one build serves both. `mart_daily_zone_revenue` therefore applies the rule by selecting `agg_trip_zone_daily`'s billable measures rather than by filtering trips itself; it still reports billable trips only.

This supersedes ADR 0002, which said every gold mart applies the rule. The models do not, and could not: a quality mart needs the rows the rule excludes, and a shift mart measures time, not billing.

## Considered options

- **Filter in silver** — rejected: the excluded rows (refunds, voids, meter errors) would be invisible to quality work.
- **Every gold mart applies it** (the statement in ADR 0002) — rejected: it contradicts the marts that must see non-billable trips, and the fleet-operations marts that do not measure billing.
- **Flag once, apply where revenue or flows are reported** — chosen: one definition, and each mart states whether it filters.

## Consequences

- Revenue and flow marts have fewer rows than `fct_trip`, always.
- A relation that publishes both populations, such as `agg_trip_zone_daily`, has the same rows as `fct_trip`'s grouping and states which columns carry which population.
- The rule uses only the total amount. It does not exclude any payment method (see ADR 0013).
- Changing the reporting window restates every mart that applies the rule.
- A new revenue or flow mart applies the rule; a new quality or fleet-operations mart does not unless a requirement says so.
- A mart that reads a relation which already publishes billable measures applies the rule by selecting them, not by filtering trips again.

## Affected designs

- [`models/core/fct_trip.md`](../design/models/core/fct_trip.md)
- [`models/intermediate/int_trip_quality_flags.md`](../design/models/intermediate/int_trip_quality_flags.md)
- [`models/finance/mart_daily_zone_revenue.md`](../design/models/finance/mart_daily_zone_revenue.md)
- [`models/agg/agg_od_flow_matrix.md`](../design/models/agg/agg_od_flow_matrix.md)
- [`models/agg/agg_trip_zone_daily.md`](../design/models/agg/agg_trip_zone_daily.md)
