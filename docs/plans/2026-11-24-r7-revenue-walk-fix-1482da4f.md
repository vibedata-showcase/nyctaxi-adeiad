# Plan: R7 · revenue walk fix

**Goal:** Stop the revenue walk counting the airport fee twice, so its nine component lines sum to billable revenue instead of `total_amount + airport_fee`.

**Requirement:** `docs/cases/2026-11-24-r7-revenue-walk-fix-1482da4f.md` (a `fix` case: the Case record stands in for the Requirement; design approved and breaking contract approved on 2026-11-24 against `38cb9f7`).

**Constraints:**

- Acceptance conditions, which stand in for `R-NN` because a fix case has none:
  - `C-01` `core.fct_trip.fare_residual` subtracts the airport fee: over the report window's billable trips its sum is `−32,638.75` at the cent, and no trip's residual is left holding an airport fee.
  - `C-02` The walk balances: every `(trip_month, service_type_key, borough_name)` group's `component_amount` lines sum to its `total_amount` within `0.01`, and the walk's total over all nine lines is `2,629,185.82` at the cent — equal to `SUM(total_amount)` over billable in-window trips.
  - `C-03` The guard exists and would have caught this: `assert_revenue_walk_balances` returns `9` groups against the pre-fix warehouse and `0` after.
  - `C-04` `ops.mart_trip_quality_scorecard.unbalanced_total_count` moves as predicted: `31,869` in-window trips before, `26,457` after, `5,942` reclassified.
  - `C-05` `core/fct_trip` contract `2.0.0`, its declared properties unchanged, and `odcs.py check` and `odcs.py diff origin/main` exit 0.
- `transformation/dbt_project.yml`: report window `report_start 2024-01-01`, `report_end 2024-04-01`; marts materialise as tables; `core.fct_trip` is the project's only incremental model (`unique_key: trip_key`, `delete+insert`, `on_schema_change: append_new_columns`).
- `dbt-models` B15 and `fct_trip` `D-04`: a changed column upstream of `fct_trip` needs `dbt build --full-refresh --select fct_trip`. Without it the corrected residual never reaches the `97,184` existing rows: the incremental predicate selects only pickups later than the loaded maximum, and the source is a closed three-month load.
- `dbt-testing` C4: singular tests live in `transformation/tests/`, are named `assert_<what_must_hold>.sql`, and return the rows that violate the assertion.
- `dbt-testing`: DuckDB `double` aggregation is not reproducible bit for bit; compare money at the cent (`round(x, 2)` or an explicit `0.01` tolerance), never bit for bit.
- `dbt-testing` C5: no unit test is required — the change is an arithmetic term in a macro, with no branch, ordering, deduplication or state classification to get wrong. C1 and C10 do not apply: no key, foreign key or derived-key join changes.
- `data-contract`: `generate` owns `data_type`, `data_tests`, `contract: {enforced}` and the dbt descriptions on a contracted relation; never hand-write them.
- Platform card `duckdb_local/dbt.md`: no production manifest is published, so never pass `--defer` and never read `/data/cache`; this Plan therefore carries no `Baseline build_sha:`.
- Platform card `duckdb_local/dbt.md`: DuckDB has no row filters or masks, so the governance check is recorded `not applicable`.
- `dbt` runs are preceded once per session by `dbt deps` in `transformation/` (`packages.yml` exists and every session starts from a fresh clone).

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `transformation/tests/assert_revenue_walk_balances.sql`, `test-map.json` | model (test) | create | `C-03` | `docs/design/models/finance/mart_revenue_component_bridge.md` `D-01`, `D-02` | `cd transformation && dbt test --select assert_revenue_walk_balances` |
| `transformation/macros/finance.sql` (`fare_residual`) | macro | modify | `C-01` | `code is contract` | `cd transformation && dbt build --full-refresh --select fct_trip` |
| `core.fct_trip` — `fare_residual` values, and its doc block in `transformation/models/docs.md` | model | modify | `C-01` | `docs/design/models/core/fct_trip.md` `D-08` | `cd transformation && dbt test --select path:models/marts/core --exclude test_type:unit` |
| `finance.mart_revenue_component_bridge` — `c_residual` and the walk total | model | modify | `C-02` | `docs/design/models/finance/mart_revenue_component_bridge.md` `D-01` | `cd transformation && dbt test --select path:models/marts/finance --exclude test_type:unit` |
| `ops.mart_trip_quality_scorecard` — `unbalanced_total_count` | model | modify | `C-04` | not applicable: no design record exists and no code changes; its values follow `fare_residual`, recorded in the Case record | `cd transformation && dbt test --select path:models/marts/ops --exclude test_type:unit` |
| `contracts/core/fct_trip.odcs.yaml` | contract | modify | `C-05` | `docs/design/models/core/fct_trip.md` `D-08` | `python3 .agents/skills/data-contract/scripts/odcs.py check && python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main` |
| the two canonical reviews of that contract, and `docs/review/` only where a review queues a doubt | contract (review) | create | `C-05` | `docs/design/models/core/fct_trip.md` `D-08`, `docs/design/models/finance/mart_revenue_component_bridge.md` `D-01` | the `validating-data-contract` and `validating-semantic-model` verdicts, with `python3 .agents/skills/data-contract/scripts/odcs.py check --relations --catalog <sandbox db>` and `python3 .agents/skills/data-contract/scripts/odcs.py profile --relation core.fct_trip --catalog <sandbox db>` at exit 0 |

