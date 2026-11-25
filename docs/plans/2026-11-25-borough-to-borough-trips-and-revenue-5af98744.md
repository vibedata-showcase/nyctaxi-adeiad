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

- [x] Author `contracts/agg/agg_borough_flow_monthly.odcs.yaml` for `agg.agg_borough_flow_monthly` with `status: proposed`, one property per published column and the grain stated: `trip_month` (DATE), `origin_borough` (VARCHAR), `destination_borough` (VARCHAR) as `primaryKey`, `is_cross_borough` (BOOLEAN), `trip_count` (BIGINT, required, non-negative), `total_revenue` (DOUBLE, required), `origin_trip_count` (BIGINT, required, greater than zero), `cross_borough_trip_count` (BIGINT, required), `outbound_cross_borough_share` (DOUBLE, required, between 0 and 1). Describe the population (billable trips with both zones in an NYC borough), that every cell is published (ADR 0018), and that the share's denominator is `origin_trip_count`. Server: `sample-nyctaxi-comp`, `type: duckdb`, `database: domain.duckdb`, `schema: agg`, matching the sibling contracts.
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0 (`contract/active-unbuilt` is not raised for a `proposed` contract).
- [x] Commit `contracts/agg/agg_borough_flow_monthly.odcs.yaml`.

### Task 2: the model, its properties and its tests

**Requirements:** `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-07` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `generating-dbt-model` · **Depends on:** Task 1

- [x] Author `transformation/models/marts/agg/agg_borough_flow_monthly.sql`: a spine of `dim_date` months in the reporting window crossed with the five NYC boroughs twice (from `dim_zone` where `is_nyc`), left-joined to a `fct_trip` aggregate of billable trips whose pickup and dropoff zones both satisfy `is_nyc`, joined on `pickup_zone_key`/`dropoff_zone_key` and the pickup month. Emit the nine columns of `D-12`; `coalesce` the three trip and revenue aggregates to 0; compute `origin_trip_count` and `cross_borough_trip_count` as window sums partitioned by `(trip_month, origin_borough)` and `outbound_cross_borough_share` with `safe_divide`.
- [x] Author the model's entry in `transformation/models/marts/agg/_agg.yml` with `contract: {enforced: true}`, every column's `data_type` and a description, and its tests: `not_null` on `trip_month`, `origin_borough`, `destination_borough`, `trip_count`, `total_revenue`, `origin_trip_count`, `cross_borough_trip_count` and `outbound_cross_borough_share`; `accepted_values` on `origin_borough` and `destination_borough` for the five NYC boroughs. The composite grain has no single-column `unique` to carry and the project installs no `dbt_utils`, so the grain is proven by the singular test below.
- [x] Author `transformation/tests/assert_borough_matrix_one_row_per_grain.sql`: one row per (month, origin, destination) by `group by` and `having count(*) > 1`.
- [x] Author `transformation/tests/assert_borough_matrix_covers_every_trip.sql`: each month's `sum(trip_count)` equals the independently counted billable trips of that month whose two zones are both in an NYC borough, counted from `fct_trip` and `dim_zone` without reading the new model, and each month holds exactly 25 rows.
- [x] Author `transformation/tests/assert_borough_share_recomputes.sql`: for every row, `outbound_cross_borough_share` equals that origin month's `cross_borough_trip_count` over `origin_trip_count` within 1e-9, and `sum(trip_count)` over an origin's month equals its `origin_trip_count`.
- [x] Run `cd transformation && dbt deps` once in the project, then `dbt build --select agg_borough_flow_monthly+ --exclude test_type:unit`; expect exit 0, the model built and its data tests passing. Upstream is not rebuilt: the sandbox already holds every Domain relation, which the platform's dbt card grants.
- [x] Run `cd transformation && dbt test --select agg_borough_flow_monthly --exclude test_type:unit`; expect exit 0 (the singular tests are downstream and already ran in the build above; this confirms the selection alone is green).
- [x] Run the acceptance queries for `R-01`, `R-02`, `R-03`, `R-05` from `docs/verify/2026-11-25-borough-to-borough-trips-and-revenue-5af98744.md` and record each observed value in the Plan's `## Execution evidence`.
- [x] Set the contract `status: active`, re-run `python3 .agents/skills/data-contract/scripts/odcs.py generate`, rebuild, and run `python3 .agents/skills/data-contract/scripts/odcs.py check` and `--relations`; expect exit 0 or the documented `engine/unavailable` for the profile gate.
- [x] Commit the model, the properties entry, the three singular tests, the regenerated keys and the contract's `active` status together.

