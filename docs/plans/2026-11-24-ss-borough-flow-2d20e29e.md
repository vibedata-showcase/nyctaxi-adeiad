# Plan: SS · borough flow

**Goal:** Publish `agg.agg_borough_flow_monthly`, one row per month × origin borough × destination borough for Q1 2024, with trips, revenue and a per-origin cross-borough share, fully mapped and contracted.

**Requirement:** `docs/requirement/2026-11-24-ss-borough-flow-2d20e29e.md`

**Design records:** `docs/design/models/agg/agg_borough_flow_monthly.md`, `docs/adr/0018-a-borough-flow-surface-has-no-trip-floor.md`, `docs/adr/0019-the-cross-borough-share-is-per-origin-borough.md`

**Constraints:**
- Gold layer `agg`, materialised as a `table`; `access: public` with `contract: {enforced: true}`.
- Grain is (month, origin borough, destination borough); every output column is cast to its contract `data_type`.
- Billable trips only, inside the reporting window, through the `in_report_window` macro over `pickup_datetime`.
- Revenue is `sum(total_amount)`; no payment-method join; no discount of no-charge or dispute payments.
- No trip floor and no `HAVING` clause anywhere in the model (ADR 0018).
- The share is per origin borough, built with `safe_divide`, published with its numerator and denominator (ADR 0016, ADR 0019).
- Both zone joins are `left` joins; no trip is dropped for a null or unknown zone key (ADR 0012, ADR 0015).
- Every write lands in the Intent sandbox only; nothing is built against the Domain warehouse.
- `core.fct_trip`, `agg.agg_od_flow_matrix`, `finance.mart_daily_zone_revenue` and every other published model stay untouched.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `agg_borough_flow_monthly` (SQL + `_agg.yml` entry) | model | create | `R-01`, `R-02`, `R-03`, `R-04`, `R-05` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit` then `dbt test --select agg_borough_flow_monthly,test_type:unit` |
| `assert_borough_flow_reconciles_to_star` | model (singular test) | create | `R-02`, `R-05` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select assert_borough_flow_reconciles_to_star` |
| `assert_borough_share_equals_its_parts` | model (singular test) | create | `R-03` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select assert_borough_share_equals_its_parts` |
| `agg_borough_flow_monthly` entry in `logical-model/nyc_taxi_analytics.ossie.yaml` + regenerated tests | logical-model | modify | `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/ && … coverage … suppliers … notes … generate-tests --check` |
| `contracts/agg/agg_borough_flow_monthly.odcs.yaml` | contract | create | `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `test-map.json` `agg` data list | model (project-config) | modify | `R-06` | `code is contract` | `python3 -m pytest tests/test_maps.py -q` |

**Change impact:** No existing artifact is touched and nothing downstream changes. `agg_borough_flow_monthly` is a new leaf in the graph: it refs `core.fct_trip` and `core.dim_zone` and nothing refs it. Confirmed by `dbt ls --select agg_borough_flow_monthly` returning no nodes before authoring, and by the `fct_trip+` consumer list (finance and ops marts, their tests) being unaffected because no model or column of theirs changes. No enforced-contract delta exists: no published column is added, removed or retyped. Governance check `not applicable` — DuckDB has no row filters, masks or access policies.

## Tasks

### Task 1: agg_borough_flow_monthly model and its properties

**Requirements:** `R-01`, `R-02`, `R-03`, `R-04`, `R-05` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `generating-dbt-model` · **Depends on:** none

