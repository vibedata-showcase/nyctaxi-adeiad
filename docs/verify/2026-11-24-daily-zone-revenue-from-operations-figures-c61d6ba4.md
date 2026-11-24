# Verification: Daily zone revenue from operations figures

## Verification

`verdict: verified` at `77e73eabe9b141a8d54f15430c919784edf8fdbc`: every requirement and every Plan scope row is covered by an independent check, and every gate passed. The data-affecting artifact is unchanged since the gate commit `a6fc094`; the later commit `77e73ea` edits two design-record sentences only — no SQL, test, contract, seed or macro — so the gates run at `a6fc094` hold for it. Ravi's four acceptance figures are exact on the rebuilt report.

## Coverage

| Item | Evidence | Result | At |
| --- | --- | --- | --- |
| `R-01` the agg is the single zone×day build | `grep` over `transformation/target/compiled/.../mart_daily_zone_revenue.sql`: occurrences of `agg_trip_zone_daily` and of `fct_trip`, plus an aggregation-function count | `agg_trip_zone_daily` 1, `fct_trip` 0, `count(|sum(|avg(|min(|max(|group by` 0 — the report selects and never aggregates | `a6fc094` |
| `R-02` every report number is unchanged | `full outer join` of the rebuilt `finance.mart_daily_zone_revenue` against `baseline.mart_daily_zone_revenue` on `(trip_date, pickup_location_id)`, at the cent | 20,770 rows each side; `only_new` 0; `only_baseline` 0; `diff_rows` 0 across `trip_count`, `borough`, `zone_name`, `reporting_region` and the five money columns; `dup_keys` 0 | `a6fc094` |
| `R-03` Ravi's acceptance figures | `select count(*), sum(trip_count), round(sum(total_revenue),2)`, and the same filtered to `pickup_location_id = 132`, over the rebuilt report | 20,770 rows; **9,604,511** trips; **263,480,834.99** revenue; JFK **416,460** trips, **33,881,378.28** revenue — all four exact | `a6fc094` |
| `R-04` the agg's published numbers are unchanged | `full outer join` of rebuilt `agg.agg_trip_zone_daily` against `baseline.agg_trip_zone_daily` on `(pickup_date, pickup_location_id)`; totals re-read | 20,771 rows each side; `only_new` 0; `only_base` 0; `diff_rows` 0 on `trip_count`, `total_revenue` (cent), `total_miles`, `attributed_driver_count`, `prev_day_trip_count`, `same_day_last_week_trip_count`, `trip_count_7d_avg`, `revenue_28d_rolling`; totals 9,722,336 and 260,487,920.62. `revenue_rank_that_day` differs on 3 of 20,771 rows; see the findings | `a6fc094` |
| `R-05` the agg publishes billable measures beside the all-trips ones | `sum(billable_trip_count)`, `round(sum(billable_revenue),2)` over the rebuilt agg | **9,604,511** and **263,480,834.99**; the all-trips `trip_count` beside it still sums 9,722,336, so the rows the rule excludes stay visible | `a6fc094` |
| `R-06` a zone-day with no billable trip publishes 0, not null | null count over all six billable columns, and the `2024-02-12` / zone `175` row | `null_measures` 0; that row `billable_trip_count` 0 and `billable_revenue` 0.0; exactly 1 zone-day with `trip_count > 0 and billable_trip_count = 0`, and the report drops that one row (20,771 → 20,770) | `a6fc094` |
| `R-07` the fare-component columns stay on the report at the same values, with no mart-side aggregation | the `R-02` join covers `fare_revenue`, `tip_revenue`, `surcharge_revenue`, `toll_revenue`, `total_revenue`; the `R-01` grep proves 0 aggregation functions in the compiled report | 0 diffs on all five; 0 aggregation functions | `a6fc094` |
| `R-08` contract, semantic binding and design records still describe what is built | `odcs.py check` (0 errors), `odcs.py diff origin/main` (additive and descriptive only), `odcs.py check --relations --catalog`, `profile` on both relations, `ossie.py validate`/`coverage`/`suppliers`/`notes`/`generate-tests --check`/`bindings`/`columns`, `assert_semantic_content_holds` on data, and a read of both design records | all green; stale text found and fixed — see the findings | `77e73ea` |
| `contracts/agg/agg_trip_zone_daily.odcs.yaml` (scope row) | `odcs.py check --relations --catalog`, `profile --relation agg.agg_trip_zone_daily --catalog <sandbox database>` | 0 errors on this contract; `profile` returned `[]` — every declared rule holds on the built rows | `a6fc094` |
| `transformation/models/marts/agg/agg_trip_zone_daily.sql` (scope row) | `dbt build --select agg_trip_zone_daily+ --exclude test_type:unit` | exit 0, `PASS=13 WARN=1 ERROR=0`; 20,771 rows built | `a6fc094` |
| `transformation/models/marts/agg/_agg.yml` (scope row) | same build; `diff_data_tests.py` base vs head | exit 0; `weaker` `[]`, `stronger` `[]` — no test declaration removed or loosened | `a6fc094` |
| `transformation/tests/assert_zone_day_billable_ties_to_fact.sql` (scope row) | `dbt test --select assert_zone_day_billable_ties_to_fact` | `pass`, 0 rows returned | `a6fc094` |
| `test-map.json` (scope row) | `python3 -m pytest tests -q` | `222 passed` | `77e73ea` |
| `contracts/finance/mart_daily_zone_revenue.odcs.yaml` (scope row) | `odcs.py check --relations --catalog`, `profile --relation finance.mart_daily_zone_revenue --catalog <sandbox database>` | 0 errors on this contract; `profile` returned one `profile/unchecked` warning on the `dim_zone` relationship — see the limits | `a6fc094` |
| `transformation/models/marts/finance/mart_daily_zone_revenue.sql` (scope row) | `dbt build --select agg_trip_zone_daily+ --exclude test_type:unit` | exit 0; `mart_daily_zone_revenue` `success`, 20,770 rows | `a6fc094` |
| `transformation/models/marts/finance/_finance.yml` (scope row) | same build; `diff_data_tests.py` base vs head | exit 0; `weaker` `[]` — the existing tests are unchanged | `a6fc094` |
| `transformation/models/marts/finance/_unit_tests.yml` (scope row) | `dbt test --select agg_trip_zone_daily+,test_type:unit` | exit 0, `PASS=3 WARN=0 ERROR=0` | `a6fc094` |
| `transformation/models/docs.md` (scope row) | the docs block renders into `_finance.yml`'s `trip_count.description`, which `odcs.py generate` then leaves alone (`check` 0 errors, no `generated/stale`) | rendered and stable | `a6fc094` |
| `logical-model/nyc_taxi_analytics.ossie.yaml` (scope row) | `ossie.py validate`, `bindings` after `dbt compile`, `columns` against the built catalog, `assert_semantic_content_holds` | validate 0 errors; bindings 0 errors with 2 `unproven` on `LTS7` — see the limits; columns 0 errors on both touched relations; the content test passes | `a6fc094` |

