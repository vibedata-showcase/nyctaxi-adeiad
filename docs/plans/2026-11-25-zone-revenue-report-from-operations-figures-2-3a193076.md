# Plan: Zone revenue report from operations figures 2

**Goal:** Build `finance.mart_daily_zone_revenue` from `agg.agg_trip_zone_daily` instead of a second aggregation of `fct_trip`, with no published number changing.

**Requirement:** `docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-2-3a193076.md`

**Constraints:**
- The billable rule (ADR 0003) is applied in `agg_trip_zone_daily`; the report reads the verdict (ADR 0018).
- Every column both relations publish keeps its name, type, grain and value; additions only.
- `mart_daily_zone_revenue` keeps its name, schema, grain and eleven columns, so its ODCS contract, the Ossie source `LTS7_daily_zone_revenue` and the generated semantic tests keep resolving.
- The report reads no relation but `agg_trip_zone_daily`: no `dim_zone` re-join (7 zone natural keys carry two SCD2 versions).
- All-`non-billable` zone-days stay in the aggregate and are not published by the report.
- dbt runs use the `dev` target, which writes `VD_EPHM_DUCKDB_LOCAL_PATH`. No `--defer`, no `/data/cache`.
- Money is compared at the cent (`round(x, 2)`), never bit for bit.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `agg_trip_zone_daily` (SQL, `_agg.yml`) | model | modify | `R-02` | `docs/design/models/agg/agg_trip_zone_daily.md` | `dbt build --select agg_trip_zone_daily --exclude test_type:unit` |
| `contracts/agg/agg_trip_zone_daily.odcs.yaml` | contract | modify | `R-02` | `docs/design/models/agg/agg_trip_zone_daily.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `transformation/tests/assert_zone_daily_one_row_per_grain.sql` | model | create | `R-02` | `docs/design/models/agg/agg_trip_zone_daily.md` | `dbt build --select agg_trip_zone_daily --exclude test_type:unit` |
| `transformation/tests/assert_zone_daily_billable_within_total.sql` | model | create | `R-02` | `docs/design/models/agg/agg_trip_zone_daily.md` | `dbt build --select agg_trip_zone_daily --exclude test_type:unit` |
| `mart_daily_zone_revenue` (SQL, `_finance.yml`) | model | modify | `R-01`, `R-03`, `R-04`, `R-05`, `R-06`, `R-07` | `docs/design/models/finance/mart_daily_zone_revenue.md` | `dbt build --select mart_daily_zone_revenue --exclude test_type:unit` |
| `contracts/finance/mart_daily_zone_revenue.odcs.yaml` | contract | modify | `R-06`, `R-07` | `docs/design/models/finance/mart_daily_zone_revenue.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `transformation/tests/assert_revenue_report_matches_zone_daily.sql` | model | create | `R-05` | `docs/design/models/finance/mart_daily_zone_revenue.md` | `dbt build --select mart_daily_zone_revenue --exclude test_type:unit` |
| `logical-model/nyc_taxi_analytics.ossie.yaml` | logical-model | modify | `R-02`, `R-06` | `docs/design/models/agg/agg_trip_zone_daily.md`, `docs/design/models/finance/mart_daily_zone_revenue.md` | `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/` |
| `transformation/tests/assert_semantic_content_holds.sql`, `assert_semantic_levels_hold.sql` (regenerated) | model | modify | `R-06` | `docs/design/models/finance/mart_daily_zone_revenue.md` | `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests --check` |

**Change impact:** `agg_trip_zone_daily` is read by `mart_daily_zone_revenue` only (0 direct refs today); its downstream is `assert_semantic_content_holds`, `assert_semantic_levels_hold`, its ODCS contract `contracts/agg/agg_trip_zone_daily.odcs.yaml` and the Ossie source `LTS2_zone_day_agg`. `mart_daily_zone_revenue` has no downstream model; its downstream is its own generic tests, `assert_semantic_content_holds`, `assert_semantic_levels_hold`, contract `contracts/finance/mart_daily_zone_revenue.odcs.yaml` v1.0.1 and Ossie source `LTS7_daily_zone_revenue`. `fct_trip` and `dim_zone` lose a direct ref and change in no other way; no other mart is read or rebuilt.

## Tasks

### Task 1: agg_trip_zone_daily publishes billable measures and the reporting region

**Requirements:** `R-02` · **Design:** `docs/design/models/agg/agg_trip_zone_daily.md` · **Skill:** `generating-dbt-model`, then `data-contract` for its contract · **Depends on:** none