- [ ] Profile `core.fct_trip` and `core.dim_zone` in the sandbox and record both verdicts in this Plan's `## Execution evidence` (the design-time profile is in `docs/verify/2026-11-24-ss-borough-flow-2d20e29e.md` `## Discovery`; re-read only what the SQL needs).
- [ ] Author `transformation/models/marts/agg/agg_borough_flow_monthly.sql`: `left join` `core.dim_zone` twice (`pickup_zone_key`, `dropoff_zone_key`), `where in_report_window('f.pickup_datetime') and f.is_billable`, no `having`, `group by` month × origin borough × destination borough. Columns, in this order: `month_start_date DATE`, `origin_borough VARCHAR`, `destination_borough VARCHAR`, `is_intra_borough BOOLEAN`, `trip_count BIGINT`, `billable_revenue DOUBLE`, `cross_borough_billable_trip_count BIGINT`, `origin_billable_trip_count BIGINT`, `cross_borough_share DOUBLE`. The two crossing measures are window sums over the origin borough and month partition, computed with `safe_divide` for the share. Cast every output to the type named here.
- [ ] Add the `agg_borough_flow_monthly` entry to `transformation/models/marts/agg/_agg.yml`: `access: public`, `contract: {enforced: true}`, a description stating the grain and that there is no floor (citing ADR 0018) and that the share is per origin borough (citing ADR 0019), and a `data_type` plus a non-empty description for every column above. `not_null` on `month_start_date`, `origin_borough`, `destination_borough`, `trip_count`, `origin_billable_trip_count`. Do not use `dbt_utils.unique_combination_of_columns`: `dbt_utils` is not in `transformation/packages.yml`, so the composite grain is proven by the singular test in Task 2.
- [ ] Add dbt unit tests to a new `unit_tests:` block in `transformation/models/marts/agg/_unit_tests.yml` (no such file exists in that folder yet; create it) covering: a trip whose origin and destination borough differ (`is_intra_borough` false, counted in the numerator); a trip within one borough (numerator 0); a trip with a null `dropoff_zone_key` (kept, null destination borough, still counted in the origin denominator); and two trips in one origin borough across two months (the share is computed per month, not across them).
- [ ] Run `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit`; expect exit 0 and the relation built in the sandbox.
- [ ] Run `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit`; expect exit 0.
- [ ] Run the acceptance conditions: (a) `select count(*) from agg.agg_borough_flow_monthly` against the sandbox returns 122; (b) the month sums of `trip_count` are 29,985 / 30,017 / 35,956; (c) `select count(*) from agg.agg_borough_flow_monthly where month_start_date = date '2024-01-01' and origin_borough='Manhattan' and destination_borough='Manhattan'` gives the intra value and the Manhattan share is 0.0601; (d) a row exists with `trip_count < 25` in each of the three months; (e) rows exist for boroughs `Unknown`, `N/A` and `EWR`. Record each figure in `## Execution evidence`.
- [ ] Commit and push `transformation/models/marts/agg/agg_borough_flow_monthly.sql`, `transformation/models/marts/agg/_agg.yml`, `transformation/models/marts/agg/_unit_tests.yml`.

### Task 2: singular tests for closure and the share

**Requirements:** `R-02`, `R-03`, `R-05` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `dbt-testing` · **Depends on:** Task 1

- [ ] Author `transformation/tests/assert_borough_flow_reconciles_to_star.sql`: re-aggregate `core.fct_trip` joined to `core.dim_zone` twice under the same window and billable predicate, grouped by month, and compare per-month `trip_count` and `billable_revenue` with the mart's sums using `is distinct from`. The population side must not reuse the mart's own filter expression as its only source of truth — recompute it from `fct_trip` independently.
- [ ] Author `transformation/tests/assert_borough_share_equals_its_parts.sql`: return any row where `cross_borough_share` differs from `cross_borough_billable_trip_count * 1.0 / nullif(origin_billable_trip_count, 0)` beyond 1e-9, or where `origin_billable_trip_count` differs from the sum of that origin borough and month's `trip_count` in the mart.
- [ ] Run `cd transformation && dbt test --select assert_borough_flow_reconciles_to_star`; expect exit 0 with 0 rows returned.
- [ ] Run `cd transformation && dbt test --select assert_borough_share_equals_its_parts`; expect exit 0 with 0 rows returned.
- [ ] Add both test names to the `agg` `data` list in `test-map.json`.
- [ ] Run `python3 -m pytest tests/test_maps.py -q`; expect exit 0.
- [ ] Commit and push both test files and `test-map.json`.