### Task 3: the semantic exclusion and the test map

**Requirements:** `R-06`, `R-07` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `semantic-model` · **Depends on:** Task 2

- [x] Add `{"relation": "agg.agg_borough_flow_monthly", "reason": "..."}` to `repo-map.json` `semantic_exclusions`, naming both reasons: its population (both endpoints in an NYC borough) is not a predicate the `trips` dataset's fields can state, and `outbound_cross_borough_share` is not additive across rows.
- [x] Add the three singular tests to `test-map.json` `modules.agg.data`, the unit tests to `modules.agg.unit`, and the exclusion to the `logical-model` coverage command.
- [x] Run `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/ && python3 .agents/skills/semantic-model/scripts/ossie.py coverage logical-model/ transformation/models/marts/core transformation/models/marts/agg transformation/models/marts/finance transformation/models/marts/ops --exclude agg.agg_od_flow_matrix --exclude finance.mart_revenue_component_bridge --exclude core.dim_fare_regime --exclude agg.agg_borough_flow_monthly && python3 .agents/skills/semantic-model/scripts/ossie.py suppliers logical-model/ && python3 .agents/skills/semantic-model/scripts/ossie.py notes logical-model/ transformation/tests docs/adr && python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests --check`; expect exit 0 and `0 coverage error(s)`.
- [x] Run `python3 -m pytest tests/test_maps.py -q`; expect exit 0 with the new exclusion accepted by `test_every_semantic_exclusion_names_a_boundary_relation_and_a_reason`.
- [x] Commit `repo-map.json` and `test-map.json`.

## Execution evidence

- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py check` — exit 0 — `contracts/agg/agg_borough_flow_monthly.odcs.yaml` (9 properties, `status: proposed`) — sha256:57204d8c76db139ae52b3ab612dcdda5432c947e477fc9f7cb241da29e88888b
- Task 2: `cd transformation && dbt build --select agg_borough_flow_monthly+ --exclude test_type:unit` — exit 0 — PASS=14 WARN=0 ERROR=0 — `agg.agg_borough_flow_monthly`, 75 rows, 9 columns; followed by `assert_dbt_destination.py`, exit 0, `DESTINATION_OK: 1 built relation(s) landed in the sandbox ephm_nyc-taxi-analytics_new-intent-5af98744`
- Task 2: `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit` — exit 0 — PASS=5 WARN=0 ERROR=0 — `transformation/models/marts/agg/_unit_tests.yml`
- Task 2, `R-01`: `select trip_month, count(*) as cells, sum(trip_count) as trips, round(sum(total_revenue),2) as revenue from agg.agg_borough_flow_monthly group by 1 order by 1` on `ephemeral` — 25 cells in each of the three months; 29,568 / 29,650 / 35,505 trips; 785,518.24 / 785,082.37 / 963,284.41 revenue; Q1 94,723 trips and 2,533,885.02 revenue
- Task 2, `R-02`: the January Manhattan to Manhattan cell reads 24,995 trips and 515,753.34 revenue
- Task 2, `R-03`: the months' totals are 417 / 367 / 451 trips below the all-billable counts of 29,985 / 30,017 / 35,956, which is the EWR and unresolved traffic the grid excludes
- Task 2, `R-04`: January shares read Manhattan 5.30%, Queens 70.52%, Brooklyn 37.18%, Bronx 58.88%, Staten Island 40.00%, each beside its origin trip count of 26,394 / 2,710 / 347 / 107 / 10
- Task 2, `R-05`: `select count(*) filter (where trip_count = 0) as zero_cells, count(*) filter (where trip_count is null or total_revenue is null) as null_cells, count(*) as rows from agg.agg_borough_flow_monthly` — 10 zero cells, 0 null cells, 75 rows; per month 22 / 20 / 23 cells carry trips and 3 / 5 / 2 carry none
- Task 2: `python3 .agents/skills/data-contract/scripts/odcs.py generate` — exit 0 — wrote the dbt keys into `transformation/models/marts/agg/_agg.yml`
- Task 2: `python3 .agents/skills/data-contract/scripts/odcs.py check` — exit 0 — clean
- Task 2: `python3 .agents/skills/data-contract/scripts/odcs.py profile --relation agg.agg_borough_flow_monthly --catalog <the sandbox duckdb file>` — exit 0 — no finding: the composite grain holds and no `required` claim is false
- Task 2: `python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main` — exit 0 — no finding
- Task 2: `python3 .agents/skills/data-contract/scripts/odcs.py check --relations --catalog transformation/target/catalog.json` — exit 1 — six `relations/mismatch` errors, every one on a bronze, mdm_raw or ops_raw source contract (`the catalog holds no such relation`), none on `agg.agg_borough_flow_monthly`: a dbt catalog holds models only, never dlt-loaded sources. Pre-existing for every source contract and outside this task's rows.
- Task 2: `sqlfluff lint transformation/models/marts/agg/agg_borough_flow_monthly.sql transformation/tests/assert_borough_matrix_one_row_per_grain.sql transformation/tests/assert_borough_matrix_covers_every_trip.sql transformation/tests/assert_borough_share_recomputes.sql` — exit 0
- Task 2: `cd transformation && dbt docs generate --static` — exit 0 — `target/static_index.html` copied to the docs bind's `.tmp` name and moved onto its served name
- Task 3: `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/` — exit 0; `coverage` with `--exclude agg.agg_borough_flow_monthly` — exit 0, `35 model(s) on disk, 31 named, 0 coverage error(s)`; `suppliers` — exit 0, 0 unsupplied; `notes` — exit 0, 0 dangling; `generate-tests --check` — exit 0, 3 generated, 0 stale
- Task 3: `python3 -m pytest tests/test_maps.py -q` — exit 0 — 31 passed
- Task 2 and 3 gates: `python3 -m pytest tests -q` — exit 0 — 222 passed; `ruff check .` — exit 0; `sqlfluff lint transformation/models` — exit 0; `python3 .github/scripts/adr_lint.py` — exit 0
- Reordering: Task 3's `repo-map.json` exclusion had to land with Task 2. `odcs.py check` fails `boundary/undeclared` on any new boundary relation no canonical document names, and `ossie.py coverage` fails `coverage/unmapped` unless the exclusion is on its command line, so neither Task 2 gate can be green without it. Both tasks' files are committed together, each with its own evidence above.
- Artifact hashes: `agg_borough_flow_monthly.sql` sha256:d8e23c41d5a1fc11d8d38c7a10c873aee39ea5f5b212e4f6a40ff62f6ea9eabf; `_agg.yml` sha256:5645cfb7a065168f3cb7508e42e758ee7a4f00dc57154718a1964127f7dd2e53; `_unit_tests.yml` sha256:262dc61d74a5cc4621afa475124ea52057d1d3742daef2a3464427b5c5b44d73; `assert_borough_matrix_covers_every_trip.sql` sha256:25d0a56a5e0f5a1bec6f7beb683e3681b34dedb40cb96b2ddf4a7f62c62c7f91; `assert_borough_matrix_one_row_per_grain.sql` sha256:7ca4dfec97b4a92465f49b7cf498f0047d7735e6499236f2d0194ef75bec0f1d; `assert_borough_share_recomputes.sql` sha256:38e471111b6413f67d934ea79d6babc5d190e53f25f1be60932e7a3cc3281c0d; `agg_borough_flow_monthly.odcs.yaml` sha256:c90c3b8d70115a659ccf3ae05b0bf0d21ffbea7dfaa41221ef5cdf2f51e05d88
