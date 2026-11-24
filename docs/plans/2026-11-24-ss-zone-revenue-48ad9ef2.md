# Plan: SS · zone revenue

**Goal:** Build `finance.mart_daily_zone_revenue` from the operations aggregate `agg.agg_trip_zone_daily`, with every published number, row and column unchanged.

**Requirement:** `docs/requirement/2026-11-24-ss-zone-revenue-48ad9ef2.md`

**Constraints:**
- The report's eleven columns, names, types and order do not change; only the relation it reads changes (`R-04`).
- `agg_trip_zone_daily` gains columns and loses none; its existing columns keep every value (`R-06`).
- The billable verdict is `fct_trip.is_billable`, computed in `int_trip_quality_flags`; nothing re-derives it (`docs/adr/0003-billable-trip-definition-and-where-it-applies.md`).
- Money is compared at the cent (`round(x, 2)`); DuckDB float aggregation is not bit-reproducible (`transformation/tests`, `.agents/skills/dbt-testing/SKILL.md`).
- Every contract change is written before the SQL and enforced through `odcs.py generate`, never by hand (`.agents/skills/data-contract/SKILL.md`).
- A boundary model that changes carries its Ossie document in the same change (`repo-map.json` `modules.logical_model`).
- Contracts: added properties are a minor version, prose is a patch (`.agents/skills/data-contract/SKILL.md`, "Which version?").
- Column names: `agg_`/`mart_` prefixes per `.agents/skills/dbt-models/SKILL.md`; no `select *` in a mart.
- Schema: `agg` and `finance`, as recorded in the two design records (user answer, 2026-11-24).
- Platform: dbt-duckdb, target `dev`, sandbox file at `VD_EPHM_DUCKDB_LOCAL_PATH`; no `--defer` (no production manifest is published).

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `agg_trip_zone_daily` (`transformation/models/marts/agg/agg_trip_zone_daily.sql`, `_agg.yml`) | model | modify | `R-05`, `R-06`, `R-07` | `docs/design/models/agg/agg_trip_zone_daily.md` | `cd transformation && dbt build --select agg_trip_zone_daily --exclude test_type:unit` then `dbt test --select agg_trip_zone_daily,test_type:unit` |
| `assert_trip_zone_daily_one_row_per_grain` (`transformation/tests/assert_trip_zone_daily_one_row_per_grain.sql`) | model (singular test) | create | `R-05` | `docs/design/models/agg/agg_trip_zone_daily.md` | `cd transformation && dbt test --select assert_trip_zone_daily_one_row_per_grain` |
| `contracts/agg/agg_trip_zone_daily.odcs.yaml` | contract | modify | `R-05`, `R-10` | `docs/design/models/agg/agg_trip_zone_daily.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check && python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main` |
| `logical-model/nyc_taxi_analytics.ossie.yaml` (`LTS2_zone_day_agg`) | logical-model | modify | `R-10` | `docs/design/models/agg/agg_trip_zone_daily.md` | `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/` then `coverage`, `suppliers`, `notes` and `generate-tests --check` |
| `assert_semantic_content_holds` (`transformation/tests/assert_semantic_content_holds.sql`) | model (generated singular test) | modify | `R-10` | `docs/design/models/agg/agg_trip_zone_daily.md` | `cd transformation && dbt test --select assert_semantic_content_holds assert_semantic_levels_hold` |
| `mart_daily_zone_revenue` (`transformation/models/marts/finance/mart_daily_zone_revenue.sql`, `_finance.yml`) | model | modify | `R-01`, `R-02`, `R-03`, `R-04`, `R-08`, `R-09` | `docs/design/models/finance/mart_daily_zone_revenue.md` | `cd transformation && dbt build --select mart_daily_zone_revenue --exclude test_type:unit` |
| `contracts/finance/mart_daily_zone_revenue.odcs.yaml` | contract | modify | `R-04`, `R-09`, `R-10` | `docs/design/models/finance/mart_daily_zone_revenue.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check && python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main` |

