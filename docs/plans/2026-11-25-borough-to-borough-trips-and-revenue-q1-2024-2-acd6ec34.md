# Plan: Borough-to-borough trips and revenue, Q1 2024

**Goal:** Publish `agg.agg_borough_flow_monthly` — one row per month, origin borough and destination borough, with the trips, the revenue and the cross-borough share, enforceable through an ODCS contract and reachable from the semantic layer.

**Requirement:** `docs/requirement/2026-11-25-borough-to-borough-trips-and-revenue-q1-2024-2-acd6ec34.md`

**Constraints:**
- Platform `duckdb_local`: every build runs against the Intent sandbox through the configured profile; no `--defer` and nothing under `/data/cache` is read, because the Domain publishes no production manifest.
- Folder `transformation/models/marts/agg/` resolves to schema `agg` (`+schema: agg` in `dbt_project.yml`). No model carries its own `schema` config.
- Model name `agg_borough_flow_monthly`, properties in `transformation/models/marts/agg/_agg.yml`, one YAML per folder.
- Billable only (`fct_trip.is_billable`), inside the reporting window via the `in_report_window` macro; revenue is `sum(total_amount)`.
- No minimum-trip floor (ADR 0018); a pair with no billable trip is omitted (R-04); unresolved and out-of-state destinations are published and count as crossings (ADR 0019).
- A rate is computed as a ratio of stated sums with `safe_divide`, never stored without its numerator and denominator (ADR 0016).
- `access: public` with `contract: {enforced: true}`; every `data_type`, `data_tests` and `contract` key is written by `odcs.py generate`, never by hand.
- Money and value comparisons are made at the cent or with an explicit tolerance, never bit for bit.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `contracts/agg/agg_borough_flow_monthly.odcs.yaml` | contract | create | `R-01` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `agg_borough_flow_monthly` (`transformation/models/marts/agg/agg_borough_flow_monthly.sql`, `_agg.yml`) | model | create | `R-01` `R-02` `R-03` `R-04` `R-05` `R-06` `R-07` `R-08` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt build --select agg_borough_flow_monthly --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` |
| `transformation/models/marts/agg/_unit_tests.yml` | model | create | `R-05` `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit` |
| `transformation/tests/assert_borough_flow_share_reconciles.sql` | model | create | `R-02` `R-05` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select assert_borough_flow_share_reconciles` |
| `test-map.json` | project-config | modify | `R-01` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 -m pytest tests/test_maps.py -q` |
| `LTS10_borough_flow_month` in `logical-model/nyc_taxi_analytics.ossie.yaml` | logical-model | modify | `R-08` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/ && python3 .agents/skills/semantic-model/scripts/ossie.py coverage logical-model/ transformation/models/marts/core transformation/models/marts/agg transformation/models/marts/finance transformation/models/marts/ops --exclude agg.agg_od_flow_matrix --exclude finance.mart_revenue_component_bridge --exclude core.dim_fare_regime && python3 .agents/skills/semantic-model/scripts/ossie.py suppliers logical-model/ && python3 .agents/skills/semantic-model/scripts/ossie.py notes logical-model/ transformation/tests docs/adr && python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests --check` |

**Change impact:** none downstream — `agg_borough_flow_monthly` is a new relation with no consumer in the repository. `fct_trip`, `dim_zone` and every published mart are read only: no column, filter or materialisation changes on them, so no existing relation is rebuilt.

## Tasks

### Task 1: the contract, proposed

**Requirements:** `R-01` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `data-contract` · **Depends on:** none

- [x] Author `contracts/agg/agg_borough_flow_monthly.odcs.yaml` from `contracts/agg/agg_od_flow_matrix.odcs.yaml`: same `apiVersion`, `kind` and `servers` block, a new `id`, `version: 1.0.0`, `status: proposed` because the table does not exist yet, `schema[].name: agg_borough_flow_monthly`.
- [x] Declare one property per output column with `logicalType` and `physicalType`, and a `dataGranularityDescription` stating the (month, origin borough, destination borough) grain, the billable population, the absent floor and the share's denominator.
- [x] Declare `required: true` and `quality: [{type: library, metric: nullValues, mustBe: 0}]` on `trip_month`, `origin_borough`, `dest_borough`, `trip_count`, `total_revenue`, `origin_trip_count`, `cross_borough_trip_count`, and on `is_cross_borough`; declare no `primaryKey` (a three-column key renders no per-column test and `profile` checks it instead).
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0 with the document shape-checked and the orphan, document-agreement and `--relations` checks skipped for `proposed`.
- [x] Commit and push `contracts/agg/agg_borough_flow_monthly.odcs.yaml`.

### Task 2: the model, its tests and its enforcement keys

**Requirements:** `R-01` … `R-08` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `generating-dbt-model` · **Depends on:** Task 1

