---
kinds: [transformation]
---

# Requirement: Zone revenue report from operations figures 2

## Ask

Ravi Menon, who owns the finance reports, asked:

> "Finance reads the daily zone revenue report every morning. Operations keeps its own daily figures by zone in the agg schema, so we pay for two builds that should give the same answers. Please build our report from the operations figures, so that there is one source. No number in our report may change. Before we accept a change, we run our usual check: for Q1 2024 the report must show 95,958 trips and 2,629,185.82 revenue in total, and 4,120 trips and 337,711.05 revenue for JFK Airport."

The consumer is the finance team reading `finance.mart_daily_zone_revenue` every morning.

The two builds do not give the same answers today, and the difference is the billable rule (ADR 0003). Measured on `domain` for Q1 2024:

| Relation | rows | trips | revenue |
| --- | --- | --- | --- |
| `finance.mart_daily_zone_revenue` | 7,961 | 95,958 | 2,629,185.82 |
| `agg.agg_trip_zone_daily` | 7,997 | 97,184 | 2,597,120.92 |

`agg_trip_zone_daily` counts every trip and sums every total, so it carries 1,226 non-billable trips and a net −32,064.90 of non-billable revenue, plus 36 zone-days whose trips are all non-billable. The report therefore cannot read the operations figures as they stand: an aggregate over whole totals cannot have the rule subtracted downstream. Restricting the same aggregation to billable trips reproduces the report exactly — 7,961 rows, zero difference on all five measures — which is what makes the requested change provable.

## Requirements

- [ ] `R-01` The daily zone revenue report is built from the operations daily zone figures, and no longer aggregates `fct_trip` itself — accept when the built manifest shows `agg_trip_zone_daily` as the model's only direct model dependency, `dbt ls --select mart_daily_zone_revenue+1 --resource-type model` lists no relation but it, and its SQL applies no join back to `fct_trip` or `dim_zone` — source: request
- [ ] `R-02` The operations daily zone figures carry everything the report needs, with the billable population computed where the rows are counted: billable trip count, billable total revenue and the billable fare, tip, surcharge and toll components, and the zone attributes the report publishes, including the reporting region — accept when `agg_trip_zone_daily` exposes those, its existing columns keep their names, types, grain and values, and the report needs no other relation to produce its eleven columns — source: answer (ADR 0018)
- [ ] `R-03` Q1 2024 totals for the whole report are exactly 95,958 trips and 2,629,185.82 revenue — accept when `select sum(trip_count), sum(total_revenue) from finance.mart_daily_zone_revenue where trip_date >= '2024-01-01' and trip_date < '2024-04-01'` returns those two figures — source: request
- [ ] `R-04` Q1 2024 figures for JFK Airport are exactly 4,120 trips and 337,711.05 revenue — accept when the same query restricted to `zone_name = 'JFK Airport'` returns those two figures — source: request
- [ ] `R-05` No cell of the report changes: every row and every value it publishes today survives the rebuild unchanged — accept when a full outer join of the rebuilt relation against the current relation on `(trip_date, pickup_location_id)` returns no differing row count, no unmatched row on either side and no value difference on any of the eleven columns — source: request
- [ ] `R-06` The report's published shape is unchanged: same name, schema, grain and eleven columns with the same names and types — accept when a structural diff of the built relation against the current one is empty and the enforced contract still validates — source: request
- [ ] `R-07` The `trip_count` description in the report properties matches what the relation publishes — it says "Trips, billable or not", but the model filters `is_billable`, so the column is the billable count; accept when the description states the billable population and every number in it agrees with the built relation — source: `transformation/models/marts/finance/_finance.yml`, finding

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain of `mart_daily_zone_revenue` | One row per pickup zone and trip date | `docs/design/models/finance/mart_daily_zone_revenue.md` |
| Grain of `agg_trip_zone_daily` | One row per pickup zone and trip date; unchanged by this intent | `transformation/models/marts/agg/agg_trip_zone_daily.sql` |
| Edge periods | not applicable: the report is at day grain with no rollup to a longer period, and the window's first and last days are full days in the data (2024-01-01 00:05:25 to 2024-03-31 23:56:17; 91 of 91 days present) | query on `core.fct_trip` |
| Where the billable rule is applied | In `agg_trip_zone_daily`, on the billable measures it gains; `mart_daily_zone_revenue` applies no rule of its own and inherits the verdict. Amends the report design record's `D-01` | answer; [ADR 0018](../../adr/0018-the-billable-rule-moves-into-the-operations-daily-zone-aggregate.md) |
| Zone-days whose trips are all non-billable | Omitted from the report, as today; the operations aggregate keeps them. Keeps the report at 7,961 rows for Q1 with no total changing | answer |
| NULLs in the revenue measures | No trip in the window has a null fare, tip, toll, surcharge or total, so plain `sum()` and a coalesced sum are the same number; the billable measures use the same aggregation the report uses today | query on `core.fct_trip` |
| Coverage beside the billable revenue | `trip_count` is published beside `total_revenue`, as today, so the reader always sees the population the revenue covers | playbook default; existing report shape |
| Reuse | Build on `agg_trip_zone_daily`, which already serves this exact grain; do not rebuild the report from upstream layers and do not rewrite a published model the request did not name | request; playbook default |
| Unmatched and null keys | Keep every row. No trip in the window has a missing or unresolvable pickup zone, and all versions of a zone agree on name, borough and reporting region, so no join in the rebuild may drop, duplicate or relabel a row | query on `core.fct_trip`, `core.dim_zone` |
| Extended scope | Not a question: `logical-model/` and `contracts/` deliverables stay in this intent, because both describe boundary relations this change touches | playbook |

## Out of scope

- The report's name, schema and published columns: it keeps `finance.mart_daily_zone_revenue` and its eleven columns so that its consumers — the Ossie document's `LTS7_daily_zone_revenue` binding and its ODCS contract — keep resolving.
- Any number in any other mart. `mart_monthly_service_summary`, `mart_revenue_component_bridge`, `mart_driver_scorecard`, `mart_vehicle_utilisation` and `mart_trip_quality_scorecard` are not read or rebuilt by this intent.
- The values `agg_trip_zone_daily` publishes today, including its rolling and lag columns. New columns are additive; nothing existing changes.
- The reporting window (`report_start`, `report_end`) and the definition of a billable trip.
- The TLC, operations and master-data ingestion; no pipeline, source or schedule changes.

## Open questions

None. Both branches that could change a row count or a value were answered: the billable rule's location (ADR 0018) and the treatment of zone-days with no billable trip (omitted).

## Approvals

<!-- Append-only, approvals only. -->
- 2026-11-25T05:34:13Z — requirement approved — "Approve and continue to design" — ab1ea8a
- 2026-11-25T05:39:44Z — design approved — "Approve and continue to planning" — 792fa36
