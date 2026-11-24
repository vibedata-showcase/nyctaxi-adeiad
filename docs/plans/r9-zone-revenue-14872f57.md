# Plan: R9 · zone revenue

**Goal:** Move the finance daily zone revenue report onto the single zone-day aggregate, so the grouping is computed once and every published number stays where it is.

**Requirement:** `docs/requirement/2026-11-24-r9-zone-revenue-14872f57.md`

**Constraints:**
- The report's population is every billable trip of both fleets inside the reporting window; a zone-day with no billable trip stays out (`ADR 0018`).
- Billable means `total_amount > 0`, applied in gold and never in silver (`ADR 0003`, and `D-02` of the report record for the superseded wording).
- The reporting window is the `report_start`/`report_end` dbt vars (`2024-01-01` to `2024-04-01`), never a sampling control.
- The report's published shape is frozen: eleven columns, their types, one row per pickup zone and trip date, key `(trip_date, pickup_location_id)`.
- The aggregate's change is additive: every existing column keeps its definition and its value, and the window columns keep their all-trip inputs.
- New measures carry the `billable_` prefix, so no metric name means two populations.
- Zone attributes are joined as of the pickup date on the zone's natural key with a half-open interval, never on the natural key alone (`ADR 0009`).
- Schemas: `transformation/models/marts/agg` → `agg`, `transformation/models/marts/finance` → `finance` (both defaults, user answer).
- Money is compared at the cent (`round(x, 2)`), never bit for bit, and other measures with an explicit tolerance.
- Domain data is read-only; every build and write lands in the Intent's sandbox only.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `contracts/agg/agg_trip_zone_daily.odcs.yaml` | contract | modify | `R-01`, `R-02`, `R-05` | `docs/design/models/agg/agg_trip_zone_daily.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `agg_trip_zone_daily` | model | modify | `R-01`, `R-02`, `R-05` | `docs/design/models/agg/agg_trip_zone_daily.md` | `cd transformation && dbt build --select agg_trip_zone_daily --exclude test_type:unit` |
| `logical-model/nyc_taxi_analytics.ossie.yaml` | logical-model | modify | `R-06` | `docs/design/models/agg/agg_trip_zone_daily.md` | `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/` |
| `mart_daily_zone_revenue` | model | modify | `R-01`, `R-02`, `R-03`, `R-04` | `docs/design/models/finance/mart_daily_zone_revenue.md` | `cd transformation && dbt build --select mart_daily_zone_revenue --exclude test_type:unit` |

**Change impact:** `agg_trip_zone_daily+` is the model and the two semantic singular tests, with no dbt model downstream; `mart_daily_zone_revenue+` is the model, its three generic tests and the same two semantic tests, with no dbt model downstream. Externally the report feeds the finance team's morning read, and the semantic layer publishes `billable_trip_count` and `billable_revenue` off it through logical source LTS7, whose columns, metrics and content filter do not move. Contracts: the aggregate's is additive (six properties added, none removed or retyped, version `1.0.1` → `1.1.0`); the report's is unchanged. No production manifest is published for this platform, so no baseline `build_sha` is recorded.

## Tasks

### Task 1: agg_trip_zone_daily gains the billable measures, with its contract

**Requirements:** `R-01`, `R-02`, `R-05` · **Design:** `docs/design/models/agg/agg_trip_zone_daily.md` · **Skill:** `data-contract` for the contract, then `generating-dbt-model` · **Depends on:** none

- [ ] In `contracts/agg/agg_trip_zone_daily.odcs.yaml`, add six properties — `billable_trip_count` (integer), `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue`, `billable_total_revenue` (number) — each with its promise and a description that says it covers billable trips only, and move the version `1.0.1` → `1.1.0`; then run the contract's own gates and the `validating-data-contract` review.
- [ ] Add to `transformation/models/marts/agg/agg_trip_zone_daily.sql` the six measures in the existing `group by`: `count(*) filter (where f.is_billable)`, and `sum(<amount>) filter (where f.is_billable)` for `f.fare_amount`, `f.tip_amount`, `f.total_surcharges`, `f.tolls_amount` and `f.total_amount`, leaving every existing column and every window function untouched.
- [ ] Run the contract's `generate` so `transformation/models/marts/agg/_agg.yml` carries the six columns, types and data tests, and write the column descriptions the generator leaves for a column it cannot ground.
- [ ] Add `transformation/models/marts/agg/_unit_tests.yml` with `agg_trip_zone_daily_computes_billable_measures`: given `fct_trip` rows that mix billable and non-billable trips in one zone-day, a second zone-day where every trip is non-billable, and one trip with a NULL `pickup_zone_key` edge kept out by the join, expect each zone-day's `billable_trip_count` and five `billable_*_revenue` values, and `billable_trip_count = 0` on the all-non-billable day.
- [ ] Add `transformation/tests/assert_zone_day_agg_one_row_per_zone_date.sql`, returning any `(pickup_date, pickup_location_id)` carried by more than one row, because the report's grain now depends on this model's.
- [ ] Build in the sandbox: `cd transformation && dbt build --select agg_trip_zone_daily --exclude test_type:unit`, then `cd transformation && dbt test --select agg_trip_zone_daily,test_type:unit`; expect both to pass.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check` and the `validating-data-contract` review; expect exit 0 and a passing report.
- [ ] Run the acceptance of `R-05` in the sandbox — `select count(*) as rows, sum(trip_count) as trips, round(sum(total_revenue), 2) as revenue from agg.agg_trip_zone_daily where pickup_date between date '2024-01-01' and date '2024-03-31'` — expect 7,997 rows, 97,184 trips, 2,597,120.92 revenue.
- [ ] Run the acceptance of `R-02` for this model in the sandbox — totals over the new measures for Q1 2024 — expect 7,961 zone-days carrying a billable trip, 95,958 billable trips and 2,629,185.82 billable revenue, and zero mismatch against a recomputation from `fct_trip` at the same grain compared at the cent.
- [ ] Commit and push the contract, the SQL, `_agg.yml`, `_unit_tests.yml` and the singular test with this task's evidence.

### Task 2: the semantic layer names the aggregate's billable measures

**Requirements:** `R-06` · **Design:** `docs/design/models/agg/agg_trip_zone_daily.md` (`## Logical Model`) · **Skill:** `semantic-model` · **Depends on:** Task 1

