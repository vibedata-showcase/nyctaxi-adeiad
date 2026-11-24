# Plan: SS · borough flow

**Goal:** Publish one boundary table of monthly trips and revenue from each borough to each borough for Q1 2024, with each row's share of its origin borough's traffic and the origin borough's leaving-borough share.

**Requirement:** `docs/requirement/2026-11-24-ss-borough-flow-4ba22d8f.md`

**Constraints:**

- Grain: one row per (trip month, origin borough, destination borough) that has at least one billable trip in the reporting window (`D-01`, `D-09`).
- Population: `fct_trip` rows with `is_billable` and a pickup inside the reporting window (`2024-01-01` to `2024-04-01`, the dbt vars) — ADR 0003 (`D-02`).
- No quality verdict filters a trip: the model reads no `dim_trip_quality` column and applies no clean/zero-distance/implausibility/sparse/rate filter — ADR 0004 (`D-18`).
- The totals include the unresolved group, so the table's totals equal the canonical `billable_trip_count` and `billable_revenue` for the window — ADR 0012 (`D-17`).
- Borough values: the five TLC-named NYC boroughs plus `EWR`; `Unknown` and `N/A` merge into one `Unresolved` group, which stands outside the in-borough and crossing counts — ADR 0018 (`D-03`, `D-05`).
- Columns, seven and no more: `trip_month DATE`, `origin_borough VARCHAR`, `destination_borough VARCHAR`, `trip_count BIGINT`, `total_revenue DOUBLE`, `destination_trip_share DOUBLE`, `origin_leaving_trip_share DOUBLE` (`D-14`).
- `trip_month` is a `DATE` on the month's first day; cast `date_trunc('month', …)` to `date` (dialect card, type fidelity) (`D-11`).
- Both shares are ratios of summed counts computed in the model through `safe_divide`; a zero denominator gives null — ADR 0019 (`D-10`).
- `origin_leaving_trip_share` repeats on every row of an origin borough and month, the `Unresolved` destination row included; it is null only where the origin has no resolved trip (`D-06`, `D-16`).
- `destination_trip_share` is null on an `Unresolved` destination row; over an origin borough and month the named-borough destinations sum to 1 (`D-07`, `D-16`).
- No minimum pair size, and no zero rows (`D-08`, `D-09`).
- No `relationships` test on either borough column; a singular test asserts no raw `Unknown`/`N/A` label and one `Unresolved` label (`D-15`).
- Schema: `transformation/models/marts/agg/` → `agg`, unchanged; no `+schema` edit (`## Schema` in the design record).
- Excluded from the semantic layer; the reason already sits in `repo-map.json` `semantic_exclusions` (`D-12`). No Ossie document, ontology mapping or `generate-tests` output changes.
- Materialised as a table with `contract: {enforced: true}`, in `agg` (`D-13`).
- Naming: `agg_` prefix for a gold aggregate; properties in `transformation/models/marts/agg/_agg.yml`; singular tests in `transformation/tests/` named `assert_<what_must_hold>.sql`; unit tests in `transformation/models/marts/agg/_unit_tests.yml`.
- Platform: DuckDB; the only dbt target is `dev`, which writes the sandbox file. No `--defer` and no `--state`: the dbt card's `## Defer` publishes no production manifest, so `/data/cache` stays unread. No `--full-refresh` anywhere; the model is new.
- Every write lands in the sandbox; the Domain database is read-only.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `contracts/agg/agg_borough_flow_monthly.odcs.yaml` | contract | create | `R-09`, `R-02`, `R-02b`, `R-04`, `R-05`, `R-06`, `R-08` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `agg_borough_flow_monthly` | model | create | `R-01`, `R-02`, `R-02b`, `R-03`, `R-04`, `R-05`, `R-06`, `R-07`, `R-08` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit` then `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit` |
| `transformation/models/marts/agg/_agg.yml` | model | modify | `R-01`, `R-08`, `R-09` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt parse` |
| `transformation/models/marts/agg/_unit_tests.yml` | model | create | `R-04`, `R-05`, `R-06`, `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit` |
| `transformation/tests/assert_borough_flow_covers_billable_trips.sql` | model | create | `R-02`, `R-02b` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select assert_borough_flow_covers_billable_trips` |
| `transformation/tests/assert_borough_flow_has_no_raw_unresolved_label.sql` | model | create | `R-04` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select assert_borough_flow_has_no_raw_unresolved_label` |
| `transformation/tests/assert_borough_flow_shares_reconcile.sql` | model | create | `R-05`, `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select assert_borough_flow_shares_reconcile` |
| `transformation/tests/assert_borough_flow_grain_is_unique.sql` | model | create | `R-01` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select assert_borough_flow_grain_is_unique` |
| `test-map.json` | project-config | modify | `R-01`, `R-02`, `R-04`, `R-05`, `R-06`, `R-09` | `code is contract` | `python3 -m pytest tests/test_maps.py -q` |

**Change impact:** No existing model changes, so nothing downstream of any published relation is rebuilt or restated. `agg_od_flow_matrix`, `agg_weather_demand_daily`, `fct_trip`, `dim_zone` and every other published relation the request did not name are untouched: this model reads `fct_trip` and `dim_zone` and nothing reads it. `_agg.yml` gains one model entry and `test-map.json` gains four singular tests in the `agg` module's `data` list and one `--exclude` in the `logical-model` module's coverage command (the new relation is in `semantic_exclusions`, and without the flag `coverage` reports it as a gap once it is on disk); neither alters an existing model entry. No enforced contract on any impacted model changes. `dbt ls --select fct_trip+` lists the ten current consumers of the fact and this model is not among them.

`Baseline build_sha:` not recorded — the dbt card's `## Defer` publishes no production manifest for this platform, so `/data/cache` was not read and there is no baseline to compare against.

