# Plan: R9 · borough flow

**Goal:** one gold table of monthly borough-to-borough billable trips, revenue and the origin borough's share, for every month of the reporting window.

**Requirement:** `docs/requirement/2026-11-24-r9-borough-flow-3f0db19d.md`

**Constraints:**

- Schema `agg` for `transformation/models/marts/agg/` (design `## Schema`, user answer).
- Table materialisation, `access: public`, `contract: { enforced: true }`.
- Billable trips only, inside `in_report_window(f.pickup_datetime)` (ADR 0003).
- No trip floor; every pair published, zero-trip pairs with 0 trips and 0 revenue (ADR 0018).
- `Unknown`, `N/A` and any zone-less trip form one `unresolved` group, kept in the totals and outside the share (ADR 0012, design stop `D-05`/`D-09`).
- The share is a ratio of summed trip counts through `safe_divide`, null on a zero denominator and on any row touching `unresolved` (ADR 0016, `D-07`).
- No quality verdict filters a trip; the billable rule is the only exclusion (ADR 0004, `D-14`).
- No production manifest is published, so no `--defer` and `/data/cache` is never read (DuckDB dbt card `## Defer`).

**Baseline build_sha:** not applicable — the DuckDB dbt card says no production manifest is published.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `agg_borough_flow_monthly` | model | create | `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-06`, `R-08` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt build --select agg_borough_flow_monthly --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` |
| `contracts/agg/agg_borough_flow_monthly.odcs.yaml` | contract | create | `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `LTS10_borough_flow_monthly` | logical-model | modify | `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 tools/ossie_lint.py` |

**Change impact:** none downstream. No existing model, contract or mart is edited; `_agg.yml` gains one model entry. The new relation is read only by the semantic-layer source added in Task 1, and no repository model refs it.

## Tasks

### Task 1: `agg_borough_flow_monthly` with its contract and canonical source

**Requirements:** `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-06`, `R-07`, `R-08` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `generating-dbt-model`, with `data-contract` and `semantic-model` for their rows · **Depends on:** none

Authoring follows `D-01` to `D-14`: months from `dim_date` filtered by `in_report_window` reduced to distinct `month_start_date`; groups from `dim_zone` with `Unknown` and `N/A` mapped to `'unresolved'` plus one row for it; `fct_trip` left-joined to `dim_zone` twice on `zone_key` with both boroughs coalesced to `'unresolved'`; billable and in-window only; `count(*)`, `sum(total_amount)`, `origin_borough = dest_borough`, and the share over the borough-to-borough rows of each (month, origin borough).

- [x] Run `cd transformation && dbt deps` before the first dbt command.
- [x] Author `contracts/agg/agg_borough_flow_monthly.odcs.yaml` first, `status: proposed`: `primaryKey` on (`trip_month`, `origin_borough`, `dest_borough`), the seven columns with `logicalType`/`physicalType` and descriptions, the monthly reconciliation rule against the billable population, and the share's null-on-unresolved rule.
- [x] Author `transformation/models/marts/agg/agg_borough_flow_monthly.sql` and its entry in `transformation/models/marts/agg/_agg.yml` (`access: public`, `contract: {enforced: true}`, explicit columns with `data_type`: `trip_month` DATE, `origin_borough` VARCHAR, `dest_borough` VARCHAR, `is_intra_borough` BOOLEAN, `trip_count` BIGINT, `total_revenue` DOUBLE, `share_of_origin_borough_trips` DOUBLE).
- [x] Add the tests the `dbt-testing` convention requires, by file and name:
  - `_agg.yml` on `agg_borough_flow_monthly`: `unique` on the three-column grain, `not_null` on `trip_month`, `origin_borough`, `dest_borough`, `is_intra_borough`, `trip_count`, `total_revenue`.
  - `transformation/tests/assert_borough_flow_grid_is_complete.sql` — every (month, group, group) present once (R-01, R-05).
  - `transformation/tests/assert_borough_flow_reconciles_to_billable_trips.sql` — per month, `sum(trip_count)` equals `fct_trip`'s billable count and `sum(total_revenue)` equals its billable `total_amount` at the cent (R-02, R-03).
  - `transformation/tests/assert_borough_flow_shares_sum_to_one.sql` — borough-to-borough shares sum to 1 per (month, origin borough) within 1e-6 and every row touching `unresolved` has a null share (R-04).
  - `transformation/models/marts/agg/_unit_tests.yml`, unit test `agg_borough_flow_monthly`: a borough-to-borough row, a borough-to-`unresolved` row (null share), an `unresolved`-to-borough row (null share), a zero-trip grid cell, and a zone-less trip landing in `unresolved`; set `report_start` and `report_end` under `overrides: {vars: …}`, since the model reads both.
