---
kinds: [fix]
---

# Case: The revenue walk counts the airport fee twice

**Anchor:** `finance.mart_revenue_component_bridge` — the fare-to-total revenue walk.
**Symptom:** for Q1 2024 the walk's nine `component_amount` lines sum to `2,641,448.07`, while billable revenue is `2,629,185.82`; the walk overshoots by `12,262.25`, exactly the airport fee.
**Window:** the three-month load, pickups `[2024-01-01, 2024-04-01)`, built from `1184020`.
**Entry:** stated defect, handed off from the reconciliation intent `4e8111a9-429b-46f3-84a8-abc6d17ae841`, which confirmed the mechanism on the Domain read-only.
**Category:** `data-quality`.

## Root-cause analysis

**Blast radius.**

- `core.fct_trip.fare_residual` — the published column. Its values change on every
  trip that pays the fee: `5,942` of the `95,958` billable in-window trips move to a
  balanced total, and the column's Q1 billable sum moves from `−20,376.50` to
  `−32,638.75`. [`sql-probe`]
- `finance.mart_revenue_component_bridge` — `c_residual` and therefore the walk's
  balance: the walk total moves `2,641,448.07` → `2,629,185.82`, and `c_residual`
  moves `−20,376.50` → `−32,638.75`. Nine of its 44 groups stop being out of
  balance by the airport fee. [`sql-probe`]
- `ops.mart_trip_quality_scorecard.unbalanced_total_count` — `31,869` in-window
  trips carry `|fare_residual| > 0.01` today, `26,457` after; `5,942` trips are
  reclassified from unbalanced to balanced. [`sql-probe`]
- The semantic-layer metric `fare_residual_total` (`SUM(trips.fare_residual)`)
  returns a smaller number over the same population. Its expression and
  description do not change. [`code-inspection`]
- Not affected: the other seven models that read `fct_trip`
  (`agg_od_flow_matrix`, `agg_trip_band_profile`, `agg_trip_zone_daily`,
  `agg_trip_zone_daypart_dow`, `agg_weather_demand_daily`,
  `mart_daily_zone_revenue`, `mart_monthly_service_summary`) read other columns.
  No declared external consumer exists on any of the three relations.
  [`code-inspection`, `manifest` via `describe_asset` → `consumers: []`]
- Operationally: `core.fct_trip` is incremental, so the corrected values reach
  existing rows only through a full refresh. Without one the walk would sum old
  and new residuals together — a worse state than today. [`provenance`]

**Root cause.**

1. `fare_residual` is defined as the total minus fare, tip, tolls and
   `total_surcharges`, and `total_surcharges` sums `extra`, `mta_tax`,
   `improvement_surcharge` and `congestion_surcharge`. `airport_fee` is in
   neither list. [`code-inspection`: `transformation/macros/finance.sql`]
2. The same warehouse models `airport_fee` everywhere else: it is its own column
   on `int_trip_fare_components` and on `fct_trip`, and its own line
   `c_airport_fee` in the bridge's unpivot, which sums
   `coalesce(f.airport_fee, 0)` separately from `sum(f.fare_residual)`.
   [`code-inspection`: `int_trip_fare_components.sql`,
   `mart_revenue_component_bridge.sql`]
3. So the fee is subtracted from nothing (inside the residual) and added on its
   own line at once: the walk sums to `total_amount + airport_fee`, and the
   difference from billable revenue is the fee, not a rounding artefact.
   [`sql-probe`: the group-level query in the Verification returns `12,262.25`
   of gap, and the same query against the corrected residual returns `0.0`]
4. The residual predates the fee being populated. `airport_fee` began joining on
   yellow trips only when `18b2e55` fixed the extras key (case
   `2026-10-14-airport-fee-rejoin-matches-nothing`); the fare arithmetic was
   written against a component list that had no fee to subtract, and nothing
   re-derived it afterwards. [`provenance`: that case record; `git log` cannot
   pin the date here — the clone is grafted to one commit]
5. Nothing failed, because no test relates the residual's component list to the
   unpivot's. Every build and every test is green with the walk out of balance;
   the only place the walk's balance was asserted was a person summing the
   lines. [`code-inspection`: `transformation/tests/` holds no test naming
   `fare_residual`, `component_amount` or the bridge]
6. `CONTEXT.md` defines a fare residual as "what is left of a trip's total after
   every modelled fare component", and the Ossie field and metric say "minus
   every modelled fare component". The airport fee is modelled, so the vocabulary
   was already right and the code was wrong. [`provenance`: `CONTEXT.md` L31,
   `logical-model/nyc_taxi_analytics.ossie.yaml` L147, L815]
