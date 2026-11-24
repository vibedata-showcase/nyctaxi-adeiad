---
status: decided
date: 2026-11-24
---

# Daily zone revenue covers every billable trip, not only the operator's fleet

Finance's daily zone revenue report counts every trip the TLC records — yellow and green — whose total is positive and whose pickup falls inside the reporting window. It is not restricted to the trips the fleet operator attributed to its own shifts, and it cannot be built from the operator's trip records: those hold only the trips the operator's own vehicles ran, so a revenue report sourced there would cover a fraction of the yellow fleet, no green trips at all, and would stop being a picture of the city's billed revenue.

The same grouping is nonetheless computed once. One daily-by-zone build carries it, publishing the all-trip figures beside the billable ones, and the report selects its billable population from that relation instead of aggregating the trip fact again. Two builds of one grouping is the cost being removed, and the two currently read different populations, so they cannot agree.

The population is settled by the finance report owner's answer when asked to choose between the options below, recorded in `docs/requirement/2026-11-24-r9-zone-revenue-14872f57.md`.

## Considered options

- **Source the report from the operator's trip records** — rejected: they hold only the trips the operator's own vehicles ran, so the report would lose most of its population, every green trip, and every published figure would move.
- **Leave both builds in place** — rejected: the two compute the same grouping over different populations and disagree by construction; keeping both keeps the disagreement.
- **One build over all trips, publishing billable measures beside the all-trip ones** — chosen: the aggregation exists once, the report selects its population from it, and its figures do not change.

## Consequences

- The report's population stays every billable trip of both fleets inside the reporting window; a zone-day with no billable trip stays out of the report rather than appearing as a zero row.
- The daily-by-zone build publishes both all-trip and billable measures, and its existing all-trip measures keep their meaning and their values for the readers that use them.
- A later revenue or flow report reads the single daily-by-zone build instead of recomputing the grouping from the trip fact.
- The report's figures describe the city's billed trips, not the operator's own revenue; fleet-attributed revenue remains a separate question, answered from the shifts and the operations marts.
