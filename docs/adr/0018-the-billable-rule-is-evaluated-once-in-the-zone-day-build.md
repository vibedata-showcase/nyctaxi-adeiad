---
status: decided
date: 2026-11-24
---

# The billable rule is evaluated once, in the zone-day build, and a report on that grain selects its measures

The billable rule ([ADR 0003](0003-billable-trip-definition-and-where-it-applies.md)) says which surfaces report the billable population and which do not. It does not say where the predicate is evaluated when two of those surfaces share one build. This decision fixes that: the zone-day build `agg_trip_zone_daily` evaluates `fct_trip.is_billable` and the reporting window once, and `mart_daily_zone_revenue`, at the same grain, selects the resulting measures and evaluates neither again.

The rule, its definition on the total amount, and the reporting window are unchanged. ADR 0003's list of surfaces still holds: `mart_daily_zone_revenue` still reports the billable population, and the marts that profile quality still report both populations without filtering. What changes is where the predicate that produces the billable population is written — in the build both surfaces read, rather than in each surface. ADR 0003's sentence naming which gold marts apply the rule is therefore read as naming which surfaces *report* the billable population; where the predicate is evaluated is this decision.

## Considered options

- **Evaluate the rule in every surface that reports it** — was the arrangement, and it is what produced two builds of one answer that could disagree. It also makes each surface a separate place the rule can quietly change.
- **Evaluate it in the fact and filter wholesale** — rejected: quality work needs the rows the rule excludes (ADR 0003).
- **Evaluate it once, in the shared build; surfaces on that grain select** — chosen. One evaluation point, and the surfaces keep their published meanings.
- **Keep the predicate in the report and let the build stay all-trips** — rejected: the report would then re-aggregate `fct_trip` or re-filter a build that already aggregated, and the duplication the business paid for twice would remain, only moved.

## Consequences

- A report on this grain carries no billable predicate of its own, and one added back is a defect even when it returns the same rows today: it restores the second evaluation point.
- A surface on this grain publishes the zone-days its billable measures cover, so a zone-day with in-window trips and no billable trip appears in the build and not in the revenue report. The report is a selection on its own billable count, never a re-derivation of the rule, and this is why the two relations legitimately have different row counts.
- A column named `trip_count` means what its surface says it means. `agg_trip_zone_daily.trip_count` counts every in-window trip; `mart_daily_zone_revenue.trip_count` counts billable trips and reads the build's `billable_trip_count`. Neither is renamed to match the other, and each description states its own population.
- Changing the rule or the reporting window changes the build, and every surface selecting from it follows without a second edit — whereas a surface that kept its own predicate would not, which is how the two drift apart.
- A new revenue or flow surface at another grain still evaluates the rule itself, per ADR 0003; this decision binds only surfaces sharing the zone-day build.

## Affected designs

- [`trips/one-zone-day-build.md`](../design/trips/one-zone-day-build.md)
- [`models/agg/agg_trip_zone_daily.md`](../design/models/agg/agg_trip_zone_daily.md)
- [`models/finance/mart_daily_zone_revenue.md`](../design/models/finance/mart_daily_zone_revenue.md)
