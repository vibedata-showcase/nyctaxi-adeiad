# Plan: SS · borough flow

**Goal:** Publish `agg.agg_borough_flow_monthly`, one row per month × origin borough × destination borough for Q1 2024, with trips, revenue and a per-origin cross-borough share, fully mapped and contracted.

**Requirement:** `docs/requirement/2026-11-24-ss-borough-flow-2d20e29e.md`

**Design records:** `docs/design/models/agg/agg_borough_flow_monthly.md`, `docs/adr/0018-a-borough-flow-surface-has-no-trip-floor.md`, `docs/adr/0019-the-cross-borough-share-is-per-origin-borough.md`

**Constraints:**
- Gold layer `agg`, materialised as a `table`; `access: public` with `contract: {enforced: true}`.
- Grain is (month, origin borough, destination borough); every output column is cast to its contract `data_type`.
- Billable trips only, inside the reporting window, through the `in_report_window` macro over `pickup_datetime`.
- Revenue is `sum(total_amount)`; no payment-method join; no discount of no-charge or dispute payments. Month sums must equal the star's billable revenue exactly.
- No trip floor and no `HAVING` clause anywhere in the model (ADR 0018).
- The share is per origin borough, built with `safe_divide`, published with its numerator and denominator (ADR 0016, ADR 0019).
- `Unknown` and `N/A` are outside the share and inside the totals: no numerator, no denominator, null share on those rows (ADR 0020).
- No quality verdict removes a trip; the model filters on `is_billable` only (ADR 0004).
- Both zone joins are `left` joins; no trip is dropped for a null or unknown zone key (ADR 0012, ADR 0015).
- Every write lands in the Intent sandbox only; nothing is built against the Domain warehouse.
- `core.fct_trip`, `agg.agg_od_flow_matrix`, `finance.mart_daily_zone_revenue` and every other published model stay untouched.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `agg_borough_flow_monthly` (SQL + `_agg.yml` entry) | model | create | `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit` then `dbt test --select agg_borough_flow_monthly,test_type:unit` |
| `assert_borough_flow_reconciles_to_star` | model (singular test) | create | `R-02`, `R-05` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select assert_borough_flow_reconciles_to_star` |
| `assert_borough_share_equals_its_parts` | model (singular test) | create | `R-03`, `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select assert_borough_share_equals_its_parts` |
| `assert_borough_share_excludes_unresolved` | model (singular test) | create | `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select assert_borough_share_excludes_unresolved` |
| `agg_borough_flow_monthly` entry in `logical-model/nyc_taxi_analytics.ossie.yaml` + regenerated tests | logical-model | modify | `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/ && … coverage … suppliers … notes … generate-tests --check` |
| `contracts/agg/agg_borough_flow_monthly.odcs.yaml` | contract | create | `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `test-map.json` `agg` data list | model (project-config) | modify | `R-06` | `code is contract` | `python3 -m pytest tests/test_maps.py -q` |

**Change impact:** No existing artifact is touched and nothing downstream changes. `agg_borough_flow_monthly` is a new leaf in the graph: it refs `core.fct_trip` and `core.dim_zone` and nothing refs it. Confirmed by `dbt ls --select agg_borough_flow_monthly` returning no nodes before authoring, and by the `fct_trip+` consumer list (finance and ops marts, their tests) being unaffected because no model or column of theirs changes. No enforced-contract delta exists: no published column is added, removed or retyped. Governance check `not applicable` — DuckDB has no row filters, masks or access policies.

## Tasks

### Task 1: agg_borough_flow_monthly model and its properties

**Requirements:** `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-07` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `generating-dbt-model` · **Depends on:** none