- [ ] Author `transformation/models/marts/agg/agg_trip_zone_daily.sql`: in the `daily` CTE keep every existing column and expression byte-identical, and add `billable_trip_count` (`count(*) filter (where f.is_billable)`), `billable_revenue`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue` (each `sum(<column>) filter (where f.is_billable)`, no `coalesce`), and `z.reporting_region` taken from the existing `dim_zone` join. Cast each double to `DOUBLE` and each count to `BIGINT` per the dialect card. Do not change the window functions, the joins, the window filter or the group by.
- [ ] Author `transformation/models/marts/agg/_agg.yml` for `agg_trip_zone_daily`: give every added column its `data_type` and a one-sentence description stating what it counts and its population; state that `trip_count` and `total_revenue` remain the all-trip figures. Add `not_null` to `billable_trip_count`, `billable_revenue` and `reporting_region` only if the build shows no null in them.
- [ ] Author `transformation/tests/assert_zone_daily_one_row_per_grain.sql`: returns any `(pickup_date, pickup_location_id)` group with more than one row. Grain test, the composite key having no per-column generic test.
- [ ] Author `transformation/tests/assert_zone_daily_billable_within_total.sql`: returns any row where `billable_trip_count > trip_count`, or any billable component sum that exceeds the matching all-trip sum, or `billable_revenue` that does not equal the sum of the four billable components when the residual is zero. `is distinct from` comparisons, so NULLs cannot pass silently.
- [ ] Edit `contracts/agg/agg_trip_zone_daily.odcs.yaml`: add the seven properties with their `logicalType`, `physicalType` and a `description` a consumer can act on, a `quality` rule `{type: library, metric: nullValues, mustBe: 0}` where the build proves no null (otherwise the stated reason there is none), and bump `version` to `1.1.0` (properties added). Then run `python3 .agents/skills/data-contract/scripts/odcs.py generate` and commit the generated keys it writes.
- [ ] Run `cd /workspace/transformation && dbt build --select agg_trip_zone_daily --exclude test_type:unit`; expect PASS for the model and every test on it.
- [ ] Run the acceptance condition of `R-02`: `dbt show --inline "select count(*) as rows_, count(*) filter (where billable_trip_count is null) as null_billable, sum(trip_count) as trips, sum(billable_trip_count) as billable_trips, round(sum(total_revenue),2) as rev, round(sum(billable_revenue),2) as billable_rev from {{ ref('agg_trip_zone_daily') }}"`; expect 7,997 rows, 0 nulls, 97,184 trips, 95,958 billable trips, 2,597,120.92 revenue, 2,629,185.82 billable revenue — the all-trip figures unchanged from today.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0 with no new warning.
- [ ] Commit and push the SQL, `_agg.yml`, the two tests, the contract and the generated keys.

### Task 2: The report reads the aggregate

**Requirements:** `R-01`, `R-03`, `R-04`, `R-05`, `R-06`, `R-07` · **Design:** `docs/design/models/finance/mart_daily_zone_revenue.md` · **Skill:** `generating-dbt-model`, then `data-contract` for its contract · **Depends on:** Task 1

- [ ] Note what the shipped report holds before the rebuild, so the comparison after it has both sides: read `domain` `select count(*) as rows_, sum(trip_count) as trips, round(sum(total_revenue),2) as revenue, count(distinct pickup_location_id) as zones from finance.mart_daily_zone_revenue` and record the figures. Expect 7,961 / 95,958 / 2,629,185.82 / 261. `domain` is read-only and stays as shipped while the sandbox is rebuilt.
- [ ] Author `transformation/models/marts/finance/mart_daily_zone_revenue.sql` to read `{{ ref('agg_trip_zone_daily') }}` only: select `pickup_date as trip_date`, `pickup_location_id`, `borough_name as borough`, `zone_name`, `reporting_region`, `billable_trip_count as trip_count`, `billable_fare_revenue as fare_revenue`, `billable_tip_revenue as tip_revenue`, `billable_surcharge_revenue as surcharge_revenue`, `billable_toll_revenue as toll_revenue`, `billable_revenue as total_revenue`; filter `billable_trip_count > 0` and `in_report_window('agg_trip_zone_daily.pickup_date')`. Cast each column to the type its contract declares. No `join`, no `fct_trip`, no `dim_zone`.
- [ ] Edit `transformation/models/marts/finance/_finance.yml`: correct `trip_count`'s description to state that the column counts billable trips in the reporting window, and give every column whose description would otherwise change meaning a description that matches the built relation. Keep `contract: {enforced: true}` and every `data_type` and test as they are.
- [ ] Author `transformation/tests/assert_revenue_report_matches_zone_daily.sql`: returns any row where a published cell differs from the aggregate's billable cell for the same `(pickup_date = trip_date, pickup_location_id)` at the cent, or where a billed zone-day is missing from either side. This holds `R-01`'s wiring and `R-05`'s equivalence inside the project.
- [ ] Edit `contracts/finance/mart_daily_zone_revenue.odcs.yaml`: add `description` to `trip_count` stating the billable population (a description-only change, so `version` moves to `1.0.2`); change no property, type, quality rule or relationship, and leave `primaryKey`, `required` and the eleven properties exactly as they are. Run `python3 .agents/skills/data-contract/scripts/odcs.py generate` and commit anything it writes.
- [ ] Run `cd /workspace/transformation && dbt build --select mart_daily_zone_revenue --exclude test_type:unit`; expect PASS.
- [ ] Run the acceptance conditions, each as its own query:
  - `R-03`: `dbt show --inline "select sum(trip_count) as trips, round(sum(total_revenue), 2) as revenue from {{ ref('mart_daily_zone_revenue') }} where trip_date >= cast('2024-01-01' as date) and trip_date < cast('2024-04-01' as date)"`; expect 95,958 and 2,629,185.82.
  - `R-04`: the same filtered to `zone_name = 'JFK Airport'`; expect 4,120 and 337,711.05.
  - `R-05`: compare the rebuilt relation against the shipped `domain` relation row by row, at the cent, from outside dbt so the built relation is read where it landed: a read-only query joining `domain` `finance.mart_daily_zone_revenue` to the ephemeral `finance.mart_daily_zone_revenue` on `(trip_date, pickup_location_id)` as a full outer join, counting unmatched rows and rows differing on any of the eleven columns (`round(x,2)` on the six money columns, `is distinct from` throughout). Expect 7,961 rows on each side, 0 unmatched, 0 differing. A full outer join across the two warehouses is not one statement on this platform: export the rebuilt relation to a session-local CSV and join it to `domain` in the comparison query, then delete the export.
  - `R-06`: `dbt show --inline "select column_name, data_type from information_schema.columns where table_schema = 'finance' and table_name = 'mart_daily_zone_revenue' order by ordinal_position"`; expect the same eleven columns in the same order with the same types as the baseline.
  - `R-01`: `dbt ls --select 1+mart_daily_zone_revenue --resource-type model --exclude mart_daily_zone_revenue`; expect exactly `agg_trip_zone_daily`.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0 with no new warning.
- [ ] Delete any session-local export made for the `R-05` comparison, then commit and push the SQL, `_finance.yml`, the test, the contract and generated keys.

### Task 3: The semantic layer's notes describe the new placement

**Requirements:** `R-02`, `R-06` · **Design:** `docs/design/models/agg/agg_trip_zone_daily.md`, `docs/design/models/finance/mart_daily_zone_revenue.md` · **Skill:** `semantic-model`, then `validating-semantic-model` · **Depends on:** Tasks 1, 2

- [ ] Edit `logical-model/nyc_taxi_analytics.ossie.yaml`: rewrite `LTS2_zone_day_agg`'s `note` so it no longer contrasts its own `trip_count` with a billable report column, and states that the table now carries the billable measures the revenue report reads. Rewrite `LTS7_daily_zone_revenue`'s `note` so it says the mart inherits the billable verdict from `agg_trip_zone_daily` instead of applying it. Change no `column_map`, `content_levels`, `content_filter`, dataset, metric or physical table.
- [ ] Regenerate the semantic tests: `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests`. Commit them only if the command changes them.
- [ ] Run the chain, each as its own command and each expecting exit 0:
  - `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/`
  - `python3 .agents/skills/semantic-model/scripts/ossie.py coverage logical-model/ transformation/models/marts/core transformation/models/marts/agg transformation/models/marts/finance transformation/models/marts/ops --exclude agg.agg_od_flow_matrix --exclude finance.mart_revenue_component_bridge --exclude core.dim_fare_regime`
  - `python3 .agents/skills/semantic-model/scripts/ossie.py suppliers logical-model/`
  - `python3 .agents/skills/semantic-model/scripts/ossie.py notes logical-model/ transformation/tests docs/adr`
  - `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests --check`
- [ ] Run `cd /workspace/transformation && dbt build --select assert_semantic_content_holds assert_semantic_levels_hold --exclude test_type:unit`; expect PASS, proving the bindings still hold against the rebuilt relations.
- [ ] Run `validating-semantic-model`; expect a passing report.
- [ ] Commit and push the document and any regenerated test.

## Execution evidence

<!-- Append-only, one line when a task's checkbox flips. -->
