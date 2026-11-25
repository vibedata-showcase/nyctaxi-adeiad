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

- [x] Add to `transformation/models/marts/agg/agg_trip_zone_daily.sql`, inside the existing `daily` CTE's `select` and after `attributed_driver_count`, the six measures: `count(*) filter (where f.is_billable) as billable_trip_count`, and `sum(f.fare_amount) filter (where f.is_billable) as billable_fare_revenue`, `sum(f.tip_amount) filter (where f.is_billable) as billable_tip_revenue`, `sum(f.total_surcharges) filter (where f.is_billable) as billable_surcharge_revenue`, `sum(f.tolls_amount) filter (where f.is_billable) as billable_toll_revenue`, `sum(f.total_amount) filter (where f.is_billable) as billable_total_revenue`. Leave `trip_count`, `total_revenue`, the `where`, the `group by` and every window function untouched; extend the `group by` only if the executor's build proves the new expressions need it (they do not: all six are aggregates over the same rows).
- [x] Add the six columns to `transformation/models/marts/agg/_agg.yml` under `agg_trip_zone_daily`, after `attributed_driver_count`, in the same order as the SQL, each with its `data_type` (`billable_trip_count` `BIGINT`; the five money columns `DOUBLE`) and a `description` stating that it counts or sums only billable trips (ADR 0003) while `trip_count` and `total_revenue` count every trip. Give `billable_trip_count` a `not_null` data test.
- [x] Add the singular test `transformation/tests/assert_billable_measures_match_billable_trips.sql`, returning the rows that violate it: full outer join `agg_trip_zone_daily` against a recomputation from `fct_trip` joined to `dim_zone` on `pickup_zone_key`, grouped by `zone_natural_key` and `pickup_date`, comparing `billable_trip_count` and the five money columns at `round(x, 2)`, and returning any cell present on one side only or holding a different value.
- [x] Register the new singular test in `test-map.json` under `modules.agg.data`.
- [x] Run `cd transformation && dbt deps`, then `cd transformation && dbt build --select +agg_trip_zone_daily --exclude test_type:unit`; expect exit 0 with the new singular test PASS and every existing test on the relation PASS.
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py version` and retry after its documented install if it reports `cli/package-missing`, then run the acceptance condition of `R-01`: query the sandbox for `sum(billable_trip_count)`, `round(sum(billable_total_revenue),2)`, `sum(trip_count)` and `round(sum(total_revenue),2)` over `agg.agg_trip_zone_daily`; expect 95,958, 2,629,185.82, 97,184 and 2,597,120.92.
- [x] Run the acceptance condition of `R-05`: query the sandbox for the relation's column names in order; expect the fourteen existing names in their existing order followed by the six new ones, and no existing name absent.
- [x] Commit and push `transformation/models/marts/agg/agg_trip_zone_daily.sql`, `transformation/models/marts/agg/_agg.yml`, `transformation/tests/assert_billable_measures_match_billable_trips.sql` and `test-map.json`.

### Task 2: agg contract and logical source

**Requirements:** `R-01`, `R-06` · **Design:** `docs/design/models/agg/agg_trip_zone_daily.md` · **Skill:** `data-contract` (contract) then `semantic-model` (document) · **Depends on:** Task 1

- [x] In `contracts/agg/agg_trip_zone_daily.odcs.yaml`, append the six properties in the same order and with the same names and types as the built relation, each with a `description` stating the billable population, and move `version` from `1.0.1` to `1.1.0` (added properties are a minor move; removed, retyped or re-grained would be major).
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0. Then run `python3 .agents/skills/data-contract/scripts/odcs.py check --relations`; expect exit 0 with the six new properties matched to the built relation.
- [x] In `logical-model/nyc_taxi_analytics.ossie.yaml`, update `LTS2_zone_day_agg`'s `note` so it records why the six billable columns are not bound: `billable_trip_count` and `billable_revenue` are already served at this grain by `LTS7_daily_zone_revenue`, so binding them here too would offer one metric twice at one grain. Change no `column_map`, `content_levels` or `content_filter` entry.
- [x] Run `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/`; expect exit 0. Then run the full structural chain from `test-map.json` `modules.logical-model.commands.structural`; expect exit 0 from every command in it.
- [x] Commit and push `contracts/agg/agg_trip_zone_daily.odcs.yaml` and `logical-model/nyc_taxi_analytics.ossie.yaml`.

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

- Task 1: `cd transformation && dbt deps` — exit 0 — `agg_trip_zone_daily.sql`, `_agg.yml`, `assert_billable_measures_match_billable_trips.sql`, `test-map.json` — sha256:8bb6bef1b41c0179d514d95537df1a3b05c780e62c2422db618d961423886645 / 2a42b2a1ac3d1a1fa9f1ff91e57dd3b19e40c1760c6e75347541a5e06fede30e / 6ac603392a0c80f9da053448adcca59123d7078b6f80dd42ec98421c303d09f1 / f749b4d2e49fc7cfaebbe70e54249ed93673bbf29dbf249f19c22cd5f6c21b72
  - Gate: `cd transformation && dbt build --select +agg_trip_zone_daily --exclude test_type:unit` — exit 0 — PASS=99 WARN=1 ERROR=0 SKIP=0 TOTAL=100. Relation `agg.agg_trip_zone_daily`, materialisation `table`.
  - Destination: `python /data/default-plugins/vibedata-data-engineering/0.148.28/scripts/assert_dbt_destination.py` — exit 0 — `DESTINATION_OK: 23 built relation(s) landed in the sandbox ephm_nyc-taxi-analytics_new-intent-667f7960`.
  - Layer gate: `cd transformation && dbt test --select path:models/marts/agg --exclude test_type:unit` — exit 0 — PASS=8 WARN=1 ERROR=0 TOTAL=9.
  - Maps: `python3 -m pytest tests/test_maps.py -q` — exit 0 — 30 passed, including the new test resolving under `modules.agg`.
  - Lint: `sqlfluff lint transformation/models/marts/agg/agg_trip_zone_daily.sql transformation/tests/assert_billable_measures_match_billable_trips.sql` — exit 0 — clean.
  - `R-01` acceptance (target `ephemeral`): `select sum(billable_trip_count), round(sum(billable_total_revenue),2), sum(trip_count), round(sum(total_revenue),2), count(*), count(*) filter (where billable_trip_count = 0), count(*) filter (where billable_fare_revenue is null) from agg.agg_trip_zone_daily` → 95,958 · 2,629,185.82 · 97,184 · 2,597,120.92 · 7,997 rows · 36 zero-billable · 36 null fare. Meets the required 95,958 / 2,629,185.82, and the pre-existing all-trip pair is unchanged at 97,184 / 2,597,120.92.
  - `R-05` acceptance (target `ephemeral`): `select column_name, ordinal_position, data_type from information_schema.columns where table_schema='agg' and table_name='agg_trip_zone_daily' order by ordinal_position` → 20 rows; the fourteen existing columns occupy positions 1-14 with their types unchanged, the six billable columns occupy 15-20.
  - New singular test: `assert_billable_measures_match_billable_trips` PASS — full outer join of the aggregate against a `fct_trip` recomputation, money at the cent, returns 0 rows.
  - Pre-existing warning, not caused here: `assert_semantic_levels_hold` WARN with 1 row, `trips.LTS5_weather_borough_daily: trips_to_pickup_zone borough key is no member`, member `unresolved` — from `agg.agg_weather_demand_daily`, which this task does not touch (91 `unresolved` borough rows on `ephemeral`), and the semantic model's own note documents that sentinel under ADR 0012. It warns by design and fails no build.
  - Coverage gap: the 13 pre-existing columns of the relation carry no `description` in `_agg.yml`. The six added here do; filling the other 13 is not this intent's scope and their absence is already recorded in `docs/review/2026-10-25-contracts-nyc-taxi.md`.
- Task 2: `python3 .agents/skills/data-contract/scripts/odcs.py generate` — exit 0 — `contracts/agg/agg_trip_zone_daily.odcs.yaml`, `logical-model/nyc_taxi_analytics.ossie.yaml`, `transformation/models/marts/agg/_agg.yml` — sha256:0080f4fe0f15918cedce99b75ee314527fbfd1c5fa64ced124b5f525f47a8f87 / 88b3adab9bda425e6a9acba55003a71bb3b10abc88c977ed9c9e9bb165bb53c0 / 8ee03a9a6cb09da5b03ef48fddfa4fa81058bed163524ee842541c49f6e899de
  - Contract: six properties appended in built-relation order, `version` `1.0.1` → `1.1.0`. `billable_trip_count` carries `required: true`; the five money columns are nullable by design (`D-06`). No `primaryKey` and no `dataGranularityDescription` were added: the relation's contract has never declared a key, and its grain is stated by the Ossie source's `content_grain` and the design record.
  - `generate` rewrote `billable_trip_count`'s hand-written description to `Trips whose total amount is positive.`, sourced from the `billable_trip_count` metric in the Ossie document — the same text the identical column carries on `agg_trip_zone_daypart_dow`. Accepted as the generated value, not overwritten.
  - `check`: `python3 .agents/skills/data-contract/scripts/odcs.py check` — exit 0 — 0 errors; the `active-unbuilt` warning cleared once the relation was rebuilt.
  - `diff`: `python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main` — exit 0 — six `diff/additive` findings (one per property), no `diff/version-not-bumped`. Purely additive, so no breaking delta and no breaking-contract stop.
  - `check --relations`: `python3 .agents/skills/data-contract/scripts/odcs.py check --relations --catalog /data/ephm_duckdb/ephm_nyc-taxi-analytics_new-intent-667f7960.duckdb` — exit 0 — 0 errors, all 20 declared properties match the built relation. Run against the sandbox file, not `dbt docs generate`'s catalog, because that catalog lists only dbt-built relations and reports the six dlt-loaded `audit_*` relations (bronze, ops_raw, mdm_raw) as absent; those six are pre-existing artifacts of the catalog, not a mismatch, and they live in `bronze`/`*_raw`, outside both relations this intent touches.
  - `profile`: `... odcs.py profile --relation agg.agg_trip_zone_daily --catalog /data/ephm_duckdb/ephm_nyc-taxi-analytics_new-intent-667f7960.duckdb` — exit 0 — 0 errors, 0 warnings.
  - Semantic structural chain, each exit 0: `ossie.py validate logical-model/` — 2 files, 0 errors, 1 pre-existing warning (`zone_poi_to_zone` to-column not a unique key, unrelated); `ossie.py coverage ...` — 34 models, 31 named, 0 coverage errors; `ossie.py suppliers` — 0 unsupplied; `ossie.py notes` — 0 dangling; `ossie.py generate-tests --check` — 3 generated, 0 stale.
  - Semantic SQL checks: `ossie.py bindings logical-model/ transformation/target/manifest.json` — exit 0 — 63 models, 0 errors, 0 warnings; `ossie.py columns logical-model/ transformation/target/catalog.json` — exit 0 — 0 errors, 5 pre-existing `columns/datatype-mismatch` warnings on `trips.total_amount`, `trips.fare_residual`, `shift.gross_revenue`, `maintenance.cost_usd`, `vehicle.maintenance_cost_usd`, all same-class-different-type and none on a column this intent added.
  - Semantic content tests on data: `cd transformation && dbt test --select assert_semantic_content_holds assert_semantic_level_keys_hold assert_semantic_levels_hold` — exit 0 — PASS=2 WARN=1 ERROR=0 (the same pre-existing `LTS5_weather_borough_daily` `unresolved` warning recorded under Task 1).
  - `validating-semantic-model`: passes. `LTS2_zone_day_agg`'s `column_map` and `content_filter` are untouched, so no binding moved; the new columns are refused in its `note`, which is where a refused aggregate column belongs. No dataset, metric, concept or mapping changed, so no ontology or contract-document delta.
  - `validating-data-contract`: passes. The key question is unjudged rather than newly answered — the relation has never declared a `primaryKey`, the review queue already holds that doubt (`pickup_location_id`, `pickup_date_key` rows), and profile does not test an undeclared key. Nothing here makes the grain claim different from before.

- Profiling verdict: upstream `core.fct_trip` and `core.dim_zone` — **Ready**, read on `domain` (declared by `transformation/models/staging/_sources.yml` and by the Requirement's design records). Evidence in the Verification's `## Discovery`: `fct_trip` has 97,184 in-window rows, 0 null `pickup_zone_key`, 0 null in each of the five amount columns, 1,226 non-billable; `dim_zone` has 272 rows over 265 natural keys with 7 two-version keys, 0 null `reporting_region` on current versions. The join key (`zone_key`) is unique by construction; the natural key is not, which is why every join carries the date.