- [x] Add `LTS10_borough_flow_monthly` to the `trips` dataset in `logical-model/nyc_taxi_analytics.ossie.yaml`: priority group 0, content grain (month, origin borough, destination borough), `column_map` `billable_trip_count` → `trip_count` and `billable_revenue` → `total_revenue`, levels `trips_to_date`/month, `trips_to_pickup_zone`/borough, `trips_to_dropoff_zone`/borough, the window-and-billable `content_filter`, and a `note` refusing `share_of_origin_borough_trips` for want of a metric and stating it is null on unresolved rows. Then set the contract `status: active`.
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate` to write the enforcement keys and descriptions; if it writes a shared-metric description that contradicts the billable population (the `trip_count` name matches the all-trips metric), record the finding and keep the contract's own wording, never hand-editing a generated description. Then run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0.
- [x] Regenerate the Ossie-owned tests with `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests` and commit the regenerated `assert_semantic_*.sql` beside the model.
- [x] Run `cd transformation && dbt build --select agg_borough_flow_monthly --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'`; expect PASS and 147 rows (3 months × 7 groups²). After the build, run the destination assertion and the ephemeral marker from `generating-dbt-model` step 9.
- [x] Run `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'`; expect PASS.
- [x] Run `python3 tools/ossie_lint.py`; expect exit 0 with no blocking finding, and record a passing `validating-semantic-model` report beside its result.
- [x] Run the R-06 acceptance query with `cd transformation && dbt show --inline "select count(distinct origin_borough) as groups, count(*) filter (where origin_borough in ('Unknown','N/A')) as named_unresolved, count(*) filter (where origin_borough = 'EWR') as ewr_rows from agg.agg_borough_flow_monthly" --target dev`; expect 7 groups, 0 named unresolved rows and a non-zero `EWR` count.
- [x] Confirm `R-08` with `git diff --stat`: no existing model SQL or contract changes; only the new model, contract and test files, `_agg.yml`, the Ossie document, and regenerated semantic tests.
- [x] Commit and push `transformation/models/marts/agg/agg_borough_flow_monthly.sql`, `transformation/models/marts/agg/_agg.yml`, `transformation/models/marts/agg/_unit_tests.yml`, `transformation/tests/assert_borough_flow_grid_is_complete.sql`, `transformation/tests/assert_borough_flow_reconciles_to_billable_trips.sql`, `transformation/tests/assert_borough_flow_shares_sum_to_one.sql`, the regenerated `transformation/tests/assert_semantic_*.sql`, `contracts/agg/agg_borough_flow_monthly.odcs.yaml` and `logical-model/nyc_taxi_analytics.ossie.yaml`.

## Execution evidence

### Task 1 — `agg_borough_flow_monthly`, its contract and `LTS10`

Built and pushed in `e2384e3` (model, contract, semantic source, tests, test map) and
`03164cb` (the design approval). `D-15` amends `D-11` at execution: the semantic source
claims the month level only, because the `unresolved` group is no Geography member.

**Profiling (step 4).** `core.fct_trip` 97,184 rows / 97,184 distinct `trip_key`, 95,958
billable, pickup `2024-01-01T00:05:25` → `2024-03-31T23:56:17` — `Ready`. `core.dim_zone`
272 rows / 272 `zone_key`, 265 natural keys, 8 borough names, every zone key resolves (0
null borough) — `Ready`. `core.dim_date` months in the window: 3. Read in the sandbox via
`lakehouse_query`, recorded in `docs/verify/2026-11-24-r9-borough-flow-3f0db19d.md`.

**Contract.** `python3 .agents/skills/data-contract/scripts/odcs.py generate` → exit 0,
`[]`: nothing to write, because `_agg.yml`'s `trip_count`/`total_revenue` descriptions were
set to the `billable_trip_count`/`billable_revenue` metric wording that `ossie_lint`'s
`generated/stale` finding asks for (the `trip_count` name also matches the all-trips metric,
whose wording would be false here — the column counts billable trips only).
`odcs.py check --catalog /data/ephm_duckdb/ephm_nyc-taxi-duckdb-100k_r9-borough-flow-3f0db19d.duckdb`
→ exit 0, 0 errors, no finding for this contract; `... check --relations --catalog ...` → exit
0, 0 errors.

**Build.** `cd transformation && dbt deps` → 0.
`cd transformation && dbt build --select agg_borough_flow_monthly --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'`
→ exit 0, `PASS=12 WARN=1 ERROR=0 SKIP=0`; relation `agg.agg_borough_flow_monthly`,
materialisation table, columns `trip_month DATE, origin_borough VARCHAR, dest_borough VARCHAR,
is_intra_borough BOOLEAN, trip_count BIGINT, total_revenue DOUBLE, share_of_origin_borough_trips DOUBLE`.
The one warning is `assert_semantic_levels_hold`'s pre-existing `trips.LTS5_weather_borough_daily`
`unresolved` row, not this source. No `--defer`: the DuckDB card publishes no production manifest.
`python3 /data/default-plugins/vibedata-data-engineering/0.148.26/scripts/assert_dbt_destination.py`
→ exit 0, `DESTINATION_OK: 1 built relation(s) landed in the sandbox ephm_nyc-taxi-duckdb-100k_r9-borough-flow-3f0db19d`;
`.../ephemeral_workspace_marker.py init` → `status: created`.

