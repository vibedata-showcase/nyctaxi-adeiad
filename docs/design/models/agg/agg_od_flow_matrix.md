---
artifacts: [agg_od_flow_matrix]
---

# agg_od_flow_matrix

Origin-to-destination flow, one row per zone pair, built from `fct_trip` with `dim_zone` joined twice — once in each role.

## Grain

One row per (origin zone, destination zone) pair that qualifies under the floor below, for the reporting window.

## Decisions

- **D-1 A pair is published only at 25 billable trips.** The rule, its alternatives and its consequences are ADR 0017; what population the table therefore answers is stated on its logical source in the semantic model, not repeated here.
- **D-2 Billable only.** The matrix counts billable trips, per ADR 0018, because a non-billable trip is not a flow anyone paid for.
- **D-3 Natural keys only.** The table carries `zone_natural_key` and the zone's descriptive columns, not surrogate keys, so a pair keeps its identity across a zone re-designation. Reason: a surrogate would split one route into two rows when a zone version changes.
- **D-4 The roles are the point.** The same dimension joined twice is what makes a matrix possible; a single zone key cannot produce an origin and a destination for the same trip.

## Consumers

Reports and ad-hoc analysis of corridors. The canonical model binds `billable_trip_count` and `billable_revenue` to this table through one logical source; see [ADR 0017](../../adr/0017-published-flows-have-a-25-trip-floor.md) for the floor.