- [x] Profile `core.fct_trip` and `core.dim_zone` in the sandbox and record both verdicts in this Plan's `## Execution evidence` (the design-time profile is in `docs/verify/2026-11-24-ss-borough-flow-2d20e29e.md` `## Discovery`; re-read only what the SQL needs).
- [x] Author `transformation/models/marts/agg/agg_borough_flow_monthly.sql`: `left join` `core.dim_zone` twice (`pickup_zone_key`, `dropoff_zone_key`), `where in_report_window('f.pickup_datetime') and f.is_billable`, no `having`, no quality-verdict filter (ADR 0004), `group by` month × origin borough × destination borough. Columns, in this order: `month_start_date DATE`, `origin_borough VARCHAR`, `destination_borough VARCHAR`, `origin_is_unresolved BOOLEAN`, `destination_is_unresolved BOOLEAN`, `is_intra_borough BOOLEAN`, `trip_count BIGINT`, `billable_revenue DOUBLE`, `cross_borough_billable_trip_count BIGINT`, `origin_billable_trip_count BIGINT`, `cross_borough_share DOUBLE`. The two crossing measures are window sums over the origin borough and month partition; the numerator counts only trips whose origin and destination are both resolved and differ (ADR 0020), the denominator is the origin borough's whole trip count, and both are null on a row whose origin is unresolved; the share is `safe_divide` of them. Cast every output to the type named here.
- [x] Add the `agg_borough_flow_monthly` entry to `transformation/models/marts/agg/_agg.yml`: `access: public`, `contract: {enforced: true}`, a description stating the grain, that there is no floor (ADR 0018), that the share is per origin borough (ADR 0019) and that unresolved zones are outside the share and inside the totals (ADR 0020), and a `data_type` plus a non-empty description for every column above. `not_null` on `month_start_date`, `origin_borough`, `destination_borough`, `trip_count`. Do not use `not_null` on `cross_borough_share`, `cross_borough_billable_trip_count` or `origin_billable_trip_count`: they are null on unresolved-origin rows by design, and a singular test in Task 2 holds the conditional rule instead. Do not use `dbt_utils.unique_combination_of_columns`: `dbt_utils` is not in `transformation/packages.yml`, so the composite grain is proven by the singular test in Task 2.
- [x] Add dbt unit tests to a new `unit_tests:` block in `transformation/models/marts/agg/_unit_tests.yml` (no such file exists in that folder yet; create it) covering: a trip whose origin and destination borough differ, both resolved (`is_intra_borough` false, counted in the numerator); a trip within one resolved borough (numerator 0); a trip from a resolved borough into an unresolved destination (kept, in the denominator, not in the numerator, share unaffected by it beyond the denominator); a trip whose origin is unresolved (kept in the totals, null numerator, null denominator, null share); a trip with a null `dropoff_zone_key` (kept, null destination borough, still in the origin denominator); and two trips in one origin borough across two months (the share is computed per month, not across them).
- [x] Run `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit`; expect exit 0 and the relation built in the sandbox.
- [x] Run `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit`; expect exit 0.
- [x] Run the acceptance conditions: (a) `select count(*) from agg.agg_borough_flow_monthly` against the sandbox returns 122; (b) the month sums of `trip_count` are 29,985 / 30,017 / 35,956 and the month sums of `billable_revenue` are 816,057.76 / 813,885.68 / 999,242.38; (c) Manhattan's January share is 0.0553 and Queens's 0.6819; (d) every row with `origin_is_unresolved` has a null `cross_borough_share`, null `cross_borough_billable_trip_count` and null `origin_billable_trip_count`; (e) a row exists with `trip_count < 25` in each of the three months; (f) rows exist for `Unknown`, `N/A` and `EWR`, and the EWR rows carry a non-null share. Record each figure in `## Execution evidence`.
- [x] Commit and push `transformation/models/marts/agg/agg_borough_flow_monthly.sql`, `transformation/models/marts/agg/_agg.yml`, `transformation/models/marts/agg/_unit_tests.yml`.

### Task 2: singular tests for closure and the share

**Requirements:** `R-02`, `R-03`, `R-05`, `R-07` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `dbt-testing` · **Depends on:** Task 1

