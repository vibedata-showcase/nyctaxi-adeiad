# Plan: R9 · revenue walk fix

**Goal:** make the nine components of `finance.mart_revenue_component_bridge` sum to its own `total_amount`, by taking the airport fee out of the residual that already contains it.

**Requirement:** `docs/cases/2026-11-24-revenue-walk-double-counts-airport-fee-ca72c1e0.md` (fix case; design approved 2026-11-24T10:23:43Z at `5a96869`).

**Constraints:**

- `CONTEXT.md`: a fare component is "the fare itself, tip, tolls, taxes and surcharges"; the residual is what is left of the total "after every modelled fare component". The airport fee is a modelled component, so it leaves the residual.
- `total_surcharges` and `surcharge_columns()` do not change: four published measures this case did not find wrong read them.
- The bridge's shape does not change: same nine components, same columns, same grain, same rows. No column is added, removed or retyped, so no contract version moves for a shape reason.
- `mart_revenue_component_bridge` is `contract: enforced` and sits in `repo-map.json` `semantic_exclusions`. `odcs.py generate` owns `data_type`, `data_tests`, `contract.enforced` and the dbt `description` on it: edit the contract, never the generated description. A prose-only contract edit is a patch version.
- `fct_trip` is incremental by `trip_key` over a closed window, so the correction reaches Q1 only through a full refresh; select `fct_trip+`, because rebuilding the fact alone leaves the downstream relations reading the replaced one.
- No `--defer`, and `/data/cache` is not read: no production manifest is published. `Baseline build_sha:` none.
- Money is compared at the cent: DuckDB double aggregation is not bit-reproducible.
- Singular tests live in `transformation/tests/`, are named `assert_<what_must_hold>.sql`, and return the rows that violate the assertion.
- SQL: lowercase keywords, one clause per line beyond a trivial select, lines up to 120 characters.
- Writes go to the Intent's sandbox only; the Domain database stays read-only. Governance: DuckDB has no row filters or masks, so that check is `not applicable`.
- `dbt deps` runs in `transformation/` before the session's first dbt command.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `transformation/tests/assert_revenue_bridge_components_sum_to_total.sql` | model (dbt singular test) | create | the case's decision | `docs/design/models/finance/mart_revenue_component_bridge.md` (`D-03`) | `cd transformation && dbt test --select assert_revenue_bridge_components_sum_to_total` |
| `test-map.json` | project-config | modify | the case's decision | `code is contract` | `python3 -m pytest tests/test_maps.py -q` |
| `transformation/macros/finance.sql` | macro | modify | the case's decision | `docs/design/models/core/fct_trip.md` (`D-08`), `docs/design/models/finance/mart_revenue_component_bridge.md` (`D-03`) | `cd transformation && dbt build --full-refresh --select fct_trip+` |
| `transformation/models/docs.md` | project-config | modify | the case's decision | `docs/design/models/core/fct_trip.md` (`D-08`) | `cd transformation && dbt parse` |
| `contracts/finance/mart_revenue_component_bridge.odcs.yaml` | contract | modify | the case's decision | `docs/design/models/finance/mart_revenue_component_bridge.md` (`D-02`) | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `transformation/models/marts/finance/_finance.yml` | project-config | modify (by `odcs.py generate`) | the case's decision | `docs/design/models/finance/mart_revenue_component_bridge.md` (`D-02`) | `python3 .agents/skills/data-contract/scripts/odcs.py generate` then `git diff` |
| `transformation/models/marts/finance/mart_revenue_component_bridge.sql` | model | modify (header comment only) | the case's decision | `docs/design/models/finance/mart_revenue_component_bridge.md` (`D-03`) | `cd transformation && dbt build --full-refresh --select fct_trip+` |

**Change impact:** `core.fct_trip.fare_residual` (published, `contract: enforced`) changes value on 5,412 in-window trips; through it `finance.mart_revenue_component_bridge` (`c_residual`, `component_share`), the canonical metric `fare_residual_total`, and `ops.mart_trip_quality_scorecard.unbalanced_total_count` (31,869 → 26,457). `mart_daily_zone_revenue`, `mart_monthly_service_summary`, `agg_trip_zone_daypart_dow` and `int_shift_economics` read `total_surcharges` and are untouched; the remaining aggregates do not read the residual. No consumer outside this repository is declared.

## Tasks

### Task 1: the balance test, failing first