## Tasks

### Task 1: contracts/agg/agg_borough_flow_monthly.odcs.yaml

**Requirements:** `R-09`, `R-02`, `R-02b`, `R-04`, `R-05`, `R-06`, `R-08` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `data-contract` · **Depends on:** none

- [x] Author `contracts/agg/agg_borough_flow_monthly.odcs.yaml`: ODCS v3.2.0, `name: agg_borough_flow_monthly`, `version: 1.0.0`, `status: proposed` (the table does not exist yet), server `sample-nyctaxi-comp` / `duckdb` / `domain.duckdb` / schema `agg`, with the seven columns of `D-14`, their logical and physical types, and a `dataGranularityDescription` stating the grain and that a pair-month with no billable trips has no row. `trip_month`, `origin_borough`, `destination_borough`, `trip_count` and `total_revenue` are required; the two share columns are not (`D-16`). No `relationships` rule on either borough column, and no `invalidValues` rule that would list `Unresolved` as a legal borough (`D-15`). Descriptions state: `trip_count` is billable trips picked up in the month; `total_revenue` is the summed total amount of those trips and the table's totals equal the canonical `billable_revenue` because no quality verdict filters a trip (ADR 0004) and the unresolved group stays in (ADR 0012); `origin_leaving_trip_share` repeats across the origin borough's rows and must not be summed; `destination_trip_share` is null on an `Unresolved` destination row.
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0, with the new contract shape-checked and its orphan and document checks skipped because it is `proposed`.
- [x] Commit and push `contracts/agg/agg_borough_flow_monthly.odcs.yaml`.

### Task 2: agg_borough_flow_monthly

**Requirements:** `R-01`, `R-02`, `R-02b`, `R-03`, `R-04`, `R-05`, `R-06`, `R-07`, `R-08` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `generating-dbt-model` · **Depends on:** Task 1

> Amended 2026-11-24 after the user restated the population: the totals must equal the canonical `billable_revenue`, no quality verdict may filter a trip (ADR 0004), and the unresolved group stays inside the totals (ADR 0012 / `D-17`). The model gains no column and no filter from that; `R-02b` is proven by the model reading no `dim_trip_quality` column at all.

