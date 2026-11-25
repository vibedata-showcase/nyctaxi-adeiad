# Plan: Borough-to-borough trips and revenue, Q1 2024

**Goal:** Publish one monthly borough-to-borough flow surface for Q1 2024 carrying trip counts, recognised revenue and the cross-borough share, built on `fct_trip`.

**Requirement:** `docs/requirement/2026-11-25-borough-to-borough-trips-and-revenue-q1-2024-1babac98.md`

**Constraints:**
- Layer: `agg` (boundary), folder `transformation/models/marts/agg/`, schema `agg` — the folder's current `+schema`, recorded in the design record's `## Schema`.
- Naming: `agg_` prefix for a gold aggregate; properties entry in `_agg.yml`; no `select *`; columns listed explicitly.
- Grain: one row per (month, origin borough, destination borough); the month column is `dim_date.month_start_date`, joined on `f.pickup_date`, not truncated in this model.
- Population: both ends `dim_zone.is_nyc` and at least 25 billable trips per pair-month (ADR 0018); no zero-filled rows.
- Revenue: `sum(total_amount)` over billable trips whose payment method has `counts_as_revenue` true, tested through `coalesce(pm.counts_as_revenue, false)` on a left join (ADR 0013, ADR 0015).
- Share: cross-borough trips ÷ all trips in the origin borough's published pairs for that month (ADR 0019).
- Billable filter: `f.is_billable` and `in_report_window('f.pickup_datetime')` (ADR 0003).
- `contract: { enforced: true }` with every output cast to its contract `data_type`; every output column carries a real description.
- Money compared at the cent (`round(x, 2)`); shares at 1e-9.
- No `--defer`, no `/data/cache`: the dbt card's `## Defer` says no production manifest is published.
- Nothing writes to the Domain: every build runs on the sandbox target.
- Do not modify `agg_od_flow_matrix`, `fct_trip`, `dim_zone`, `dim_payment_method` or any finance mart.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `contracts/agg/agg_borough_flow_monthly.odcs.yaml` | contract | create | `R-01`, `R-02`, `R-03`, `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `agg_borough_flow_monthly` | model | create | `R-01`–`R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` |
| `transformation/models/marts/agg/_unit_tests.yml` | model | create | `R-01`, `R-03`, `R-05` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` |
| three singular tests under `transformation/tests/assert_borough_flow_*.sql` | model | create | `R-01`, `R-03`, `R-05` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select path:models/marts/agg --exclude test_type:unit --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` |
| `test-map.json` `modules.agg.unit` | project-config | modify | `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 -m pytest tests/test_maps.py -q` |
| `repo-map.json` `semantic_exclusions` | project-config | modify | `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` (`D-08`) | `python3 -m pytest tests/test_maps.py -q` |

**Change impact:** no existing dbt model is modified and nothing in the project `ref()`s the new relation, so no downstream consumer changes. The two map edits are read by `tests/test_maps.py` and `tools/ossie_lint.py`. `CONTEXT.md`, ADR 0018, ADR 0019 and the affected-designs links on ADR 0003/0012/0013/0015/0017 were committed with the design (commit `70f97ee`).

## Tasks

### Task 1: the contract, the model and its tests

**Requirements:** `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-06`, `R-07` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `data-contract`, then `generating-dbt-model` · **Depends on:** none

- [ ] Author `contracts/agg/agg_borough_flow_monthly.odcs.yaml` with `status: proposed`, mirroring `contracts/agg/agg_od_flow_matrix.odcs.yaml`: the grain statement, `primaryKey` over `month_start_date`, `origin_borough`, `destination_borough`, and these properties — `month_start_date` (DATE), `origin_borough` (VARCHAR), `destination_borough` (VARCHAR), `is_intra_borough` (BOOLEAN), `trip_count` (BIGINT), `revenue_trip_count` (BIGINT), `recognised_revenue` (DOUBLE), `origin_month_trip_count` (BIGINT), `cross_borough_trip_count` (BIGINT), `cross_borough_trip_share` (DOUBLE), each `required` except `is_intra_borough`.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate`; expect exit 0 with the `data_type`s, tests and `contract` written from the contract.
- [ ] Author `transformation/models/marts/agg/agg_borough_flow_monthly.sql`: `fct_trip` inner joined to `dim_zone` twice (`o` on `pickup_zone_key`, `d` on `dropoff_zone_key`), left joined to `dim_payment_method` (`pm`) on `payment_method_key`, left joined to `dim_date` (`dt`) on `f.pickup_date = dt.calendar_date`; `where in_report_window('f.pickup_datetime') and f.is_billable and o.is_nyc and d.is_nyc`; grouped by `dt.month_start_date`, `o.borough_name`, `d.borough_name`; `having count(*) >= 25`.
- [ ] In the same file write the aggregates: `count(*) as trip_count`, `count(*) filter (where coalesce(pm.counts_as_revenue, false)) as revenue_trip_count`, `coalesce(sum(f.total_amount) filter (where coalesce(pm.counts_as_revenue, false)), 0) as recognised_revenue`, `o.borough_name = d.borough_name as is_intra_borough`.
- [ ] In the same file write the origin-month windows over the grouped rows — `sum(trip_count) over w as origin_month_trip_count`, `coalesce(sum(trip_count) filter (where is_intra_borough = false) over w, 0) as cross_borough_trip_count`, and `cross_borough_trip_share` as `{{ safe_divide('cross_borough_trip_count', 'origin_month_trip_count') }}` — with `w` = `(partition by month_start_date, origin_borough)` in a `qualify`-free form: a `select` over the grouped subquery, so the window reads the aggregated columns.
- [ ] Write the model's entry in `transformation/models/marts/agg/_agg.yml` from the generated keys: `contract: { enforced: true }`, `access: public`, every column's `data_type` and description, `unique` and `not_null` on the three grain columns, `not_null` on the counts and `accepted_values` on `origin_borough` and `destination_borough` over Bronx, Brooklyn, Manhattan, Queens and Staten Island.
- [ ] Write `transformation/models/marts/agg/_unit_tests.yml` (a new file: `_unit_tests.yml` sits beside the models it covers) with two unit tests whose `given` rows cover `fct_trip`, `dim_zone`, `dim_payment_method` and `dim_date` — `borough_flow_excludes_trips_with_an_end_outside_the_city` (one intra-city trip, one trip to an `is_nyc = false` zone, one trip from one; expects one row with `trip_count` 1) and `borough_flow_share_counts_only_published_pairs` (24 trips Bronx→Brooklyn and 26 trips Bronx→Bronx, one of the 26 with a null `payment_method_key`; expects only the Bronx→Bronx row, with `trip_count` 26, `revenue_trip_count` 25, `origin_month_trip_count` 26 and `cross_borough_trip_share` 0.0).
- [ ] Write `transformation/tests/assert_borough_flow_one_row_per_month_pair.sql`: returns every `(month_start_date, origin_borough, destination_borough)` whose row count exceeds 1.
- [ ] Write `transformation/tests/assert_borough_flow_floor.sql`: returns every row whose `trip_count < 25`, or whose `origin_borough` or `destination_borough` is not one of the five city boroughs.
- [ ] Write `transformation/tests/assert_borough_flow_share_reconciles.sql`: returns every row where `cross_borough_trip_share` differs from `cross_borough_trip_count / origin_month_trip_count` by more than 1e-9, and every origin-month whose `origin_month_trip_count` differs from the sum of its own `trip_count` rows.
- [ ] Run `cd transformation && dbt deps`; expect exit 0.
- [ ] Run `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'`; expect exit 0 with the model built and its data tests passing.
- [ ] Run `python3 /data/default-plugins/vibedata-data-engineering/0.148.28/scripts/assert_dbt_destination.py`; expect exit 0.
- [ ] Run `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'`; expect exit 0 with both unit tests passing.
- [ ] Set the contract `status: active`, re-run `python3 .agents/skills/data-contract/scripts/odcs.py generate`, rebuild the model with the same `dbt build` command, then run `python3 .agents/skills/data-contract/scripts/odcs.py check && python3 .agents/skills/data-contract/scripts/odcs.py check --relations && python3 .agents/skills/data-contract/scripts/odcs.py profile --relation agg.agg_borough_flow_monthly`; expect exit 0 on the chain, and a `profile/unchecked` warning recorded as unproven rather than passing.
- [ ] Run the `R-05` acceptance query on the sandbox — `select count(*) as rows, sum(trip_count) as trips, round(sum(recognised_revenue), 2) as revenue from agg.agg_borough_flow_monthly` — expect 39, 94,624, 2,494,501.46; and `select count(*) from agg.agg_borough_flow_monthly where trip_count < 25` — expect 0.
- [ ] Record every command with its exit code and observed value in `## Execution evidence`, then commit the contract, SQL, YAML and the three singular tests together.

### Task 2: the map entries and their gates

**Requirements:** `R-07` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` (`D-08`) · **Skill:** `semantic-model` · **Depends on:** Task 1

- [ ] Add to `repo-map.json` `semantic_exclusions` an entry for `agg.agg_borough_flow_monthly` whose `reason` says its population is a `HAVING` floor per pair-month (ADR 0018), which no `content_filter` predicate can state, so the surface is excluded rather than given a document.
- [ ] Add `modules.agg.unit` and `modules.agg.selectors.unit` to `test-map.json`, naming `transformation/models/marts/agg/_unit_tests.yml` and `path:models/marts/agg`.
- [ ] Run `python3 -m pytest tests/test_maps.py -q`; expect exit 0.
- [ ] Run `python3 tools/ossie_lint.py`; expect exit 0.
- [ ] Run `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/` and then `coverage` over the four boundary roots with `--exclude` for `agg.agg_od_flow_matrix`, `agg.agg_borough_flow_monthly`, `finance.mart_revenue_component_bridge` and `core.dim_fare_regime`; expect exit 0 with the new relation counted as an exclusion.
- [ ] Record every command with its exit code and observed value in `## Execution evidence`, then commit both map files.

## Execution evidence
