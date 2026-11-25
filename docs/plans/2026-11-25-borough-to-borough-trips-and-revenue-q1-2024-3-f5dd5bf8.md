# Plan: Borough-to-borough trips and revenue, Q1 2024 3

**Goal:** Add a gold table of monthly trips, revenue and cross-borough trip share for every origin borough × destination borough pair in Q1 2024.

**Requirement:** `docs/requirement/2026-11-25-borough-to-borough-trips-and-revenue-q1-2024-3-f5dd5bf8.md`

**Constraints:**
- Grain is (month, origin borough, destination borough); one row per observed pair only, no zero-filled grid (`D-01`, `D-05`).
- Population is billable trips inside the reporting window `2024-01-01` … `2024-04-01` (`D-02`, ADR 0003).
- Revenue is gross billable `total_amount`; no payment method excluded (`D-03`, ADR 0013).
- No 25-trip floor at borough grain (`D-04`, ADR 0018).
- `cross_borough_trip_share` is a ratio of sums over the origin borough's month traffic, via `safe_divide`, repeated on each of that origin's rows (`D-07`, ADR 0016).
- `EWR`, `Unknown` and `N/A` stay in the rollup as borough groups (`D-06`, ADR 0012).
- Model lives in `transformation/models/marts/agg/`, schema `agg`, materialised `table`, `contract: {enforced: true}`, every output cast to its declared type (DuckDB does not coerce).
- No `select *`; columns listed explicitly; no audit columns.
- Money compared at the cent (`round(x, 2)`), never bit-for-bit.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `agg_borough_flow_monthly` | model | create | `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `dbt build --select agg_borough_flow_monthly --target dev` then `dbt test --select agg_borough_flow_monthly --target dev` |
| `contracts/agg/agg_borough_flow_monthly.odcs.yaml` | contract | create | `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `logical-model/nyc_taxi_analytics.ossie.yaml` | logical-model | modify | `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `ossie.py validate`, `coverage`, `suppliers`, `notes`, `generate-tests --check` |
| `ontology/nyc_taxi_analytics.mapping.yaml` | ontology | modify | `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `ossie.py validate ontology/`, `refs`, `glossary` |

**Change impact:** No existing artifact changes. `agg_borough_flow_monthly` is new, so it has no downstream consumer and no upstream model is edited. `agg.agg_od_flow_matrix`, `finance.mart_daily_zone_revenue` and every other published model are untouched — `fct_trip` and `dim_zone` are read, not modified, and their contracts are unchanged. The Ossie document gains one aggregate logical source and two metrics on the existing trips star; no existing dataset, metric or relationship changes.

**Baseline build_sha:** not applicable — the dbt card's `## Defer` says no production manifest is published, so `/data/cache` was not read.

## Tasks

### Task 1: `agg_borough_flow_monthly` model, its properties entry, its tests and its contract

**Requirements:** `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-06` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `generating-dbt-model` with `data-contract` · **Depends on:** none

