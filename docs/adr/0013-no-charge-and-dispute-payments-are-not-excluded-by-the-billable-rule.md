---
status: decided
date: 2026-10-14
---

# No-charge and dispute payments are not excluded by the billable rule; each metric decides

The billable rule (ADR 0003) looks only at the total amount, so a no-charge or disputed trip with a positive total is billable. Whether a given metric counts such a trip is that metric's decision, made through the payment method master: `counts_as_revenue` is false for no charge, dispute, unknown and voided, and `tip_is_captured` is false for them. Billable revenue therefore includes them, and recognised shift revenue does not.

## Considered options

- **Exclude them in the billable rule** — rejected: it would make the rule depend on the payment method and change every count that uses it.
- **A separate rule in each mart** — rejected: the definitions would drift apart.
- **Leave the rule on the total, let metrics read the payment method flags** — chosen.

## Consequences

- A metric states whether it counts these payments.
- The tip rate is null for them (ADR 0011).

## Affected designs

- [`models/core/fct_trip.md`](../design/models/core/fct_trip.md)
- [`models/intermediate/int_trip_quality_flags.md`](../design/models/intermediate/int_trip_quality_flags.md)
- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