**Tests.** `dbt test --select agg_borough_flow_monthly,test_type:unit --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'`
→ exit 0, `PASS=1`. The composite grain's `unique` is `assert_borough_flow_grid_is_complete.sql`
(dbt's `unique` takes one column and the project carries no `dbt_utils`); it fails on a
missing cell, a duplicated cell or an out-of-window group and passes on 147 rows. The unit
test needs no `overrides.vars`: the project's `report_start`/`report_end` already bound the
window the fixture uses.

**Semantic layer.** `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests`
→ exit 0, `3 generated test(s), 0 stale`; `... ossie.py bindings logical-model/ transformation/target/manifest.json`
after `dbt compile --select agg_borough_flow_monthly` → exit 0, `33 model(s) with SQL, 0
error(s)`. `python3 tools/ossie_lint.py` → exit 0, `0 blocking finding(s)` (`validate model`
1 warning, `refs` 2 warnings, `contracts` 26 warnings — all pre-existing).

**The binding finding.** The first `dbt build --select +agg_borough_flow_monthly ...` left
`assert_semantic_content_holds` FAIL with 148 rows, every one of them an `unresolved` sentinel
beside the detail's `Unknown`/`N/A`. The month totals were exact at every borough. The source
now claims the month level only (`D-15`, user answer `month_only`), and the test passes.

**Semantic review (`validating-semantic-model`).** `validate` 0 errors (1 pre-existing
`zone_poi_to_zone` warning), `coverage` 0 coverage errors, `suppliers` `[]`, `notes` 0
dangling, `generate-tests --check` 0 stale, `bindings` 0 errors, `columns` exit 0 with 5
pre-existing `Decimal`-vs-float warnings on other datasets and none on `LTS10`. Content
items 1–6 and 9–12 hold on the SQL: `trip_count` counts the billable in-window population
the `billable_trip_count` metric states (the confirming sentence is in the source `note`),
`total_revenue` sums `total_amount` over exactly that population, the two `LEFT` joins drop
no row, the `CASE` mapping drops no row, `share_of_origin_borough_trips` and
`is_intra_borough` are refused with their reasons, and the datatypes are
`DATE/VARCHAR/BOOLEAN/BIGINT/DOUBLE`. Items 7: `assert_semantic_content_holds` and
`assert_semantic_level_keys_hold` pass; `assert_semantic_levels_hold` warns on one
pre-existing `LTS5_weather_borough_daily` `unresolved` row, unrelated to this source. Item 6
carries one deliberate deviation, approved as `D-15`: the source holds a three-way grain but
declares the month level only, so its declared levels are coarser than its `GROUP BY` — the
`unresolved` group is no Geography member and cannot be predicated away.

**Acceptance.** `dbt show --inline "select count(distinct origin_borough) as groups, ... from agg.agg_borough_flow_monthly"`
→ `groups 7 | named_unresolved 0 | ewr_rows 21` (R-06). `select count(*)` on the relation → 147
(3 months × 7 groups², 43 zero-trip cells). Per month the grid sums to `fct_trip`'s billable
population: 29,985 / 30,017 / 35,956 trips and 816,057.76 / 813,885.68 / 999,242.38 revenue,
matching to the cent (R-02, R-03). Each borough's shares sum to 1 in each month (18
(month, borough) groups, all 1.0) and the 39 rows touching `unresolved` carry no share (R-04).

**Repo gates.** `python3 -m pytest tests -q` → 0, `223 passed`; `python3 .github/scripts/adr_lint.py`
→ 0; `ruff check .` → 0; `sqlfluff lint transformation/models` → 0.

**R-08.** `git show --stat e2384e3`: the new model, its `_agg.yml` entry, its unit-test file,
three singular tests, the contract, the Ossie document and the two regenerated
`assert_semantic_*.sql`; no existing model SQL, contract or mart changed.

**Artifacts.** `agg_borough_flow_monthly.sql` sha256 `b6b5c2d6b7fb1e9d…`,
`agg_borough_flow_monthly.odcs.yaml` `9d5cc68d9a26aaf9…`,
`assert_borough_flow_grid_is_complete.sql` `22a11e4f472c1ffd…`,
`assert_borough_flow_reconciles_to_billable_trips.sql` `eef88e8775d3c8c5…`,
`assert_borough_flow_shares_sum_to_one.sql` `3ff09c5763be5b9a…`,
`_unit_tests.yml` `41bb8fdaae64eead…`.