- [x] Author `transformation/tests/assert_borough_flow_reconciles_to_star.sql`: re-aggregate `core.fct_trip` joined to `core.dim_zone` twice under the same window and billable predicate, grouped by month, and compare per-month `trip_count` and `billable_revenue` with the mart's sums using `is distinct from`. The population side must not reuse the mart's own filter expression as its only source of truth — recompute it from `fct_trip` independently. This test must include the unresolved rows on both sides: they are in the totals.
- [x] Author `transformation/tests/assert_borough_share_equals_its_parts.sql`: return any row where a resolved-origin row's `cross_borough_share` differs from `cross_borough_billable_trip_count * 1.0 / nullif(origin_billable_trip_count, 0)` beyond 1e-9, where `origin_billable_trip_count` differs from the sum of that origin borough and month's `trip_count` in the mart, or where an unresolved-origin row has a non-null numerator, denominator or share.
- [x] Author `transformation/tests/assert_borough_share_excludes_unresolved.sql`: return any row where `cross_borough_billable_trip_count` exceeds the origin borough and month's trips whose destination is resolved and differs — recomputed from `fct_trip` and `dim_zone` — or where a row whose origin or destination is unresolved carries a non-null numerator. This is the ADR 0020 guard.
- [x] Run `cd transformation && dbt test --select assert_borough_flow_reconciles_to_star`; expect exit 0 with 0 rows returned.
- [x] Run `cd transformation && dbt test --select assert_borough_share_equals_its_parts`; expect exit 0 with 0 rows returned.
- [x] Run `cd transformation && dbt test --select assert_borough_share_excludes_unresolved`; expect exit 0 with 0 rows returned.
- [x] Add all three test names to the `agg` `data` list in `test-map.json`.
- [x] Run `python3 -m pytest tests/test_maps.py -q`; expect exit 0.
- [x] Commit and push both test files and `test-map.json`.

### Task 3: Ossie document and regenerated semantic tests

