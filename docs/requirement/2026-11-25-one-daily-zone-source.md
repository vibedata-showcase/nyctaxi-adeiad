---
kinds: [transformation]
---

# Requirement: One daily zone source for the finance report

## Ask

Ravi Menon, who owns the finance reports:

> "Finance reads the daily zone revenue report every morning. Operations keeps its own daily figures by zone in the agg schema, so we pay for two builds that should give the same answers. Please build our report from the operations figures, so that there is one source. No number in our report may change. Before we accept a change, we run our usual check: for Q1 2024 the report must show 95,958 trips and 2,629,185.82 revenue in total, and 4,120 trips and 337,711.05 revenue for JFK Airport."

Two outcomes: one daily zone source instead of two, and `mart_daily_zone_revenue` still reporting exactly what it reports today.

## Requirements

- [ ] `R-01` `mart_daily_zone_revenue` reports the same numbers after the change as before it, row for row — accept when, at the same code and data, the pre-change relation and the post-change relation agree on `trip_count`, `fare_revenue`, `tip_revenue`, `surcharge_revenue`, `toll_revenue` and `total_revenue` within half a cent for every (trip_date, pickup_location_id), on `borough`, `zone_name` and `reporting_region` exactly, on the same row count, and with no key present on one side only — source: request ("No number in our report may change")
- [ ] `R-02` Finance's own acceptance check passes on the built relation — accept when `sum(trip_count) = 95,958` and `sum(total_revenue) = 2,629,185.82` over Q1 2024, and `sum(trip_count) = 4,120` and `sum(total_revenue) = 337,711.05` for `zone_name = 'JFK Airport'` — source: request (Ravi's stated check); values independently confirmed against `core.fct_trip` on 2026-11-25
- [ ] `R-03` One daily zone source remains for the figures finance reads, so the duplicate build is retired rather than duplicated again — accept when a lineage read of `mart_daily_zone_revenue` shows no path that rebuilds daily zone revenue independently of the surviving source, and the relation the work retires is removed from the dbt project, its contract and the semantic layer in the same change — source: request ("so that there is one source")
- [ ] `R-04` The surviving relation is a boundary relation that still carries an enforced dbt contract, its ODCS contract and honest column documentation after the change — accept when `dbt build` passes with `contract: enforced`, `odcs.py check`, `check --relations` and `profile` pass, and every column carries a description that matches the built SQL — source: `repo-map.json` (`layers.finance`, `artifact_paths.data_contract`)

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain of the finance report | One row per (pickup zone, trip date) — unchanged | request; `docs/design/models/finance/mart_daily_zone_revenue.md` (`## Grain`) |
| Period boundary | The project's `report_start` / `report_end` vars, 2024-01-01 to 2024-04-01 — unchanged | `transformation/dbt_project.yml`; request's Q1 2024 acceptance figures |
| Edge periods | not applicable — the window is three whole calendar months and `core.fct_trip` holds a trip on all 91 days | verified against `core.fct_trip`, 2026-11-25 |
| Billable rule in the finance report | Applies — "A billable trip is one with a positive total, applied where revenue and flows are reported", and `mart_daily_zone_revenue` is one of the marts it names. **Unchanged by this intent.** | `docs/adr/0003-billable-trip-definition-and-where-it-applies.md` |
| Billable rule in `agg_trip_zone_daily` | Does **not** apply — ADR 0003 lists `agg_trip_zone_daypart_dow`, `agg_trip_band_profile` and `mart_trip_quality_scorecard` as marts that "report billable and non-billable counts side by side instead of filtering", and `agg_trip_zone_daily` publishes `trip_count` documented as "Trips, billable or not." **Unchanged by this intent.** | `docs/adr/0003-billable-trip-definition-and-where-it-applies.md`; `transformation/models/marts/agg/_agg.yml` |
| Coverage of revenue | Publish the count of trips the revenue measure covers beside it — already published as `trip_count`, which is the billable count today because the report filters on `is_billable` | playbook default (Coverage) |
| Unmatched and null keys | Keep every row: `dim_zone` is inner-joined today, so a null zone key is dropped; that behaviour is held unchanged by `R-01` rather than revisited | `docs/adr/0015-unmatched-dimension-keys-stay-null.md`; `mart_daily_zone_revenue.sql` |
| Reuse | Which relation is "the one source" is **Open** — see open question 1 | open question 1 |
| Which relation retires | **Open** — must match the reuse answer | open question 1 |
| The five revenue columns | **Open** — `fare_revenue`, `tip_revenue`, `surcharge_revenue` and `toll_revenue` have no counterpart in `agg_trip_zone_daily` | open question 2 |
| Extended scope | not applicable — no schedule requested, so no `orchestration` kind | `_shared/playbooks/kinds/transformation.md` |

