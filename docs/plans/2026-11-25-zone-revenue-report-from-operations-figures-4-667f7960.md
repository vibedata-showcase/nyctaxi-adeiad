# Plan: Zone revenue report from operations figures 4

**Goal:** Build `finance.mart_daily_zone_revenue` from `agg.agg_trip_zone_daily` so one build answers the daily zone revenue question, with no number in the report changing.

**Requirement:** `docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-4-667f7960.md`

**Constraints:**

- The report's published shape does not move: the same eleven columns, types, order and values (design `D-06`, `R-03`, `R-06`).
- The aggregate's fourteen existing columns keep their names, types, positions and all-trip meanings; the six billable columns are appended (design `D-02`, `R-05`).
- Billable columns are named `billable_<measure>`, matching `agg_trip_zone_daypart_dow` (design `D-02`).
- A filtered sum returns NULL where no row matches; the money columns stay NULL on a zero-billable zone-day and the count says 0 beside them (design `D-06`).
- The report filters `billable_trip_count > 0` (design `D-03`).
- Any join to `dim_zone` carries the date and is half-open, `>=` and `<` (ADR 0009; design `D-04`).
- Money is compared at the cent, `round(x, 2)` (`.agents/skills/dbt-testing`, `## Comparing values`).
- Platform: `duckdb_local`; every build runs against the Intent's sandbox, never the Domain file.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `agg_trip_zone_daily` | model | modify | `R-01`, `R-05` | `docs/design/models/agg/agg_trip_zone_daily.md` | `cd transformation && dbt build --select agg_trip_zone_daily --exclude test_type:unit` |
| `contracts/agg/agg_trip_zone_daily.odcs.yaml` | contract | modify | `R-01`, `R-06` | `docs/design/models/agg/agg_trip_zone_daily.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `LTS2_zone_day_agg` in `logical-model/nyc_taxi_analytics.ossie.yaml` | logical-model | modify | `R-06` | `docs/design/models/agg/agg_trip_zone_daily.md` | `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/` |
| `mart_daily_zone_revenue` | model | modify | `R-02`, `R-03`, `R-04`, `R-06` | `docs/design/models/finance/mart_daily_zone_revenue.md` | `cd transformation && dbt build --select mart_daily_zone_revenue --exclude test_type:unit` |
| `contracts/finance/mart_daily_zone_revenue.odcs.yaml` | contract | modify | `R-06` | `docs/design/models/finance/mart_daily_zone_revenue.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `LTS7_daily_zone_revenue` in `logical-model/nyc_taxi_analytics.ossie.yaml` | logical-model | modify | `R-06` | `docs/design/models/finance/mart_daily_zone_revenue.md` | `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/` |

**Change impact:** `agg_trip_zone_daily` is read by `mart_daily_zone_revenue` and bound as logical source `LTS2_zone_day_agg`; it is read by `assert_semantic_content_holds` and `assert_semantic_levels_hold`. `mart_daily_zone_revenue` is bound as logical source `LTS7_daily_zone_revenue` and read by the same two tests. No other model in the project refs either relation.

## Tasks

### Task 1: agg_trip_zone_daily

**Requirements:** `R-01`, `R-05` · **Design:** `docs/design/models/agg/agg_trip_zone_daily.md` · **Skill:** `generating-dbt-model` · **Depends on:** none