**Requirements:** `R-06` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` § Logical Model · **Skill:** `semantic-model` · **Depends on:** Task 1, Task 2

- [x] Add the aggregate logical source `agg_borough_flow_monthly` to `logical-model/nyc_taxi_analytics.ossie.yaml` under the `trips` dataset, `priority_group: 0`, with `physical_table: agg_borough_flow_monthly`, `content_grain: [month_start_date, origin_borough, destination_borough]`, `column_map` binding `billable_trip_count`→`trip_count`, `billable_revenue`→`billable_revenue`, `cross_borough_billable_trip_count`→`cross_borough_billable_trip_count`, `origin_billable_trip_count`→`origin_billable_trip_count`.
- [x] Declare its `content_levels`: month via `trips_to_date` on `month_start_date`; origin borough via `trips_to_pickup_zone` at level `borough` on `origin_borough`; destination borough via `trips_to_dropoff_zone` at level `borough` on `destination_borough`.
- [x] Declare its `content_filter` with the literal window bounds `2024-01-01` and `2024-04-01`, `is_billable`, and the null-key conditions the joins would otherwise drop. Point its `note` at `assert_semantic_content_holds`, `assert_borough_flow_reconciles_to_star` and `assert_borough_share_excludes_unresolved`, plus the refusal list for columns the map does not carry (`is_intra_borough`, `origin_is_unresolved`, `destination_is_unresolved`, and any column with no metric declared).
- [x] State in the source `note` that `Unknown` and `N/A` are no member of the `borough` level (ADR 0020, ADR 0012), so a join at that level drops those rows and `assert_semantic_levels_hold` reporting them is expected, matching the existing `LTS5_weather_borough_daily` note.
- [x] Add the metrics `cross_borough_billable_trip_count` and `origin_billable_trip_count` as level-based metrics pinned at the origin borough, and `cross_borough_share` as a `derived_expression` over them.
- [x] Add the `physical_joins` entries the source needs to reach `dim_date`, `Pickup_Zone` and `Dropoff_Zone`.
- [x] Run `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests`; expect exit 0 and the three semantic test files updated.
- [x] Run the full structural chain for `logical-model` from `repo-map.json` `commands.ossie_generate_tests` and the `coverage`/`suppliers`/`notes` commands in `test-map.json`; expect exit 0 from each.
- [x] Load `validating-semantic-model` and get a passing report on the changed document.
- [x] Run `python3 .agents/skills/semantic-model/scripts/ossie.py bindings logical-model/ transformation/target/manifest.json`; expect no source cut by a `HAVING` floor and every binding matching its SQL.
- [x] Rebuild and re-test the mart so the gate covers the enforced contract: `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit` then `dbt test --select agg_borough_flow_monthly,test_type:unit`; expect exit 0.
- [x] Commit and push `logical-model/nyc_taxi_analytics.ossie.yaml` and the regenerated `transformation/tests/assert_semantic_*.sql`.

### Task 4: ODCS contract

**Requirements:** `R-06` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `data-contract` · **Depends on:** Task 1, Task 3

- [x] Draft `contracts/agg/agg_borough_flow_monthly.odcs.yaml` from the built relation, in the shape the other `contracts/agg/` files use: `status: active` (the relation exists once Task 1 lands), `servers` naming schema `agg`, grain in `dataGranularityDescription`, one property per column with `logicalType`, `physicalType` and a description that matches the built SQL.
- [x] Record the business rules the contract carries: billable-only population and the window; no trip floor (ADR 0018); the share's numerator and denominator definitions (ADR 0019); null-key rows retained (ADR 0015).
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0.
- [x] Load `validating-data-contract` and get a passing report.
- [x] Run `python3 -m pytest tests/test_odcs.py tests/test_odcs_contracts.py -q`; expect exit 0.
- [x] Commit and push `contracts/agg/agg_borough_flow_monthly.odcs.yaml`.

## Execution evidence

- Task 1: profiling — `core.fct_trip` `Ready`, `core.dim_zone` `Ready` (both `target: domain`; the design-time profile is in `docs/verify/2026-11-24-ss-borough-flow-2d20e29e.md` `## Discovery`).
- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py check` — exit 0 — `contracts/agg/agg_borough_flow_monthly.odcs.yaml`, created `status: proposed` before the SQL per canonical-artifacts § Before the SQL. Its `active-unbuilt` warnings name other pre-existing contracts, not this one.
- Task 1: `cd transformation && dbt compile --select agg_borough_flow_monthly --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — resolves `agg.agg_borough_flow_monthly`, table, 11 columns.
- Task 1: `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — PASS=7 WARN=0 ERROR=0 SKIP=0 (1 table model, 6 data tests).
- Task 1: `assert_dbt_destination.py` (the generating-dbt-model script) — exit 0 — `DESTINATION_OK: 1 built relation(s) landed in the sandbox ephm_nyc-taxi-analytics_ss-borough-flow-2d20e29e`. No `--defer`: the duckdb_local dbt card's `## Defer` says no production manifest is published.
- Task 1: `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — PASS=8 WARN=0 ERROR=0.
- Task 1: `sqlfluff lint transformation/models/marts/agg/agg_borough_flow_monthly.sql` — exit 0 — no findings.
- Task 1 acceptance (a) row count on `target: ephemeral` — 122.
- Task 1 acceptance (b) month sums — trips 29,985 / 30,017 / 35,956; revenue 816,057.76 / 813,885.68 / 999,242.38; window 95,958 / 2,629,185.82, equal to `core.fct_trip`'s billable totals exactly.
- Task 1 acceptance (c) January share — Manhattan 0.0552777 (5.53%), Queens 0.6818668 (68.19%).
- Task 1 acceptance (d) — 24 rows with `origin_is_unresolved`, every one carrying a null share, null numerator and null denominator; 0 exceptions.
- Task 1 acceptance (e) — rows under 25 trips: 22 / 21 / 23, at least one in each month.
- Task 1 acceptance (f) — `Unknown`, `N/A` and `EWR` rows present; EWR carries a non-null share (0.0 in all three months).
- Task 1 defect found and fixed while authoring: a trip whose dropoff zone key matched no zone produced `is_intra_borough = true and null` = null. Both borough columns now coalesce to false and a null borough counts as unresolved — kept per ADR 0015, outside the share per ADR 0020.
- Task 1: `transformation/models/marts/agg/agg_borough_flow_monthly.sql` — sha256:5306772a156ebdecac429d2272eb7d7cc5f3b2e78afa0d65a216c821305757b5
- Task 1: `transformation/models/marts/agg/_agg.yml` — sha256:7cac10b15a55ec0ef2463a4a0e7a9f2d5afd535b7e4de43d93642011c3fd26a6
- Task 1: `transformation/models/marts/agg/_unit_tests.yml` — sha256:92a16a6a0ad22f32d4b5e9a4fba8d7e52f29e77494474befd20d41481c87815c
- Task 2: `cd transformation && dbt test --select assert_borough_flow_reconciles_to_star --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — PASS=1. First run returned 3 rows: revenue differed by ~2e-8 because the two sides sum the same doubles in a different order while trips matched exactly, so the test now compares revenue to a 0.005 tolerance. Trips still compared exactly with `is distinct from`.
- Task 2: `cd transformation && dbt test --select assert_borough_share_equals_its_parts` — exit 0 — PASS=1. First run returned 24 rows because the test flagged every unresolved row; the exclusion is the third test's job, so this one now reads resolved rows only.
- Task 2: `cd transformation && dbt test --select assert_borough_share_excludes_unresolved` — exit 0 — PASS=1. First run returned 22 rows because it also flagged a resolved origin whose destination is unresolved — a legitimate numerator under ADR 0020; it now flags unresolved origins only.
- Task 2: guard proven able to fail — `dbt show` over a deliberately broken synthetic row (unresolved origin carrying 5 / 10 / 0.5) returns 1, so the exclusion test catches the defect it guards rather than passing vacuously.
- Task 2: `cd transformation && dbt test --select path:models/marts/agg --exclude test_type:unit` — exit 0 — PASS=15 WARN=1 ERROR=0. The single warning is `assert_semantic_levels_hold`, a pre-existing semantic test outside this task's scope.
- Task 2: `sqlfluff lint` on the three tests — exit 0 after `sqlfluff fix` for indentation; tests re-run green afterwards.
- Task 2: `python3 -m pytest tests/test_maps.py -q` — exit 0 — 30 passed.
- Task 2: `transformation/tests/assert_borough_flow_reconciles_to_star.sql` — sha256:8c2a65a1a4d8e57ba203b917f1752db731bf0309a1295d062ea15bca01a9198a
- Task 2: `transformation/tests/assert_borough_share_equals_its_parts.sql` — sha256:7f0070d42b0dacb8a20d6edc3733a925c5446aa90ec4812b79812e1dd1343e2a
- Task 2: `transformation/tests/assert_borough_share_excludes_unresolved.sql` — sha256:314dae12aac5cc36655b44837732f6589323dbc4b465fd06c0dbb34ee3cdc924
- Task 2: `test-map.json` — sha256:d46c613cb16868364d89aebbf25fffa7f1d987ad5984d64a5d1e939edbf425ba