**Change impact:** `core.fct_trip` has nine downstream models in the compiled graph. Two read `fare_residual` and move with it: `finance.mart_revenue_component_bridge` (`c_residual`, and therefore the walk balance) and `ops.mart_trip_quality_scorecard` (`unbalanced_total_count`). The other seven — `agg_od_flow_matrix`, `agg_trip_band_profile`, `agg_trip_zone_daily`, `agg_trip_zone_daypart_dow`, `agg_weather_demand_daily`, `mart_daily_zone_revenue`, `mart_monthly_service_summary` — read other columns and are rebuilt but unchanged. The semantic-layer metric `fare_residual_total` (`SUM(trips.fare_residual)`) returns a smaller value over the same population; its expression, description and binding do not change, so no Ossie document is edited. `contracts/finance/mart_revenue_component_bridge.odcs.yaml` and `contracts/ops/mart_trip_quality_scorecard.odcs.yaml` were checked and are not changed: their declared properties and promises are unchanged, and the data now honours them. No declared external consumer exists on any affected relation (`describe_asset` → `consumers: []`).

## Tasks

### Task 1: the guard that fails today

**Requirements:** `C-03` · **Design:** `docs/design/models/finance/mart_revenue_component_bridge.md` `D-01`, `D-02` · **Skill:** `generating-dbt-model` · **Depends on:** none

- [x] Create `transformation/tests/assert_revenue_walk_balances.sql`: group `finance.mart_revenue_component_bridge` by `trip_month, service_type_key, borough_name`, and return each group where `abs(sum(component_amount) - max(total_amount)) > 0.01`, with the group's `count(*)`, `sum(component_amount)` and `max(total_amount)` as the evidence columns. Comment why: the residual and the walk share one component list, and a component published on its own line but not subtracted in the residual makes the walk overshoot.
- [x] Add `"data": ["transformation/tests/assert_revenue_walk_balances.sql"]` to the `finance` module of `test-map.json`, so the map keeps naming the tests that protect each layer.
- [x] Run `cd transformation && dbt deps`, then `cd transformation && dbt build --select mart_revenue_component_bridge` and `cd transformation && dbt test --select assert_revenue_walk_balances`; expect the test to **fail with 9 rows**, and record the row count and the summed gap (`12,262.25`).
- [x] Commit and push both files.

### Task 2: subtract the airport fee in the residual, and rebuild the fact

**Requirements:** `C-01` · **Design:** `code is contract` (the macro), `docs/design/models/core/fct_trip.md` `D-08` · **Skill:** `generating-dbt-model` · **Depends on:** Task 1

- [x] In `transformation/macros/finance.sql`, subtract `- coalesce({{ alias }}.airport_fee, 0)` in `fare_residual`, after the tolls term and before `total_surcharges`, and extend the macro's comment to say the residual subtracts every component the walk publishes. Do **not** add the fee to `surcharge_columns()`: that macro feeds `total_surcharges`, a separate published column this case does not ask to move.
- [x] In `transformation/models/docs.md`, correct the `fare_residual` doc block so its component list names the airport fee and no longer describes the defect.
- [x] Run `cd transformation && dbt build --full-refresh --select +fct_trip`; expect a successful build of the fact and its tests. The selection carries the `+`: the residual reaches the fact through `int_trip_fare_components`, a view, and `--select fct_trip` alone leaves that view holding its pre-fix definition, so the full refresh re-reads the old residual and still exits 0. (Corrected during execution from `--select fct_trip` after the acceptance probe caught it.)
- [x] Run `cd transformation && dbt test --select path:models/marts/core --exclude test_type:unit`; expect every core data test to pass.
- [x] Re-run `cd transformation && dbt test --select assert_revenue_walk_balances`; expect it still to fail — the bridge table has not been rebuilt yet — and say so rather than treating it as a regression.
- [x] Commit and push the macro and the doc block.

