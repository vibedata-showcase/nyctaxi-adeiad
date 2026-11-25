---
status: decided
date: 2026-10-14
---

# Weeks start on Monday, and `dim_date.week_start_date` is the single week boundary

A week starts on Monday. `dim_date.week_start_date` truncates a date to its week and is the only week boundary in the warehouse; a model that reports by week joins to it. No model reports by week yet; this records the answer so that a requirement does not have to ask.

## Considered options

- **Weeks start on Sunday** — rejected: it differs from the ISO week the calendar already carries.
- **Each mart defines its own week** — rejected: two weekly numbers would disagree.
- **Monday, from `dim_date`** — chosen.

## Consequences

- A weekly metric uses `week_start_date`; none truncates a date itself.
- A change of convention changes this ADR and `dim_date`, not each consumer.

## Affected designs

- [`models/core/dim_date.md`](../design/models/core/dim_date.md)
- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
