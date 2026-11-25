---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

One row per calendar month and borough pair, for pairs a reader may treat as a borough flow: both ends in a New York City borough and at least 25 billable trips in that month. Built from `fct_trip` with `dim_zone` joined twice, once per role, and `dim_payment_method` joined for the revenue test.

## Grain

One row per (month, origin borough, destination borough). The period boundary is the calendar month, carried from `dim_date.month_start_date`, which is the warehouse's one month boundary; the alternative — truncating the trip's pickup date in this model — would put a second month boundary beside it.

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer, this intent.

## Decisions

- `D-01` A pair is published only when both ends resolve to a New York City borough and it carries at least 25 billable trips in that month. The rule, its alternatives and its consequences are ADR 0018; the surface is therefore a subset of the star's billable metrics, short by every pair under the floor and every pair with an end outside the city. "Billable" is the star's own verdict (ADR 0003), and excluding the two unresolved borough labels here is the consumer filter ADR 0012 allows a borough rollup to apply, not a change to how those trips are kept. Source: ADR 0018, from the user's answers "New York City boroughs only" and "the 25-trip floor".
- `D-02` Revenue is recognised revenue: `sum(total_amount)` restricted to payment methods whose `counts_as_revenue` is true. ADR 0013 leaves that call to each metric; the user chose it over the billable total the zone-pair matrix publishes. Source: user answer, this intent.
- `D-03` The payment-method join is a left join and the test is `coalesce(pm.counts_as_revenue, false)`. A billable trip with a null `payment_method_key` keeps its row and its trip count, and contributes no recognised revenue, because an absent payment method is not a method that counts as revenue. Dropping the row instead would break ADR 0015's rule that an unmatched lookup leaves the key null and the row in place. Source: ADR 0015.
- `D-04` Two counts are published, not one: `trip_count` (every billable trip in the pair) and `revenue_trip_count` (those that carry recognised revenue). The measure is present only on the second set, so the count that carries it is published beside it and the gap is visible rather than implied. Source: convention, the `transformation` playbook's Coverage default.
- `D-05` The cross-borough share is computed over the published pairs of the origin borough and month: trips to a different borough divided by all trips in those pairs. The bias this accepts, and the alternative it rejects, are ADR 0019. Source: user answer "only the published pairs".
- `D-06` The share's numerator and denominator are published as columns (`cross_borough_trip_count`, `origin_month_trip_count`) rather than left implicit, so a reader can recompute it from the row instead of trusting it. Source: `R-03`.
- `D-07` No zero-filled rows and no row for a borough-month with nothing published. A month in which an origin borough has no qualifying pair is absent from the surface, which is the statement that nothing cleared the floor. Source: ADR 0018.
- `D-08` The table is not a member of a star: the floor is a population no row predicate can state, so it is recorded in `repo-map.json` `semantic_exclusions` instead of a document. Source: `semantic-model` modelling rules, the exit a `HAVING` floor takes.

## Rejected

- **Building on `agg_od_flow_matrix`** — rejected: ADR 0017 states that summing its measures undercounts the network, so a borough rollup over it would inherit a zone-pair floor on top of its own and report neither population. Built from `fct_trip` instead.
- **A row predicate instead of a floor in `fct_trip`** — rejected: the floor is a property of the published surface, not of the trips; nothing is removed upstream.
- **A share over every trip of the origin borough** — rejected: the table's own rows would not add up to the number printed beside them. Recorded in ADR 0019 with its cost.
- **Publishing `avg_fare` and the other zone-matrix measures** — rejected: not requested, and each would need its own null and coverage rule.

## Logical Model

```yaml
documents: []
datasets: []
metrics: []
logical_sources: []
```

No Ossie document is touched. The relation is excluded from the canonical model because its population is a `HAVING` floor, which no `content_filter` predicate can state; the exclusion is recorded in `repo-map.json` `semantic_exclusions` with that reason, per `D-08`. `ontology/` gains no concept and no mapping.

## Consumers

Reports answering the city's cross-borough question, and ad-hoc borough-to-borough analysis for Mobility Planning. It is outside the canonical model, so no metric binds to it; a metric question about the whole network is answered from `fct_trip`.

## History

- 2026-11-25 — new-intent-1babac98 — created for the borough flow surface — `D-01`–`D-08` — terms: added cross-borough share, published borough flow
