---
status: decided
date: 2026-11-25
---

# The crossing share divides all of a borough's crossing trips by all of its billable departures

The borough-to-borough surface publishes, beside its floored pairs, the share of a borough's traffic that leaves the borough it started in. Both sides of that ratio come from the full billable population of the origin borough-month, not from the published pairs: the denominator is every billable trip departing the borough in that month, the numerator every one of those trips whose destination borough differs from its origin borough, whether or not its pair clears ADR 0018's floor. The Mobility Planning Lead set this on the question the city asked — how much traffic crosses borough lines — which is a fact about the borough's traffic, not about the rows the floor happens to publish. A numerator restricted to published pairs would understate every borough: the Bronx's January share reads 49.4% that way against 59.3% over all its traffic, and EWR, N/A and Staten Island clear no pair at all in January, so their share would have no row to sit on.

Because the ratio is wider than the pairs, the surface publishes it on a row of its own grain: every origin borough-month carries a row, including the 9 borough-months where no pair clears the floor, and those rows carry a zero trip and revenue total with a real share. The share is therefore never a summary of the pair rows beside it, and a consumer who wants the published total sums the pair rows rather than dividing the share out.

## Considered options

- **Share over the published pairs only** (numerator and denominator both floored) — rejected: it answers how much of the published traffic crosses, which is not the question, and it reads as a finding about a small borough rather than about the floor.
- **Share over all traffic with the numerator floored to published pairs** — rejected: the two sides then describe different populations, and the ratio systematically understates crossing.
- **Publish no share, let the consumer derive it** — rejected: every consumer would choose one of the three above, and the city's question would get three answers.
- **Both sides over the full billable population, the share carried on every origin borough-month** — chosen.

## Consequences

- The share does not reconcile with the pair rows: over Q1 2024 the numerators sum to 12,214 crossing trips while the published crossing pairs carry 12,023, and the denominators sum to 95,958 against the pairs' 95,705.
- A borough-month with no published pair is a row with a share and no pairs; a consumer filtering to pairs must not read its zero total as missing data.
- The share is a ratio of counts, rebuilt through `safe_divide` so a zero denominator gives null rather than zero (ADR 0016).
- Changing the floor (ADR 0018) does not move the share; changing the billable rule or the reporting window moves both.