7. One document agreed with the bug: the `fare_residual` doc block enumerated
   "fare, tip, tolls, extra, MTA tax, improvement surcharge and congestion
   surcharge" and omitted the fee, contradicting `CONTEXT.md` and the Ossie
   field. It is part of the fix. [`provenance`:
   `transformation/models/docs.md` L21]

**Confidence.** High. The mechanism is arithmetic, confirmed independently by the
per-group identity (the gap equals the group's airport fee), by the aggregate
(`12,262.25` = `SUM(airport_fee)`), and by the corrected expression balancing all
44 groups to `0.0` with no trip lost to the zone join (`95,958 = 95,958`).
Not checked: no dbt run history exists for the Domain warehouse (`describe_run`
returns one dlt audit run and no dbt artifact), so "the build was green" rests on
the models and tests as authored rather than on a run record; and no consumer
outside this repository is known to read either relation.

**Checks run.**

| Check | Outcome |
| --- | --- |
| Walk total against billable revenue and the airport fee | `2,641,448.07` vs `2,629,185.82`, gap `12,262.25` = `SUM(airport_fee)`: confirms |
| Group-level walk balance today, and with the fee subtracted in the residual | `9` of `44` groups out by `12,262.25` today; `0` of `44` out, worst gap `0.0`, under the fix: confirms |
| Billable trips before and after the zone join | `95,958` = `95,958`, no null zone: the walk covers billable revenue exactly |
| `mart_trip_quality_scorecard` counts before and after | `31,869` → `26,457`, `5,942` explained by the fee alone: the scorecard moves as predicted |
| What the residual still holds after the fix | `−32,648.75` concentrated on `±2.50`; `ehail_fee` is `0.00` everywhere: a different component, not the fee |

**Decision.** `code-change`. Class: failing or missing dbt test. Sandbox
verification: re-run the affected models and tests.

- Subtract the airport fee inside the `fare_residual` macro, so the residual and
  the walk share one component list and the walk balances to `total_amount`.
- Correct the `fare_residual` doc in `transformation/models/docs.md`, whose
  component list omitted the fee and so described the defect.
- Add the test that fails today and passes after: every group's nine
  `component_amount` lines sum to its `total_amount`.

Data-loss check: the fix adds no filter, no deduplication and no
`ROW_NUMBER()`, and changes no grain — it changes the value of one computed
column. ADR check: consistent with [ADR 0003](../../docs/adr/0003-billable-trip-definition-and-where-it-applies.md)
(which trips the walk counts, unchanged) and restores the definition `CONTEXT.md`
and the Ossie document already state; no ADR is contradicted or superseded.

**Found, not fixed** — put to the user at the design stop and kept out of this
case on their answer: (a) the green `2024-02` `N/A`-borough group carries 8
component lines because `sum(congestion_surcharge)` is NULL there and the unpivot
drops the row; (b) the `±2.50` residual that survives the fix, `26,457` trips, is
a second signal that some totals do not equal their modelled parts. Both are
carried in `## Open questions` below.

## Open questions

- **(a)** The walk emits no line for a component whose aggregate is NULL, so a
  group can carry eight rows where nine are expected. Recorded as behaviour in
  [`models/finance/mart_revenue_component_bridge.md`](../design/models/finance/mart_revenue_component_bridge.md)
  `D-02`; left unfixed by this case (user answer, 2026-11-24). Reopen when a
  consumer needs all nine names present.
- **(b)** A `±2.50` residual (with a tail of `±1.00`–`±4.50`) survives the fix on
  `26,457` in-window trips and totals `−32,648.75`; `ehail_fee` is `0.00`
  everywhere, so it is a component value that disagrees with the total rather
  than an unmodelled column. Left unfixed by this case (user answer,
  2026-11-24). Reopen as its own case.

## Approvals
- 2026-11-24T08:08:36Z — design approved — "approve" — 38cb9f7
- 2026-11-24T08:08:36Z — breaking contract approved — core.fct_trip 2.0.0: fare_residual keeps its name and DOUBLE type, and its value becomes the total minus every modelled component including the airport fee; the corrected value reaches existing rows only through a full refresh of the fact, and "abort" was offered first with a dual-write cutover beside it — 38cb9f7
- 2026-11-24T09:15:30Z — ship approved — "approved" — cae9846
