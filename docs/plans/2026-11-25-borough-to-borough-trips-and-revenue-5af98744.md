# Plan: Borough-to-borough trips and revenue

**Goal:** Publish `agg.agg_borough_flow_monthly`, one row per Q1 2024 pickup month × origin borough × destination borough over the five NYC boroughs, with billable trips, their revenue and each origin borough's outbound cross-borough share.

**Requirement:** `docs/requirement/2026-11-25-borough-to-borough-trips-and-revenue-5af98744.md`

**Constraints:**
- Every cell of the 3 × 5 × 5 grid is published; a cell with no trips carries 0 trips and 0 revenue, never a null, and no row is suppressed for being thin (ADR 0018).
- The population is billable trips whose pickup and dropoff zones are both in an NYC borough, selected by `dim_zone.is_nyc` rather than a name list (ADR 0012, ADR 0003).
- Revenue is `sum(total_amount)` over billable trips, including no-charge and dispute payments (ADR 0003, ADR 0013).
- `dim_zone` is joined twice on the fact's as-of surrogate keys `pickup_zone_key` and `dropoff_zone_key`; never on the natural key, which multiplies facts across versions (ADR 0009).
- Money is compared at the cent, other measures at an explicit tolerance; DuckDB float aggregation is not bit-reproducible.
- The relation is a `semantic_exclusions` entry in `repo-map.json`, not an aggregate logical source; `core.fct_trip` is not changed.
- SQL follows `.agents/skills/sql-style/SKILL.md`; every model, column and test file is registered where `repo-map.json` and `test-map.json` say.
- No `--full-refresh` and no change to any published model the Requirement did not name.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `contracts/agg/agg_borough_flow_monthly.odcs.yaml` | contract | create | `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `transformation/models/marts/agg/agg_borough_flow_monthly.sql` | model | create | `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt build --select agg_borough_flow_monthly+ --exclude test_type:unit` |
| `transformation/models/marts/agg/_agg.yml` | model | modify | `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select agg_borough_flow_monthly --exclude test_type:unit` |
| `transformation/tests/assert_borough_matrix_one_row_per_grain.sql` | model | create | `R-01` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select assert_borough_matrix_one_row_per_grain` |
| `transformation/tests/assert_borough_matrix_covers_every_trip.sql` | model | create | `R-01`, `R-05` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select assert_borough_matrix_covers_every_trip` |
| `transformation/tests/assert_borough_share_recomputes.sql` | model | create | `R-04` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select assert_borough_share_recomputes` |
| `repo-map.json` `semantic_exclusions` | project-config | modify | `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 -m pytest tests/test_maps.py -q` |
| `test-map.json` `agg.data` | project-config | modify | `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 -m pytest tests/test_maps.py -q` |

**Change impact:** none downstream. `dbt ls --select 1+agg_borough_flow_monthly --exclude agg_borough_flow_monthly` selects only existing tests on `core.fct_trip` and `core.dim_zone`; no model reads the new relation, and the models it reads are unchanged. `core.fct_trip` and `core.dim_zone` are read, not modified.

## Tasks

### Task 1: the contract for the new boundary relation

**Requirements:** `R-06` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `data-contract` · **Depends on:** none

- [ ] Author `contracts/agg/agg_borough_flow_monthly.odcs.yaml` for `agg.agg_borough_flow_monthly` with `status: proposed`, one property per published column and the grain stated: `trip_month` (DATE), `origin_borough` (VARCHAR), `destination_borough` (VARCHAR) as `primaryKey`, `is_cross_borough` (BOOLEAN), `trip_count` (BIGINT, required, non-negative), `total_revenue` (DOUBLE, required), `origin_trip_count` (BIGINT, required, greater than zero), `cross_borough_trip_count` (BIGINT, required), `outbound_cross_borough_share` (DOUBLE, required, between 0 and 1). Describe the population (billable trips with both zones in an NYC borough), that every cell is published (ADR 0018), and that the share's denominator is `origin_trip_count`. Server: `sample-nyctaxi-comp`, `type: duckdb`, `database: domain.duckdb`, `schema: agg`, matching the sibling contracts.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0 (`contract/active-unbuilt` is not raised for a `proposed` contract).
- [ ] Commit `contracts/agg/agg_borough_flow_monthly.odcs.yaml`.

### Task 2: the model, its properties and its tests

**Requirements:** `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-07` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `generating-dbt-model` · **Depends on:** Task 1

