---
kinds: [transformation]
---

# Requirement: Zone revenue report from operations figures 3

## Ask

Ravi Menon (finance reports) asked:

> "Finance reads the daily zone revenue report every morning. Operations keeps its own daily figures by zone in the agg schema, so we pay for two builds that should give the same answers. Please build our report from the operations figures, so that there is one source. No number in our report may change. Before we accept a change, we run our usual check: for Q1 2024 the report must show 95,958 trips and 2,629,185.82 revenue in total, and 4,120 trips and 337,711.05 revenue for JFK Airport."

The consumer is the finance team's morning daily zone revenue report, served by `finance.mart_daily_zone_revenue`.

**Finding on the premise.** The daily zone figures in the `agg` schema are not the fleet operator's figures. `transformation/models/marts/agg/agg_trip_zone_daily.sql` reads `ref('fct_trip')` and `ref('dim_zone')` — the same inputs `mart_daily_zone_revenue` reads — and contains no reference to `ops_raw`, `fct_shift` or `dim_driver`. Its trips and revenue are city-wide TLC, not the simulated fleet's. The two builds already share one source; they differ by the billable rule (ADR 0003) and by five columns, so building the report from `agg` as it stands would change every number and fail Ravi's own check. Measured for Q1 2024 against the current warehouse:

| | `agg.agg_trip_zone_daily` | `finance.mart_daily_zone_revenue` |
| --- | --- | --- |
| rows (zone-days) | 7,997 | 7,961 |
| trips | 97,184 | 95,958 |
| revenue | 2,597,120.92 | 2,629,185.82 |
| JFK trips / revenue | 4,261 / 329,766.06 | 4,120 / 337,711.05 |
| columns | 14 | 11 |

The revenue gap is fully explained and is not a defect: `agg` aggregates every trip, the mart applies `is_billable`; non-billable Q1 trips total −32,064.90, and 2,597,120.92 − (−32,064.90) = 2,629,185.82. The 36 extra `agg` zone-days are days whose only trips were non-billable (37 trips, −545.10). The mart also carries `fare_revenue`, `tip_revenue`, `surcharge_revenue`, `toll_revenue` and `reporting_region`, none of which `agg` publishes. Zone names and boroughs agree on all 7,961 shared zone-days.

Asked which constraint wins, the user chose to **preserve the numbers**: keep `finance.mart_daily_zone_revenue` as the single daily zone revenue figure and stop maintaining the duplicate `agg.agg_trip_zone_daily`. This removes the second build without changing a number in the report.

## Requirements