- [ ] Author `transformation/models/marts/agg/agg_borough_flow_monthly.sql`: `fct_trip` joined to `dim_zone` twice (origin and destination, per `D-04`), filtered by `in_report_window('f.pickup_datetime')` and `f.is_billable`; a labelled borough per side where `borough_name in ('Unknown', 'N/A')` becomes `'Unresolved'` and every other value is kept, `EWR` included (`D-03`); `trip_month` as `cast(date_trunc('month', f.pickup_datetime) as date)` (`D-11`); `count(*)` and `sum(f.total_amount)` cast to `bigint` and `double`; `origin_resolved_trips` as the origin-borough-month's trips whose destination is not `Unresolved`; `destination_trip_share` as `case when destination_borough = 'Unresolved' then null else safe_divide(trip_count, origin_resolved_trips) end`, so the row whose trips are outside the denominator gets null instead of a ratio above 1 (`D-07`); `origin_leaving_trip_share` as `safe_divide(sum(trip_count) filter (where destination_borough <> origin_borough and destination_borough <> 'Unresolved'), origin_resolved_trips)` over the origin-borough-month window, so it repeats on every row of that origin borough and month including the `Unresolved` destination row, and is null on an `Unresolved` origin because that origin's denominator is null (`D-06`, `D-10`). Explicit column list, no `select *`; the folder already sets `materialized: table`; write the header comment stating ADR 0003, ADR 0004, ADR 0012, ADR 0018 and ADR 0019 by number.
- [ ] Author the model entry in `transformation/models/marts/agg/_agg.yml`: `agg_borough_flow_monthly` under `models:`, `contract: {enforced: true}`, the seven columns with `data_type` matching `D-14`, and `data_tests`: `not_null` on `trip_month`, `origin_borough`, `destination_borough`, `trip_count` and `total_revenue`, and no `unique` on any single column because the grain is the three-column key and `dbt_utils` is not installed. The grain is proven by `assert_borough_flow_grain_is_unique` below. Every column gets a non-empty `description`; `origin_leaving_trip_share`'s says it repeats across the origin borough's rows and must not be summed.
- [ ] Author `transformation/models/marts/agg/_unit_tests.yml` with five `unit_tests:` entries over `ref('fct_trip')` and `ref('dim_zone')` fixtures:
  - `borough_flow_merges_unresolved_labels` — an `Unknown` and an `N/A` destination zone both land in one `Unresolved` row, and an `EWR` zone keeps `EWR`.
  - `borough_flow_shares_use_the_resolved_denominator` — shares are computed over the origin borough's non-`Unresolved` trips; the `Unresolved` destination row's `destination_trip_share` is null while its `origin_leaving_trip_share` equals the other rows' value.
  - `borough_flow_excludes_non_billable_and_out_of_window_trips` — a non-billable trip and a trip picked up on 2023-12-31 or 2024-04-01 add no row and no count.
  - `borough_flow_unresolved_destination_share_is_null` — an origin sending more trips to an unplaced zone than to named boroughs (a case the data contains: Staten Island in February sends 3 to `Unresolved` against 2 to itself) gives a null `destination_trip_share` on that row rather than a share above 1, while the named-borough rows still sum to 1.
  - `borough_flow_leaving_share_is_null_for_an_unresolved_origin` — an origin whose every trip starts in an unplaced zone gives null for both shares, because it has no resolved trip to measure against.