**Requirements:** the case's decision · **Design:** `docs/design/models/finance/mart_revenue_component_bridge.md` · **Skill:** `generating-dbt-model` · **Depends on:** none

- [x] Author `transformation/tests/assert_revenue_bridge_components_sum_to_total.sql`: group `mart_revenue_component_bridge` by `trip_month`, `service_type_key`, `borough_name`, take `max(total_amount)` once per group and `sum(component_amount)`, and return every group where `abs(component_total - total_amount) > 0.01`. A comment says why the total is read once per group. No unit test is needed: the macro this guards has no branch, only arithmetic.
- [x] Add the test to `test-map.json` under `modules.finance.data`.
- [x] Run `cd transformation && dbt deps`, then `dbt test --select assert_revenue_bridge_components_sum_to_total`; expect **FAIL** reporting the groups whose components miss their total by the airport fee — it fails on **9** groups totalling 12,262.25 (the case's 44 groups is the whole walk; only the ones carrying a fee can miss).
- [x] Run `python3 -m pytest tests/test_maps.py -q`; expect exit 0.
- [x] Commit and push `transformation/tests/assert_revenue_bridge_components_sum_to_total.sql` and `test-map.json`.

### Task 2: take the airport fee out of the residual

**Requirements:** the case's decision · **Design:** `docs/design/models/core/fct_trip.md` (`D-08`), `docs/design/models/finance/mart_revenue_component_bridge.md` (`D-03`) · **Skill:** `generating-dbt-model` · **Depends on:** Task 1

- [x] In `transformation/macros/finance.sql`, subtract `coalesce({{ alias }}.airport_fee, 0)` inside `fare_residual`, after `total_surcharges`. Leave `surcharge_columns()` and `total_surcharges` untouched. Adjust the macro's own comment to say why the fee is subtracted here rather than folded into the surcharge list.
- [x] In `transformation/models/docs.md`, add the airport fee to the components the `fare_residual` doc block names.
- [x] Run `cd transformation && dbt deps && dbt build --full-refresh --select +fct_trip+`; expect every selected model and test to pass, including Task 1's test. The ancestry is required: `int_trip_fare_components` is a view that holds the macro's compiled SQL, so selecting `fct_trip+` alone rebuilt the fact from the stale view and left the test failing on the same 9 groups.
- [x] Run the case's reconciliation against the sandbox (`select trip_month, sum(case when component_name = 'c_fare' then total_amount else 0 end) as walk_total, sum(component_amount) as component_sum, sum(case when component_name = 'c_airport_fee' then component_amount else 0 end) as airport_fee, sum(case when component_name = 'c_residual' then component_amount else 0 end) as residual from finance.mart_revenue_component_bridge group by 1 order by 1`); expect `component_sum = walk_total` per month (2,629,185.82 in total), and the residual to be each month's old value minus that month's fee: −12,848.50, −11,481.50, −8,308.75.
- [x] Run `cd transformation && dbt test --select path:models/marts/core,path:models/marts/finance,path:models/marts/ops --exclude test_type:unit`; expect exit 0.
- [x] Commit and push `transformation/macros/finance.sql` and `transformation/models/docs.md`.

### Task 3: the prose the change falsifies, and the project gates

**Requirements:** the case's decision · **Design:** `docs/design/models/finance/mart_revenue_component_bridge.md` (`D-02`) · **Skill:** `generating-dbt-model` · **Depends on:** Task 2

- [x] In `contracts/finance/mart_revenue_component_bridge.odcs.yaml`, make `dataGranularityDescription` say what holds after the fix: the residual is its own component, and a non-zero residual means the total is not the sum of its modelled parts — not that the walk fails to balance. Bump `version` `1.0.1` → `1.0.2` (prose is a patch).
- [x] Rewrite the header comment in `transformation/models/marts/finance/mart_revenue_component_bridge.sql` to the same claim; change no SQL.
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate`, then `git diff --stat`: expect `transformation/models/marts/finance/_finance.yml` to follow the contract and nothing else to move; if another file moves, revert that file and report it rather than keeping the churn.
- [x] Run `cd transformation && dbt build --full-refresh --select fct_trip+` again so the rebuilt `_finance.yml` description is on the table, then `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0.
- [x] Run the project gates: `python3 -m pytest tests -q`, `ruff check .`, `sqlfluff lint transformation/models`, `cd transformation && dbt test --exclude test_type:unit`, `cd transformation && dbt test --select test_type:unit`, `python3 .github/scripts/adr_lint.py`, `python3 tools/ossie_lint.py`, `python3 .agents/skills/data-contract/scripts/odcs.py check --relations --catalog /data/ephm_duckdb/ephm_nyc-taxi-duckdb-100k_r9-revenue-walk-fix-ca72c1e0.duckdb`; expect exit 0 from each, and record each code.
- [x] Commit and push the contract, the model comment and whatever `generate` rewrote.

## Execution evidence
- Task 1: `cd transformation && dbt deps` — exit 0 — packages installed (dbt_project_evaluator 1.4.1, up to date)
- Task 1: `cd transformation && dbt test --target dev --select assert_revenue_bridge_components_sum_to_total --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 with `ERROR=1`, `Got 9 results, configured to fail if != 0` — the intended failure before the fix. The 9 groups are three months x {Manhattan, Queens, Unknown}, differences 5.25/3984.75/7.00, 3.50/3543.75/3.50, 1.75/4705.75/7.00, summing to 12,262.25. `lakehouse_query` on ephemeral lists them (`finance.mart_revenue_component_bridge`, target `ephemeral`).
- Task 1: `python3 -m pytest tests/test_maps.py -q` — exit 0 — `30 passed in 54.80s`
- Task 1: profiling verdicts — `core.fct_trip` **Ready** (`domain`; declared: boundary layer, design record `docs/design/models/core/fct_trip.md`; 95,958 billable in-window trips, `fare_residual` and `airport_fee` DOUBLE, residual equals the fee on 5,942 of 7,184 fee trips) and `core.dim_zone` **Ready** (`domain`; 0 billable in-window trips without a zone key, so the bridge's inner join covers the fact). No relation unprofiled; `BRONZE_INADEQUATE` not reached.
- Task 1: `transformation/tests/assert_revenue_bridge_components_sum_to_total.sql` — sha256:161136529d3154ce9a4b472889d437c7eaee22025dabd3c8cf6a9bc753126320
- Task 2: `cd transformation && dbt build --target dev --full-refresh --select fct_trip+ --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 with `ERROR=1` — the balance test still failed on the same 9 groups. Cause, read from the database: `information_schema.tables` shows `intermediate.int_trip_fare_components` as `VIEW`, which stores the macro's compiled SQL, and it is upstream of `fct_trip`, so the selection never rebuilt it.
- Task 2: `cd transformation && dbt build --target dev --full-refresh --select +fct_trip+ --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — `PASS=117 WARN=1 ERROR=0`: 1 incremental model, 14 table models, 15 view models, 1 seed, 84 data tests and 3 unit tests in 15.48s. The one warning is `assert_semantic_levels_hold`, which warns by config over 91 `agg_weather_demand_daily` rows whose borough is the `unresolved` sentinel; it reads no fare column, and the semantic model's own LTS5 note records it.
- Task 2: `assert_dbt_destination.py` from the generating-dbt-model plugin scripts — exit 0 — `DESTINATION_OK: 31 built relation(s) landed in the sandbox`; `ephemeral_workspace_marker.py init` — exit 0 — `{"status": "created"}`.
- Task 2: reconciliation on `ephemeral` with the case's query — `walk_total` equals `component_sum` in each month, gap `-0.0` at 6 dp; totals 816,057.76, 813,885.68 and 999,242.38, i.e. 2,629,185.82; `c_airport_fee` 3,997.00, 3,550.75 and 4,714.50 unchanged; `c_residual` -12,848.50, -11,481.50 and -8,308.75, each the old value minus that month's fee.
- Task 2: cross-check on `ephemeral` — `billable_revenue` 2,629,185.82, unchanged; `ops.mart_trip_quality_scorecard.unbalanced_total_count` 26,457, equal to the fact's unbalanced trip count, as the case predicted (31,869 to 26,457).
- Task 2: `cd transformation && dbt test --target dev --select path:models/marts/core path:models/marts/finance path:models/marts/ops --exclude test_type:unit --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — `PASS=86 WARN=1 ERROR=0`, the same pre-existing warning.
- Task 2: `cd transformation && dbt docs generate --static --target dev` — exit 0; static index published to the Intent docs bind, catalog written to `transformation/target/catalog.json`.
- Task 2: sha256 84c93403dec854e6a193f9f7050cb9033b95be06f273913ea59d5229e6ac41f1 for `transformation/macros/finance.sql`; sha256 41d1d9b1c0e30b595669b262cb22e4428317a8d03d150ad0a8cb1dbd2ea61566 for `transformation/models/docs.md`
- Task 3: contract prose corrected and `version` moved 1.0.1 to 1.0.2 in `contracts/finance/mart_revenue_component_bridge.odcs.yaml`; the same claim written into the model header comment. `python3 .agents/skills/data-contract/scripts/odcs.py generate` — exit 0 — output `[]`, and `git diff --stat` shows only the files this task edited, so the model-level `description` in `_finance.yml` is hand-written: `generate` returned no change for it and left the corrected text in place (it owns the column descriptions, not the relation description).
- Task 3: `cd transformation && dbt build --target dev --select mart_revenue_component_bridge --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — `PASS=3 WARN=0 ERROR=0`; `assert_dbt_destination.py` — exit 0 — `DESTINATION_OK: 1 built relation(s)`; marker `exists`.
- Task 3: `cd transformation && dbt build --target dev` — exit 0 — `PASS=239 WARN=1 ERROR=0` over 67 relations; `assert_dbt_destination.py` — exit 0 — `DESTINATION_OK: 67 built relation(s) landed in the sandbox`. The one warning is the pre-existing `assert_semantic_levels_hold` sentinel case.
- Task 3: `python3 .agents/skills/data-contract/scripts/odcs.py check` — exit 0 — 3 findings, all `boundary/excluded` info for the three declared semantic exclusions and no warning. Run against the last dbt invocation, so a full `dbt build` has to precede it: after a partial build `check` reports `contract/active-unbuilt` for every relation.
- Task 3: `python3 .agents/skills/data-contract/scripts/odcs.py check --relations --catalog /data/ephm_duckdb/ephm_nyc-taxi-duckdb-100k_r9-revenue-walk-fix-ca72c1e0.duckdb` — exit 0 — the same 3 info findings, no `relations/mismatch`.
- Task 3: `cd transformation && dbt test --target dev --exclude test_type:unit` — exit 0 — `PASS=166 WARN=1 ERROR=0`; `dbt test --target dev --select test_type:unit` — exit 0 — `PASS=6 WARN=0 ERROR=0`.
- Task 3: `python3 -m pytest tests -q` — first run exit 0 with `1 failed, 221 passed`: `tests/test_adr_links.py::test_every_cited_adr_lists_the_record` failed because the new bridge design record cites ADR 0003, which did not list it. Fixed by adding the record to ADR 0003's `## Affected designs` (a back-link only; no decision text changed). Re-run — exit 0 — `222 passed in 171.77s`.
- Task 3: `ruff check .` — exit 0 — `All checks passed!`; `sqlfluff lint transformation/models` — exit 0 — `All Finished!`; `python3 .github/scripts/adr_lint.py` — exit 0 — no duplicate numbers, no dangling references; `python3 tools/ossie_lint.py` — exit 0 — 0 blocking findings.
- Task 3: semantic layer carried with the commit — `ossie.py validate logical-model/` exit 0; `ossie.py coverage ...` exit 0 (bridge reported `excluded from coverage`, as declared); `ossie.py generate-tests logical-model/ transformation/tests --check` exit 0 — `3 generated test(s), 0 stale`. No Ossie document changed: the bridge is excluded from the canonical model and `fare_residual_total`'s definition ("Trip total minus every modelled fare component, summed") is what the corrected column now computes.
- Task 3: sha256 96b9064c132fefd37a49ae0513e593bc51e70d5e2764bcf0c938b6ad81005af5 for `contracts/finance/mart_revenue_component_bridge.odcs.yaml`; sha256 00451a219baab616e7181a5b148e97b6d36f4d289f0f63f5cf79c0e2555fe1ce for `transformation/models/marts/finance/mart_revenue_component_bridge.sql`; sha256 3a6ed79738f926cc94aa03f2f75d64795b0b80a6c35974204ebcbb2fd9aec844 for `transformation/models/marts/finance/_finance.yml`; sha256 8d2825ce39e46bd8ad87af1485c4fab1a6a0cd9d9edddeb81f1c32b3b6a0c7aa for `docs/adr/0003-billable-trip-definition-and-where-it-applies.md`
