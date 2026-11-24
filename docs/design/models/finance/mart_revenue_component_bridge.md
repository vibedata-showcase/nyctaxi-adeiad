---
artifacts: [mart_revenue_component_bridge]
---

# mart_revenue_component_bridge

The fare-to-total walk: every billable trip's total unpivoted into one row per modelled component, so the arithmetic from fare to total can be audited line by line.

## Grain

One row per trip month, service type, borough and component. A group carries nine rows, one per component; `total_amount`, `trip_count` and the trip's other measures repeat on each of them, so a consumer reads those once per group and never sums them across components.

## Decisions

- `D-01` Apply the billable rule and the reporting window here rather than upstream, so quality work still sees the excluded rows ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: docs/cases/2026-11-24-revenue-walk-double-counts-airport-fee-ca72c1e0.md, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-02` The residual is a component row of its own rather than being absorbed into a real component: a walk that hides what it cannot explain cannot be audited, and a non-zero residual is a finding about the source. Source: `CONTEXT.md` `Fare residual`.
- `D-03` The components must sum to the group's `total_amount`. That is the walk's whole claim, and it is why `c_residual` is `total_amount` minus every other modelled component — the airport fee included — rather than a fixed expression repeated in this model. A component that a model adds but the residual does not subtract is counted twice. Source: docs/cases/2026-11-24-revenue-walk-double-counts-airport-fee-ca72c1e0.md.
- `D-04` The model is not a star member and stays out of the semantic layer (`repo-map.json` `semantic_exclusions`): summing its measures across trips fans out through the unpivot. Source: `repo-map.json` `semantic_exclusions`.

## Rejected

- Absorbing the residual into `c_extra` or `c_fare`: it would make the walk balance by construction and destroy the finding it exists to surface.
- Computing the residual inside this model instead of reading `fct_trip.fare_residual`: the same expression would then live in two places, and a consumer of the fact would still get the uncorrected number.

## Consumers

None in this repo. No external consumer is declared; the relation is excluded from the semantic layer, so no canonical metric binds it.

## History

- - 2026-11-24 — r9-revenue-walk-fix — design record written; the walk's components sum to `total_amount` once the residual subtracts the airport fee — D-01, D-02, D-03, D-04