- [ ] `R-01` Every figure in the finance report is unchanged: for Q1 2024 the report totals 95,958 trips and 2,629,185.82 revenue, and JFK Airport (`pickup_location_id` 132) shows 4,120 trips and 337,711.05 revenue — accept when a query over the built `finance.mart_daily_zone_revenue` for `trip_date >= DATE '2024-01-01' AND trip_date < DATE '2024-04-01'` returns `sum(trip_count) = 95958`, `round(sum(total_revenue), 2) = 2629185.82`, and for `pickup_location_id = 132` returns `sum(trip_count) = 4120` and `round(sum(total_revenue), 2) = 337711.05` — source: request; figures independently recomputed from `core.fct_trip` as `count(*) filter (where is_billable)` and `sum(total_amount) filter (where is_billable)` in the reporting window
- [ ] `R-02` The mart has one source and only one build produces it: `agg.agg_trip_zone_daily` is retired — its model SQL, its `_agg.yml` properties entry and its ODCS contract are removed — accept when the relation is absent from the `agg` schema after a full build and `grep` finds no `agg_trip_zone_daily` in `transformation/models/`, `contracts/` or `logical-model/` — source: user answer to the opening question
- [ ] `R-03` The surviving report keeps its published promise: `finance.mart_daily_zone_revenue` keeps its grain (one row per pickup zone and trip date), its 11 published columns with their names and types, and the billable rule it applies — accept when the built relation's column list equals the 11 names in `contracts/finance/mart_daily_zone_revenue.odcs.yaml`, a grain-uniqueness check returns no duplicate `(trip_date, pickup_location_id)` pair, and the Q1 row count is 7,961 — source: `docs/design/models/finance/mart_daily_zone_revenue.md`, [ADR 0003](../../adr/0003-billable-trip-definition-and-where-it-applies.md)
- [ ] `R-04` Removing the duplicate costs the report nothing: the mart's SQL and its properties are not edited by this intent — accept when `git diff origin/main -- transformation/models/marts/finance/mart_daily_zone_revenue.sql transformation/models/marts/finance/_finance.yml` is empty — source: request ("No number in our report may change")
- [ ] `R-05` Nothing in the project still builds on the retired relation: the two generated semantic tests that reference it are regenerated and the whole selection still passes — accept when `dbt build` over `+mart_daily_zone_revenue+` and the full data-test selection pass, and no compiled node in `target/manifest.json` has `agg_trip_zone_daily` among its `depends_on.nodes` — source: `transformation/tests/assert_semantic_content_holds.sql`, `transformation/tests/assert_semantic_levels_hold.sql`
- [ ] `R-06` The semantic layer stops binding the retired relation and loses no answer: the `LTS2_zone_day_agg` logical source is withdrawn, and its only bound metric `trip_count` still resolves through the detail source with identical values — accept when `semantic_query` for `trip_count` grouped by `trips_to_date` day and `trips_to_pickup_zone` zone under the aggregate's content filter returns the same result set as the detail source, and `ossie_lint` and the Ossie validation pass with no physical table naming `agg_trip_zone_daily` — source: `logical-model/nyc_taxi_analytics.ossie.yaml` (`LTS2_zone_day_agg`); measured before the change: 7,997 groups from each route, 0 rows differing in either direction
- [ ] `R-07` The documentation names only what still exists: the design records that list `agg_trip_zone_daily` as a dependency no longer do — accept when `grep -rn "agg_trip_zone_daily" docs/design/` returns nothing — source: `repo-map.json` maintenance rules

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Which relation survives as the single daily zone revenue figure | `finance.mart_daily_zone_revenue`; `agg.agg_trip_zone_daily` retired | user answer to the opening question |
| Grain of `finance.mart_daily_zone_revenue` | One row per pickup zone and trip date — unchanged | existing model; `docs/design/models/finance/mart_daily_zone_revenue.md` |
| Billable rule and where it applies | Adopted verbatim from ADR 0003: "A trip is **billable** when its total amount is positive… Gold marts that report revenue or flows apply it, inside the reporting window: `mart_daily_zone_revenue`, …" | `docs/adr/0003-billable-trip-definition-and-where-it-applies.md` |
| Revenue measure in the report | `sum(total_amount)` over billable trips, published as `total_revenue` — unchanged | existing model; recomputed against `core.fct_trip` for R-01 |
| Population of the report | Billable trips in the reporting window, grouped by pickup zone and day; a zone-day whose only trips are non-billable is omitted, not emitted as a zero row — unchanged | existing model (36 such zone-days exist in `agg` and are correctly absent from the mart) |
| Edge periods | Not applicable: the mart is at daily grain, not rolled up to a period, and the window is fully covered — Q1 2024 is 91 calendar days and both relations carry all 91 | measured: first trip day 2024-01-01, last 2024-03-31, 91 distinct days in each relation |
| Coverage | Not applicable: no measure is added to or removed from the mart, so no coverage count is owed beside one | playbook default, no measure change |
| Reuse | Keep the published mart and record it rather than rebuilding from a finer or coarser relation | playbook default |
| Unmatched and null keys | Not applicable: no join, filter or grouping in the surviving report changes | playbook default, no change to the mart |
| Measures that exist only in the retired relation | Seven columns are dropped with `agg_trip_zone_daily` (`total_miles`, `attributed_driver_count`, `prev_day_trip_count`, `same_day_last_week_trip_count`, `trip_count_7d_avg`, `revenue_28d_rolling`, `revenue_rank_that_day`) and no semantic metric is lost: the Ossie document binds only `trip_count` from this relation and explicitly refuses `prev_day_trip_count`, `same_day_last_week_trip_count`, `trip_count_7d_avg` and `revenue_28d_rolling`; `total_miles`, `attributed_driver_count` and `revenue_rank_that_day` have no metric declared at all, and the request does not name them | user answer; `logical-model/nyc_taxi_analytics.ossie.yaml` `LTS2_zone_day_agg` note |
| Extended scope | Not a question: no schedule is added, so `kinds:` is `transformation` alone | playbook |

## Out of scope

- Any edit to `finance.mart_daily_zone_revenue`'s SQL, properties or contract, beyond what regeneration requires. Its numbers, grain and published columns do not change.
- Adding columns to the report: the airport surcharge (pending request R3), zone-by-daypart grain (pending request R12), or rehoming the retired relation's rolling-window context. Each is a separate request.
- Any change to `core.fct_trip`, the intermediate models, `ops_raw` or the ingestion pipelines.
- The other `agg` relations, which are untouched.
- Rewriting Ravi's expected figures. They are reproduced by the current report and are the acceptance criterion.

## Open questions

- `docs/proposal/pending-requests.md` **R12** proposes retiring `finance.mart_daily_zone_revenue` itself in favour of a zone-by-daypart grain, the opposite direction to this intent. It is a proposal, not a decision, so it does not block; but if that request is accepted later it reopens this one.
- Ravi's wording assumes Operations keeps daily zone figures of its own. In this warehouse the `agg` daily figures are built from the TLC trip fact, so the fleet's own numbers (4,574 fleet-attributed Q1 trips) are nowhere in `agg`. If Operations does keep figures in a system outside this warehouse, that is a new source and a different intent; the user's answer settled this intent on the warehouse as it stands.

## Approvals
- 2026-11-25T05:59:09Z — requirement approved — "Approve and continue to design" — b5ff927
- 2026-11-25T06:06:13Z — design approved — "Approve, but stop for now" — 688cafe