## Out of scope

- Every other published model: `agg_od_flow_matrix`, `agg_borough_flow_monthly`, `agg_trip_zone_daypart_dow`, `agg_trip_band_profile`, `agg_weather_demand_daily`, `mart_monthly_service_summary`, `mart_trip_quality_scorecard`, `fct_trip`, `dim_zone` and the ingestion pipelines stay as they are.
- ADR 0003's billable rule and its list of which marts apply it. This intent reconciles two marts to one source; it does not change which population is billable.
- The reporting window, the grain, and the definitions of the five revenue measures.
- Anything outside Q1 2024.

## Open questions

1. **The premise is false: the two builds do not give the same answers, and building finance from `agg_trip_zone_daily` would change every number.** Measured on `domain` on 2026-11-25:

   | | trips | revenue | rows |
   | --- | --- | --- | --- |
   | `finance.mart_daily_zone_revenue` | 95,958 | 2,629,185.82 | 7,961 |
   | `agg.agg_trip_zone_daily` | 97,184 | 2,597,120.92 | 7,997 |

   The 1,226-trip gap is the billable rule: ADR 0003 has finance filter on `is_billable` and has the ops aggregate publish "Trips, billable or not." Per zone-day key, 962 of 7,997 keys carry a different trip count and 36 keys exist only in `agg`. JFK alone reads 4,261 trips / 329,766.06 in `agg` against finance's 4,120 / 337,711.05 — and Ravi's own acceptance check names the second pair. So sourcing finance from `agg` fails `R-02` on the day it ships, and would fail `R-01` on every row.

   The fix Ravi is asking for and the guarantee he needs are in conflict. **Holds: the whole intent.** The options, with what each costs:
   - **Publish a billable daily zone source in `agg`, and build finance from it**, retiring the duplicate *calculation*. The ops relation that serves operations keeps its all-trips population; finance gets a billable-population sibling in the same schema. Both numbers stay true to their own definition, one definition of each lives in the code, and `R-01`/`R-02` hold. Costs: one new relation in `agg`.
   - **Add a billable filter to `agg_trip_zone_daily` and point finance at it.** One relation instead of two, but it silently changes operations' figures from 97,184 to 95,958 trips — a number outside finance's report changes, and the ops mart's own documented promise ("Trips, billable or not") would have to be broken.
   - **Build finance from `agg_trip_zone_daily` as it stands**, which Ravi literally asked for. Every number changes and his acceptance check fails. This cannot be what he wants; it is listed so the record shows it was considered and why it cannot be.
2. **Four of finance's six measures do not exist in `agg_trip_zone_daily`.** Finance publishes `fare_revenue`, `tip_revenue`, `surcharge_revenue` and `toll_revenue` beside `total_revenue`; the ops aggregate carries only `total_revenue` (and `total_miles` and `attributed_driver_count`, which finance does not publish). Q1 totals on billable trips: fare 1,802,576.08, tip 313,865.43, surcharges 481,752.42, tolls 51,368.39, total 2,629,185.82 — the components do not sum to the total, by design (`fare_residual`). Whatever becomes the single source must carry all four components, and `R-01` holds them to their current values. Holds: `R-01`, `R-03`, `R-04`.
3. **`agg_trip_zone_daily` carries five rolling/period columns that finance does not publish**: `prev_day_trip_count`, `same_day_last_week_trip_count`, `trip_count_7d_avg`, `revenue_28d_rolling` and `revenue_rank_that_day`. If it becomes a source for finance these are carried along or dropped from it; if a new billable sibling is created they are not needed. Confirm the surviving ops relation keeps them, since other consumers may read them. Holds: `R-03`.

## Approvals

<!-- Append-only, approvals only. -->
