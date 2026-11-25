---
status: decided
date: 2026-10-14
---

# A billable trip is one with a positive total, applied where revenue and flows are reported

A trip is **billable** when its total amount is positive. The warehouse computes the verdict once, in `int_trip_quality_flags`, and `fct_trip` keeps every trip and exposes it as `is_billable`. Gold marts that report revenue or flows apply it, inside the reporting window: `mart_daily_zone_revenue`, `mart_monthly_service_summary`, `mart_revenue_component_bridge` and `agg_od_flow_matrix`. Marts that profile quality or banding report billable and non-billable counts side by side instead of filtering (`agg_trip_zone_daypart_dow`, `agg_trip_band_profile`, `mart_trip_quality_scorecard`), and the fleet-operations marts do not use the rule at all.

This supersedes ADR 0002, which said every gold mart applies the rule. The models do not, and could not: a quality mart needs the rows the rule excludes, and a shift mart measures time, not billing.

## Considered options

- **Filter in silver** — rejected: the excluded rows (refunds, voids, meter errors) would be invisible to quality work.
- **Every gold mart applies it** (the statement in ADR 0002) — rejected: it contradicts the marts that must see non-billable trips, and the fleet-operations marts that do not measure billing.
- **Flag once, apply where revenue or flows are reported** — chosen: one definition, and each mart states whether it filters.

## Consequences

- Revenue and flow marts have fewer rows than `fct_trip`, always.
- The rule uses only the total amount. It does not exclude any payment method (see ADR 0013).
- Changing the reporting window restates every mart that applies the rule.
- A new revenue or flow mart applies the rule; a new quality or fleet-operations mart does not unless a requirement says so.

## Affected designs

- [`models/core/fct_trip.md`](../design/models/core/fct_trip.md)
- [`models/intermediate/int_trip_quality_flags.md`](../design/models/intermediate/int_trip_quality_flags.md)
- [`models/finance/mart_daily_zone_revenue.md`](../design/models/finance/mart_daily_zone_revenue.md)
- [`models/agg/agg_od_flow_matrix.md`](../design/models/agg/agg_od_flow_matrix.md)
- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