- [ ] Author `transformation/tests/assert_borough_flow_covers_billable_trips.sql`: returns a row when `sum(trip_count)` differs from `count(*)` over `fct_trip` with `is_billable` and a pickup inside the reporting window, or when `sum(total_revenue)` differs from their summed `total_amount` by more than 0.01, and one further arm returning a row when `sum(total_revenue)` differs from the canonical billable revenue re-derived as `sum(case when is_billable then total_amount else 0 end)` over the same window by more than 0.01. `is distinct from` on the counts so an empty table fails rather than passes (`R-02`). No `dim_trip_quality` filter appears in the test, so a model that quietly excluded a verdict fails it (`R-02b`).
- [ ] Author `transformation/tests/assert_borough_flow_has_no_raw_unresolved_label.sql`: two `select`s unioned, each returning the value that violates the rule: one returns any row whose `origin_borough` or `destination_borough` is `'Unknown'` or `'N/A'`; the other returns a row when `'EWR'` never appears as an origin or as a destination, so a merge that swallowed a named borough fails too (`R-04`, `D-15`).
- [ ] Author `transformation/tests/assert_borough_flow_grain_is_unique.sql`: returns the grain columns of any (trip_month, origin_borough, destination_borough) occurring more than once (`R-01`).
- [ ] Author `transformation/tests/assert_borough_flow_shares_reconcile.sql`: returns a row when, per origin borough and month, the `destination_trip_share` values of the named-borough destinations differ from 1 by more than 1e-9, when the shares of the destinations other than the origin differ from `origin_leaving_trip_share` by more than 1e-9, when `origin_leaving_trip_share` is not constant within an origin borough and month, or when `origin_leaving_trip_share` differs from an independent recomputation off `fct_trip` and `dim_zone` by more than 1e-9 (`R-05`, `R-06`).
- [ ] Add the four singular tests to `test-map.json` under `modules.agg.data`, beside the existing four, and add `--exclude agg.agg_borough_flow_monthly` to `modules.logical-model.commands.structural`'s `coverage` invocation, beside the three existing `--exclude` flags, so the excluded relation is not reported as a coverage gap.
- [ ] Run `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit`; expect exit 0 with all data tests passing.
- [ ] Run `python "$SKILL_DIR/../../scripts/assert_dbt_destination.py"`, substituting the skill's directory; expect exit 0 before reading the build result.
- [ ] Run `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit`; expect exit 0 with the five unit tests passing.
- [ ] Run the acceptance conditions this task serves: `sum(trip_count)` = 95,958 and `round(sum(total_revenue),2)` = 2,629,185.82 over the built sandbox table, equal to the canonical `billable_trip_count` and `billable_revenue` (`R-02`), and `grep -nE "dim_trip_quality|is_clean_trip|is_zero_distance|is_implausibly|is_sparse_vendor_feed|is_undocumented_rate_code" transformation/models/marts/agg/agg_borough_flow_monthly.sql` finds nothing (`R-02b`); the table holds exactly three `trip_month` values, 2024-01-01, 2024-02-01 and 2024-03-01 (`R-03`); no row carries `Unknown` or `N/A`, `Unresolved` appears as one value and `EWR` appears as both an origin and a destination (`R-04`); Manhattan's `origin_leaving_trip_share` is 0.055545, 0.054238 and 0.055979 and Queens' is 0.705492, 0.722063 and 0.731730 for Jan–Mar, each to 6 decimal places (`R-05`); 104 rows, none with `trip_count` 0, 35 / 33 / 36 by month (`R-07`); `round(sum(total_revenue),2)` matches the summed `total_amount` of the same trips (`R-08`).
- [ ] Commit and push `transformation/models/marts/agg/agg_borough_flow_monthly.sql`, `transformation/models/marts/agg/_agg.yml`, `transformation/models/marts/agg/_unit_tests.yml`, the four `transformation/tests/assert_borough_flow_*.sql` files and `test-map.json`.

### Task 3: promote the contract to active

**Requirements:** `R-09` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `data-contract` · **Depends on:** Task 1, Task 2

- [ ] Set `status: active` in `contracts/agg/agg_borough_flow_monthly.odcs.yaml`.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate`; expect exit 0, with the dbt keys and descriptions written from the contract and the Ossie documents.
- [ ] Run `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit`, then `python "$SKILL_DIR/../../scripts/assert_dbt_destination.py"`; expect exit 0 from both, the rebuild green under the enforced contract.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check && python3 .agents/skills/data-contract/scripts/odcs.py check --relations && python3 .agents/skills/data-contract/scripts/odcs.py profile --relation agg.agg_borough_flow_monthly`; expect exit 0 with no `relations/mismatch` and no profile error. A `profile/unchecked` warning is reported as unproven, never as passing.
- [ ] Run `validating-data-contract` and record its report; expect a pass with no open finding.
- [ ] Commit and push `contracts/agg/agg_borough_flow_monthly.odcs.yaml` and any file `generate` rewrote.

## Execution evidence

- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py check` — exit 0 — `contracts/agg/agg_borough_flow_monthly.odcs.yaml` — sha256:21c4cefa36cfc0b21c10c95576ec4c676215d6c68e1a8ad4b042c429115bb123 — commit b3a0917 — output: three `info` findings for the pre-existing `semantic_exclusions` relations (`agg_od_flow_matrix`, `core.dim_fare_regime`, `finance.mart_revenue_component_bridge`), no finding for the new contract, which is `status: proposed` so its orphan and document checks are skipped.
