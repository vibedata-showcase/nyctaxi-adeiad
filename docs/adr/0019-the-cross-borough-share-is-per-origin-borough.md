---
status: decided
date: 2026-11-24
---

# The cross-borough share is measured per origin borough, not for the network

"Share of trips that leave the borough they started in" is reported **per origin borough and period**: the billable trips picked up in that borough and set down in a different one, divided by all billable trips picked up in that borough. The borough flow mart carries it once per origin borough per month, on every row of that borough's matrix rows, so the denominator is visible beside each numerator.

The network figure is a different measure and is not what this surface publishes. In January 2024 the two differ by more than a factor of two: Manhattan sends 6.0% of its trips outside its own boundary while Queens sends 71.5%, and the city-wide figure of 12.8% describes neither borough. A single network number would be dominated by Manhattan's volume and would answer "how much of the city's traffic crosses a line" rather than the question asked.

The grouping follows the zone dimension's own borough attribute, so an unresolved borough (`Unknown`, `N/A`) is an origin like any other and its trips are counted, per ADR 0012. A trip whose destination borough is unresolved counts as leaving the origin borough, because it did not stay inside it.

## Considered options

- **One network-wide share per month** — rejected: it averages boroughs of wildly different size into a number that describes no borough and hides the ones whose traffic mostly leaves.
- **Both a per-origin share and a network share** — rejected: two denominators under one name invite a reader to compare or add them, and the network figure is a one-line query over this mart when somebody wants it.
- **Per origin borough, carried on every one of its rows** — chosen.

## Consequences

- The share is not additive across origin boroughs: a borough's share applies to that borough, and summing the column means nothing.
- A reader who wants the network figure aggregates the mart's trips and crossing trips themselves, and gets a different, clearly-labelled number.
- The share is computed from the same rows as the matrix, so it can never disagree with the trips and revenue published beside it.
- A change to how boroughs are assigned changes this measure, and it is a decision to record rather than a filter to add quietly.