**Change impact:** `dbt ls --select 1+mart_daily_zone_revenue --exclude mart_daily_zone_revenue` returns `dim_zone` and `fct_trip` as its only direct refs and `dbt ls --select mart_daily_zone_revenue+` returns the mart alone, so nothing downstream of the report moves. `dbt ls --select agg_trip_zone_daily+` likewise returns the aggregate alone: no dbt model reads it, so its new columns reach no model; they reach the semantic layer (`LTS2_zone_day_agg`) and the two generated singular tests, which Task 1 carries.

| Model | Layer | Bucket | Anticipated change | Notes |
| --- | --- | --- | --- | --- |
| `mart_daily_zone_revenue` | finance | target | Reads `agg_trip_zone_daily`; the same eleven columns with the same values. Enforced contract. | The published shape is unchanged, so no contract break; the contract's prose changes only. |
| `agg_trip_zone_daily` | agg | target | Six columns added, billable measures and `reporting_region`. Enforced contract. | Additive, a minor contract version. Existing columns unchanged. |
| `dim_zone` | core | shared upstream | No change expected: the mart stops reading it, the aggregate keeps reading it as it does today. | Still feeds `fct_trip`, the aggregate and four other `agg` models. |
| `fct_trip` | core | shared upstream | No change expected: the aggregate keeps reading it and adds conditional aggregates. | Incremental model with an enforced contract; untouched. |
| `assert_semantic_content_holds`, `assert_semantic_levels_hold` | test | downstream consumer | Regenerated comparisons: `LTS2_zone_day_agg` gains the two billable metrics, `LTS7_daily_zone_revenue` keeps its two. | Both must return no rows. |

No register holds a second consumer of either relation: the semantic layer and the two contracts are the only in-repo readers, and no `governance` policy exists on this platform (DuckDB has no row filters or masks), so that check is `not applicable`.

## Tasks

### Task 1: `agg_trip_zone_daily` — the billable measures and `reporting_region`

**Requirements:** `R-05`, `R-06`, `R-07`, and the `R-10` half that covers the aggregate's contract and its Ossie source · **Design:** `docs/design/models/agg/agg_trip_zone_daily.md` · **Skill:** `data-contract` for the contract first, then `semantic-model` for the document, then `generating-dbt-model` for the SQL and tests · **Depends on:** none

- [ ] Confirm the sandbox is the write destination: `dbt deps` (the project has `packages.yml`), then read `VD_EPHM_DUCKDB_LOCAL_PATH` through `get_intent_context`, never the shell.
- [ ] Read the baseline: `python3 .agents/skills/data-contract/scripts/odcs.py check` and record its exit code before any edit.
- [ ] Write the contract change in `contracts/agg/agg_trip_zone_daily.odcs.yaml`: seven new properties — `billable_trip_count` (integer, `BIGINT`), `billable_revenue`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue` (number, `DOUBLE`) and `reporting_region` (string, `VARCHAR`) — each with a description stating what it counts and that the billable revenue columns are null when the zone-day has no billable trip, and bump `version` from `1.0.1` to `1.1.0` (added properties are a minor).
- [ ] Update `LTS2_zone_day_agg` in `logical-model/nyc_taxi_analytics.ossie.yaml`: add `billable_trip_count` → `billable_trip_count` and `billable_revenue` → `billable_revenue` to its `column_map`, and drop the sentence in its `note` that refuses those two metrics. Add no metric and no level; `reporting_region` stays unbound.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate` and `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests`; commit nothing yet. `generate` writes the dbt `description`s and the enforced-contract keys into `_agg.yml`.
- [ ] Author `transformation/models/marts/agg/agg_trip_zone_daily.sql`: keep the existing `daily` CTE and window block exactly, add `z.reporting_region` to the select and `group by`, and add six conditional aggregates beside the existing measures:
  ```sql
  count(*) filter (where f.is_billable) as billable_trip_count,
  sum(f.total_amount) filter (where f.is_billable) as billable_revenue,
  sum(f.fare_amount) filter (where f.is_billable) as billable_fare_revenue,
  sum(f.tip_amount) filter (where f.is_billable) as billable_tip_revenue,
  sum(f.total_surcharges) filter (where f.is_billable) as billable_surcharge_revenue,
  sum(f.tolls_amount) filter (where f.is_billable) as billable_toll_revenue,
  ```
  Cast `reporting_region` to `VARCHAR` and `billable_trip_count` to `BIGINT` (DuckDB coerces nothing to a contract type); leave the sum expressions as they are, since they are already `DOUBLE`. Write no `coalesce`: a null is the answer `R-07` asks for. Extend the file's header comment to say the billable measures are computed here beside the all-trip ones, in one scan.
