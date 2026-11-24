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

**Change impact:** `core.fct_trip` has nine downstream models in the compiled graph. Two read `fare_residual` and move with it: `finance.mart_revenue_component_bridge` (`c_residual`, and therefore the walk balance) and `ops.mart_trip_quality_scorecard` (`unbalanced_total_count`). The other seven — `agg_od_flow_matrix`, `agg_trip_band_profile`, `agg_trip_zone_daily`, `agg_trip_zone_daypart_dow`, `agg_weather_demand_daily`, `mart_daily_zone_revenue`, `mart_monthly_service_summary` — read other columns and are rebuilt but unchanged. The semantic-layer metric `fare_residual_total` (`SUM(trips.fare_residual)`) returns a smaller value over the same population; its expression, description and binding do not change, so no Ossie document is edited. `contracts/finance/mart_revenue_component_bridge.odcs.yaml` and `contracts/ops/mart_trip_quality_scorecard.odcs.yaml` were checked and are not changed: their declared properties and promises are unchanged, and the data now honours them. No declared external consumer exists on any affected relation (`describe_asset` → `consumers: []`).

## Tasks

### Task 1: the guard that fails today

**Requirements:** `C-03` · **Design:** `docs/design/models/finance/mart_revenue_component_bridge.md` `D-01`, `D-02` · **Skill:** `generating-dbt-model` · **Depends on:** none

- [ ] Create `transformation/tests/assert_revenue_walk_balances.sql`: group `finance.mart_revenue_component_bridge` by `trip_month, service_type_key, borough_name`, and return each group where `abs(sum(component_amount) - max(total_amount)) > 0.01`, with the group's `count(*)`, `sum(component_amount)` and `max(total_amount)` as the evidence columns. Comment why: the residual and the walk share one component list, and a component published on its own line but not subtracted in the residual makes the walk overshoot.
- [ ] Add `"data": ["transformation/tests/assert_revenue_walk_balances.sql"]` to the `finance` module of `test-map.json`, so the map keeps naming the tests that protect each layer.
- [ ] Run `cd transformation && dbt deps`, then `cd transformation && dbt build --select mart_revenue_component_bridge` and `cd transformation && dbt test --select assert_revenue_walk_balances`; expect the test to **fail with 9 rows**, and record the row count and the summed gap (`12,262.25`).
- [ ] Commit and push both files.

### Task 2: subtract the airport fee in the residual, and rebuild the fact

**Requirements:** `C-01` · **Design:** `code is contract` (the macro), `docs/design/models/core/fct_trip.md` `D-08` · **Skill:** `generating-dbt-model` · **Depends on:** Task 1

- [ ] In `transformation/macros/finance.sql`, subtract `- coalesce({{ alias }}.airport_fee, 0)` in `fare_residual`, after the tolls term and before `total_surcharges`, and extend the macro's comment to say the residual subtracts every component the walk publishes. Do **not** add the fee to `surcharge_columns()`: that macro feeds `total_surcharges`, a separate published column this case does not ask to move.
- [ ] In `transformation/models/docs.md`, correct the `fare_residual` doc block so its component list names the airport fee and no longer describes the defect.
- [ ] Run `cd transformation && dbt build --full-refresh --select fct_trip`; expect a successful build of the fact and its tests.
- [ ] Run `cd transformation && dbt test --select path:models/marts/core --exclude test_type:unit`; expect every core data test to pass.
- [ ] Re-run `cd transformation && dbt test --select assert_revenue_walk_balances`; expect it still to fail — the bridge table has not been rebuilt yet — and say so rather than treating it as a regression.
- [ ] Commit and push the macro and the doc block.

### Task 3: rebuild the consumers and prove the walk balances

**Requirements:** `C-02`, `C-03`, `C-04` · **Design:** `docs/design/models/finance/mart_revenue_component_bridge.md` `D-01` · **Skill:** `generating-dbt-model` · **Depends on:** Task 2

- [ ] Run `cd transformation && dbt build --select fct_trip+`; expect a successful build of every downstream model and every test under it, including `assert_revenue_walk_balances` now returning no rows.
- [ ] Run `cd transformation && dbt test --select path:models/marts/finance --exclude test_type:unit` and `cd transformation && dbt test --select path:models/marts/ops --exclude test_type:unit`; expect both to pass.
- [ ] Confirm `C-01`, `C-02` and `C-04` with probes against the sandbox, independent of the tests: the billable residual totals `−32,638.75` at the cent; the walk's nine lines total `2,629,185.82` at the cent and equal `SUM(total_amount)` over billable in-window trips; `unbalanced_total_count` totals `26,457` across the scorecard's groups. Record each figure.
- [ ] Commit and push any file this task touched (the sandbox build alone changes nothing in the repository).

### Task 4: the contract version and the project gates

**Requirements:** `C-05` · **Design:** `docs/design/models/core/fct_trip.md` `D-08` · **Skill:** `data-contract` · **Depends on:** Task 3

- [ ] In `contracts/core/fct_trip.odcs.yaml`, move `version` from `1.1.0` to `2.0.0`. Change no property: `fare_residual` keeps its name, `logicalType: number` and `physicalType: DOUBLE`. The major bump is the signal that a consumer's stored values are stale, not a shape change.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate`, then `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main`; expect exit 0 and no `diff/version-not-bumped`.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check --relations`; expect exit 0, or record the exact refusal code if it cannot read the built relations.
- [ ] Run the repository's pre-push gates: `python3 -m pytest tests -q`, `ruff check .`, `sqlfluff lint transformation/models`, `cd transformation && dbt test --exclude test_type:unit`, `cd transformation && dbt test --select test_type:unit`; expect exit 0 from each, and record each exit code.
- [ ] Commit and push the contract together with any file `generate` rewrote.

## Execution evidence
