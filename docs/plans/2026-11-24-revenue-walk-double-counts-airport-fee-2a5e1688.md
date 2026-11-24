# Plan: The revenue walk counts the airport fee twice

**Goal:** Make `finance.mart_revenue_component_bridge` a true decomposition of the total it reports, so the nine components sum to `total_amount` per group and the Q1 2024 walk reads 2,629,185.82.

**Requirement:** `docs/cases/2026-11-24-revenue-walk-double-counts-airport-fee-2a5e1688.md`

**Constraints:**
- The walk's components are disjoint parts of one total (ADR 0018).
- `surcharge_columns()` keeps its four columns: `total_surcharges` and every `surcharge_revenue` that reads it must not move (ADR 0018).
- `airport_fee` stays a component of the walk as `c_airport_fee` (ADR 0018).
- The billable metric stays at 2,629,185.82 for Q1 2024; the fix changes the walk, not the revenue.
- Every contract change is authored in the contract and rendered by `odcs.py generate`, never hand-written into the properties file.
- Money comparisons are at the cent (`.agents/skills/dbt-testing/SKILL.md`).

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `transformation/macros/finance.sql` | macro | modify | `R-01` | `docs/design/models/intermediate/int_trip_fare_components.md` | `cd transformation && dbt parse` |
| `transformation/models/intermediate/int_trip_fare_components.sql` | model | modify | `R-01` | `docs/design/models/intermediate/int_trip_fare_components.md` | `cd transformation && dbt build --select int_trip_fare_components+ --exclude test_type:unit` |
| `transformation/models/marts/finance/mart_revenue_component_bridge.sql` | model | modify | `R-01`, `R-02` | `docs/design/models/finance/mart_revenue_component_bridge.md` | `cd transformation && dbt build --select mart_revenue_component_bridge --exclude test_type:unit` |
| `transformation/tests/assert_revenue_walk_decomposes_total.sql` | test (singular) | create | `R-02` | `docs/design/models/finance/mart_revenue_component_bridge.md` | `cd transformation && dbt test --select assert_revenue_walk_decomposes_total` |
| `contracts/core/fct_trip.odcs.yaml` | contract | modify | `R-03` | `docs/design/models/core/fct_trip.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `contracts/finance/mart_revenue_component_bridge.odcs.yaml` | contract | modify | `R-03` | `docs/design/models/finance/mart_revenue_component_bridge.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `transformation/models/docs.md` (`fare_residual` doc block) | project-config | modify | `R-03` | `docs/design/models/core/fct_trip.md` | `cd transformation && dbt parse` |
| `logical-model/nyc_taxi_analytics.ossie.yaml` | logical-model | modify | `R-03` | `docs/design/models/core/fct_trip.md` | `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/` |
| `docs/design/models/ops/mart_trip_quality_scorecard.md` | design record | create | `R-04` | `docs/design/models/ops/mart_trip_quality_scorecard.md` | `timeout 300 python3 -m pytest tests/test_adr_links.py -q` |

**Change impact:** `transformation/macros/finance.sql` `fare_residual` feeds `int_trip_fare_components`, and through it `core.fct_trip.fare_residual`, `finance.mart_revenue_component_bridge.c_residual` and `ops.mart_trip_quality_scorecard.unbalanced_total_count`. The semantic metric `fare_residual_total` reads it. `billable_revenue`, `mart_daily_zone_revenue` and `mart_monthly_service_summary` read `total_amount` and do not move. `fct_trip` is incremental with no `on_schema_change`, so the corrected residual needs `dbt build --full-refresh --select fct_trip` — the breaking delta the Case record's approval names.

## Tasks

### Task 1: The decomposition macro

**Requirements:** `R-01` · **Design:** `docs/design/models/intermediate/int_trip_fare_components.md` · **Skill:** `generating-dbt-model` · **Depends on:** none

- [ ] Add `decomposed_columns()` to `transformation/macros/finance.sql`: `['fare_amount', 'tip_amount', 'tolls_amount'] + surcharge_columns() + ['airport_fee']`, ordered as named.
- [ ] Rewrite `fare_residual(alias)` in the same file to subtract every column in `decomposed_columns()` from `coalesce(total_amount, 0)`, replacing the four hard-coded subtractions and the `total_surcharges()` call.
- [ ] Leave `surcharge_columns()` and `total_surcharges()` byte-identical, so `total_surcharges` keeps its meaning and `fct_shift` does not gain the fee twice.
- [ ] Update the `fare_residual` doc block in `transformation/models/docs.md` to say the residual is the total minus every component the walk publishes, `airport_fee` included, and that the component list is `decomposed_columns()`.
- [ ] Run `cd transformation && dbt deps` if `transformation/dbt_packages/` is missing, then `cd transformation && dbt parse`; expect exit 0.
- [ ] Run the acceptance condition of `R-01` at trip grain on the sandbox: `select count(*) filter (where round(coalesce(fare_amount,0)+coalesce(tip_amount,0)+coalesce(tolls_amount,0)+coalesce(extra,0)+coalesce(mta_tax,0)+coalesce(improvement_surcharge,0)+coalesce(congestion_surcharge,0)+coalesce(airport_fee,0)+coalesce(fare_residual,0),2) <> round(coalesce(total_amount,0),2)) from core.fct_trip where {{ in_report_window('pickup_datetime') }}`; expect 0 on a rebuilt `fct_trip` (the pre-fix value is 7,184).
- [ ] Commit and push `transformation/macros/finance.sql` and `transformation/models/docs.md`.

### Task 2: The bridge's component list