### Task 3: rebuild the consumers and prove the walk balances

**Requirements:** `C-02`, `C-03`, `C-04` · **Design:** `docs/design/models/finance/mart_revenue_component_bridge.md` `D-01` · **Skill:** `generating-dbt-model` · **Depends on:** Task 2

- [x] Run `cd transformation && dbt build --select fct_trip+`; expect a successful build of every downstream model and every test under it, including `assert_revenue_walk_balances` now returning no rows.
- [x] Run `cd transformation && dbt test --select path:models/marts/finance --exclude test_type:unit` and `cd transformation && dbt test --select path:models/marts/ops --exclude test_type:unit`; expect both to pass.
- [x] Confirm `C-01`, `C-02` and `C-04` with probes against the sandbox, independent of the tests: the billable residual totals `−32,638.75` at the cent; the walk's nine lines total `2,629,185.82` at the cent and equal `SUM(total_amount)` over billable in-window trips; `unbalanced_total_count` totals `26,457` across the scorecard's groups. Record each figure.
- [x] Commit and push any file this task touched (the sandbox build alone changes nothing in the repository).

### Task 4: the contract version and the project gates

**Requirements:** `C-05` · **Design:** `docs/design/models/core/fct_trip.md` `D-08` · **Skill:** `data-contract` · **Depends on:** Task 3

- [x] In `contracts/core/fct_trip.odcs.yaml`, move `version` from `1.1.0` to `2.0.0`. Change no property: `fare_residual` keeps its name, `logicalType: number` and `physicalType: DOUBLE`. The major bump is the signal that a consumer's stored values are stale, not a shape change.
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate`, then `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0.
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main`; expect exit 0 and no `diff/version-not-bumped`.
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py check --relations`; expect exit 0, or record the exact refusal code if it cannot read the built relations.
- [x] Run the repository's pre-push gates: `python3 -m pytest tests -q`, `ruff check .`, `sqlfluff lint transformation/models`, `cd transformation && dbt test --exclude test_type:unit`, `cd transformation && dbt test --select test_type:unit`; expect exit 0 from each, and record each exit code.
- [x] Commit and push the contract together with any file `generate` rewrote.
- [ ] Run the two canonical reviews of that contract and record their verdicts. First `validating-data-contract` over `contracts/core/fct_trip.odcs.yaml` and every contract that declares a key it declares, with the dynamic gates handed the sandbox database so they run instead of refusing: `python3 .agents/skills/data-contract/scripts/odcs.py check --relations --catalog /data/ephm_duckdb/ephm_nyc-taxi-duckdb-100k_r7-revenue-walk-fix-1482da4f.duckdb` and `python3 .agents/skills/data-contract/scripts/odcs.py profile --relation core.fct_trip --catalog /data/ephm_duckdb/ephm_nyc-taxi-duckdb-100k_r7-revenue-walk-fix-1482da4f.duckdb` (that path is the `VD_EPHM_DUCKDB_LOCAL_PATH` setting, read through `get_intent_context`, never echoed through the shell); expect both exit 0, every `profile/unchecked` warning carried as unproven, and each doubt the data and the business cannot settle queued in `docs/review/`. Then `validating-semantic-model` over `logical-model/`, with `validate`, `coverage`, `suppliers`, `notes` and `generate-tests --check` re-run at exit 0 and its verdict recorded. A defect either review finds goes back to `data-contract` or `semantic-model`, which re-runs its gates.
- [ ] Reopened by the Verification at `2c3317b`, whose Coverage rows for the data-contract and semantic-model canonical gates read `uncovered`: the contract was committed at `2c6dc81` without the review `data-contract` step 9 requires before commit, and no `validating-semantic-model` report exists in this intent. Every line above stands — the contract, its version and its gates are all green — and this task ends when both verdicts are recorded in `## Execution evidence`.

## Execution evidence