## Gate results

| Gate | Command | Exit | Outcome |
| --- | --- | --- | --- |
| Data and unit tests (data) | `dbt build --select agg_trip_zone_daily+ --exclude test_type:unit` | 0 | pass — `PASS=13 WARN=1 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=14`; the warning is the pre-existing `assert_semantic_levels_hold` `LTS5` sentinel (ADR 0012) |
| Data and unit tests (unit) | `dbt test --select agg_trip_zone_daily+,test_type:unit` | 0 | pass — `PASS=3 WARN=0 ERROR=0` |
| Sandbox destination after each write | `python3 .../scripts/assert_dbt_destination.py` | 0 | pass — `DESTINATION_OK: 2 built relation(s) landed in the sandbox ephm_nyc-taxi-analytics_new-intent-c61d6ba4` |
| Acceptance checks | the eight queries recorded in `## Coverage` | 0 | pass — see each row |
| Docs match data | read of ADR 0018, ADR 0003's diff, and both design records against the built relation and the SQL | - | pass after two fixes — the agg record's `Consumers` line and the shared record's ADR 0018 link, both fixed in `77e73ea`. No document states a figure that disagreed with the data |
| Refactor equivalence | the `R-02` and `R-04` joins, at the cent | 0 | pass — 0 differing rows on every column `R-04` names except `revenue_rank_that_day`, recorded as a finding |
| Project audit | `dbt build --select package:dbt_project_evaluator --vars '{dbt_project_evaluator_enabled: true}' --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` | 0 | pass — `PASS=66 WARN=12 ERROR=0`; no evaluator finding names `agg_trip_zone_daily` or `mart_daily_zone_revenue` (`core.fct_model_fanout` and `core.fct_root_models` return 0 rows for both) |
| Logical Model contract | read of the `## Logical Model` sections of every design record this intent wrote | - | not applicable — none carries that section |
| Dev-artifact scan | `grep -rn "dev_mode\|add_limit(\|profile target"` over the changed model and test directories | 1 | pass — no match; `grep` exits 1 on no match. No dev-mode flag, no hard-coded limit, no profile edit |
| Baseline cross-check | none | - | not applicable — the platform card's `## Defer` says no production manifest is published, so no `state:modified+` comparison exists |
| Semantic model (structural) | `ossie.py validate logical-model/` | 0 | pass — `2 file(s), 0 error(s), 1 warning(s)`; the warning is the pre-existing `zone_poi_to_zone`/`zone_natural_key` pair |
| Semantic model (coverage) | `ossie.py coverage logical-model/ <4 boundary roots> --exclude agg.agg_od_flow_matrix --exclude finance.mart_revenue_component_bridge --exclude core.dim_fare_regime` | 0 | pass — `34 model(s) on disk, 31 named, 0 coverage error(s)` |
| Semantic model (suppliers, notes, generated tests) | `ossie.py suppliers`; `ossie.py notes`; `ossie.py generate-tests --check` | 0 | pass — `0 unsupplied item(s)`; `0 dangling pointer(s), 0 unchecked director(ies)`; `3 generated test(s), 0 stale.` |
| Semantic model (bindings) | `ossie.py bindings logical-model/ transformation/target/manifest.json`, after `dbt compile` | 0 | pass — `63 model(s) with SQL, 0 error(s), 2 warning(s)`, both `bindings/unproven` on `LTS7` — see the limits |
| Semantic model (columns) | `ossie.py columns logical-model/ transformation/target/catalog.json` | 0 | pass — `87 relation(s), 0 error(s), 5 warning(s)`, all pre-existing same-class `datatype-mismatch`, none on either touched relation |
| Semantic model (content, on data) | `dbt test --select assert_semantic_content_holds assert_semantic_level_keys_hold assert_semantic_levels_hold` | 0 | pass — `PASS=2 WARN=1`; the warning is the same pre-existing `LTS5` sentinel |
| Ontology | none | - | not applicable — this Domain has no `docs/ontology/` and `repo-map.json` names no ontology |
| Data contract (check) | `python3 .agents/skills/data-contract/scripts/odcs.py check` | 0 | pass — 0 errors |
| Data contract (diff) | `python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main` | 0 | pass — seven `diff/additive` properties on the agg and one `diff/descriptive` on the report; no breaking entry |
| Data contract (check --relations) | `... odcs.py check --relations --catalog transformation/target/catalog.json` | 0 | pass on this intent's rows; 6 `relations/mismatch` errors on dlt-managed audit tables outside the impacted set — see the limits |
| Data contract (profile, agg) | `... odcs.py profile --relation agg.agg_trip_zone_daily --catalog <sandbox database>` | 0 | pass — `[]` |
| Data contract (profile, report) | `... odcs.py profile --relation finance.mart_daily_zone_revenue --catalog <sandbox database>` | 0 | pass with one `profile/unchecked` warning on the `dim_zone` relationship — see the limits |
| Weakening: dbt test declarations | `diff_data_tests.py` on `_finance.yml` and `_agg.yml`, base `1184020` vs head | 0 | pass — `weaker` `[]`, `stronger` `[]`, `ambiguous` `[]` on both |
| Weakening: enforced contracts | `diff_manifest_contract.py /tmp/base_manifest.json transformation/target/manifest.json`, the base materialized at `1184020` with `--deps` | 0 | pass — `weaker` `[]`; `stronger` is the seven added agg columns |
| Weakening: dlt schema contracts | none | - | not applicable — no dlt pipeline changed |
| Weakening: singular SQL tests and macros | read of both versions of `assert_semantic_content_holds.sql` | - | pass — the regenerated file adds the two `LTS7` binding arms; no assertion removed. No macro changed |
| Python tests | `python3 -m pytest tests -q` | 0 | pass — `222 passed in 121.97s` |
| Python lint | `ruff check tests transformation` | 0 | pass — `All checks passed!` |
| SQL lint | `sqlfluff lint transformation/models` | 0 | pass — `All Finished!` |
| ADR link hygiene | `tests/test_adr_links.py`, inside the pytest run, plus a link-resolution read of every markdown link in the three intent records | 0 | pass — `2 passed`; one dangling ADR 0018 link found by the read and fixed in `77e73ea` |

