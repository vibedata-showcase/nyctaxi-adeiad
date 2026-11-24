---
status: decided
date: 2026-11-24
---

# A borough-level flow surface has no trip floor

The 25-trip floor in ADR 0017 is a rule about **zone-pair** flows: it keeps a 265 × 265 cross product from publishing ones and twos as routes. It does not carry to a **borough-pair** surface. A borough pair is already an aggregate of many zones, and the surface must answer a share — the trips that leave the borough they started in — whose denominator is every trip that borough generated. A floor would drop pairs from the numerator while their trips stayed in the denominator, so the published share and the published matrix would describe different populations.

The borough flow mart therefore publishes every borough pair that carries at least one billable trip in the month, and sums over it reconcile exactly to the star's billable trips by origin and destination borough (ADR 0003 population, inside the reporting window).

The trade-off is accepted rather than hidden: of roughly 40 populated pairs a month, 21 to 23 carry fewer than 25 billable trips in January through March 2024, and those rows are published anyway. They are small on a borough surface rather than noise on a zone surface, and a reader comparing two borough pairs of the same size is comparing like with like.

## Considered options

- **Apply ADR 0017's 25-trip floor per borough pair per month** — rejected: it removes about half the populated pairs each month, and a share computed over the surviving rows would no longer be the share of the borough's traffic.
- **Apply the floor per borough pair over the whole quarter** — rejected: it makes a monthly row inherit a rule settled on quarter totals, and a pair published in one month and absent in another cannot be summed across the quarter.
- **Publish every populated borough pair and state the closure** — chosen.

## Consequences

- `agg_borough_flow_monthly` carries no `HAVING` clause. Its absence is the decision, not an omission, and a floor added there needs this ADR superseded.
- A borough pair appears in a month only when it carries a billable trip that month; a month in which a pair is empty has no row, so a quarter total is the sum of the rows that exist.
- Summing the mart's trips over a month reproduces the star's billable trip count for that month exactly. That closure is a testable property and is tested.
- ADR 0017 is unchanged: `agg_od_flow_matrix` keeps its floor, and the two surfaces answer different questions and are not interchangeable.
