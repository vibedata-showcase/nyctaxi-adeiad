---
artifacts: [mart_revenue_component_bridge]
---

# mart_revenue_component_bridge

The fare-to-total revenue walk: each trip total split into its components, one
component per row, for reconciliation line by line.

## Grain

One row per trip month, service type, pickup borough and component. `trip_count`
and `total_amount` repeat on every row of their group and are never summed
across components.

## Decisions

- `D-01` The walk's component lines and `fare_residual` share one component list. A component published here on its own line is subtracted in the residual, so the nine lines sum to the group's `total_amount` by construction and `c_residual` is only what no other line explains. Registering a new component means adding it to both. Source: `CONTEXT.md` "Fare residual", `docs/cases/2026-11-24-r7-revenue-walk-fix-1482da4f.md`, [D-08](../core/fct_trip.md).
- `D-02` A group carries fewer than nine rows when one of its component aggregates is NULL, because the unpivot emits no row for NULL. The balance holds regardless: such a line contributes nothing to the total either. A consumer that expects exactly nine rows per group must left-join the component names, not count rows. Source: `docs/cases/2026-11-24-r7-revenue-walk-fix-1482da4f.md` (side finding a).
- `D-03` The residual is its own line rather than being absorbed into a real component, so a total that does not equal its parts stays visible as a finding about the source. Source: `docs/cases/2026-11-24-r7-revenue-walk-fix-1482da4f.md`.

## Rejected

- Absorbing the residual into one of the real components — it would hide an unbalanced total inside a figure that then no longer means what it says.
- Making the walk a fact in the semantic layer — summing its measures across `component_name` fans out; it is a walk, so `repo-map.json` excludes it.

## Consumers

None declared in this repository. The reconciliation intent
`4e8111a9-429b-46f3-84a8-abc6d17ae841` reads it for its answer; no external
consumer is known.

## Logical Model

Excluded from the semantic layer by `repo-map.json` `semantic_exclusions` (an
unpivot cannot be a star member), so no document under `logical-model/` names
this relation and nothing is added, changed or retired there.

```yaml
documents:
  nyc_taxi_analytics:
    datasets: {added: [], changed: [], retired: []}
    metrics: {added: [], changed: [], retired: []}
    logical_sources: {added: [], changed: [], retired: []}
```

## History

- 2026-11-24 — r7-revenue-walk-fix-1482da4f — design record written; the residual and the walk share one component list, and the fee no longer sits in both — D-01, D-02, D-03 — terms: none new