- [ ] Author `transformation/tests/assert_trip_zone_daily_one_row_per_grain.sql` returning the rows that break the grain: `select pickup_date, pickup_location_id, count(*) as n from {{ ref('agg_trip_zone_daily') }} group by 1, 2 having count(*) > 1`, with a header comment naming the grain.
- [ ] Add unit tests to `transformation/models/marts/agg/_unit_tests.yml`, with fixtures over `ref('fct_trip')` and `ref('dim_zone')` that supply every column the model reads. Cases: **one** — a zone-day with two billable and one non-billable trip gives `billable_trip_count` 2, an all-trip `trip_count` 3, and each billable component equal to the billable trips only; **two** — a zone-day whose only trips are non-billable gives `billable_trip_count` 0 and NULL in all five billable revenue columns, with a non-zero all-trip `total_revenue`; **three** — two consecutive days of one zone, so the `lag` and rolling windows are pinned on the all-trip `trip_count` and `total_revenue` only. Each expected value is derived from these requirements and the design record, never from the SQL.
- [ ] Run `cd transformation && dbt build --select agg_trip_zone_daily --exclude test_type:unit`; expect exit 0 with the model, its contract, the singular test and the generic tests passing.
- [ ] Run `cd transformation && dbt test --select agg_trip_zone_daily,test_type:unit`; expect exit 0.
- [ ] Run the acceptance conditions: `R-05` — the built relation's columns and the grain query `select count(*) as rows, count(distinct pickup_date || '|' || cast(pickup_location_id as varchar)) as zone_days from agg.agg_trip_zone_daily` on `ephemeral` returns equal counts; `R-06` — `select sum(trip_count), round(sum(total_revenue),2), round(sum(total_miles),2), sum(attributed_driver_count) from agg.agg_trip_zone_daily` on `ephemeral` and on `domain` return the same values, and a full `except` on the eleven pre-existing columns returns 0 rows each way; `R-07` — `select count(*) from agg.agg_trip_zone_daily where billable_trip_count = 0 and (billable_revenue is not null or billable_fare_revenue is not null or billable_tip_revenue is not null or billable_surcharge_revenue is not null or billable_toll_revenue is not null)` returns 0, and every such row has `trip_count > 0`.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check && python3 .agents/skills/data-contract/scripts/odcs.py check --relations && python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main`; expect exit 0 from the chain.
- [ ] Run the semantic gates: `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/`, then `coverage logical-model/ transformation/models/marts/core transformation/models/marts/agg transformation/models/marts/finance transformation/models/marts/ops --exclude agg.agg_od_flow_matrix --exclude finance.mart_revenue_component_bridge --exclude core.dim_fare_regime`, then `suppliers logical-model/`, then `notes logical-model/ transformation/tests docs/adr`, then `generate-tests logical-model/ transformation/tests --check`; expect exit 0 and an empty supplier and dangling-pointer list from each.
- [ ] Run `cd transformation && dbt compile --select agg_trip_zone_daily` and then `python3 .agents/skills/semantic-model/scripts/ossie.py bindings logical-model/ transformation/target/manifest.json`; expect exit 0 with the two new bindings proven.
- [ ] Run `cd transformation && dbt test --select assert_semantic_content_holds assert_semantic_levels_hold`; expect exit 0 with no rows returned.
- [ ] Record `dbt docs generate` output path in the evidence, and run `python3 .agents/skills/semantic-model/scripts/ossie.py columns logical-model/ transformation/target/catalog.json`; expect exit 0.
- [ ] Commit and push `agg_trip_zone_daily.sql`, `_agg.yml`, `_unit_tests.yml`, the new singular test, the contract, the Ossie document and the regenerated `assert_semantic_content_holds.sql`.

### Task 2: `mart_daily_zone_revenue` reads the operations aggregate

