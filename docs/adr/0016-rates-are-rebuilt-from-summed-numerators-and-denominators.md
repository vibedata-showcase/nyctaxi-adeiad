---
status: decided
date: 2026-10-14
---

# A rate is rebuilt from summed numerators and denominators, and a zero denominator gives null

Every rate that aggregates shift-level measures (occupancy rate, revenue per online hour, utilisation) is computed as a sum of numerators over a sum of denominators, through the `safe_divide` macro, which returns null when the denominator is zero. Such a rate is never the average of lower-level rates. The measurable tip rate is the exception: it is a trip-level measure with no denominator to sum, and its aggregate is a mean over the trips where it is measurable, with the measurable share published beside it (ADR 0011). Each aggregation level is built from the one below, so day, month and ranking levels cannot disagree. The semantic model's ratio metrics are built the same way.

## Considered options

- **Average the rates of the level below** — rejected: the mean of two ratios is not the ratio anyone asked for.
- **Zero for an empty denominator** — rejected: it reads as a measured zero.
- **Ratio of sums, null on zero** — chosen.

## Consequences

- A new aggregate carries its numerators and denominators so a higher level can sum them.
- A null rate means the denominator was zero.

## Affected designs

- [`models/agg/agg_driver_daily.md`](../design/models/agg/agg_driver_daily.md)
- [`models/core/fct_shift.md`](../design/models/core/fct_shift.md)
- [`models/ops/mart_driver_scorecard.md`](../design/models/ops/mart_driver_scorecard.md)
- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