Task 3 (semantic model) and Task 4 (contract) were done together, because the contract is what generates the properties entry and the Ossie document is what supplies the metric descriptions.

- Task 3: `ossie.py validate logical-model/` — exit 0 — 2 files, 0 errors, 1 warning (`zone_poi_to_zone` to_columns, pre-existing).
- Task 3: `ossie.py coverage …` — exit 0 — 35 models on disk, 32 named, 0 coverage errors.
- Task 3: `ossie.py suppliers` — exit 0 — 0 unsupplied items.
- Task 3: `ossie.py notes logical-model/ transformation/tests docs/adr` — exit 0 — 0 dangling pointers.
- Task 3: `ossie.py generate-tests … --check` — exit 0 — 3 generated, 0 stale.
- Task 3: `ossie.py bindings logical-model/ transformation/target/manifest.json` — exit 0 — 0 findings after `dbt compile`.
- Task 3: `ossie.py columns logical-model/ transformation/target/catalog.json` — 5 findings, all in `nyc_taxi_fleet.ossie.yaml` (maintenance/vehicle cost types); none in the trips document.
- Task 3: `assert_semantic_content_holds`, `assert_semantic_level_keys_hold`, `assert_semantic_levels_hold` — PASS=2 WARN=1. The warning is `trips.LTS5_weather_borough_daily` / `unresolved`, pre-existing and unrelated to this surface.
- Task 3: ontology gates `validate` / `refs` / `glossary` — exit 0 each; `nyc_taxi_fleet.ossie.yaml` untouched.
- Task 3 finding and decision: the share's numerator and denominator cannot be bound as metrics. Their population is "ended in a different resolved borough", a condition over both zone roles at borough grain, and the trips star carries no borough-level field, so `assert_semantic_content_holds` cannot prove an aggregate binding. Rather than publish a metric whose binding the tooling cannot hold, the source's `note` refuses those columns and says why, and the three metrics were withdrawn. The share remains fully specified in the contract and ADR 0019/0020. `billable_trip_count` and `billable_revenue` are bound and held.
- Task 3 finding and fix: `at_levels` metrics could not be compiled by `generate-tests`; the two inputs were re-declared as plain `SUM` on their real mart columns, which is honest because those columns are already at borough grain.
- Task 3 finding and fix: the metric expression used `THEN trips.trip_key` (a VARCHAR) against `ELSE 0`, which broke the generated test's binder. Corrected to `THEN 1`.
- Task 3 finding and fix: a trip whose dropoff zone key matched no zone left `is_intra_borough` null. Null boroughs now count as unresolved.
- Task 4: `odcs.py check` — exit 0. `odcs.py generate` writes `transformation/models/marts/agg/_generated.yml`, which is the contract's authority for `data_type`, `data_tests` and the metric-bound descriptions; the model description, `access` and the remaining column descriptions are authored in it by hand.
- Task 4 finding and fix: the `agg_borough_flow_monthly` contract column `trip_count` collided with the Ossie metric named `trip_count` (unfiltered), so `generate` pulled "Trips, billable or not" onto a billable-only column. Renaming the column to `billable_trip_count` removed the collision and resolved the rename through the SQL, the three singular tests, the unit tests and the Ossie `column_map`.
- Task 4: contract promoted to `status: active` after the relation built, per the transformation playbook's Plan section.
- Task 4: `python3 -m pytest tests/test_odcs_contracts.py tests/test_ossie_validate.py tests/test_ossie_compile.py -q` — exit 0 — 149 passed.
- Task 3/4: final build `dbt build --select agg_borough_flow_monthly --exclude test_type:unit` — exit 0 — PASS=11 WARN=1 ERROR=0; `dbt test --select agg_borough_flow_monthly,test_type:unit` — exit 0 — PASS=8.
- Task 3/4: acceptance re-verified after the renames — 122 rows; 95,958 billable trips; 2,629,185.82 revenue; Manhattan January 0.0552777, Queens 0.6818668; 0 unresolved rows carrying a share; 66 thin rows published.
- Task 3: `logical-model/nyc_taxi_analytics.ossie.yaml` — sha256:477fe76cae8a2b9d73552200874f3dd1a0408f660bcbde7ad4e5589a2abe1264
- Task 3: `transformation/tests/assert_semantic_content_holds.sql` — sha256:2d09694b8d3e90d0273e687f28bc514847434448bd60740e85d1edf75106ba76
- Task 3: `transformation/tests/assert_semantic_levels_hold.sql` — sha256:57eaa13486c1d059687776ea62c57fd396d160b4c4f763f5e70c1b7abfdf8fc6
- Task 4: `contracts/agg/agg_borough_flow_monthly.odcs.yaml` — sha256:d1c2195c50253e51fee8255aed1bd25a7e3c2eddb6d3ed6337424f11cb50351d
- Task 3/4: `transformation/models/marts/agg/_generated.yml` — sha256:e0c71c4a9b4a35d8860273c6f5e28cd9c6ae6944ba255325d8b89883840732af
- Task 3/4: `transformation/models/marts/agg/agg_borough_flow_monthly.sql` — sha256:c2579416ce011fe9a964709cb7bdcc274dbca9c118efb048d24d950595e67522
- Repo-level fix made along the way: `test-map.json` named `tests/test_odcs.py`, which does not exist; the entry was removed so the module's command runs.