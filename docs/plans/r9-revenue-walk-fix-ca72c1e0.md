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

- [ ] Author `transformation/tests/assert_revenue_bridge_components_sum_to_total.sql`: group `mart_revenue_component_bridge` by `trip_month`, `service_type_key`, `borough_name`, take `max(total_amount)` once per group and `sum(component_amount)`, and return every group where `abs(component_total - total_amount) > 0.01`. A comment says why the total is read once per group. No unit test is needed: the macro this guards has no branch, only arithmetic.
- [ ] Add the test to `test-map.json` under `modules.finance.data`.
- [ ] Run `cd transformation && dbt deps`, then `dbt test --select assert_revenue_bridge_components_sum_to_total`; expect **FAIL** reporting the 44 groups whose components miss their total by the airport fee — the signal recorded in the case.
- [ ] Run `python3 -m pytest tests/test_maps.py -q`; expect exit 0.
- [ ] Commit and push `transformation/tests/assert_revenue_bridge_components_sum_to_total.sql` and `test-map.json`.

### Task 2: take the airport fee out of the residual

**Requirements:** the case's decision · **Design:** `docs/design/models/core/fct_trip.md` (`D-08`), `docs/design/models/finance/mart_revenue_component_bridge.md` (`D-03`) · **Skill:** `generating-dbt-model` · **Depends on:** Task 1

- [ ] In `transformation/macros/finance.sql`, subtract `coalesce({{ alias }}.airport_fee, 0)` inside `fare_residual`, after `total_surcharges`. Leave `surcharge_columns()` and `total_surcharges` untouched. Adjust the macro's own comment to say why the fee is subtracted here rather than folded into the surcharge list.
- [ ] In `transformation/models/docs.md`, add the airport fee to the components the `fare_residual` doc block names.
- [ ] Run `cd transformation && dbt deps && dbt build --full-refresh --select fct_trip+`; expect every selected model and test to pass, including Task 1's test.
- [ ] Run the case's reconciliation against the sandbox (`select trip_month, sum(case when component_name = 'c_fare' then total_amount else 0 end) as walk_total, sum(component_amount) as component_sum, sum(case when component_name = 'c_airport_fee' then component_amount else 0 end) as airport_fee, sum(case when component_name = 'c_residual' then component_amount else 0 end) as residual from finance.mart_revenue_component_bridge group by 1 order by 1`); expect `component_sum = walk_total` per month (2,629,185.82 in total), and the residual to be each month's old value minus that month's fee: −12,848.50, −11,481.50, −8,308.75.
- [ ] Run `cd transformation && dbt test --select path:models/marts/core,path:models/marts/finance,path:models/marts/ops --exclude test_type:unit`; expect exit 0.
- [ ] Commit and push `transformation/macros/finance.sql` and `transformation/models/docs.md`.

### Task 3: the prose the change falsifies, and the project gates

**Requirements:** the case's decision · **Design:** `docs/design/models/finance/mart_revenue_component_bridge.md` (`D-02`) · **Skill:** `generating-dbt-model` · **Depends on:** Task 2

- [ ] In `contracts/finance/mart_revenue_component_bridge.odcs.yaml`, make `dataGranularityDescription` say what holds after the fix: the residual is its own component, and a non-zero residual means the total is not the sum of its modelled parts — not that the walk fails to balance. Bump `version` `1.0.1` → `1.0.2` (prose is a patch).
- [ ] Rewrite the header comment in `transformation/models/marts/finance/mart_revenue_component_bridge.sql` to the same claim; change no SQL.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate`, then `git diff --stat`: expect `transformation/models/marts/finance/_finance.yml` to follow the contract and nothing else to move; if another file moves, revert that file and report it rather than keeping the churn.
- [ ] Run `cd transformation && dbt build --full-refresh --select fct_trip+` again so the rebuilt `_finance.yml` description is on the table, then `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0.
- [ ] Run the project gates: `python3 -m pytest tests -q`, `ruff check .`, `sqlfluff lint transformation/models`, `cd transformation && dbt test --exclude test_type:unit`, `cd transformation && dbt test --select test_type:unit`, `python3 .github/scripts/adr_lint.py`, `python3 tools/ossie_lint.py`, `python3 .agents/skills/data-contract/scripts/odcs.py check --relations --catalog /data/ephm_duckdb/ephm_nyc-taxi-duckdb-100k_r9-revenue-walk-fix-ca72c1e0.duckdb`; expect exit 0 from each, and record each code.
- [ ] Commit and push the contract, the model comment and whatever `generate` rewrote.

## Execution evidence
