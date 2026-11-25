---
status: decided
date: 2026-11-25
---

# The daily zone aggregation is built once, in `agg`, and carries both populations side by side

Daily figures by pickup zone used to be computed twice: `agg.agg_trip_zone_daily` over every trip, and `finance.mart_daily_zone_revenue` over the billable trips only. Ravi Menon, who owns the finance reports, asked for one source built from the operations figures without changing any number in the report. Those two requirements only hold together if the operations relation carries the billable measures too, because its existing columns aggregate every trip and an aggregate cannot be split back into the billable subset.

So the daily zone aggregation is computed once, in `agg_trip_zone_daily`, which publishes the all-trips measures and the billable measures beside them. Revenue and flow marts read the billable columns; quality and demand work reads the all-trips columns. The finance daily zone revenue report reads the billable columns and no trip-grain relation of its own.

This is a business definition of what each population means, supplied by the request and consistent with ADR 0003: the two populations are different measures, not a disagreement about one.

## Considered options

- **Two builds, one per population** — rejected: it is the duplication the request exists to remove, and the two figures were being read as though they should agree when they never could.
- **One build, billable only** — rejected: it weakens `agg_trip_zone_daily`'s published promise and destroys the all-trips figures its existing contract carries.
- **One build, all trips only, and the report filters** — rejected: the non-billable trips are inside the same zone-day as billable ones, so the subset cannot be recovered from a summed total.
- **One build carrying both populations** — chosen: one aggregation, every consumer keeps its numbers, and each population keeps its own definition.

## Consequences

- A consumer of a daily zone figure states which population it wants; there is no default.
- The two populations are expected to disagree, and neither is a defect against the other.
- A new daily zone measure is added here once, for both populations, rather than in a second build.

## Affected designs

- [`models/agg/agg_trip_zone_daily.md`](../design/models/agg/agg_trip_zone_daily.md)
- [`models/finance/mart_daily_zone_revenue.md`](../design/models/finance/mart_daily_zone_revenue.md)