- [x] Profile `core.fct_trip` and `core.dim_zone` on the `domain` target per the profiling reference and record each verdict in `## Execution evidence`; the Verification's `## Discovery` already holds this intent's probes.
- [x] Author `transformation/models/marts/agg/agg_borough_flow_monthly.sql`: `fct_trip` joined `left` to `core.dim_zone` twice (pickup, dropoff), filtered on `in_report_window('f.pickup_datetime')` and `f.is_billable`, grouped by the month of `pickup_date`, the origin borough and the destination borough, carrying `trip_count`, `total_revenue`, `is_cross_borough`, `cross_borough_trip_count` (a window sum over the origin-month partition) and `origin_trip_count` (the partition total), with `cross_borough_share` from `safe_divide`.
- [x] Add the model's entry to `transformation/models/marts/agg/_agg.yml` with `access: public`, a description stating the grain, the billable population, the absent floor, the unresolved and out-of-state destinations and the non-additivity of the two repeated counts, and one description per column.
- [x] Author `transformation/models/marts/agg/_unit_tests.yml` with unit tests covering: a same-borough row carrying `is_cross_borough` false and excluded from `cross_borough_trip_count`; a differing destination counted in it; a null destination borough (unmatched zone key) kept as a row and treated as crossing; and the denominator equal to the whole origin-month including the rows of other destinations.
- [x] Author `transformation/tests/assert_borough_flow_share_reconciles.sql`: returns any row where `cross_borough_trip_count` differs from the sum of its origin-month's rows whose destination differs, or `origin_trip_count` from that month's total, or the share from the ratio of the two.
- [x] Run `cd transformation && dbt deps` if `dbt_packages/` is absent, then `dbt build --select agg_borough_flow_monthly --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'`; expect exit 0.
- [x] Run `python3 "$SKILL_DIR/../../scripts/assert_dbt_destination.py"` with the skill's own directory substituted; expect exit 0, then the ephemeral workspace marker.
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate` to write `contract: {enforced: true}`, every `data_type` and every `data_tests`; expect exit 0 and the keys present in `_agg.yml`.
- [x] Run `cd transformation && dbt build --select agg_borough_flow_monthly --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` again, so the enforced contract is the one that built; expect exit 0.
- [x] Add the agg layer's `unit` selector and the new singular test to `test-map.json`, then run `python3 -m pytest tests/test_maps.py -q`; expect exit 0.
- [x] Run the acceptance conditions of `R-01`…`R-07` from `## Discovery`'s independent queries; expect 122 rows, three months, every origin-month reconciling, no zero `trip_count`, and Manhattan January 2024 at 6.01%.
- [x] Commit and push the SQL, `_agg.yml`, `_unit_tests.yml`, the singular test and `test-map.json`.

### Task 3: the semantic source, the contract set active, the rebuild

**Requirements:** `R-08` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `semantic-model` · **Depends on:** Task 2

- [x] Add the aggregate logical source `LTS10_borough_flow_month` to the `trips` dataset in `logical-model/nyc_taxi_analytics.ossie.yaml`: `physical_table: agg_borough_flow_monthly`, `priority_group: 0`, `content_grain: [trip_month, origin_borough, dest_borough]`, `column_map` binding `billable_trip_count` and `billable_revenue`, `content_levels` at the month level and at the borough level of both zone roles, and a `content_filter` carrying the window dates, `is_billable`, and the two joins' non-null keys as the inner-join equivalents.
- [x] Refuse the share and its two counts in that source's `note`, naming each and why (they compare the two zone roles, and the two counts are not additive across destination rows), and point the note at `assert_borough_flow_share_reconciles`.
- [x] Set `contracts/agg/agg_borough_flow_monthly.odcs.yaml` to `status: active` and re-run `odcs.py generate`, then rebuild the mart so the gate covers the enforced contract.
- [x] Regenerate the semantic tests: `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests`.
- [x] Run the structural chain quoted in the scope row's Gate; expect exit 0 from every command, then a passing `validating-semantic-model` review with its findings recorded.
- [x] Re-run `python3 .agents/skills/semantic-model/scripts/ossie.py validate ontology/ && python3 .agents/skills/semantic-model/scripts/ossie.py refs ontology/ logical-model/ && python3 .agents/skills/semantic-model/scripts/ossie.py glossary ontology/ CONTEXT.md`; expect exit 0 and no ontology edit, because no dataset, concept or mapping moves.
- [x] Commit and push the Ossie document, the regenerated tests and the contract.

