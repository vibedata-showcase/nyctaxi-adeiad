---
status: decided
date: 2026-11-24
---

# Every published rate is a ratio of summed numerators and denominators, whatever level it aggregates

Every rate this Domain publishes — occupancy rate, revenue per online hour, utilisation, an average fare derived from two sums, a share of trips — is computed as a sum of numerators over a sum of denominators at the grain the rate is published at, through the `safe_divide` macro, which returns null when the denominator is zero. A rate is never the mean of the rates one level below it.

This widens ADR 0016, which stated the rule for the rates that aggregate shift-level measures, named the measurable tip rate as its one exception, and added that the semantic model's ratio metrics follow it. The rule it settled was right and the boundary it drew was narrower than the rule: a trip share computed as the mean of its members' shares is exactly the error the ADR rejects, and so is a share averaged across destinations rather than rebuilt from the borough's own counts. The measurable tip rate remains the one exception, for the reason 0016 gives: it is a trip-level measure with no denominator to sum, so its aggregate is a mean over the trips where it is measurable, and its measurable share is published beside it (ADR 0011).

Source: the Mobility Planning Lead's answer at the design stop of 2026-11-24, on being shown that the new borough flow table's shares followed this rule while ADR 0016's text did not reach them.

## Considered options

- **Leave the rule at shift-level rates, and record each new rate as following it deliberately** — rejected: every later rate then re-argues whether the rule binds it, and a rate that is wrong in the same way 0016 rejects has an ADR that says nothing about it.
- **Restate 0016 in place** — rejected: 0016 is decided and its consequences are already relied on; a decided ADR changes only through a superseding one.
- **Name the levels the rule covers instead of the kinds of measure** — rejected: a list of levels drifts as marts are added, while "at the grain it is published at" is the property that makes the rule true.
- **Widen it to every published rate, keeping the tip rate's exception** — chosen.

## Consequences

- A new rate carries its numerators and denominators at its own grain, so a higher level can sum them rather than average the rates.
- A rate whose denominator is zero is null, never zero.
- A rate that genuinely cannot be rebuilt from sums — a mean over records that carry no denominator, like the tip rate — states its exception and publishes the share of records it speaks for.
- A rate published at more than one grain is rebuilt at each, so the levels cannot disagree.
- ADR 0016 is superseded and its design records cite this one: `fct_shift`, `agg_driver_daily` and `mart_driver_scorecard`, whose decisions it settles, plus `agg_borough_flow_monthly`, the first relation whose rates needed the wider rule.

## Affected designs

- [`models/core/fct_shift.md`](../design/models/core/fct_shift.md)
- [`models/agg/agg_driver_daily.md`](../design/models/agg/agg_driver_daily.md)
- [`models/ops/mart_driver_scorecard.md`](../design/models/ops/mart_driver_scorecard.md)
- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
