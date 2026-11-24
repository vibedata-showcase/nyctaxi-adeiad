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
- [ ] `R-02` Every billable trip picked up inside the reporting window lands in exactly one row, whether or not its boroughs resolve, and the unresolved group stays inside the totals — accept when `sum(trip_count)` and `sum(total_revenue)` over the whole table equal the canonical `billable_trip_count` and `billable_revenue` from the semantic model for the same window (95,958 trips and 2,629,185.82 for Q1 2024, and 29,985 / 30,017 / 35,956 and 816,057.76 / 813,885.68 / 999,242.38 by month), with the 1,000 trips that touch `Unresolved` among them — source: request, user answer 2026-11-24, `docs/adr/0003-billable-trip-definition-and-where-it-applies.md`
- [ ] `R-02b` No quality verdict removes a trip from the table — accept when the model reads no column of `dim_trip_quality`, so the totals above still hold with the 2,421 billable trips carrying a physical verdict and the 11,266 carrying any verdict included — source: user answer 2026-11-24, `docs/adr/0004-quality-verdicts-flag-trips-and-never-delete-them.md`
- [ ] `R-03` The months are exactly January, February and March 2024, with no month outside Q1 and no period cut short — accept when the table holds those three `trip_month` values and nothing else, and each month covers its full calendar (Jan 31/31, Feb 29/29, Mar 31/31 days observed) — source: request
- [ ] `R-04` A borough the TLC does not name is never an origin or a destination: `Unknown` and `N/A` zones report as one `Unresolved` group, and `EWR` stays a borough of its own — accept when no row carries `Unknown` or `N/A` in either borough column, exactly one distinct `Unresolved` value exists, and `EWR` appears as an origin and as a destination — source: answer, `docs/adr/0018-only-tlc-named-boroughs-count-and-unresolved-zones-form-one-group.md`
- [ ] `R-05` Each row's leaving-borough share is the share of the origin borough's resolved trips in that month that end in another named borough: identical on every row of one origin borough and month, the `Unresolved` destination row included, and equal to an independent recomputation — accept when the value matches a recompute from `fct_trip` and `dim_zone` for every origin borough and month (Manhattan 5.5545%, 5.4238%, 5.5979%; Queens 70.5492%, 72.2063%, 73.1730% for Jan–Mar) and is null only where the origin borough has no resolved trip — source: answer
- [ ] `R-06` Each row also carries the pair's own share of the origin borough's resolved trips that month, null on a row whose destination is `Unresolved`, and those shares sum to 1 per origin borough and month over the named-borough destinations — accept when the per-origin-month sums are 1 to within 1e-9, the column is null exactly on the `Unresolved` destination rows, and the non-null shares recompute from `fct_trip` and `dim_zone` — source: answer
- [ ] `R-07` A borough pair with no billable trips in a month has no row, and no threshold withholds a pair that has any — accept when the table holds no zero-trip row and 104 rows for Q1 2024 (35 in January, 33 in February, 36 in March) — source: answer
- [ ] `R-08` Revenue is the canonical billable revenue: the summed total amount of the row's billable trips, with the trip count published beside it — accept when the column matches `sum(total_amount)` over the row's trips, and the count equals the number of trips carrying it — source: `logical-model/nyc_taxi_analytics.ossie.yaml` (`billable_revenue`), `docs/adr/0003-billable-trip-definition-and-where-it-applies.md`
- [ ] `R-09` The table is published as a boundary relation: an enforced dbt contract, an ODCS contract beside it, and a recorded exclusion from the semantic layer that states the reason, with descriptions that say the leaving share repeats and must not be summed — accept when `dbt` enforces the contract, `odcs.py check` and `ossie_lint.py` pass, the repo map's `semantic_exclusions` names the relation with its reason, and the design record's `## Logical Model` block names the documents actually changed — source: `repo-map.json` (`layers.agg`, `modules.contracts`), `AGENTS.md`; amended by the user's answer at the design stop of 2026-11-24, which chose a recorded exclusion over a canonical-model binding

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain | One row per (month, origin borough, destination borough) that has billable trips; the month is the trip's pickup month | request |
| Edge periods | No period is cut short: the reporting window is 2024-01-01 to 2024-04-01 and each of the three months is fully covered by observed trip days, so no incompleteness mark is needed | repository (`transformation/dbt_project.yml`), query over `fct_trip` |
| Population | Billable trips only, inside the reporting window, per ADR 0003: "Gold marts that report revenue or flows apply it" | `docs/adr/0003-billable-trip-definition-and-where-it-applies.md` |
| Quality verdicts | None filter a trip out: a verdict flags a trip and the consumer decides, per ADR 0004. Only `is_billable` and the reporting window narrow the population; the refund verdict needs no filter because it coincides exactly with `not is_billable` | user answer 2026-11-24, `docs/adr/0004-quality-verdicts-flag-trips-and-never-delete-them.md` |
| Unresolved group in the totals | Inside them: every billable trip reaches a row, so the table's totals equal the canonical `billable_trip_count` and `billable_revenue`; the group is outside the shares, never outside the totals | user answer 2026-11-24, `docs/adr/0012-unresolved-zones-are-retained-and-flagged.md` |
| Borough values | The five TLC-named NYC boroughs plus `EWR`; `Unknown` and `N/A` merge into one `Unresolved` group | answer; `docs/adr/0018-only-tlc-named-boroughs-count-and-unresolved-zones-form-one-group.md` |
| Leaving-borough share | A crossing is a trip resolved to two different named boroughs at both ends; the share's numerator and denominator both exclude any trip touching `Unresolved`, and the value repeats on every row of that origin borough and month, the `Unresolved` destination row included | answer; `docs/adr/0018-...md` |
| Per-row share | The pair's trips over the origin borough's trips that month resolved to a named borough at both ends; null on the `Unresolved` destination row, whose trips are outside that denominator; shares sum to 1 per origin borough and month over the named-borough destinations | answer |
| Minimum pair size | None: every borough pair with billable trips is published. ADR 0017's 25-trip floor is a rule about published zone-pair flows and is not applied here | answer |
| Periods with no trips | Omitted, never emitted as a zero row | answer |
| Measure coverage | `trip_count` is published beside `total_revenue`; a billable trip always carries a total, so the count is the coverage | playbook default (`transformation` Coverage) |
| NULLs in the aggregate | None reach the revenue sum: every billable trip in the window has a non-null total amount (checked: 0 nulls of 95,958) | repository (query over `fct_trip`) |
| Reuse | Built from `fct_trip` with `dim_zone` joined twice, as `agg_od_flow_matrix` is. That model is not reused: its 25-trip floor leaves 27,445 of 95,958 billable trips out, so its population cannot carry this table | `transformation/models/marts/agg/agg_od_flow_matrix.sql`, `docs/adr/0017-published-flows-have-a-25-trip-floor.md` |
| ADRs applied and where | ADR 0003 (billable), ADR 0004 (no verdict filter), ADR 0012 (unresolved kept), ADR 0017 (not applied, zone-pair floor), ADR 0018 (named boroughs, one unresolved group), ADR 0019 (ratio of sums; supersedes 0016), each with the line of the model it lands on: the design record's `## Decisions applied from the Domain's ADRs` | design record `docs/design/models/agg/agg_borough_flow_monthly.md` |
| Unmatched and null keys | Every row is kept: a trip whose zone key does not resolve is reported with `Unresolved` at that end, never dropped. No trip in the window is in that state today (0 null pickup keys, 0 null dropoff keys) | playbook default (`transformation` Unmatched and null keys), `docs/adr/0015-unmatched-dimension-keys-stay-null.md` |
| Extended scope | No schedule and no new source, so no `orchestration` or `ingestion` kind. The boundary contract and the ODCS contract are part of this change, not a separate one | playbook default (`transformation` Extended scope) |
| Schema of `transformation/models/marts/agg/` | `agg`, the folder's current `+schema` | user answer (schema question, design stop 2026-11-24) |
| Semantic-layer routing | Excluded from the canonical model and recorded in the repo map's `semantic_exclusions`, because its merged `Unresolved` group is no member of the zone dimension's borough level and no honest aggregate binding can name its population | user answer (design stop 2026-11-24); `docs/adr/0018-only-tlc-named-boroughs-count-and-unresolved-zones-form-one-group.md` |

## Out of scope

- The zone-grain `agg_od_flow_matrix` and its 25-trip floor are unchanged (ADR 0017).
- `fct_trip`, `dim_zone` and every other published model the request did not name are unchanged.
- No new source, pipeline or schedule.
- Quality reporting and the fleet-operations marts are untouched.

## Open questions

None.

## Approvals
- 2026-11-24T16:19:31Z — requirement approved — "Approve, but stop here" — 4e52c16
- 2026-11-24T16:39:01Z — design approved — "Please write the design records and the Plan. Stop when the Plan is written. Do not start the build yet." — 21e6c93
- 2026-11-24T16:53:30Z — design approved — "Unknown and N/A are not boroughs (ADR 0012). Keep their trips in their own unresolved group, outside the share, and keep them in the totals. EWR is a borough: keep its trips. The totals must equal billable revenue. Also show where ADR 0016 and ADR 0004 apply. [+ widen: ADR 0019 supersedes 0016]" — f7dbd7d
