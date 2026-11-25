---
status: decided
date: 2026-11-25
---

# A billable trip is one with a positive total, and the zone-day billable measures are computed once in the aggregate

A trip is **billable** when its total amount is positive. The warehouse computes the verdict once, in `int_trip_quality_flags`, and `fct_trip` keeps every trip and exposes it as `is_billable`. Gold marts that report revenue or flows apply it, inside the reporting window: `mart_monthly_service_summary`, `mart_revenue_component_bridge` and `agg_od_flow_matrix` filter `fct_trip` themselves. Marts that profile quality or banding report billable and non-billable counts side by side instead of filtering (`agg_trip_zone_daypart_dow`, `agg_trip_band_profile`, `mart_trip_quality_scorecard`), and the fleet-operations marts do not use the rule at all.

For the zone and trip date grain it is applied one layer earlier. `agg.agg_trip_zone_daily` publishes the billable zone-day measures — billable trip count and billable fare, tip, surcharge, toll and total revenue — beside its existing unfiltered measures, and `finance.mart_daily_zone_revenue` reads them rather than filtering `fct_trip` itself. Both relations carry the same grain, so before this decision two builds produced one population and Finance and Operations could read different numbers off it. An operations aggregate that reports unfiltered volume publishes the billable measures beside the unfiltered ones rather than replacing them, so both questions stay answerable from one relation.

This supersedes ADR 0003, which named `mart_daily_zone_revenue` as a model applying the rule in gold. The definition is carried over unchanged; only its placement at this grain moves. It is hard to reverse because a published relation either carries these measures or does not, and moving the computation again restates every consumer. It is surprising without context because ADR 0003 named that mart, and it no longer applies the rule.

## Considered options

- **Filter in silver** — rejected: the excluded rows (refunds, voids, meter errors) would be invisible to quality work.
- **Every gold mart applies it** (the statement in ADR 0002) — rejected: it contradicts the marts that must see non-billable trips, and the fleet-operations marts that do not measure billing.
- **Flag once, apply where revenue or flows are reported** — chosen, and carried over from ADR 0003.
- **Leave the two zone-day builds and document that they differ** — rejected: the request is one source, and two aggregations of one population drift silently.
- **Make `agg_trip_zone_daily` billable-only** — rejected: it would change the operation's own published volume and revenue, which answer a different question than the revenue report.
- **Recompute the report from `fct_trip` and keep the aggregate as a second, unfiltered build** — rejected: that is the duplication the request removes.
- **Carry the billable measures in the aggregate and inherit them in the mart** — chosen.

## Consequences

- Revenue and flow marts have fewer rows than `fct_trip`, always.
- The rule uses only the total amount. It does not exclude any payment method (see ADR 0013).
- Changing the reporting window restates every mart that applies the rule, and now also the aggregate that computes it for the zone-day grain.
- A new revenue or flow mart applies the rule itself, or reads a relation that already did, and says which.
- `agg.agg_trip_zone_daily` publishes both populations at its grain: unfiltered `trip_count` and `total_revenue`, and billable measures whose names state their population. A reader must pick the measure that states the population it wants.
- A zone-day with no billable trip carries `billable_trip_count` 0 and null billable revenue measures in the aggregate; the finance mart publishes it with its measures at zero, so every zone-day the operation has activity on appears in the revenue report.
- A published relation that a semantic document binds gains these measures in its `column_map`; a model that only republishes them under other names keeps its own bindings.
- A dimension is still Type 2 where its source versions history (ADR 0009), so a lookup that resolves zone attributes carries the fact's own date.

## Affected designs

- [`models/agg/agg_trip_zone_daily.md`](../design/models/agg/agg_trip_zone_daily.md)
- [`models/finance/mart_daily_zone_revenue.md`](../design/models/finance/mart_daily_zone_revenue.md)
- [`models/core/fct_trip.md`](../design/models/core/fct_trip.md)
- [`models/intermediate/int_trip_quality_flags.md`](../design/models/intermediate/int_trip_quality_flags.md)
- [`models/agg/agg_od_flow_matrix.md`](../design/models/agg/agg_od_flow_matrix.md)