- Task 1: `cd transformation && dbt deps` — exit 0 — `dbt_packages/` installed (`dbt_project_evaluator` 1.4.1)
- Task 1: `cd transformation && dbt compile --select assert_revenue_walk_balances --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — resolves `"finance"."mart_revenue_component_bridge"`, no catalog named
- Task 1: `cd transformation && dbt build --select mart_revenue_component_bridge --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0, `PASS=2 WARN=0 ERROR=1 SKIP=0 NO-OP=0 REUSED=0 TOTAL=3` — the 1 error is the intended pre-fix failure: `assert_revenue_walk_balances ... [FAIL 9]`, `Got 9 results, configured to fail if != 0`
- Task 1: `python /data/default-plugins/vibedata-data-engineering/0.148.26/scripts/assert_dbt_destination.py` — exit 0 — `DESTINATION_OK: 1 built relation(s) landed in the sandbox ephm_nyc-taxi-duckdb-100k_r7-revenue-walk-fix-1482da4f`
- Task 1: `python /data/default-plugins/vibedata-data-engineering/0.148.26/scripts/ephemeral_workspace_marker.py init` — exit 0 — `{"status": "created"}`
- Task 1: pre-fix failing rows, sandbox probe — `select count(*) as failing_groups, round(sum(component_sum - total_amount), 2) as total_gap from (select trip_month, service_type_key, borough_name, sum(component_amount) as component_sum, max(total_amount) as total_amount from finance.mart_revenue_component_bridge group by 1,2,3 having abs(sum(component_amount) - max(total_amount)) > 0.01)` → `9 | 12262.25`
- Task 1: profiling verdict — `finance.mart_revenue_component_bridge` `Ready`, read in the Verification's `## Discovery` (44 groups, 9 out of balance by `12,262.25` pre-fix)
- Task 1: `transformation/tests/assert_revenue_walk_balances.sql` — sha256:7912a7b2df6bcb0bfbe17bd468ad85b23c5759954172cb3a0d36f33a286f098d
- Task 1: `test-map.json` — sha256:245dc6ddeed34c16a77b1083cbf494ced29c713d864d228126afe9c5ab66c7e5
- Task 2: `cd transformation && dbt compile --select int_trip_fare_components --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — the compiled residual is `coalesce(t.total_amount, 0) - … - coalesce(t.tolls_amount, 0) - coalesce(t.airport_fee, 0) - (coalesce(t.extra, 0) + …)`
- Task 2: `cd transformation && dbt build --full-refresh --select fct_trip --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0, `PASS=16 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=16` — **insufficient gate**: the sandbox probe after it still read `billable_residual = -20376.5`, because `int_trip_fare_components` is a view and `--select fct_trip` does not re-create it
- Task 2: `cd transformation && dbt build --full-refresh --select +fct_trip --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0, `PASS=99 WARN=1 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=100` — the warning is the pre-existing `assert_semantic_levels_hold` sentinel-borough warning
- Task 2: `python /data/default-plugins/vibedata-data-engineering/0.148.26/scripts/assert_dbt_destination.py` — exit 0 — `DESTINATION_OK: 22 built relation(s) landed in the sandbox`
- Task 2: `python /data/default-plugins/vibedata-data-engineering/0.148.26/scripts/ephemeral_workspace_marker.py init` — exit 0 — `{"status": "exists"}`
- Task 2: `cd transformation && dbt test --select path:models/marts/core --exclude test_type:unit` — exit 0, `PASS=74 WARN=1 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=75`
- Task 2: `cd transformation && dbt test --select assert_revenue_walk_balances` — exit 0 with `ERROR=1`, `Got 9 results` — expected: the bridge table is still the pre-fix build
- Task 2: acceptance `C-01`, sandbox probe — `select round(sum(fare_residual), 2) as billable_residual, count(*) filter (where abs(fare_residual - (total_amount - coalesce(fare_amount,0) - coalesce(tip_amount,0) - coalesce(tolls_amount,0) - coalesce(extra,0) - coalesce(mta_tax,0) - coalesce(improvement_surcharge,0) - coalesce(congestion_surcharge,0) - coalesce(airport_fee,0))) > 0.01) as residuals_off_definition, count(*) as billable_trips, round(sum(coalesce(airport_fee,0)), 2) as airport_fee from core.fct_trip where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'` → `-32638.75 | 0 | 95958 | 12262.25`
- Task 2: `transformation/macros/finance.sql` — sha256:ab3fed5755d46401f92a0247875b6b3ea3edd72fc49870a3f665b732b67ab617
- Task 2: `transformation/models/docs.md` — sha256:1b6394586f767cf65ed60c3dad4ed8a885e9471382178d80ae7b0a1c6fa2a8ba
- Task 3: `cd transformation && dbt build --select fct_trip+ --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0, `PASS=36 WARN=1 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=37`; `target/run_results.json` records `test.nyc_taxi_analytics.assert_revenue_walk_balances pass 0` and `model.nyc_taxi_analytics.mart_revenue_component_bridge success`
- Task 3: `python /data/default-plugins/vibedata-data-engineering/0.148.26/scripts/assert_dbt_destination.py` — exit 0 — `DESTINATION_OK: 10 built relation(s) landed in the sandbox`
- Task 3: `python /data/default-plugins/vibedata-data-engineering/0.148.26/scripts/ephemeral_workspace_marker.py init` — exit 0 — `{"status": "exists"}`
- Task 3: `cd transformation && dbt test --select path:models/marts/finance --exclude test_type:unit` — exit 0, `PASS=8 WARN=1 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=9`
- Task 3: `cd transformation && dbt test --select path:models/marts/ops --exclude test_type:unit` — exit 0, `PASS=7 WARN=1 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=8`
- Task 3: acceptance `C-01`, `C-02`, `C-04`, sandbox probe — `select (select round(sum(component_amount), 2) from finance.mart_revenue_component_bridge) as walk_total, (select round(sum(total_amount), 2) from core.fct_trip where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01') as billable_revenue, (select count(*) from (select trip_month, service_type_key, borough_name from finance.mart_revenue_component_bridge group by 1,2,3 having abs(sum(component_amount) - max(total_amount)) > 0.01)) as groups_unbalanced, (select round(sum(component_amount), 2) from finance.mart_revenue_component_bridge where component_name = 'c_residual') as walk_residual, (select sum(unbalanced_total_count) from ops.mart_trip_quality_scorecard) as unbalanced_total_count` → `2629185.82 | 2629185.82 | 0 | -32638.75 | 26457`
- Task 4: `contracts/core/fct_trip.odcs.yaml` — `version` moved `1.1.0` → `2.0.0`, no property touched; `grep -n version:` reads `5:version: 2.0.0`; sha256:8b216f845effd751668c74c60494e26cffa7d0ea981c7f476fc7c64c5ac4e192
- Task 4: `python3 .agents/skills/data-contract/scripts/odcs.py generate` — exit 0
- Task 4: `python3 .agents/skills/data-contract/scripts/odcs.py check` — exit 0 — no `contract/active-unbuilt` for `core.fct_trip` (the two `agg.agg_driver_*` warnings this step surfaced earlier are pre-existing: neither model is built in the sandbox and neither is touched by this change)
- Task 4: `python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main` — exit 0, no `diff/version-not-bumped`
- Task 4: `python3 .agents/skills/data-contract/scripts/odcs.py check --relations` — **exit 1**, `catalog/missing`: "relations: no Intent context names a warehouse; pass `--catalog` with the built local database file or dbt's catalog.json" — the gate cannot read the built relations without being handed a catalog
- Task 4: `cd transformation && dbt docs generate` — exit 0 — `Catalog written to /workspace/transformation/target/catalog.json`
- Task 4: `python3 .agents/skills/data-contract/scripts/odcs.py check --relations --catalog transformation/target/catalog.json` — exit 1 — `core.fct_trip` is **not** among the findings, so the relation this change touches matches its contract; the 6 errors are `relations/mismatch` on `bronze|mdm_raw|ops_raw.audit_runs` and `.audit_table_loads`, all "the catalog holds no such relation". Pre-existing and outside this change: those six relations are dlt inputs (they exist in the sandbox — `information_schema.tables` lists all 6), and dbt's `catalog.json` only ever covers dbt-built relations. Reported to the user, not fixed here.
- Task 4: `python3 -m pytest tests -q` — exit 0 — `222 passed in 164.98s`
- Task 4: `ruff check .` — exit 0 — `All checks passed!`
- Task 4: `sqlfluff lint transformation/models` — exit 0 — `All Finished!`
- Task 4: `cd transformation && dbt test --exclude test_type:unit` — exit 0 — `PASS=166 WARN=1 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=167` — the warning is the pre-existing `assert_semantic_levels_hold`
- Task 4: `cd transformation && dbt test --select test_type:unit` — exit 0 — `PASS=6 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=6`