### Task 3: Ossie document and regenerated semantic tests

**Requirements:** `R-06` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` § Logical Model · **Skill:** `semantic-model` · **Depends on:** Task 1, Task 2

- [ ] Add the aggregate logical source `agg_borough_flow_monthly` to `logical-model/nyc_taxi_analytics.ossie.yaml` under the `trips` dataset, `priority_group: 0`, with `physical_table: agg_borough_flow_monthly`, `content_grain: [month_start_date, origin_borough, destination_borough]`, `column_map` binding `billable_trip_count`→`trip_count`, `billable_revenue`→`billable_revenue`, `cross_borough_billable_trip_count`→`cross_borough_billable_trip_count`, `origin_billable_trip_count`→`origin_billable_trip_count`.
- [ ] Declare its `content_levels`: month via `trips_to_date` on `month_start_date`; origin borough via `trips_to_pickup_zone` at level `borough` on `origin_borough`; destination borough via `trips_to_dropoff_zone` at level `borough` on `destination_borough`.
- [ ] Declare its `content_filter` with the literal window bounds `2024-01-01` and `2024-04-01`, `is_billable`, and the null-key conditions the joins would otherwise drop. Point its `note` at `assert_semantic_content_holds` and `assert_borough_flow_reconciles_to_star`, plus the refusal list for columns the map does not carry (`is_intra_borough`, and any column with no metric declared).
- [ ] Add the metrics `cross_borough_billable_trip_count` and `origin_billable_trip_count` as level-based metrics pinned at the origin borough, and `cross_borough_share` as a `derived_expression` over them.
- [ ] Add the `physical_joins` entries the source needs to reach `dim_date`, `Pickup_Zone` and `Dropoff_Zone`.
- [ ] Run `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests`; expect exit 0 and the three semantic test files updated.
- [ ] Run the full structural chain for `logical-model` from `repo-map.json` `commands.ossie_generate_tests` and the `coverage`/`suppliers`/`notes` commands in `test-map.json`; expect exit 0 from each.
- [ ] Load `validating-semantic-model` and get a passing report on the changed document.
- [ ] Run `python3 .agents/skills/semantic-model/scripts/ossie.py bindings logical-model/ transformation/target/manifest.json`; expect no source cut by a `HAVING` floor and every binding matching its SQL.
- [ ] Rebuild and re-test the mart so the gate covers the enforced contract: `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit` then `dbt test --select agg_borough_flow_monthly,test_type:unit`; expect exit 0.
- [ ] Commit and push `logical-model/nyc_taxi_analytics.ossie.yaml` and the regenerated `transformation/tests/assert_semantic_*.sql`.

### Task 4: ODCS contract

**Requirements:** `R-06` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `data-contract` · **Depends on:** Task 1, Task 3

- [ ] Draft `contracts/agg/agg_borough_flow_monthly.odcs.yaml` from the built relation, in the shape the other `contracts/agg/` files use: `status: active` (the relation exists once Task 1 lands), `servers` naming schema `agg`, grain in `dataGranularityDescription`, one property per column with `logicalType`, `physicalType` and a description that matches the built SQL.
- [ ] Record the business rules the contract carries: billable-only population and the window; no trip floor (ADR 0018); the share's numerator and denominator definitions (ADR 0019); null-key rows retained (ADR 0015).
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0.
- [ ] Load `validating-data-contract` and get a passing report.
- [ ] Run `python3 -m pytest tests/test_odcs.py tests/test_odcs_contracts.py -q`; expect exit 0.
- [ ] Commit and push `contracts/agg/agg_borough_flow_monthly.odcs.yaml`.

## Execution evidence