---
artifacts: [int_trip_fare_components]
---

# int_trip_fare_components

Decomposes each trip total into its parts and states what is left over.

## Grain

One row per trip (`trip_key`).

## Decisions

- `D-01` The residual is the total minus **every** component the revenue walk publishes, `airport_fee` included ([ADR 0018](../../../adr/0018-the-revenue-walk-decomposes-the-total-it-reports.md)). The subtraction reads one ordered list, `decomposed_columns()` in `transformation/macros/finance.sql`, so the residual and the bridge cannot hold different ideas of what has been accounted for. Leaving a published component out of the subtraction makes the walk count it twice, which is the defect ADR 0018 closes. Source: [ADR 0018](../../../adr/0018-the-revenue-walk-decomposes-the-total-it-reports.md).
- `D-02` `surcharge_columns()` stays the surcharge set and does not gain `airport_fee`: its sum is published in its own right, as `total_surcharges` and as `surcharge_revenue`. The decomposition list is a separate macro built on top of it. Source: [ADR 0018](../../../adr/0018-the-revenue-walk-decomposes-the-total-it-reports.md).
- `D-03` `has_unexplained_residual` is `abs(fare_residual) > 0.01`. Its population moves whenever the residual's definition moves, which is the intended behaviour: the flag asks what the modelled components do not explain, and `airport_fee` is modelled. Source: [ADR 0018](../../../adr/0018-the-revenue-walk-decomposes-the-total-it-reports.md).
- `D-04` `measurable_tip_rate` is null where the payment method does not record tips ([ADR 0011](../../../adr/0011-tips-are-measured-only-where-the-meter-records-them.md)). Source: [ADR 0011](../../../adr/0011-tips-are-measured-only-where-the-meter-records-them.md).
- `D-05` Materialise as a view: the trip grain is stored once, in `fct_trip`. Source: `.agents/skills/dbt-models/SKILL.md` B15.

## Rejected

- Carrying the component list inline in the residual expression and again in the bridge's unpivot: two lists drift, and a drifted pair is exactly the defect this record closes.
- Adding `airport_fee` to `surcharge_columns()`: it would move `total_surcharges` and every `surcharge_revenue` that reads it ([ADR 0018](../../../adr/0018-the-revenue-walk-decomposes-the-total-it-reports.md)).

## Consumers

Depended on by: `fct_trip`, `int_shift_economics`.

## History

- 2026-11-24 — ss-revenue-walk-fix — record written; the residual stops absorbing `airport_fee`, which the walk publishes as its own component — D-01, D-02, D-03, D-04, D-05 — terms: none new