## Findings

- **`revenue_rank_that_day` is not reproducible across builds, and this change did not make it so.** The rebuilt agg differs from `baseline.agg_trip_zone_daily` on that column in 3 of 20,771 rows. The Plan's task-1 evidence records the controlled experiment: two consecutive builds of byte-identical SQL (same `sha256`) differ from each other on 2 rows, and the domain's stored table does not reproduce its own columns from `fct_trip` (9,877 raw diffs). In the domain, 149 rows sit in exact `total_revenue` ties across 73 distinct tied values, where `rank()` order is arbitrary. Ravi's answer of record — "equal to the cent; bit-for-bit equality is not achievable" — puts every money-derived comparison at the cent, and `rank()` over a `DOUBLE` sum inherits exactly that. Every other column `R-04` names matches exactly or at the cent. Recorded, not fixed: the column is not a defect this change introduced, and no available test would distinguish a regression in it from this float noise.
- **A stale `LTS7_daily_zone_revenue` note was corrected.** It claimed the report applies `f.is_billable` itself, which stopped being true when the report became a selection. Fixed in `a6fc094` and recorded in the Plan's `## Execution evidence`.
- **A stale design-record `Consumers` line was corrected.** `docs/design/models/agg/agg_trip_zone_daily.md` said the semantic layer maps only `trip_count`. Fixed in `77e73ea`.
- **A dangling ADR link was corrected.** `docs/design/trips/one-zone-day-build.md` cited ADR 0018 under a filename it does not have. Fixed in `77e73ea`. `tests/test_adr_links.py` does not catch this — it checks two-way listing, not that the target path resolves.