**Requirements:** `R-01`, `R-02` · **Design:** `docs/design/models/finance/mart_revenue_component_bridge.md` · **Skill:** `generating-dbt-model` · **Depends on:** Task 1

- [ ] In `transformation/models/marts/finance/mart_revenue_component_bridge.sql`, keep the nine-component unpivot and its `component_order` values, and state in the file header that the components are a decomposition of `total_amount` and that `c_residual` excludes every published component.
- [ ] Keep the grain and the columns unchanged: `trip_month`, `service_type_key`, `borough_name`, `trip_count`, `total_amount`, `component_name`, `component_order`, `component_amount`, `component_share`.
- [ ] Rebuild the fact and the walk on the sandbox with the corrected residual: `cd transformation && dbt build --select fct_trip --full-refresh`; expect exit 0 (this is the approved breaking delta for `core.fct_trip`).
- [ ] Rebuild the walk: `cd transformation && dbt build --select mart_revenue_component_bridge --exclude test_type:unit`; expect exit 0.
- [ ] Run the acceptance condition of `R-01`: `select count(*) from (select trip_month, service_type_key, borough_name from finance.mart_revenue_component_bridge group by 1,2,3 having abs(sum(component_amount) - max(total_amount)) > 0.01)`; expect 0 (the pre-fix value is 9).
- [ ] Run the acceptance condition of `R-02`: `select round(sum(component_amount),2), round((select sum(total_amount) from core.fct_trip where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'),2) from finance.mart_revenue_component_bridge`; expect `2629185.82, 2629185.82`.
- [ ] Commit and push `transformation/models/marts/finance/mart_revenue_component_bridge.sql`.

### Task 3: The test that would have caught it

**Requirements:** `R-02` · **Design:** `docs/design/models/finance/mart_revenue_component_bridge.md` · **Skill:** `dbt-testing` · **Depends on:** Task 2

- [ ] Create `transformation/tests/assert_revenue_walk_decomposes_total.sql` as a singular test: group `finance.mart_revenue_component_bridge` by `trip_month`, `service_type_key`, `borough_name` and return every group whose `round(sum(component_amount), 2)` differs from `round(max(total_amount), 2)`, with the group's keys, the two sums and the difference. Return no rows when the walk decomposes the total.
- [ ] Prove it fails without the fix by running the identical SQL read-only against `domain`, whose `finance.mart_revenue_component_bridge` is still the pre-fix build at `1184020`: expect the 9 off-balance groups, gap totalling 12,262.25. Never revert the macro to demonstrate it.
- [ ] Run `cd transformation && dbt test --select assert_revenue_walk_decomposes_total` against the sandbox; expect PASS and 0 rows returned.
- [ ] Record both runs in `docs/verify/2026-11-24-revenue-walk-double-counts-airport-fee-2a5e1688.md` under a `## Verification` section.
- [ ] Register the test in `test-map.json` `modules.finance.data` and confirm `timeout 600 python3 -m pytest tests/test_maps.py -q -k "test_map_paths_exist or selectors_resolve"` passes.
- [ ] Commit and push `transformation/tests/assert_revenue_walk_decomposes_total.sql` and `test-map.json`.

### Task 4: The contracts and the canonical model

**Requirements:** `R-03` · **Design:** `docs/design/models/core/fct_trip.md`, `docs/design/models/finance/mart_revenue_component_bridge.md` · **Skill:** `data-contract` · **Depends on:** Task 2

- [ ] In `contracts/core/fct_trip.odcs.yaml`, give the `fare_residual` property a description stating the corrected meaning, and bump `version` from `1.1.0` to `1.1.1` (a description-only change).
- [ ] In `contracts/finance/mart_revenue_component_bridge.odcs.yaml`, correct `dataGranularityDescription`, the `component_name` description and the `component_amount` description so they state that the components sum to `total_amount` per group; bump `version` from `1.0.1` to `1.0.2`.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate` to render the dbt keys and descriptions from the contracts; do not hand-edit `_core.yml` or `_finance.yml`.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0. Then `python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main`; expect exit 0 with no `diff/version-not-bumped`.
- [ ] In `logical-model/nyc_taxi_analytics.ossie.yaml`, correct the `fare_residual` field description and the `fare_residual_total` metric description to the corrected meaning; change no expression, key or `column_map`.
- [ ] Run `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/`; expect exit 0.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check --relations`; expect exit 0.
- [ ] Commit and push the two contracts, `transformation/models/marts/core/_core.yml`, `transformation/models/marts/finance/_finance.yml` and `logical-model/nyc_taxi_analytics.ossie.yaml`.

### Task 5: The scorecard's changed population

**Requirements:** `R-04` · **Design:** `docs/design/models/ops/mart_trip_quality_scorecard.md` · **Skill:** `generating-dbt-model` · **Depends on:** Task 2

- [ ] Write `docs/design/models/ops/mart_trip_quality_scorecard.md` recording that `unbalanced_total_count` counts trips the modelled components do not explain, so its population moves when `fare_residual`'s definition moves (ADR 0018); cite ADR 0018 and add the record to that ADR's `## Affected designs`.
- [ ] Rebuild the scorecard: `cd transformation && dbt build --select mart_trip_quality_scorecard --exclude test_type:unit`; expect exit 0.
- [ ] Run the acceptance condition of `R-04`: `select sum(unbalanced_total_count) from ops.mart_trip_quality_scorecard`; expect 26,457 for the Q1 window, against 31,869 before the fix.
- [ ] Commit and push `docs/design/models/ops/mart_trip_quality_scorecard.md` and `docs/adr/0018-the-revenue-walk-decomposes-the-total-it-reports.md`.

## Execution evidence
