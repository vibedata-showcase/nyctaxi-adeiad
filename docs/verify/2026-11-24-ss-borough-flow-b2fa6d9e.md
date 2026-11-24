# Verification: SS · borough flow

## Verification

`verdict: verified` at `571c823`: `agg_borough_flow_matrix` publishes the 108-row month × origin × destination matrix the Requirement asks for, its 95,723 trips and 2,599,668.55 of revenue close against `fct_trip`, every one of the 15 per-borough monthly shares reproduces the Discovery, and no gate failed. Two limits are recorded below and neither leaves a row uncovered: `odcs.py profile` refused on this platform, so the contract's claims rest on direct recomputation instead, and `month_start_date` diverges in type from three sibling `agg` contracts — a pre-existing defect in those three, not in this one.

## Coverage

| Item | Evidence | Result | At |
| --- | --- | --- | --- |
| `R-01` one row per month × origin × destination, Q1 2024, no duplicates | `lakehouse_query` on `agg.agg_borough_flow_matrix`: `count(*)`, `count(distinct month_start_date)`, and a grouped duplicate-grain count | 108 rows; 3 months; 6 origin and 6 destination members; 0 duplicate (month, origin, destination) triples; no month outside 2024-01/02/03 | `571c823` |
| `R-02` every combination present, zero-trip pairs carried at 0 | same query: `count(*) filter (where trip_count = 0)`; plus `assert_borough_flow_population_closes` deriving the spine from `dim_date` × `dim_zone` members | 15 zero rows, 93 populated, 15 + 93 = 108 = 3 × 6 × 6; the closure test passes | `571c823` |
| `R-03` trips and revenue per pair, billable only | `lakehouse_query`: `sum(trip_count)`, `round(sum(revenue),2)`; independently recomputed by `assert_borough_flow_population_closes` from `fct_trip` | 95,723 trips and 2,599,668.55 revenue, both equal to the independent recomputation; 0 null `revenue` | `571c823` |
| `R-04` each city borough's leaving share, one value per origin-month, null on unresolved, reproducing 5.30 / 58.88 / 70.52 for January | `lakehouse_query`: `any_value(cross_borough_share)`, `count(distinct cross_borough_share)` per (month, origin); all 15 percentages compared to Discovery line 71 | all 15 match (Bronx 58.88/64.63/50.67, Brooklyn 37.18/40.21/42.96, Manhattan 5.30/5.21/5.36, Queens 70.52/72.17/73.13, Staten Island 40.00/0.00/37.50); `distinct_shares` = 1 on every origin-month; 18 null-share rows, exactly the 3 months × 6 destination rows of the unresolved origin | `571c823` |
| `R-05` numerator and denominator published beside the share | same query: `origin_cross_borough_trips`, `origin_trips_to_known_destination`; `assert_borough_flow_share_is_its_ratio` recomputes the share from them | every row carries both counts; the share equals one over the other within 1e-9 relative | `571c823` |
| `R-06` unresolved destinations neither cross- nor in-borough, in the unresolved group | `lakehouse_query`: sums by `flow_class`; `borough_flow_share_ignores_unresolved_destinations` unit test | cross 11,249 + in-borough 83,474 = 94,723 city-to-city, disjoint from the 1,000 unresolved-touching trips; the 1,000 sit only on rows with `unresolved` as origin or destination | `571c823` |
| `R-07` EWR excluded on both sides, difference exactly the 235 EWR trips | `lakehouse_query` on domain: billable trips in window = 95,958, and a direct count of billable trips touching an EWR zone = 235; on ephemeral: 95,958 − table total = 235; plus a count of EWR/`Unknown`/`N/A` label rows | 0 EWR rows, 0 raw-label rows, difference 235, matching the 235 counted directly | `571c823` |
| `R-08` no 25-trip floor | `lakehouse_query` on the fact: 65 city-to-city month-pairs, thinnest 1; `assert_borough_flow_has_no_floor` compares every populated fact pair to the table | all 65 present with equal counts, including Bronx → Brooklyn January at 11 and the thinnest pair at 1; no `having` in the SQL | `571c823` |
| `R-09` boundary relation with properties, tests, contract, docs matching data | `dbt build --select +agg_borough_flow_matrix+`; `odcs.py check`, `generate`, `diff`; `ossie.py` gates; the whole-model `sqlfluff lint transformation/models` | build PASS=108 WARN=1 (the warning is the pre-existing `assert_semantic_levels_hold`); contract gates exit 0; every description checked against the built relation below | `571c823` |
| model SQL (scope row) | `dbt build --select agg_borough_flow_matrix` then `assert_dbt_destination.py` | exit 0; `PASS=14`; `DESTINATION_OK: 1 built relation(s)` | `571c823` |
| `_agg.yml` entry (scope row) | `dbt test --select agg_borough_flow_matrix --exclude test_type:unit` | exit 0; PASS=11 — 5 `not_null` (month, origin, destination, flow_class, revenue), 1 `accepted_values` on `flow_class`, and the 4 singular tests selected with the model | `571c823` |
| `_unit_tests.yml` (scope row) | `dbt test --select +agg_borough_flow_matrix+,test_type:unit` | exit 0; PASS=9 (6 of them this model's) | `571c823` |
| ODCS contract (scope row) | `odcs.py check`; `odcs.py diff origin/main`; `check --relations --catalog` | check and diff exit 0; relations check exits 1 only for the six pre-existing `*_raw`/`bronze` audit-table mismatches, none naming this relation | `571c823` |
| four singular tests (scope row) | `dbt test --select assert_borough_flow_*` | exit 0; PASS=4; each shown to bite by injection during Task 2 | `571c823` |
| `test-map.json` (scope row) | `python3 -m pytest tests/test_maps.py -q` | exit 0; 31 passed, including `[agg-unit]` | `571c823` |

## Gate results

| Gate | Command | Exit | Outcome |
| --- | --- | --- | --- |
| data and unit tests | `cd transformation && dbt build --select +agg_borough_flow_matrix+ --exclude test_type:unit --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` | 0 | pass — PASS=108 WARN=1 ERROR=0 (the warning is `assert_semantic_levels_hold`, pre-existing and unrelated) |
| unit tests | `cd transformation && dbt test --select +agg_borough_flow_matrix+,test_type:unit --target dev` | 0 | pass — PASS=9 |
| sandbox destination | `python3 /data/default-plugins/vibedata-data-engineering/0.148.28/scripts/assert_dbt_destination.py` | 0 | pass — `DESTINATION_OK: 23 built relation(s)` |
| project audit | `cd transformation && dbt build --select package:dbt_project_evaluator --vars '{dbt_project_evaluator_enabled: true}' --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}' --target dev` | 0 | pass — PASS=66 WARN=12 ERROR=0; no warning names `agg_borough_flow_matrix` |
| contract static | `python3 .agents/skills/data-contract/scripts/odcs.py check` | 0 | pass — no errors, no warnings naming this contract |
| contract version | `python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main` | 0 | pass — `[]` |
| contract relations | `python3 .agents/skills/data-contract/scripts/odcs.py check --relations --catalog transformation/target/catalog.json` | 1 | fail outside the impacted set — six `relations/mismatch` for `bronze`/`mdm_raw`/`ops_raw` audit tables the dbt catalog does not hold; nothing names `agg_borough_flow_matrix`. A source-table finding, not this intent's. |
| contract profile | `python3 .agents/skills/data-contract/scripts/odcs.py profile --relation agg.agg_borough_flow_matrix` | 1 | unrun — `catalog/missing` (no Intent context names a warehouse), then `catalog/unreadable` when handed dbt's `catalog.json` ("profile queries rows, so it reads a database"). Every claim it would test was recomputed directly instead, see Coverage. |
| semantic model gates | `python3 .agents/skills/semantic-model/scripts/ossie.py validate` / `suppliers` / `notes` / `generate-tests --check` | 0 | pass — all four exit 0 |
| semantic coverage | `python3 .agents/skills/semantic-model/scripts/ossie.py coverage logical-model/ <four boundary roots> --exclude … --exclude agg.agg_borough_flow_matrix` | 0 | pass — the new relation is excluded by `repo-map.json`, per `D-14`; without the `--exclude` the same command exits 1 with `coverage/unmapped` naming it, which is the exclusion working |
| ontology gates | `python3 .agents/skills/semantic-model/scripts/ossie.py validate ontology/` / `refs` / `glossary` | 0 | pass — all three exit 0 |
| Python tests | `python3 -m pytest tests -q --ignore=tests/setup` | 0 | pass — 216 passed |
| Python lint | `ruff check .` | 0 | pass — `All checks passed!` |
| SQL lint | `sqlfluff lint transformation/models` | 0 | pass — clean |
| ADR lint | `python3 .github/scripts/adr_lint.py` | 0 | pass — no duplicate numbers, no dangling references |
| ADR links | `python3 -m pytest tests/test_adr_links.py -q` | 0 | pass — every ADR this record cites lists the design record and vice versa |
| dev-artifact scan | `grep` for `dev_mode`, `.add_limit(`, a hardcoded environment id, an edited profile target across the changed paths | 0 | pass — none present; no profile, target or adapter was edited |

## Weakening

`git diff origin/main..HEAD` over the model, its properties, the contract and the four tests shows no test removed or loosened. `not_null` is deliberately absent on `origin_cross_borough_trips` and `origin_trips_to_known_destination` because `D-11` makes them null on the unresolved origin's rows — the Task 1 checkbox asking for `not_null` there was wrong, and the deviation is recorded in the Plan's `## Execution evidence` rather than applied silently. All three other constrained columns keep their tests, and `flow_class` keeps both `not_null` and `accepted_values`.

## Words against the data

- Every number in `docs/verify/2026-11-24-ss-borough-flow-b2fa6d9e.md` `## Discovery` was recomputed against the built relation or the fact: 108 / 15 / 95,723 / 2,599,668.55 / 11,249 / 83,474 / 1,000 / 235 / $29,517.27, the 15 shares, and all six spot-check pairs match to the cent.
- `docs/adr/0018-…md` states 43 of 93 populated month-pairs would fall to a 25-trip floor, and Bronx → Brooklyn at 11 trips in January: both recomputed and true. Its "five city boroughs plus one unresolved group" matches what the table publishes.
- `CONTEXT.md`'s two new entries (**Cross-borough trip**, **EWR**) match the model: `flow_class` implements exactly the entry's "neither in-borough nor cross-borough" rule, and EWR is absent from the table.
- The design record's grain (month × origin × destination), its nine columns, its `table` materialisation and its `contract: {enforced: true}` all match what was built. Its `D-12` choice of `DATE` for `month_start_date` is what the relation carries.
- Every column description states a rule the SQL implements, and each was checked against the built values, not the Plan.

## Findings carried

- **`month_start_date` type divergence.** `date`/`DATE` in `dim_date` and in this contract; `timestamp`/`TIMESTAMP` in `agg_driver_monthly`, `agg_garage_monthly` and `agg_vehicle_monthly`, where `date_trunc('month', shift_date)` genuinely returns `TIMESTAMP`. Pre-existing and outside this intent's scope rows. `D-12` chose `DATE` deliberately to match the calendar dimension, so this contract is not the defect.
- **`odcs.py profile` unrun.** Recorded as unrun, never as passing; the same claims were recomputed directly and are in Coverage.
- **Six pre-existing `relations/mismatch` findings** for the `bronze`/`mdm_raw`/`ops_raw` audit tables, which dbt's catalog does not hold because they are dlt-loaded sources.