- [ ] Author `transformation/models/marts/agg/agg_borough_flow_monthly.sql`: a spine of `dim_date` months in the reporting window crossed with the five NYC boroughs twice (from `dim_zone` where `is_nyc`), left-joined to a `fct_trip` aggregate of billable trips whose pickup and dropoff zones both satisfy `is_nyc`, joined on `pickup_zone_key`/`dropoff_zone_key` and the pickup month. Emit the nine columns of `D-12`; `coalesce` the three trip and revenue aggregates to 0; compute `origin_trip_count` and `cross_borough_trip_count` as window sums partitioned by `(trip_month, origin_borough)` and `outbound_cross_borough_share` with `safe_divide`.
- [ ] Author the model's entry in `transformation/models/marts/agg/_agg.yml` with `contract: {enforced: true}`, every column's `data_type` and a description, and its tests: `not_null` on `trip_month`, `origin_borough`, `destination_borough`, `trip_count`, `total_revenue`, `origin_trip_count`, `cross_borough_trip_count` and `outbound_cross_borough_share`; `accepted_values` on `origin_borough` and `destination_borough` for the five NYC boroughs. The composite grain has no single-column `unique` to carry and the project installs no `dbt_utils`, so the grain is proven by the singular test below.
- [ ] Author `transformation/tests/assert_borough_matrix_one_row_per_grain.sql`: one row per (month, origin, destination) by `group by` and `having count(*) > 1`.
- [ ] Author `transformation/tests/assert_borough_matrix_covers_every_trip.sql`: each month's `sum(trip_count)` equals the independently counted billable trips of that month whose two zones are both in an NYC borough, counted from `fct_trip` and `dim_zone` without reading the new model, and each month holds exactly 25 rows.
- [ ] Author `transformation/tests/assert_borough_share_recomputes.sql`: for every row, `outbound_cross_borough_share` equals that origin month's `cross_borough_trip_count` over `origin_trip_count` within 1e-9, and `sum(trip_count)` over an origin's month equals its `origin_trip_count`.
- [ ] Run `cd transformation && dbt deps` once in the project, then `dbt build --select agg_borough_flow_monthly+ --exclude test_type:unit`; expect exit 0, the model built and its data tests passing. Upstream is not rebuilt: the sandbox already holds every Domain relation, which the platform's dbt card grants.
- [ ] Run `cd transformation && dbt test --select agg_borough_flow_monthly --exclude test_type:unit`; expect exit 0 (the singular tests are downstream and already ran in the build above; this confirms the selection alone is green).
- [ ] Run the acceptance queries for `R-01`, `R-02`, `R-03`, `R-05` from `docs/verify/2026-11-25-borough-to-borough-trips-and-revenue-5af98744.md` and record each observed value in the Plan's `## Execution evidence`.
- [ ] Set the contract `status: active`, re-run `python3 .agents/skills/data-contract/scripts/odcs.py generate`, rebuild, and run `python3 .agents/skills/data-contract/scripts/odcs.py check` and `--relations`; expect exit 0 or the documented `engine/unavailable` for the profile gate.
- [ ] Commit the model, the properties entry, the three singular tests, the regenerated keys and the contract's `active` status together.

### Task 3: the semantic exclusion and the test map

**Requirements:** `R-06`, `R-07` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `semantic-model` · **Depends on:** Task 2

- [ ] Add `{"relation": "agg.agg_borough_flow_monthly", "reason": "..."}` to `repo-map.json` `semantic_exclusions`, naming both reasons: its population (both endpoints in an NYC borough) is not a predicate the `trips` dataset's fields can state, and `outbound_cross_borough_share` is not additive across rows.
- [ ] Add the three singular tests to `test-map.json` `modules.agg.data`.
- [ ] Run `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/ && python3 .agents/skills/semantic-model/scripts/ossie.py coverage logical-model/ transformation/models/marts/core transformation/models/marts/agg transformation/models/marts/finance transformation/models/marts/ops --exclude agg.agg_od_flow_matrix --exclude finance.mart_revenue_component_bridge --exclude core.dim_fare_regime --exclude agg.agg_borough_flow_monthly && python3 .agents/skills/semantic-model/scripts/ossie.py suppliers logical-model/ && python3 .agents/skills/semantic-model/scripts/ossie.py notes logical-model/ transformation/tests docs/adr && python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests --check`; expect exit 0 and `0 coverage error(s)`.
- [ ] Run `python3 -m pytest tests/test_maps.py -q`; expect exit 0 with the new exclusion accepted by `test_every_semantic_exclusion_names_a_boundary_relation_and_a_reason`.
- [ ] Commit `repo-map.json` and `test-map.json`.

## Execution evidence
