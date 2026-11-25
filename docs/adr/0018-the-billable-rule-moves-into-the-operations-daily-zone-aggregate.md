---
status: decided
date: 2026-11-25
---

# The billable rule moves into the operations daily zone aggregate

`agg_trip_zone_daily` gains billable measures beside the all-trip measures it already publishes, and `mart_daily_zone_revenue` reads them from it instead of applying the rule itself. Billable means what ADR 0003 says it means: a trip whose total amount is positive. What changes is where the rule is applied for this one report.

The trigger is that two builds answered the same question. Finance's daily zone revenue report and the operations daily zone aggregate both group the same trips to zone and day, and the report was a second build of a grain the operations aggregate already publishes. Making the report read the aggregate means the aggregate has to answer what the report asks, and the report asks for billable trips only. An aggregate over whole totals cannot have a rule subtracted from it downstream, so the split has to be computed where the rows are counted.

It is hard to reverse: once consumers read billable figures off the aggregate, withdrawing them breaks those consumers, and the report cannot fall back to its own build without becoming a second source again. It is surprising without this record: the aggregate is a demand mart, and ADR 0003's list of models that apply the rule is a list of revenue and flow marts. It was a real trade-off, recorded under `## Considered options`.

## Considered options

- **Publish billable measures beside the all-trip ones in the aggregate** — chosen. The aggregate keeps every row and every measure it publishes today, so quality and demand work still sees non-billable trips; the report reads one relation and applies no rule of its own.
- **Filter the aggregate to billable trips** — rejected: it would drop the trips quality and demand work needs, which is the thing ADR 0003 exists to prevent, and it would change the aggregate's published values.
- **Keep the report's own build over `fct_trip`** — rejected: it is the second build the change exists to remove.
- **Apply the rule in the report over the aggregate** — rejected: the aggregate publishes a count and a summed total, and non-billable trips carry negative totals, so no arithmetic on those two columns recovers the billable population.

## Consequences

- `agg_trip_zone_daily` publishes billable and all-trip measures side by side. Its existing columns, values and grain do not change, so its consumers are unaffected.
- `mart_daily_zone_revenue` applies no rule and holds no reporting-window filter of its own beyond the window the aggregate already applies; its numbers must not move.
- A zone-day whose trips are all non-billable carries no billable revenue to report. The report omits it; the aggregate keeps it.
- ADR 0003 still holds. The aggregate joins the models that apply the rule, and `mart_daily_zone_revenue` stops being one of them, inheriting the verdict instead.

## Affected designs

- [`models/agg/agg_trip_zone_daily.md`](../design/models/agg/agg_trip_zone_daily.md)
- [`models/finance/mart_daily_zone_revenue.md`](../design/models/finance/mart_daily_zone_revenue.md)
