---
artifacts: [mart_revenue_component_bridge]
---

# mart_revenue_component_bridge

The fare-to-total walk, unpivoted one component per row, so the decomposition is auditable line by line.

## Grain

One row per (trip month, service type, pickup borough, component). `total_amount` and `trip_count` are repeated on every component row of the group and must not be summed across components.

## Decisions

- `D-01` The components are a decomposition of `total_amount`: summed over a group's rows they equal that group's `total_amount` ([ADR 0018](../../../adr/0018-the-revenue-walk-decomposes-the-total-it-reports.md)). A singular test asserts it per group, so a component added to the walk without being excluded from the residual fails the build. Source: [ADR 0018](../../../adr/0018-the-revenue-walk-decomposes-the-total-it-reports.md).
- `D-02` The residual is computed from one ordered macro list (`decomposed_columns()` in `transformation/macros/finance.sql`: fare, tip, tolls, the surcharges and the airport fee), while the unpivot names its nine components explicitly so the SQL stays readable. The two are held together by the group-balance test, not by trust: a component added to the unpivot and not to the list makes the walk double-count and fails the build. Source: [ADR 0018](../../../adr/0018-the-revenue-walk-decomposes-the-total-it-reports.md).
- `D-03` The residual is carried as its own component rather than absorbed into a real one. A non-zero residual is a finding about the source, not a rounding difference to bury. Source: [ADR 0018](../../../adr/0018-the-revenue-walk-decomposes-the-total-it-reports.md).
- `D-04` Apply the billable rule and the reporting window here, in gold ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-05` Inner-join `dim_zone` on the resolved pickup zone key, so the walk reports a borough per group. A trip whose zone does not resolve is absent from the walk rather than grouped under a sentinel; the group-balance test reads the bridge's own groups, so it does not detect that absence. Source: [ADR 0012](../../../adr/0012-unresolved-zones-are-retained-and-flagged.md).

## Rejected

- Dropping `c_airport_fee` and leaving the fee in the residual: it balances by removing a line finance reads ([ADR 0018](../../../adr/0018-the-revenue-walk-decomposes-the-total-it-reports.md)).
- Publishing the walk as fact in the semantic layer: summing its measures across trips fans out, so it is listed in the map's `semantic_exclusions`.

## Consumers

None in this repo. Excluded from the semantic layer (`repo-map.json` `semantic_exclusions`).

## Logical Model

```yaml
documents:
  logical-model/nyc_taxi_analytics.ossie.yaml:
    datasets: {}
    metrics: {}
    logical_sources: {}
    concepts: {}
    mappings: {}
```

The relation is in `repo-map.json` `semantic_exclusions`: summing its measures across trips fans out, so no Ossie dataset names it and this change moves nothing in the canonical model.

## History

- 2026-11-24 — ss-revenue-walk-fix — record written; the walk becomes a true decomposition, with the component list taken from the macros — D-01, D-02, D-03, D-04, D-05 — terms: none new