## Execution evidence
- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py check` — exit 0 — `contracts/agg/agg_borough_flow_monthly.odcs.yaml` (status proposed, 9 properties) — sha256:a170bea015c83ca3397bf315110f4e33f5b2632ddf93c4cc6a58fb415ead503b
- Task 2 profiling: `core.fct_trip` — Ready, read on target `domain` (`lakehouse_schema` core.fct_trip: 43 columns, pickup_datetime TIMESTAMP, pickup_date DATE, pickup_zone_key/dropoff_zone_key VARCHAR, total_amount DOUBLE, is_billable BOOLEAN; the Verification's Discovery adds 97,184 in-window trips, 95,958 billable, 0 null zone keys, 0 null totals) — `core.dim_zone` — Ready, read on target `domain` (zone_key VARCHAR, borough_name VARCHAR; 8 borough groups, both trip zone keys resolve on every in-window trip)
- Task 2 unit tests: `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — PASS=3 ERROR=0
- Task 2 build: `cd transformation && dbt build --select agg_borough_flow_monthly --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — `agg.agg_borough_flow_monthly` created in the sandbox, PASS=5 ERROR=0 (1 table model, 1 singular test, 3 unit tests) — defer: not applicable, the Domain publishes no production manifest — sha256:d741feb37c60be59e0339b043aa6030bcc33c758f11ffe7c68acc0364e2e29e7
- Task 2 destination: `python "/data/default-plugins/vibedata-data-engineering/0.148.28/skills/generating-dbt-model/../../scripts/assert_dbt_destination.py"` — exit 0 — DESTINATION_OK 1 relation in `ephm_nyc-taxi-analytics_new-intent-acd6ec34`; marker `ephemeral_workspace_marker.py init` exit 0, status created
- Task 2 lint: `sqlfluff lint transformation/models/marts/agg/agg_borough_flow_monthly.sql` — exit 0 (the first draft failed ST03/AL08/PRS on `is distinct from` in a grouped select; the model now states the null-safe comparison as a CASE)
- Task 2 docs: `cd transformation && dbt docs generate --static --target dev` — exit 0 — catalog written, `/data/ephm_dbt_docs/static_index.html` refreshed
- Task 2 acceptance (built sandbox table, independent recomputation from `core.fct_trip` + `core.dim_zone`): 122 rows, 3 months 2024-01-01…2024-03-01, 0 duplicate grain, 0 zero-trip rows, 0 rows where trips, revenue at the cent, `origin_trip_count`, `cross_borough_trip_count` or the share (within 1e-12) differ from the recomputation; 8 origin and 8 destination groups, 42 destination rows on the unresolved or out-of-state groups; Manhattan Jan share 6.01% (26,593 origin, 1,598 crossing), Queens 71.54% — the values R-06 requires
- Task 2 maps: `python3 -m pytest tests/test_maps.py -q` — exit 0 — 31 passed
- Task 3 semantics: LTS10_borough_flow_month called for renaming the counts, which #1 evidence records; the source's note refuses is_cross_borough, cross_borough_billable_trip_count, origin_billable_trip_count and cross_borough_share and points at assert_borough_flow_share_reconciles; physical_tables gained agg_borough_flow_monthly and physical_joins gained to_Pickup_Zone, to_Dropoff_Zone and to_dim_date — `logical-model/nyc_taxi_analytics.ossie.yaml` sha256:1c046faad5ff43d1e2124058c874794f7e8594c3359430936f33c165ce6a43bc
- Task 3 contract: status `active`, version 1.0.0, nine properties renamed to the column names the model publishes — `python3 .agents/skills/data-contract/scripts/odcs.py generate` — exit 0 — `contract: {enforced: true}`, one data_type and the six not_null data_tests written into `transformation/models/marts/agg/_agg.yml`
- Task 3 build: `cd transformation && dbt build --select agg_borough_flow_monthly --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — PASS=13 WARN=1 ERROR=0; the one warning is `assert_semantic_levels_hold` reporting `trips.LTS5_weather_borough_daily: trips_to_pickup_zone borough key is no member` for the `unresolved` sentinel, a pre-existing finding on another source and not this model's
- Task 3 destination: `python "/data/default-plugins/vibedata-data-engineering/0.148.28/skills/generating-dbt-model/../../scripts/assert_dbt_destination.py"` — exit 0 — DESTINATION_OK 1 relation in the sandbox
- Task 3 acceptance after the restructure (independent recomputation from `core.fct_trip` + `core.dim_zone`): 122 rows, 0 duplicate grain, 0 zero-trip rows, 0 unmatched, 0 rows differing on trips or revenue at the cent, on either count, or on the share within 1e-12
- Task 3 gates: `ossie.py validate` exit 0 (one pre-existing warning), `coverage` 32 named of 35, 0 errors, `suppliers` 0 unsupplied, `notes` 0 dangling, `generate-tests --check` 0 stale; `bindings` 0 errors and no finding for LTS10 after the SQL was restructured to a joined origin-month aggregate (the first version's window functions hid the aggregation, which the check reported as `bindings/unproven`); `columns` 5 findings, all on other documents, none on this model
- Task 3 ontology: `ossie.py validate ontology/` exit 0, `refs` exit 0 with 2 pre-existing warnings, `glossary` exit 0 — no ontology edit, since no dataset, concept or mapping moved
- Task 3 lint: `sqlfluff lint transformation/models/marts/agg/agg_borough_flow_monthly.sql` — exit 0
