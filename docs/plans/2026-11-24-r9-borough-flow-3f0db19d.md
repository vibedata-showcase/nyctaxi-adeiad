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

- [ ] Run `cd transformation && dbt deps` before the first dbt command.
- [ ] Author `contracts/agg/agg_borough_flow_monthly.odcs.yaml` first, `status: proposed`: `primaryKey` on (`trip_month`, `origin_borough`, `dest_borough`), the seven columns with `logicalType`/`physicalType` and descriptions, the monthly reconciliation rule against the billable population, and the share's null-on-unresolved rule.
- [ ] Author `transformation/models/marts/agg/agg_borough_flow_monthly.sql` and its entry in `transformation/models/marts/agg/_agg.yml` (`access: public`, `contract: {enforced: true}`, explicit columns with `data_type`: `trip_month` DATE, `origin_borough` VARCHAR, `dest_borough` VARCHAR, `is_intra_borough` BOOLEAN, `trip_count` BIGINT, `total_revenue` DOUBLE, `share_of_origin_borough_trips` DOUBLE).
- [ ] Add the tests the `dbt-testing` convention requires, by file and name:
  - `_agg.yml` on `agg_borough_flow_monthly`: `unique` on the three-column grain, `not_null` on `trip_month`, `origin_borough`, `dest_borough`, `is_intra_borough`, `trip_count`, `total_revenue`.
  - `transformation/tests/assert_borough_flow_grid_is_complete.sql` — every (month, group, group) present once (R-01, R-05).
  - `transformation/tests/assert_borough_flow_reconciles_to_billable_trips.sql` — per month, `sum(trip_count)` equals `fct_trip`'s billable count and `sum(total_revenue)` equals its billable `total_amount` at the cent (R-02, R-03).
  - `transformation/tests/assert_borough_flow_shares_sum_to_one.sql` — borough-to-borough shares sum to 1 per (month, origin borough) within 1e-6 and every row touching `unresolved` has a null share (R-04).
  - `transformation/models/marts/agg/_unit_tests.yml`, unit test `agg_borough_flow_monthly`: a borough-to-borough row, a borough-to-`unresolved` row (null share), an `unresolved`-to-borough row (null share), a zero-trip grid cell, and a zone-less trip landing in `unresolved`; set `report_start` and `report_end` under `overrides: {vars: …}`, since the model reads both.
- [ ] Add `LTS10_borough_flow_monthly` to the `trips` dataset in `logical-model/nyc_taxi_analytics.ossie.yaml`: priority group 0, content grain (month, origin borough, destination borough), `column_map` `billable_trip_count` → `trip_count` and `billable_revenue` → `total_revenue`, levels `trips_to_date`/month, `trips_to_pickup_zone`/borough, `trips_to_dropoff_zone`/borough, the window-and-billable `content_filter`, and a `note` refusing `share_of_origin_borough_trips` for want of a metric and stating it is null on unresolved rows. Then set the contract `status: active`.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate` to write the enforcement keys and descriptions; if it writes a shared-metric description that contradicts the billable population (the `trip_count` name matches the all-trips metric), record the finding and keep the contract's own wording, never hand-editing a generated description. Then run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0.
- [ ] Regenerate the Ossie-owned tests with `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests` and commit the regenerated `assert_semantic_*.sql` beside the model.
- [ ] Run `cd transformation && dbt build --select agg_borough_flow_monthly --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'`; expect PASS and 147 rows (3 months × 7 groups²). After the build, run the destination assertion and the ephemeral marker from `generating-dbt-model` step 9.
- [ ] Run `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'`; expect PASS.
- [ ] Run `python3 tools/ossie_lint.py`; expect exit 0 with no blocking finding, and record a passing `validating-semantic-model` report beside its result.
- [ ] Run the R-06 acceptance query with `cd transformation && dbt show --inline "select count(distinct origin_borough) as groups, count(*) filter (where origin_borough in ('Unknown','N/A')) as named_unresolved, count(*) filter (where origin_borough = 'EWR') as ewr_rows from agg.agg_borough_flow_monthly" --target dev`; expect 7 groups, 0 named unresolved rows and a non-zero `EWR` count.
- [ ] Confirm `R-08` with `git diff --stat`: no existing model SQL or contract changes; only the new model, contract and test files, `_agg.yml`, the Ossie document, and regenerated semantic tests.
- [ ] Commit and push `transformation/models/marts/agg/agg_borough_flow_monthly.sql`, `transformation/models/marts/agg/_agg.yml`, `transformation/models/marts/agg/_unit_tests.yml`, `transformation/tests/assert_borough_flow_grid_is_complete.sql`, `transformation/tests/assert_borough_flow_reconciles_to_billable_trips.sql`, `transformation/tests/assert_borough_flow_shares_sum_to_one.sql`, the regenerated `transformation/tests/assert_semantic_*.sql`, `contracts/agg/agg_borough_flow_monthly.odcs.yaml` and `logical-model/nyc_taxi_analytics.ossie.yaml`.

## Execution evidence
