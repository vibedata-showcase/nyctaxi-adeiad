---
kinds: [transformation]
---

# Requirement: SS · zone revenue

## Ask

Ravi Menon, who owns the finance reports, asked:

> "Finance reads the daily zone revenue report every morning. Operations keeps its own daily figures by zone in the agg schema, so we pay for two builds that should give the same answers. Please build our report from the operations figures, so that there is one source. No number in our report may change. Before we accept a change, we run our usual check: for Q1 2024 the report must show 95,958 trips and 2,629,185.82 revenue in total, and 4,120 trips and 337,711.05 revenue for JFK Airport."

Consumers: the finance team reading `finance.mart_daily_zone_revenue` every morning, and whoever reads `agg.agg_trip_zone_daily` as the operations figures.

The two relations are at the same grain — one row per pickup zone and trip date — but they do not give the same answers today. `mart_daily_zone_revenue` counts only billable trips and carries five revenue components plus `reporting_region`; `agg_trip_zone_daily` counts every trip and carries one unfiltered total. For Q1 2024 the finance report totals 95,958 trips and 2,629,185.82; the operations figures total 97,184 and 2,597,120.92, and JFK Airport 4,261 and 329,766.06 against the report's 4,120 and 337,711.05. Read as they stand, the operations figures cannot reproduce the report.

## Requirements