- [x] Author `transformation/models/marts/agg/agg_borough_flow_monthly.sql`: `fct_trip` aliased `f`, `dim_zone` joined twice (`o` on `pickup_zone_key`, `d` on `dropoff_zone_key`), `where {{ in_report_window('f.pickup_datetime') }} and f.is_billable`, grouped to `cast(date_trunc('month', f.pickup_date) as date) as trip_month`, `o.borough_name as origin_borough`, `d.borough_name as dest_borough`, carrying `count(*) as trip_count`, `sum(f.total_amount) as total_revenue`, `count(*) filter (where d.borough_name is distinct from o.borough_name) as cross_borough_trip_count`, and the origin share via `{{ safe_divide(...) }}` computed in a window over the origin borough's month; every output cast to its declared type. `is_distinct_from`, not `<>`, so a null borough name can never silently read as "same borough".
- [x] Author `transformation/models/marts/agg/_agg.yml` entry: `agg_borough_flow_monthly` with `contract: {enforced: true}`, every column typed and described, `not_null` on `trip_month`, `origin_borough`, `dest_borough`, `trip_count`, `total_revenue`, `cross_borough_trip_count`, and `accepted_values` on `origin_borough` and `dest_borough` covering exactly the 8 groups on `dim_zone` (`Bronx`, `Brooklyn`, `EWR`, `Manhattan`, `N/A`, `Queens`, `Staten Island`, `Unknown`). A `relationships` test is deliberately not used: `borough_name` is not unique on the versioned `dim_zone`, so the closed set is the honest check.
- [x] Author `transformation/tests/assert_borough_flow_monthly_one_row_per_grain.sql`: returns rows where (`trip_month`, `origin_borough`, `dest_borough`) repeats.
- [x] Author `transformation/tests/assert_borough_flow_monthly_covers_every_trip.sql`: per month, the table's `trip_count` and `total_revenue` against `fct_trip`'s billable counts and `total_amount` in the window, compared at the cent with `is distinct from`.
- [x] Author `transformation/tests/assert_borough_flow_monthly_share_is_a_ratio_of_sums.sql`: recomputes each origin borough's month share from the table's own rows (`sum(cross_borough_trip_count)` over `sum(trip_count)` per origin and month) and returns rows where any published `cross_borough_trip_share` departs from it by more than `1e-9`.
- [x] Author a unit test `borough_flow_share_is_a_ratio_of_sums` in `transformation/models/marts/agg/_unit_tests.yml` (created there as the agg folder's first unit-test file): given two origin boroughs, one crossing and one intra-borough trip, and an `EWR` destination, expect the share on every row of each origin and month; `overrides: {vars: {report_start: ..., report_end: ...}}`.
- [x] Author `contracts/agg/agg_borough_flow_monthly.odcs.yaml` with `status: proposed` — the relation exists but no Ossie document names it until Task 2, and `odcs.py check` fails a boundary relation no canonical document names. Run `odcs.py reverse --catalog /data/ephm_duckdb/ephm_nyc-taxi-analytics_new-intent-f5dd5bf8.duckdb` to draft it, keep the drafted grain and types, then run `odcs.py generate` so the dbt contract keys and descriptions come from the contract.
- [x] Run `dbt build --select agg_borough_flow_monthly --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'`, then `python "$SKILL_DIR/../../scripts/assert_dbt_destination.py"` and `python "$SKILL_DIR/../../scripts/ephemeral_workspace_marker.py" init`; expect exit 0 and 1 model + its tests built.
- [x] Run `dbt test --select agg_borough_flow_monthly --target dev`; expect every data test and the unit test to pass.
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0 with no `error`-severity finding, then the `validating-data-contract` report; expect a pass.
- [x] Run the acceptance conditions: `R-01` via the grain test (0 rows); `R-02`/`R-03` via the coverage test (0 rows) and a read of the three months against 29,985 / 30,017 / 35,956 and 816,057.76 / 813,885.68 / 999,242.38; `R-04` via the ratio-of-sums test (0 rows) and one recomputed origin-month by hand; `R-05` via an 8-group check.
- [x] Commit and push `agg_borough_flow_monthly.sql`, `_agg.yml`, `_unit_tests.yml`, the three singular tests and the contract.

### Task 2: The Ossie logical source, its two metrics, and the ontology references

**Requirements:** `R-06` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` (`## Logical Model`) · **Skill:** `semantic-model` with `ontology` · **Depends on:** Task 1

- [ ] Add `LTS10_borough_flow_monthly` to the `trips` dataset's `logical_sources` in `logical-model/nyc_taxi_analytics.ossie.yaml`: `physical_table: agg_borough_flow_monthly`, `column_map` binding `trip_count` → `billable_trip_count` and `total_revenue` → `billable_revenue`, `content_grain` at the model's grain, `content_levels` reaching the `month` level of `date` and the `borough` level of `zone` through both roles, `content_filter` naming the window, `is_billable` and both zone keys. Its `note` refuses `cross_borough_trip_share` with the reason in `D-11`.
- [ ] Declare metric `cross_borough_trip_count` (a `SUM` over the source's `trip_count`, filtered to rows where origin and destination borough differ) and `cross_borough_trip_share` (a `derived_expression` over that numerator and `billable_trip_count`).
- [ ] Run `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests` to regenerate the semantic tests, and commit what it writes.
- [ ] Run the structural chain: `ossie.py validate logical-model/`, `coverage` with the four boundary roots and the three `--exclude`s from `test-map.json`, `suppliers`, `notes`, `generate-tests --check`; expect exit 0 each.
- [ ] Run the `validating-semantic-model` review; expect a pass.
- [ ] Re-run the `ontology` gates (`validate ontology/`, `refs`, `glossary`) since the trips dataset gained a source; expect exit 0 each, then the `validating-ontology` report.
- [ ] Run `dbt build --select agg_borough_flow_monthly --target dev` again so the enforced contract and the regenerated semantic tests are exercised together; expect exit 0, then the destination check.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate` so the dbt contract keys and column descriptions come from the contract, then re-run `dbt build --select agg_borough_flow_monthly --target dev`; expect exit 0 and the destination check to pass.
- [ ] Flip `contracts/agg/agg_borough_flow_monthly.odcs.yaml` to `status: active` now the document names the relation, run `odcs.py check`; expect exit 0 with no `error`-severity finding.
- [ ] Commit and push the Ossie document, the regenerated semantic tests, the contract's new status, and any ontology file it touches.

## Execution evidence

- Task 1: `cd transformation && dbt build --select agg_borough_flow_monthly --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — `agg.agg_borough_flow_monthly` built, PASS=12 (1 model, 11 data tests) — sha256:197b77704ad5cd7f `agg_borough_flow_monthly.sql`
- Task 1: `python .../scripts/assert_dbt_destination.py` — exit 0 — `DESTINATION_OK: 1 built relation(s) landed in the sandbox ephm_nyc-taxi-analytics_new-intent-f5dd5bf8`
- Task 1: `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit --target dev` — exit 0 — PASS=1 (`borough_flow_share_is_a_ratio_of_sums`) — sha256:8ce3108d79d4627a `_unit_tests.yml`
- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py reverse --catalog /data/ephm_duckdb/ephm_nyc-taxi-analytics_new-intent-f5dd5bf8.duckdb` — exit 0 — `contracts/agg/agg_borough_flow_monthly.odcs.yaml` drafted, `status: proposed` — sha256:2b26a347474418e8
- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py check` — exit 0 — 0 error-severity findings (`contract/no-document` warning stands until Task 2 names the relation)
- Task 1 acceptance `R-01`: the grain test `assert_borough_flow_monthly_one_row_per_grain` passed with 0 rows; independent read on `target: ephemeral`: `select count(*) ... from agg.agg_borough_flow_monthly` → 122 rows, no repeat.
- Task 1 acceptance `R-02`/`R-03`: the closure test `assert_borough_flow_monthly_covers_every_trip` passed with 0 rows; independent read on `target: ephemeral` → 2024-01 29,985 trips / $816,057.76; 2024-02 30,017 / $813,885.68; 2024-03 35,956 / $999,242.38 — identical to the star, at the cent.
- Task 1 acceptance `R-04`: the test `assert_borough_flow_monthly_share_is_a_ratio_of_sums` passed with 0 rows; independent read on Queens → 2024-01 2,008/2,807 = 0.7153544709654436 across 8 rows with 1 distinct share value, matching the discovery figure 0.715354; 2024-02 0.7309825673534073; 2024-03 0.7395989224783.
- Task 1 acceptance `R-05`: independent read → 8 distinct `origin_borough` and 8 distinct `dest_borough` groups, 0 rows with `cross_borough_trip_count > trip_count`; the `accepted_values` tests on both columns passed.
- Task 1 finding, fixed in the Plan rather than the gate: `odcs.py check` fails a boundary relation no canonical document names, and that document is Task 2's. The contract is therefore drafted `status: proposed` here and flipped to `active` in Task 2, which is what the Playbook's Plan section asks for anyway. Both Plan lines were corrected.