## Limits

- `bindings` reports 2 `bindings/unproven` warnings on `LTS7_daily_zone_revenue`: `'total_revenue' is not computed by an aggregation in the SQL`, and the same for `trip_count`. This is the honest limit of a static trace, not a mismatch — by design (`R-01`) the report's SQL now contains no aggregation to trace into. `unproven` means the SQL could not be traced; the data-level test `assert_semantic_content_holds` holds both bindings and passes, reconciling the report's `sum(trip_count)` and `sum(total_revenue)` to `fct_trip` under the billable filter at `(date, zone)`.
- `profile --relation finance.mart_daily_zone_revenue` returns one `profile/unchecked` warning: the relationship from `pickup_location_id` to `dim_zone.zone_natural_key` is not checked because the contract has no `dim_zone` schema. That claim is unproven here, not disproven; the equivalent join is exercised by the `R-02` comparison (0 unmatched rows either side) and by the passing `relationships_mart_daily_zone_revenue_pickup_location_id__zone_natural_key` dbt test.
- `odcs.py check --relations --catalog` reports 6 `relations/mismatch` errors on `bronze.audit_runs`, `bronze.audit_table_loads`, `ops_raw.audit_runs`, `ops_raw.audit_table_loads`, `mdm_raw.audit_runs` and `mdm_raw.audit_table_loads`. These are dlt-managed audit tables whose contracts expect relations the dbt catalog does not describe; they are outside this intent's impacted set, and neither relation this intent touched appears in the error list.
- `diff_manifest_contract.py --materialize` needs `--deps` in this repository: without it the disposable worktree has no `dbt_packages/` and `dbt parse` fails. Recorded so a later run does not mistake it for a contract difference.

## Discovery

Written by designing. Each result below is the design's input-adequacy evidence; the
queries ran read-only against the Domain warehouse at commit `1184020`. Measurements
live here, never in a design record.

- **Relations are located on `domain`**: `finance.mart_daily_zone_revenue`,
  `agg.agg_trip_zone_daily` and `core.fct_trip` were read through `lakehouse_schema`
  on target `domain` with `schemaName` and `tableName` set, which found each on that
  target. The sandbox holds the same 102 relations and is a copy taken at activation.

- **Input adequacy: `Ready` for `agg_trip_zone_daily`.** Its upstream `core.fct_trip`
  is non-empty and complete for the window; the sandbox `fct_trip` holds 9,722,362
  rows in total and 9,722,336 inside the reporting window, with 9,604,511 billable.
  No required field is absent and no join key is null. — `select count(*) from core.fct_trip`

- **Zone join drops no row and has no null key in the window.** `fct_trip` in the
  window: 0 null `pickup_zone_key`, 0 `pickup_zone_key` with no `dim_zone` row,
  262 distinct `pickup_zone_key` values. — `select ... from core.fct_trip where
  pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'`

- **Every money and count column the mart needs is populated on billable trips.**
  Among in-window billable trips: 0 null `total_amount`, 0 null `fare_amount`,
  0 null `tip_amount`, 0 null `total_surcharges`, 0 null `tolls_amount`. —
  `select count(*) filter (where <col> is null) ... where is_billable and <window>`