- [ ] `R-01` The daily zone revenue report is built from the operations figures: `mart_daily_zone_revenue` reads `agg_trip_zone_daily` and no longer reads `fct_trip` or `dim_zone` — accept when the mart's lineage names `agg_trip_zone_daily` as its only upstream relation — source: request
- [ ] `R-02` The report's Q1 2024 check figures are unchanged: 95,958 trips and 2,629,185.82 revenue in total, and 4,120 trips and 337,711.05 revenue for JFK Airport — accept when the two queries return exactly those values — source: request
- [ ] `R-03` No number in the report changes, row by row: 7,961 rows over Q1 2024, each at `(trip_date, pickup_location_id)` with identical `borough`, `zone_name`, `reporting_region`, `trip_count`, `fare_revenue`, `tip_revenue`, `surcharge_revenue`, `toll_revenue` and `total_revenue` — accept when a full-outer comparison of the rebuilt mart against the merge-base build returns 0 differing rows and 0 rows on either side — source: request; merge-base build
- [ ] `R-04` The report's published shape does not move: the same eleven columns, names and types as today — accept when `contracts/finance/mart_daily_zone_revenue.odcs.yaml` shows no added, removed or retyped property against the merge-base and the dbt contract build passes — source: request; `transformation/models/marts/finance/_finance.yml`
- [ ] `R-05` `agg_trip_zone_daily` gains the billable measures the report needs — a billable trip count, billable total revenue, and billable fare, tip, surcharge and toll revenue — and `reporting_region`, all at its existing zone-day grain — accept when the built relation carries those columns and its grain is still unique on `(pickup_date, pickup_location_id)` — source: user answer; `transformation/models/marts/agg/agg_trip_zone_daily.sql`
- [ ] `R-06` `agg_trip_zone_daily`'s existing published columns are unchanged: `trip_count`, `total_revenue`, `total_miles`, `attributed_driver_count` and the five window columns keep their values — accept when Q1 2024 totals and a row-by-row comparison against the merge-base build return no difference — source: request; `contracts/agg/agg_trip_zone_daily.odcs.yaml`
- [ ] `R-07` A zone-day with traffic but no billable trip carries `billable_trip_count` 0 and NULL in every billable revenue column — accept when no row has a NULL billable revenue column beside a non-zero billable trip count, and every such row has a positive all-trip `trip_count` — source: user answer
- [ ] `R-08` The report omits zone-days with no billable trip, as it does today (36 such zone-days in Q1 2024) — accept when the rebuilt mart holds 7,961 rows and none with a zero billable trip count — source: user answer
- [ ] `R-09` Every description, design record and contract line the change touches agrees with the built relations, including how and where the billable rule is applied — accept when no file states a rule, grain or value the built relations contradict — source: request; ADR 0003
- [ ] `R-10` The two contracts and the semantic layer still hold: `contracts/agg/agg_trip_zone_daily.odcs.yaml` and `contracts/finance/mart_daily_zone_revenue.odcs.yaml` match the built relations, and the singular semantic tests pass — accept when `odcs.py check` and the contract build pass, and `assert_semantic_content_holds` and `assert_semantic_levels_hold` return no rows — source: `contracts/`, `logical-model/nyc_taxi_analytics.ossie.yaml`

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain of `mart_daily_zone_revenue` | One row per pickup zone and trip date, unchanged | request ("no number may change"); `docs/design/models/finance/mart_daily_zone_revenue.md` |
| Grain of `agg_trip_zone_daily` | One row per pickup date and pickup location; the billable measures are added at that grain, not a finer one | existing model (`transformation/models/marts/agg/agg_trip_zone_daily.sql`) |
| Edge periods | not applicable: the report's period is the day, and the data window's first (2024-01-01) and last (2024-03-31) days each carry all 24 hours, so no period is cut short. Eight interior days carry 23 of 24 hours; that is a source gap inside a whole period, recorded as a finding, and it changes no period boundary | query over `core.fct_trip` |
| Population: billable rule | A billable trip is one with a positive total; the report keeps publishing only billable trips, and the verdict still comes from `int_trip_quality_flags` through `fct_trip.is_billable` | `docs/adr/0003-billable-trip-definition-and-where-it-applies.md` |
| Population: where the billable measures are computed | In `agg_trip_zone_daily`, as new columns beside its existing all-trip columns; the report reads them and applies no filter of its own beyond excluding zone-days with no billable trip | user answer: "No. Add new columns only. ADR 0003 stays as it is." |
| Population: what the operations aggregate supplies | Additive only — new billable columns; its existing all-trip `trip_count` and `total_revenue` keep their meaning for its other readers | user answer |
| Population: zone-days with no billable trip | Omitted from the report, so its row population stays at today's 7,961 | user answer |
| Coverage: `billable_fare_revenue` | NULL when the zone-day has no billable trip; `billable_trip_count` beside it states how many trips carry it | user answer |
| Coverage: `billable_tip_revenue` | NULL when the zone-day has no billable trip | user answer |
| Coverage: `billable_surcharge_revenue` | NULL when the zone-day has no billable trip | user answer |
| Coverage: `billable_toll_revenue` | NULL when the zone-day has no billable trip | user answer |
| Coverage: `billable_revenue` | NULL when the zone-day has no billable trip | user answer |
| Coverage: `billable_trip_count` | 0 for a zone-day with traffic but no billable trip; never null | user answer |
| Coverage: `reporting_region` | Carried on the aggregate from the zone's own row, so the report needs no second join; null only where the zone has none, which is currently no zone | user answer; query over `core.dim_zone` |
| Reuse: source of the report | Build the report on the published `agg_trip_zone_daily` rather than on `fct_trip`, which is the point of the ask; `dim_zone` stops being read by the mart because the aggregate already carries the zone attributes as of the trip | request |
| Unmatched and null keys | Keep every row: the aggregate's 262 pickup locations all resolve in `dim_zone`, every in-window trip resolves to a zone row, and the report's 261 zones are unchanged — no zone-day is dropped or relabelled | query over `core.fct_trip`, `core.dim_zone` |
| ADR 0003 | Stays as it is; no ADR text changes. The new columns are additive, and the report's published population is still billable trips only | user answer |
| Extended scope | Not a question: no schedule is added, so `kinds:` stays `transformation` alone | playbook |

## Out of scope

- The operations report itself and every other `agg` model: `agg_trip_zone_daypart_dow`, `agg_od_flow_matrix`, `agg_trip_band_profile`, the driver, vehicle, garage and weather aggregates. No published column of theirs changes.
- `fct_trip`, `dim_zone`, `int_*` and the staging layer: unchanged.
- The other two revenue marts, `mart_monthly_service_summary` and `mart_revenue_component_bridge`: unchanged.
- The ingestion pipelines and the simulated `ops_raw` source: unchanged. The "operations figures" of the request are `agg.agg_trip_zone_daily`, not `ops_raw`.
- Editing ADR 0003.
- The eight interior days that carry 23 of 24 hours, and the missing hour's cause.

## Open questions

None.

## Approvals

- 2026-11-24T17:42:54Z — requirement approved — "Approve and stop" — aec0fda