- [ ] In `logical-model/nyc_taxi_analytics.ossie.yaml`, add the aggregate logical source `LTS10_zone_day_billable` over `agg_trip_zone_daily` — `priority_group: 0`, `content_grain: [pickup_date, pickup_location_id]`, `content_levels` for the day and zone levels the existing `agg_trip_zone_daily` joins carry, and a `content_filter` stating the window and `trips.is_billable` — mapping `billable_trip_count` and `billable_revenue` and the four new metrics, with a `note` pointing at `assert_semantic_content_holds`.
- [ ] Add the four metrics `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue` and `billable_toll_revenue`: `SUM(CASE WHEN trips.is_billable THEN trips.<amount> ELSE 0 END)`, `filter: trips.is_billable`, datatype `Decimal`, a description naming the component and that it covers billable trips only; map them on the detail source `LTS1_detail` as well, since the detail supplies every metric.
- [ ] Leave `LTS7_daily_zone_revenue` and the report's binding exactly as they are, and leave `LTS2_zone_day_agg`'s all-trip mapping and `trip_count` unchanged.
- [ ] Regenerate the semantic tests — `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests` — and commit the regenerated `assert_semantic_content_holds.sql`, `assert_semantic_levels_hold.sql` and `assert_semantic_level_keys_hold.sql`.
- [ ] Run `ossie.py validate logical-model/`, then `coverage logical-model/ transformation/models/marts/core transformation/models/marts/agg transformation/models/marts/finance transformation/models/marts/ops --exclude agg.agg_od_flow_matrix --exclude finance.mart_revenue_component_bridge --exclude core.dim_fare_regime`, then `suppliers logical-model/`, `notes logical-model/ transformation/tests docs/adr` and `generate-tests logical-model/ transformation/tests --check`; expect exit 0, `0 coverage error(s)`, an empty supplier list and nothing stale.
- [ ] Run `cd transformation && dbt test --select assert_semantic_content_holds assert_semantic_levels_hold assert_semantic_level_keys_hold`; expect all to pass, which is the acceptance of `R-06` together with the unchanged LTS7 columns, metrics and content filter.
- [ ] Run the `validating-semantic-model` review; expect a passing report.
- [ ] Commit and push the document and the regenerated tests with this task's evidence.

### Task 3: the report reads the aggregate's billable measures

**Requirements:** `R-01`, `R-02`, `R-03`, `R-04` · **Design:** `docs/design/models/finance/mart_daily_zone_revenue.md` · **Skill:** `generating-dbt-model` · **Depends on:** Task 1

- [ ] Rewrite `transformation/models/marts/finance/mart_daily_zone_revenue.sql` to select the six billable measures from `agg_trip_zone_daily`, keeping the zone-days with `billable_trip_count > 0`, renaming the measures to the report's names, and joining `dim_zone` as of the pickup date on the natural key (`pickup_date >= valid_from_date and pickup_date < valid_to_date`) for `borough`, `zone_name` and `reporting_region`; carry no window predicate and no billable filter of its own.
- [ ] Add `transformation/models/marts/finance/_unit_tests.yml` with `mart_daily_zone_revenue_reads_billable_zone_days`: given aggregate rows for one zone-day with a billable count above zero and one with zero, and `dim_zone` rows for one zone in two versions whose intervals meet on the pickup date, expect the one report row for the billable zone-day, its six renamed measures, and the attributes of the version in force on that date.
- [ ] Build in the sandbox: `cd transformation && dbt build --select mart_daily_zone_revenue --exclude test_type:unit`, then `cd transformation && dbt test --select mart_daily_zone_revenue,test_type:unit`; expect both to pass.
- [ ] Run the acceptance of `R-01`: the compiled model reads `agg_trip_zone_daily` and contains no `count`/`sum` over `fct_trip` — `cd transformation && dbt compile --select mart_daily_zone_revenue`.
- [ ] Run the acceptance of `R-02` in the sandbox against the pinned figures — expect 7,961 rows, 95,958 trips and 2,629,185.82 revenue for Q1 2024, and 4,120 trips with 337,711.05 revenue for JFK Airport.
- [ ] Run the acceptance of `R-03` in the sandbox: a full join of the rebuilt report against an independent recomputation from `fct_trip` and `dim_zone` at the zone-day grain, over the whole reporting window, on all six measures compared at the cent — expect zero key differences and zero value differences.
- [ ] Run the acceptance of `R-04`: `python3 .agents/skills/data-contract/scripts/odcs.py check` reports no schema change for `finance.mart_daily_zone_revenue`, and the built relation carries the same eleven columns with the same types.
- [ ] Commit and push the SQL and the unit test with this task's evidence.

## Execution evidence