- **Zone attributes are functionally determined by `zone_natural_key`, so adding
  `reporting_region` to the agg cannot split a group.** `dim_zone` has 272 rows over
  265 distinct `zone_natural_key` values; 7 zones carry two versions, and for every
  one of them `zone_name`, `borough_name` and `reporting_region` are identical across
  the versions. Queried as: 0 zones with more than one `zone_name`, 0 with more than
  one `borough_name`, 0 with more than one `reporting_region`. — `select ... from
  core.dim_zone group by zone_natural_key`

- **Adding `reporting_region` to the agg's group-by leaves its row set identical.**
  Today's `agg.agg_trip_zone_daily` has 20,771 rows; the same grouping plus
  `reporting_region` returns 20,771 rows with 0 rows on either side of a full outer
  join. — `with abs as (...) ... full outer join`

- **Adding billable measures does not add rows either.** A group-by at zone × day
  with `count(*) filter (where is_billable)` and the billable sums returns 20,771
  rows, the same set. — `with filtersum as (...) ...`

- **The mart's row set is a strict subset of the agg's: 20,770 of 20,771.** The one
  extra agg row is `2024-02-12`, zone `175`, with `trip_count` 1 and
  `total_revenue` 0.0 — a trip with a zero total, so no billable trip on that
  zone-day. This is the row the user's "publish 0" answer covers. — `full outer join`
  of `finance.mart_daily_zone_revenue` against `agg.agg_trip_zone_daily`

- **The consolidated build reproduces the mart's numbers at cent precision.**
  Rebuilding the mart's six numeric columns from `fct_trip` at zone × day with
  `filter (where is_billable)` and comparing row by row against today's mart over
  20,770 rows: 0 differing `trip_count`, 0 differing money values at `round(x, 2)`,
  and 0 differing `borough`/`zone_name`/`reporting_region`. — `with new_mart as
  (...) select count(*) filter (where round(n.total_revenue,2) <> round(o.total_revenue,2)) ...`

- **Money sums are not bit-reproducible, which is why the acceptance is cent
  precision.** The same comparison without rounding differs in the last float bits
  on 9,836 of 20,770 rows, max absolute delta 2.97e-9. The cause is not the
  restructuring: recomputing `agg.agg_trip_zone_daily`'s own stored `total_revenue`
  and `total_miles` from `fct_trip` with its own SQL shape differs from the stored
  values on 9,877 of 20,771 rows, max absolute delta 3.49e-9. Exact
  `DECIMAL(18,2)` summation then cast back to `DOUBLE` also differs from the stored
  mart on 7,652 of 20,770 rows, so decimal arithmetic is not a route to bit equality
  either. — two queries: the unrounded form of the comparison above, and
  `with recomputed as (...) join agg.agg_trip_zone_daily`

- **Ravi's acceptance figures are today's mart, and the two candidate "operations"
  sources are different populations.** Over Q1 2024:
  `finance.mart_daily_zone_revenue` gives 9,604,511 trips and 263,480,834.99
  revenue, JFK (zone 132) 416,460 and 33,881,378.28;
  `agg.agg_trip_zone_daily` gives 9,722,336 and 260,487,920.62, JFK 429,806 and
  33,140,983.67; `ops_raw.trip_assignment` joined to `fct_trip` for billable
  in-window trips gives 457,991 and 12,639,955.27, JFK 20,713 and 1,679,105.07. The
  agg carries no billable revenue column at all. — three aggregate queries, one per
  relation

- **The operator's records match `fct_trip` exactly on the trips they cover, and
  cover only the fleet.** `ops_raw.trip_assignment` has 463,848 rows, all of which
  match a `fct_trip` row by `trip_key`; on those, `pickup_location_id`,
  `total_amount` and pickup time are identical to `fct_trip`, and 5,857 are
  non-billable. `fct_trip` has 463,848 `is_fleet_attributed` rows out of 9,722,362,
  all of them yellow. — `with m as (...) select count(*), sum(...) ...`

- **The data covers every day of Q1, so no period is cut short.** `fct_trip` spans
  2002-12-31 to 2024-04-01, and inside the window it has 91 distinct `pickup_date`
  values from 2024-01-01 to 2024-03-31, which is every day of the quarter. — `select
  min(pickup_date), max(pickup_date), count(distinct pickup_date) ...`

- **DuckDB concurrency**: the sandbox admits one writer, and the Domain file is
  read-only to this work; all queries above are `select` only.