- [ ] Add to `transformation/models/marts/agg/agg_trip_zone_daily.sql`, inside the existing `daily` CTE's `select` and after `attributed_driver_count`, the six measures: `count(*) filter (where f.is_billable) as billable_trip_count`, and `sum(f.fare_amount) filter (where f.is_billable) as billable_fare_revenue`, `sum(f.tip_amount) filter (where f.is_billable) as billable_tip_revenue`, `sum(f.total_surcharges) filter (where f.is_billable) as billable_surcharge_revenue`, `sum(f.tolls_amount) filter (where f.is_billable) as billable_toll_revenue`, `sum(f.total_amount) filter (where f.is_billable) as billable_total_revenue`. Leave `trip_count`, `total_revenue`, the `where`, the `group by` and every window function untouched; extend the `group by` only if the executor's build proves the new expressions need it (they do not: all six are aggregates over the same rows).
- [ ] Add the six columns to `transformation/models/marts/agg/_agg.yml` under `agg_trip_zone_daily`, after `attributed_driver_count`, in the same order as the SQL, each with its `data_type` (`billable_trip_count` `BIGINT`; the five money columns `DOUBLE`) and a `description` stating that it counts or sums only billable trips (ADR 0003) while `trip_count` and `total_revenue` count every trip. Give `billable_trip_count` a `not_null` data test.
- [ ] Add the singular test `transformation/tests/assert_billable_measures_match_billable_trips.sql`, returning the rows that violate it: full outer join `agg_trip_zone_daily` against a recomputation from `fct_trip` joined to `dim_zone` on `pickup_zone_key`, grouped by `zone_natural_key` and `pickup_date`, comparing `billable_trip_count` and the five money columns at `round(x, 2)`, and returning any cell present on one side only or holding a different value.
- [ ] Register the new singular test in `test-map.json` under `modules.agg.data`.
- [ ] Run `cd transformation && dbt deps`, then `cd transformation && dbt build --select +agg_trip_zone_daily --exclude test_type:unit`; expect exit 0 with the new singular test PASS and every existing test on the relation PASS.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py version` and retry after its documented install if it reports `cli/package-missing`, then run the acceptance condition of `R-01`: query the sandbox for `sum(billable_trip_count)`, `round(sum(billable_total_revenue),2)`, `sum(trip_count)` and `round(sum(total_revenue),2)` over `agg.agg_trip_zone_daily`; expect 95,958, 2,629,185.82, 97,184 and 2,597,120.92.
- [ ] Run the acceptance condition of `R-05`: query the sandbox for the relation's column names in order; expect the fourteen existing names in their existing order followed by the six new ones, and no existing name absent.
- [ ] Commit and push `transformation/models/marts/agg/agg_trip_zone_daily.sql`, `transformation/models/marts/agg/_agg.yml`, `transformation/tests/assert_billable_measures_match_billable_trips.sql` and `test-map.json`.

### Task 2: agg contract and logical source

**Requirements:** `R-01`, `R-06` · **Design:** `docs/design/models/agg/agg_trip_zone_daily.md` · **Skill:** `data-contract` (contract) then `semantic-model` (document) · **Depends on:** Task 1

- [ ] In `contracts/agg/agg_trip_zone_daily.odcs.yaml`, append the six properties in the same order and with the same names and types as the built relation, each with a `description` stating the billable population, and move `version` from `1.0.1` to `1.1.0` (added properties are a minor move; removed, retyped or re-grained would be major).
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0. Then run `python3 .agents/skills/data-contract/scripts/odcs.py check --relations`; expect exit 0 with the six new properties matched to the built relation.
- [ ] In `logical-model/nyc_taxi_analytics.ossie.yaml`, update `LTS2_zone_day_agg`'s `note` so it records why the six billable columns are not bound: `billable_trip_count` and `billable_revenue` are already served at this grain by `LTS7_daily_zone_revenue`, so binding them here too would offer one metric twice at one grain. Change no `column_map`, `content_levels` or `content_filter` entry.
- [ ] Run `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/`; expect exit 0. Then run the full structural chain from `test-map.json` `modules.logical-model.commands.structural`; expect exit 0 from every command in it.
- [ ] Commit and push `contracts/agg/agg_trip_zone_daily.odcs.yaml` and `logical-model/nyc_taxi_analytics.ossie.yaml`.

### Task 3: mart_daily_zone_revenue

**Requirements:** `R-02`, `R-03`, `R-04`, `R-06` · **Design:** `docs/design/models/finance/mart_daily_zone_revenue.md` · **Skill:** `generating-dbt-model` · **Depends on:** Task 1

- [ ] Rewrite `transformation/models/marts/finance/mart_daily_zone_revenue.sql` to read its measures from `agg_trip_zone_daily` and `dim_zone`: select `a.pickup_date as trip_date`, `a.pickup_location_id`, `z.borough_name as borough`, `a.zone_name`, `z.reporting_region`, `a.billable_trip_count as trip_count`, `a.billable_fare_revenue as fare_revenue`, `a.billable_tip_revenue as tip_revenue`, `a.billable_surcharge_revenue as surcharge_revenue`, `a.billable_toll_revenue as toll_revenue`, `a.billable_total_revenue as total_revenue`; `from {{ ref('agg_trip_zone_daily') }} a`; `left join {{ ref('dim_zone') }} z on z.zone_natural_key = a.pickup_location_id and a.pickup_date >= z.valid_from_date and a.pickup_date < z.valid_to_date`; `where a.billable_trip_count > 0`. Write no `fct_trip` reference and no `in_report_window` call — the window is already applied by the aggregate. Keep one comment saying the billable rule and the window are applied upstream by ADR 0018, and that the non-billable zone-days are excluded because the report publishes only zone-days that carry billable revenue.
- [ ] In `transformation/models/marts/finance/_finance.yml`, change `mart_daily_zone_revenue`'s `trip_count` description from `Trips, billable or not.` to `Billable trips; the model publishes only zone-days with at least one.` Add a `description` to `total_revenue` and to each of `fare_revenue`, `tip_revenue`, `surcharge_revenue` and `toll_revenue` stating that it sums only billable trips. Change no column name, type, order or test.
- [ ] Add the singular test `transformation/tests/assert_daily_zone_revenue_matches_billable_trips.sql`, returning the rows that violate it: full outer join `mart_daily_zone_revenue` against a recomputation from `fct_trip` joined to `dim_zone` on `pickup_zone_key` and filtered `is_billable` inside the reporting window, grouped by `zone_natural_key` and `pickup_date`, comparing `trip_count` and the five money columns at `round(x, 2)`, returning any cell present on one side only or holding a different value. This is the test that would catch the report drifting from the billable population now that it no longer filters the fact itself.
- [ ] Register the new singular test in `test-map.json` under `modules.finance.data`.
- [ ] Run `cd transformation && dbt build --select mart_daily_zone_revenue --exclude test_type:unit`; expect exit 0 and both new and existing tests PASS.
- [ ] Run the acceptance condition of `R-02`: `cd transformation && dbt compile --select mart_daily_zone_revenue`, then confirm the compiled SQL contains `agg_trip_zone_daily` and contains no `fct_trip`.
- [ ] Run the acceptance condition of `R-03`: query the sandbox for Q1 totals (`sum(trip_count)`, `round(sum(total_revenue),2)`) and for `pickup_location_id = 132`; expect 95,958 / 2,629,185.82 and 4,120 / 337,711.05.
- [ ] Run the acceptance condition of `R-04`: query the sandbox for row count, distinct `pickup_location_id`, distinct `trip_date`, and `count(distinct zone_name)`, `count(distinct borough)` and the distinct `reporting_region` values; expect 7,961 rows, 261 zones, 91 dates, 260 distinct `zone_name`, 8 distinct `borough`, and exactly `Manhattan Core`, `Out of State`, `Outer Boroughs`, `Unresolved`.
- [ ] Commit and push `transformation/models/marts/finance/mart_daily_zone_revenue.sql`, `transformation/models/marts/finance/_finance.yml`, `transformation/tests/assert_daily_zone_revenue_matches_billable_trips.sql` and `test-map.json`.

### Task 4: mart contract and logical source

**Requirements:** `R-06` · **Design:** `docs/design/models/finance/mart_daily_zone_revenue.md` · **Skill:** `data-contract` (contract) then `semantic-model` (document) · **Depends on:** Task 3

- [ ] In `contracts/finance/mart_daily_zone_revenue.odcs.yaml`, keep every property, type and relationship as it is and add prose only: a `description` on `trip_count` stating it is the billable count and that a zone-day with no billable trip is absent, and a `description` on `total_revenue` and the four component columns stating the billable population. No property is added, removed, renamed or retyped, so `version` stays `1.0.1`, as design `D-06` records.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0. Then run `python3 .agents/skills/data-contract/scripts/odcs.py check --relations`; expect exit 0 with no presence or type difference reported.
- [ ] In `logical-model/nyc_taxi_analytics.ossie.yaml`, update `LTS7_daily_zone_revenue`'s `content_filter` to the population the rebuilt model reads (`pickup_date >= DATE '2024-01-01' AND pickup_date < DATE '2024-04-01' AND billable_trip_count > 0`, expressed in the fact's own terms as the document's other sources do) and correct its `note` so it no longer refuses `trip_count` or `pickup_zone_key` for reasons that stopped being true. Keep `billable_trip_count` mapped to `trip_count` and `billable_revenue` mapped to `total_revenue`.
- [ ] Run `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/`; expect exit 0. Then run the full structural chain from `test-map.json` `modules.logical-model.commands.structural`, including `generate-tests --check`; expect exit 0 from every command.
- [ ] Run the `validating-semantic-model` gate and the `validating-data-contract` gate over both contracts; expect a passing report from each.
- [ ] Commit and push `contracts/finance/mart_daily_zone_revenue.odcs.yaml`, `logical-model/nyc_taxi_analytics.ossie.yaml` and any test the semantic-model `generate-tests` regenerated.

## Execution evidence

