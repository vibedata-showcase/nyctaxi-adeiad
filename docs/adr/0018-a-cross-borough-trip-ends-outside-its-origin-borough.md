---
status: decided
date: 2026-11-25
---

# A cross-borough trip is one that ends outside the borough it started in

A trip crosses a borough line when its destination borough differs from its pickup borough, compared as plain equality on the borough values `dim_zone` carries. Nothing is remapped, dropped or weighted, and the unresolved boroughs are not special-cased out.

Two consequences follow, and both were answered by the Mobility Planning Lead rather than derived from the data:

- **An unresolved borough is a borough on the same axis.** A trip that ends in `Unknown` or `N/A` counts as having left its origin borough. This follows ADR 0012: those zones are real zones that a borough rollup reports as their own group, and a trip that leaves Manhattan for a zone TLC could not place did leave Manhattan. Excluding such trips from both the numerator and the denominator would answer a different question — about trips whose geography is fully known — without saying so.
- **EWR is a borough.** It is not one of the five NYC boroughs, but `dim_zone` carries it as a borough value and a trip between Queens and EWR crosses a borough line in the same sense as one between Queens and Brooklyn.

## Considered options

- **Require both ends to resolve, and restrict the axis to the five NYC boroughs** — rejected: the resulting rate describes only the fully resolved population, and a reader cannot tell it apart from the whole.
- **Count unresolved destinations in the denominator only** — rejected: the rate then understates crossing while the rest of the population is unaccounted for in it.
- **One axis of every borough value the zone dimension carries, unresolved groups and EWR included** — chosen.

## Consequences

- Any mart reporting a cross-borough rate uses this definition, so rates in different surfaces agree.
- A consumer wanting only the resolved NYC boroughs filters on the zone dimension's own flags (`is_unresolved_zone`, `is_nyc`); the mart does not pre-filter for it, and its totals therefore include unresolved and non-NYC boroughs.
- A trip whose pickup or dropoff finds no zone row keeps a null zone key (ADR 0015) and cannot be placed on the axis; it is outside any borough rate.

## Affected designs

- [`models/agg/agg_borough_flow_monthly.md`](../design/models/agg/agg_borough_flow_monthly.md)
