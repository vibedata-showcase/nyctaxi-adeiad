---
kinds: [transformation]
---

# Requirement: SS · borough flow

## Ask

Leila Haddad, Mobility Planning Lead, for the city's question about how much of the city's traffic crosses borough lines:

> "The city asked how much of our traffic crosses borough lines. For each month of Q1 2024, I need the trips and the revenue from each borough to each borough, and the share of trips that leave the borough they started in."

She consumes the result as a table in the warehouse. It is a new boundary relation in `agg`, so it also owes a boundary contract and a binding in the canonical model.

## Requirements

- [ ] `R-01` One row per month, origin borough and destination borough, with no duplicates — accept when a uniqueness check over (trip_month, origin_borough, destination_borough) returns no rows — source: request
- [ ] `R-02` Every billable trip picked up inside the reporting window lands in exactly one row, whether or not its boroughs resolve — accept when `sum(trip_count)` equals the count of `fct_trip` rows with `is_billable` and a pickup inside the reporting window (95,958 for Q1 2024), and `sum(total_revenue)` equals their summed `total_amount` (2,629,185.82) — source: request, `docs/adr/0003-billable-trip-definition-and-where-it-applies.md`
- [ ] `R-03` The months are exactly January, February and March 2024, with no month outside Q1 and no period cut short — accept when the table holds those three `trip_month` values and nothing else, and each month covers its full calendar (Jan 31/31, Feb 29/29, Mar 31/31 days observed) — source: request
- [ ] `R-04` A borough the TLC does not name is never an origin or a destination: `Unknown` and `N/A` zones report as one `Unresolved` group, and `EWR` stays a borough of its own — accept when no row carries `Unknown` or `N/A` in either borough column, exactly one distinct `Unresolved` value exists, and `EWR` appears as an origin and as a destination — source: answer, `docs/adr/0018-only-tlc-named-boroughs-count-and-unresolved-zones-form-one-group.md`
- [ ] `R-05` Each row's leaving-borough share is the share of the origin borough's resolved trips in that month that end in another named borough: identical on every row of one origin borough and month, null on an `Unresolved` destination row, and equal to an independent recomputation — accept when the value matches a recompute from `fct_trip` and `dim_zone` for every origin borough and month (Manhattan 5.5545%, 5.4238%, 5.5979%; Queens 70.5492%, 72.2063%, 73.1730% for Jan–Mar) — source: answer
- [ ] `R-06` Each row also carries the pair's own share of the origin borough's resolved trips that month, and those shares sum to 1 per origin borough and month over the named-borough destinations — accept when the per-origin-month sums are 1 to within 1e-9 and the column is null exactly where the leaving share is null — source: answer
- [ ] `R-07` A borough pair with no billable trips in a month has no row, and no threshold withholds a pair that has any — accept when the table holds no zero-trip row and 104 rows for Q1 2024 (35 in January, 33 in February, 36 in March) — source: answer
- [ ] `R-08` Revenue is the canonical billable revenue: the summed total amount of the row's billable trips, with the trip count published beside it — accept when the column matches `sum(total_amount)` over the row's trips, and the count equals the number of trips carrying it — source: `logical-model/nyc_taxi_analytics.ossie.yaml` (`billable_revenue`), `docs/adr/0003-billable-trip-definition-and-where-it-applies.md`
- [ ] `R-09` The table is published as a boundary relation: an enforced dbt contract, an ODCS contract beside it, a canonical-model binding for its measures and dimensions, and descriptions that say the leaving share repeats and must not be summed — accept when `dbt` enforces the contract, `odcs.py check` and `ossie_lint.py` pass, and the design record's `## Logical Model` block names the documents actually changed — source: `repo-map.json` (`layers.agg`, `modules.contracts`), `AGENTS.md`

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain | One row per (month, origin borough, destination borough) that has billable trips; the month is the trip's pickup month | request |
| Edge periods | No period is cut short: the reporting window is 2024-01-01 to 2024-04-01 and each of the three months is fully covered by observed trip days, so no incompleteness mark is needed | repository (`transformation/dbt_project.yml`), query over `fct_trip` |
| Population | Billable trips only, inside the reporting window, per ADR 0003: "Gold marts that report revenue or flows apply it" | `docs/adr/0003-billable-trip-definition-and-where-it-applies.md` |
| Borough values | The five TLC-named NYC boroughs plus `EWR`; `Unknown` and `N/A` merge into one `Unresolved` group | answer; `docs/adr/0018-only-tlc-named-boroughs-count-and-unresolved-zones-form-one-group.md` |
| Leaving-borough share | A crossing is a trip resolved to two different named boroughs at both ends; the share's numerator and denominator both exclude any trip touching `Unresolved` | answer; `docs/adr/0018-...md` |
| Per-row share | The pair's trips over the origin borough's trips that month resolved to a named borough at both ends; null on the `Unresolved` destination row; shares sum to 1 per origin borough and month | answer |
| Minimum pair size | None: every borough pair with billable trips is published. ADR 0017's 25-trip floor is a rule about published zone-pair flows and is not applied here | answer |
| Periods with no trips | Omitted, never emitted as a zero row | answer |
| Measure coverage | `trip_count` is published beside `total_revenue`; a billable trip always carries a total, so the count is the coverage | playbook default (`transformation` Coverage) |
| NULLs in the aggregate | None reach the revenue sum: every billable trip in the window has a non-null total amount (checked: 0 nulls of 95,958) | repository (query over `fct_trip`) |
| Reuse | Built from `fct_trip` with `dim_zone` joined twice, as `agg_od_flow_matrix` is. That model is not reused: its 25-trip floor leaves 27,445 of 95,958 billable trips out, so its population cannot carry this table | `transformation/models/marts/agg/agg_od_flow_matrix.sql`, `docs/adr/0017-published-flows-have-a-25-trip-floor.md` |
| Unmatched and null keys | Every row is kept: a trip whose zone key does not resolve is reported with `Unresolved` at that end, never dropped. No trip in the window is in that state today (0 null pickup keys, 0 null dropoff keys) | playbook default (`transformation` Unmatched and null keys), `docs/adr/0015-unmatched-dimension-keys-stay-null.md` |
| Extended scope | No schedule and no new source, so no `orchestration` or `ingestion` kind. The boundary contract and the canonical-model binding are part of this change, not a separate one | playbook default (`transformation` Extended scope) |

## Out of scope

- The zone-grain `agg_od_flow_matrix` and its 25-trip floor are unchanged (ADR 0017).
- `fct_trip`, `dim_zone` and every other published model the request did not name are unchanged.
- No new source, pipeline or schedule.
- Quality reporting and the fleet-operations marts are untouched.

## Open questions

None.

## Approvals
