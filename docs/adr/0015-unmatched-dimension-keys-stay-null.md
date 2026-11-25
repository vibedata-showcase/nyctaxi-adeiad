---
status: decided
date: 2026-10-14
---

# A dimension lookup that finds no row leaves the key null; there are no placeholder members

When a fact's lookup finds no dimension row in force, the key is null. No dimension has an "unknown" member and no key is replaced by a sentinel value. Fleet attribution works the same way, with an explicit flag: driver, vehicle and shift are null for trips outside the operator's fleet, and `is_fleet_attributed` says so. A trip whose pickup time lies before any version of a zone or vendor (a malformed timestamp) has null zone and vendor keys, and stays in the fact.

## Considered options

- **A placeholder member such as -1** — rejected: it joins cleanly and hides the gap in every rollup.
- **An inner join** — rejected: it drops trips, which a row-count test forbids.
- **Null keys, with a flag where the null is meaningful** — chosen.

## Consequences

- The fact keeps one row per trip.
- Consumers decide how to treat a null key.
- Unresolved zones are different: they are real rows (ADR 0012), not unmatched lookups.

## Affected designs

- [`models/core/fct_trip.md`](../design/models/core/fct_trip.md)
- [`models/agg/agg_trip_zone_daily.md`](../design/models/agg/agg_trip_zone_daily.md)
