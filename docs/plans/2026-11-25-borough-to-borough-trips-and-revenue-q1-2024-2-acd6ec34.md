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

- [ ] Profile `core.fct_trip` and `core.dim_zone` on the `domain` target per the profiling reference and record each verdict in `## Execution evidence`; the Verification's `## Discovery` already holds this intent's probes.
- [ ] Author `transformation/models/marts/agg/agg_borough_flow_monthly.sql`: `fct_trip` joined `left` to `core.dim_zone` twice (pickup, dropoff), filtered on `in_report_window('f.pickup_datetime')` and `f.is_billable`, grouped by the month of `pickup_date`, the origin borough and the destination borough, carrying `trip_count`, `total_revenue`, `is_cross_borough`, `cross_borough_trip_count` (a window sum over the origin-month partition) and `origin_trip_count` (the partition total), with `cross_borough_share` from `safe_divide`.
- [ ] Add the model's entry to `transformation/models/marts/agg/_agg.yml` with `access: public`, a description stating the grain, the billable population, the absent floor, the unresolved and out-of-state destinations and the non-additivity of the two repeated counts, and one description per column.
- [ ] Author `transformation/models/marts/agg/_unit_tests.yml` with unit tests covering: a same-borough row carrying `is_cross_borough` false and excluded from `cross_borough_trip_count`; a differing destination counted in it; a null destination borough (unmatched zone key) kept as a row and treated as crossing; and the denominator equal to the whole origin-month including the rows of other destinations.
- [ ] Author `transformation/tests/assert_borough_flow_share_reconciles.sql`: returns any row where `cross_borough_trip_count` differs from the sum of its origin-month's rows whose destination differs, or `origin_trip_count` from that month's total, or the share from the ratio of the two.
- [ ] Run `cd transformation && dbt deps` if `dbt_packages/` is absent, then `dbt build --select agg_borough_flow_monthly --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'`; expect exit 0.
- [ ] Run `python3 "$SKILL_DIR/../../scripts/assert_dbt_destination.py"` with the skill's own directory substituted; expect exit 0, then the ephemeral workspace marker.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate` to write `contract: {enforced: true}`, every `data_type` and every `data_tests`; expect exit 0 and the keys present in `_agg.yml`.
- [ ] Run `cd transformation && dbt build --select agg_borough_flow_monthly --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` again, so the enforced contract is the one that built; expect exit 0.
- [ ] Add the agg layer's `unit` selector and the new singular test to `test-map.json`, then run `python3 -m pytest tests/test_maps.py -q`; expect exit 0.
- [ ] Run the acceptance conditions of `R-01`…`R-07` from `## Discovery`'s independent queries; expect 122 rows, three months, every origin-month reconciling, no zero `trip_count`, and Manhattan January 2024 at 6.01%.
- [ ] Commit and push the SQL, `_agg.yml`, `_unit_tests.yml`, the singular test and `test-map.json`.

### Task 3: the semantic source, the contract set active, the rebuild

**Requirements:** `R-08` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `semantic-model` · **Depends on:** Task 2

- [ ] Add the aggregate logical source `LTS10_borough_flow_month` to the `trips` dataset in `logical-model/nyc_taxi_analytics.ossie.yaml`: `physical_table: agg_borough_flow_monthly`, `priority_group: 0`, `content_grain: [trip_month, origin_borough, dest_borough]`, `column_map` binding `billable_trip_count` and `billable_revenue`, `content_levels` at the month level and at the borough level of both zone roles, and a `content_filter` carrying the window dates, `is_billable`, and the two joins' non-null keys as the inner-join equivalents.
- [ ] Refuse the share and its two counts in that source's `note`, naming each and why (they compare the two zone roles, and the two counts are not additive across destination rows), and point the note at `assert_borough_flow_share_reconciles`.
- [ ] Set `contracts/agg/agg_borough_flow_monthly.odcs.yaml` to `status: active` and re-run `odcs.py generate`, then rebuild the mart so the gate covers the enforced contract.
- [ ] Regenerate the semantic tests: `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests`.
- [ ] Run the structural chain quoted in the scope row's Gate; expect exit 0 from every command, then a passing `validating-semantic-model` review with its findings recorded.
- [ ] Re-run `python3 .agents/skills/semantic-model/scripts/ossie.py validate ontology/ && python3 .agents/skills/semantic-model/scripts/ossie.py refs ontology/ logical-model/ && python3 .agents/skills/semantic-model/scripts/ossie.py glossary ontology/ CONTEXT.md`; expect exit 0 and no ontology edit, because no dataset, concept or mapping moves.
- [ ] Commit and push the Ossie document, the regenerated tests and the contract.

## Execution evidence
- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py check` — exit 0 — `contracts/agg/agg_borough_flow_monthly.odcs.yaml` (status proposed, 9 properties) — sha256:a170bea015c83ca3397bf315110f4e33f5b2632ddf93c4cc6a58fb415ead503b