**Requirements:** `R-01`, `R-02`, `R-03`, `R-04`, `R-08`, `R-09`, and the `R-10` half covering the mart's contract · **Design:** `docs/design/models/finance/mart_daily_zone_revenue.md` · **Skill:** `data-contract` for the prose patch, then `generating-dbt-model` · **Depends on:** Task 1

- [ ] Before rebuilding, record the merge-base build for the row-level comparison: the read-only `domain` target still holds the pre-change `finance.mart_daily_zone_revenue`, so query it on `domain` and store the result count and totals in the task's evidence.
- [ ] Patch `contracts/finance/mart_daily_zone_revenue.odcs.yaml`: no property, type, key or rule changes; add or correct prose that says the relation publishes the billable zone-days the operations aggregate computes, and bump `version` from `1.0.1` to `1.0.2` (prose is a patch).
- [ ] Author `transformation/models/marts/finance/mart_daily_zone_revenue.sql`. List the columns in the order the contract declares them, because dbt emits a contracted relation in that order and the published order must not move:
  ```sql
  select
      a.pickup_date as trip_date,
      a.billable_revenue as total_revenue,
      a.pickup_location_id,
      a.borough_name as borough,
      a.zone_name,
      a.reporting_region,
      a.billable_trip_count as trip_count,
      a.billable_fare_revenue as fare_revenue,
      a.billable_tip_revenue as tip_revenue,
      a.billable_surcharge_revenue as surcharge_revenue,
      a.billable_toll_revenue as toll_revenue
  from {{ ref('agg_trip_zone_daily') }} as a
  where a.billable_trip_count > 0
  ```
  Rewrite the header comment: the report publishes the billable zone-days the operations aggregate computes, and this model's `where` is what keeps out the zone-days that carry no billable trip.
- [ ] Update the model description in `transformation/models/marts/finance/_finance.yml` to the same statement, and re-run `python3 .agents/skills/data-contract/scripts/odcs.py generate` so the generated prose and the enforced-contract keys agree with the contract.
- [ ] Run `cd transformation && dbt build --select mart_daily_zone_revenue --exclude test_type:unit`; expect exit 0 with the enforced contract, `not_null` on `trip_date` and `total_revenue`, `relationships` on `pickup_location_id`, and both singular semantic tests passing.
- [ ] Run the acceptance conditions:
  - `R-01`: `dbt ls --select +mart_daily_zone_revenue --resource-type model` lists `agg_trip_zone_daily` and neither `fct_trip` nor `dim_zone`, and `grep -n "ref(" transformation/models/marts/finance/mart_daily_zone_revenue.sql` shows that one ref.
  - `R-02`: on `ephemeral`, `select sum(trip_count) as trips, round(sum(total_revenue),2) as revenue from finance.mart_daily_zone_revenue where trip_date >= DATE '2024-01-01' and trip_date < DATE '2024-04-01'` returns `95958` and `2629185.82`; and `select sum(trip_count), round(sum(total_revenue),2) from finance.mart_daily_zone_revenue where pickup_location_id = 132 and trip_date >= DATE '2024-01-01' and trip_date < DATE '2024-04-01'` returns `4120` and `337711.05`.
  - `R-03`: on `ephemeral`, `select count(*) from finance.mart_daily_zone_revenue` returns `7961`; the per-row comparison against the merge-base build is a full outer join of the `ephemeral` relation to the values recorded from `domain` on `(trip_date, pickup_location_id)` with money compared at the cent, and it returns 0 rows in either direction and 0 differing values on the ten other columns.
  - `R-04`: the built relation's `information_schema.columns` list for `finance.mart_daily_zone_revenue` matches the eleven the merge-base build has, in the same order and with the same types.
  - `R-08`: `select count(*) from finance.mart_daily_zone_revenue where trip_count = 0` on `ephemeral` returns `0`.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check && python3 .agents/skills/data-contract/scripts/odcs.py check --relations && python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main`; expect exit 0.
- [ ] Run `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests --check` and `python3 -m pytest tests -q`; expect exit 0.
- [ ] Run `dbt docs generate`, then commit and push `mart_daily_zone_revenue.sql`, `_finance.yml`, the finance contract and any regenerated test file.

## Execution evidence

