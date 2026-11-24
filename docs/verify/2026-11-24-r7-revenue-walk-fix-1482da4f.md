# Verification: R7 · revenue walk fix

## Verification

`verdict: verified` at `1cb2529`. Every acceptance criterion is proven by an
executed command, and the two canonical gates that were uncovered when this
record first returned are closed: `validating-data-contract` reviewed
`contracts/core/fct_trip.odcs.yaml` with `--catalog` set to the sandbox
database, and `validating-semantic-model` reviewed `logical-model/`. The sandbox
probes were re-run at `1cb2529` and the read-only Domain probes still return the
pre-fix figures; every test, lint, contract and semantic gate was re-run there
and is green. The walk's nine lines total `2,629,185.82`, equal to billable
revenue at the cent; `44/44` groups balance; `fare_residual` equals its declared
definition on every row (`residuals_off_definition 0`); and the guard that
returned `9` groups on the pre-fix warehouse returns none. What is still not
shown, and named in Findings: the balance partly restates the build, the sign of
the surviving residual is unexplained, and `530` trips became unbalanced as a
consequence the user accepted.

## Coverage

| Item | Evidence | Result | At |
| --- | --- | --- | --- |
| `C-01` `core.fct_trip.fare_residual` subtracts the airport fee: over the billable window its sum is `−32,638.75` and no trip is left holding a fee | Sandbox probe recomputing the residual from its parts, independently of the macro: `select round(sum(fare_residual),2), count(*) filter (where abs(fare_residual - (total_amount - coalesce(fare_amount,0) - coalesce(tip_amount,0) - coalesce(tolls_amount,0) - coalesce(extra,0) - coalesce(mta_tax,0) - coalesce(improvement_surcharge,0) - coalesce(congestion_surcharge,0) - coalesce(airport_fee,0))) > 0.01) from core.fct_trip where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'` → `-32638.75 \| 0`. The pre-fix warehouse sums the same population to `−20,376.50`. `describe_asset fct_trip` reports `fare_residual` `data_type: DOUBLE`, `tests: []` and `latest_result: null` (**never run**: no dbt artifact is recorded for the Domain warehouse) | pass | `1cb2529` |
| `C-02` The walk balances: every group's lines sum to its `total_amount` within `0.01`, and the walk's total is `2,629,185.82` = `SUM(total_amount)` over billable in-window trips | Sandbox probe over the built walk and fact: `walk_total 2629185.82`, `billable_revenue 2629185.82`, `groups_unbalanced 0`, `walk_rows 395`. The domain warehouse still reads `walk_total 2641448.07` against the same `2629185.82`. `assert_revenue_walk_balances` re-run as its own gate returns `PASS=1`. `describe_asset mart_revenue_component_bridge` reports `latest_result: null` (**never run**) | pass | `1cb2529` |
| `C-03` The guard exists and would have caught this: `9` groups against the pre-fix warehouse, `0` after | The guard's own SQL run against the read-only Domain warehouse: `groups_unbalanced 9`, gap `walk_total − billable_revenue = 12262.25` = `SUM(coalesce(airport_fee,0))`; the same query against the sandbox returns `0`. `dbt test --select assert_revenue_walk_balances` → `PASS=1 WARN=0 ERROR=0` | pass | `1cb2529` |
| `C-04` `ops.mart_trip_quality_scorecard.unbalanced_total_count` moves as predicted: `31,869` before, `26,457` after, `5,942` reclassified | Domain probe of both directions in one query: `unbalanced_before 31869`, `unbalanced_after 26457`, `fixed_by_change 5942`, `newly_unbalanced 530` — the net move is `5,412`, because subtracting the fee also pushes `530` trips that sat inside `0.01` outside it. Sandbox probe: `sum(unbalanced_total_count) = 26457`, the same figure as the trip count, so the scorecard's groups partition the trips | pass | `1cb2529` |
| `C-05` `core/fct_trip` contract `2.0.0`, declared properties unchanged, `check` and `diff origin/main` exit 0 | `grep -n version: contracts/core/fct_trip.odcs.yaml` → `5:version: 2.0.0`; the file's diff against `1184020` is that one line; `odcs.py check` exit 0; `odcs.py diff origin/main` → `[]`, exit 0. The relation still matches the contract: `check --relations --catalog <sandbox db>` exit 0 and `profile --relation core.fct_trip` exit 0 | pass | `1cb2529` |
| Scope: `transformation/tests/assert_revenue_walk_balances.sql`, `test-map.json` | `dbt test --select assert_revenue_walk_balances` → `PASS=1`; the map registers the test under `finance`; `python3 -m pytest tests -q` → `222 passed` (the map tests check the registration) | pass | `1cb2529` |
| Scope: `transformation/macros/finance.sql` (`fare_residual`) | `dbt build --full-refresh --select +fct_trip` → `PASS=99 WARN=1 ERROR=0`, exit 0; the compiled residual reads `coalesce(t.total_amount,0) - … - coalesce(t.tolls_amount,0) - coalesce(t.airport_fee,0) - (…)`. `--select fct_trip` alone is not the gate: `int_trip_fare_components` is a view, so the full refresh has to reach it | pass | `1cb2529` |
| Scope: `core.fct_trip` values and its `fare_residual` doc block | `dbt test --select path:models/marts/core --exclude test_type:unit` → `PASS=74 WARN=1 ERROR=0`; the corrected block lists eight components and the macro subtracts eight | pass | `1cb2529` |
| Scope: `finance.mart_revenue_component_bridge` (`c_residual`, walk total) | `dbt test --select path:models/marts/finance --exclude test_type:unit` → `PASS=8 WARN=1 ERROR=0`; the built walk emits exactly the nine names the column description lists, in order `1`–`9`, at `44` groups (`c_congestion` on `43`, the deferred NULL aggregate) | pass | `1cb2529` |
| Scope: `ops.mart_trip_quality_scorecard` (`unbalanced_total_count`) | `dbt test --select path:models/marts/ops --exclude test_type:unit` → `PASS=7 WARN=1 ERROR=0`; the count moved as `C-04` records | pass | `1cb2529` |
| Scope: `contracts/core/fct_trip.odcs.yaml` | The gates above; the contract's own review is the canonical-gate row below, and it passes | pass | `1cb2529` |
| Canonical gate: data contract — the `validating-data-contract` report | No such report exists in this intent: the Plan's Task 4 named the `data-contract` skill and ran `generate`, `check`, `diff`, but not that skill's step 9 ("Load `validating-data-contract` for the review before commit"), and `grep -rn validating-data-contract docs/plans docs/cases docs/verify` matches nothing for this intent. Its commands were run here instead (see `## Gate results`); the judgement review did not happen | pass — the `validating-data-contract` review is recorded with no finding; the dynamic gates ran against the sandbox database rather than reporting `catalog/missing` | `1cb2529` |
| Canonical gate: semantic model — the `validating-semantic-model` report | The Domain has `logical-model/` and this intent changed a boundary model an Ossie document maps, so the gate applies; no `validating-semantic-model` report exists in this intent and its Plan has no such task. Its five structural gates were re-run here and all exit 0 | pass — the `validating-semantic-model` review is recorded; its structural gates exit `0` | `1cb2529` |
| Weakening: no existing test or contract declaration was loosened | `diff_data_tests.py` on `_core.yml` base vs head → `{"weaker": [], "stronger": [], "ambiguous": []}`; `diff_manifest_contract.py` on the base and head manifests → `{"weaker": [], "stronger": []}`; the only test change is the new singular test, and the only contract change is the `version` line | pass | `1cb2529` |
| Words against the data | `docs.md` names eight subtracted components and the macro subtracts eight; `fct_trip.md` `D-08` and the bridge record `D-01`–`D-03` state no figure that contradicts the build; the bridge's `component_name` description lists the nine names the relation emits; the Ossie field `fare_residual` ("Trip total minus every modelled fare component") now agrees with the code, and no Ossie document was edited | pass | `1cb2529` |
| Scope: nothing changed outside the Plan's rows | `git diff --stat 1184020...HEAD` lists 10 files, every one a Plan row or this case's own record; no published model the case put out of scope was modified; no new business rule was decided without a recorded source (the change restores the definition `CONTEXT.md` and the Ossie field already state) | pass | `1cb2529` |

## Gate results

| Gate | Command | Exit | Outcome |
| --- | --- | --- | --- |
| `fare_residual` macro (full refresh) | `cd transformation && dbt build --full-refresh --select +fct_trip --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` | 0 | pass — `PASS=99 WARN=1 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=100`; the warning is the pre-existing `assert_semantic_levels_hold` sentinel-borough warning |
| Sandbox destination (after the full refresh) | `python /data/default-plugins/vibedata-data-engineering/0.148.26/scripts/assert_dbt_destination.py` | 0 | pass — `DESTINATION_OK: 22 built relation(s) landed in the sandbox` |
| Playbook sandbox verification (the consumers) | `cd transformation && dbt build --select fct_trip+ --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` | 0 | pass — `PASS=36 WARN=1 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=37` |
| Sandbox destination (after the consumers) | `python /data/default-plugins/vibedata-data-engineering/0.148.26/scripts/assert_dbt_destination.py` | 0 | pass — `DESTINATION_OK: 10 built relation(s) landed in the sandbox` |
| Core tests | `cd transformation && dbt test --select path:models/marts/core --exclude test_type:unit` | 0 | pass — `PASS=74 WARN=1 ERROR=0` |
| Finance tests | `cd transformation && dbt test --select path:models/marts/finance --exclude test_type:unit` | 0 | pass — `PASS=8 WARN=1 ERROR=0` |
| Ops tests | `cd transformation && dbt test --select path:models/marts/ops --exclude test_type:unit` | 0 | pass — `PASS=7 WARN=1 ERROR=0` |
| Walk guard | `cd transformation && dbt test --select assert_revenue_walk_balances --exclude test_type:unit` | 0 | pass — `PASS=1 WARN=0 ERROR=0` |
| dbt data tests | `cd transformation && dbt test --exclude test_type:unit` | 0 | pass — `PASS=166 WARN=1 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=167` |
| dbt unit tests | `cd transformation && dbt test --select test_type:unit` | 0 | pass — `PASS=6 WARN=0 ERROR=0` |
| Python tests | `python3 -m pytest tests -q` | 0 | pass — `222 passed in 164.98s` |
| Python lint | `ruff check .` | 0 | pass — `All checks passed!` |
| SQL style | `sqlfluff lint transformation/models` | 0 | pass — `All Finished!` |
| Canonical-artifact lint (CI) | `python3 tools/ossie_lint.py` | 0 | pass — `contracts exit 0, 31 warning(s)`, `0 blocking finding(s)` |
| ADR numbering (CI) | `python3 .github/scripts/adr_lint.py` | 0 | pass — `no duplicate numbers, no dangling references` |
| Contract check | `python3 .agents/skills/data-contract/scripts/odcs.py check` | 0 | pass — 34 items: `31 contract/active-unbuilt` warnings + 3 `boundary/excluded` infos, all pre-existing (see Findings) |
| Contract diff | `python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main` | 0 | pass — `[]`, no `diff/version-not-bumped` |
| Contract relations | `python3 .agents/skills/data-contract/scripts/odcs.py check --relations` | 1 | unrun — `catalog/missing`: "relations: no Intent context names a warehouse; pass `--catalog` with the built local database file or dbt's catalog.json" |
| Contract relations against dbt's catalog | `… odcs.py check --relations --catalog transformation/target/catalog.json` | 1 | not the gate — 6 `relations/mismatch` errors, none naming `core.fct_trip` (see Findings) |
| Contract relations against the sandbox | `… odcs.py check --relations --catalog /data/ephm_duckdb/ephm_nyc-taxi-duckdb-100k_r7-revenue-walk-fix-1482da4f.duckdb` | 0 | pass — no `relations/mismatch` |
| Contract profile | `… odcs.py profile --relation core.fct_trip --catalog /data/ephm_duckdb/ephm_nyc-taxi-duckdb-100k_r7-revenue-walk-fix-1482da4f.duckdb` | 0 | pass — 9 `profile/unchecked` warnings (the nine relationships to dimensions the contract declares no schema for); no `profile/error` |
| Semantic model: validate | `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/` | 0 | pass — `0 error(s), 1 warning(s)` (`relationship/to-column-not-a-key`); the Ossie documents are unchanged by this intent |
| Semantic model: coverage | `… ossie.py coverage logical-model/ transformation/models/marts/core/ transformation/models/marts/agg/ transformation/models/marts/finance/ transformation/models/marts/ops/ --exclude agg.agg_od_flow_matrix --exclude finance.mart_revenue_component_bridge --exclude core.dim_fare_regime` | 0 | pass — no coverage error; the three `coverage/excluded` infos are the declared `semantic_exclusions` |
| Semantic model: suppliers | `… ossie.py suppliers logical-model/` | 0 | pass — `0 unsupplied item(s)` |
| Semantic model: notes | `… ossie.py notes logical-model/ transformation/tests docs/adr` | 0 | pass — `0 dangling pointer(s), 0 unchecked director(ies)` |
| Semantic model: generated tests | `… ossie.py generate-tests logical-model/ transformation/tests --check` | 0 | pass — `3 generated test(s), 0 stale` |
| Weakening: dbt test declarations | `python …/scripts/diff_data_tests.py <base _core.yml> <head _core.yml>` | 0 | pass — `{"weaker": [], "stronger": [], "ambiguous": []}` |
| Weakening: enforced contracts | `python …/scripts/diff_manifest_contract.py /tmp/base_manifest.json transformation/target/manifest.json` (base materialised with `--materialize 1184020 transformation …`) | 0 | pass — `{"weaker": [], "stronger": []}` |
| Canonical gate: data contract | `validating-data-contract` over `contracts/core/fct_trip.odcs.yaml`, with `--catalog` set to the sandbox database | 0 | pass — review recorded with no finding; `check` exit `0`, `diff origin/main` exit `0`, `check --relations` exit `0`, `profile` exit `0` |
| Canonical gate: semantic model | `validating-semantic-model` over `logical-model/` | 0 | pass — review recorded; `validate`, `coverage`, `suppliers`, `notes`, `generate-tests --check`, `bindings` and `columns` all exit `0`, with the profile warnings named in Findings |

## Findings

- **Both canonical-gate gaps are closed.** `validating-data-contract` reviewed
  `contracts/core/fct_trip.odcs.yaml` with `--catalog` set to the sandbox
  database, so its dynamic gates ran instead of reporting `catalog/missing`, and
  `validating-semantic-model` reviewed `logical-model/`. Both verdicts are
  recorded in the Plan's Task 4 at `1cb2529`, and the two rows above and in
  `## Gate results` cite them.
- **The semantic layer carries profile warnings this intent did not create.**
  `ossie.py bindings` reports `14` `bindings/unproven`, one of them
  `shift.LTS8_vehicle_utilisation` → `mart_vehicle_utilisation` with "no SQL in
  the manifest; run `dbt compile` first"; `ossie.py columns` reports `5`
  `columns/datatype-mismatch` — `trips.total_amount`, `trips.fare_residual` and
  `shift.gross_revenue` are declared `Decimal` over a `DOUBLE` warehouse column.
  `fare_residual`'s type is unchanged by this intent (`DOUBLE` before and after),
  so these are pre-existing; the review judged them non-blocking here.
- **The balance partly restates the build.** `assert_revenue_walk_balances`
  compares the bridge with `fct_trip`, and the bridge's eight non-residual lines
  are `SUM`s of those same `fct_trip` columns, so "the walk equals billable
  revenue" holds algebraically once the residual's definition does. The
  independent evidence is elsewhere: `residuals_off_definition = 0` recomputes
  the residual from its nine parts in a query written for this Verification, not
  by the macro, and the same guard returned `9` groups before the change.
- **`check --relations --catalog <dbt catalog.json>` names six input relations
  as mismatches** — `bronze`, `mdm_raw` and `ops_raw` `audit_runs` and
  `audit_table_loads`, all "the catalog holds no such relation". All six exist in
  the sandbox (`information_schema.tables`) and all six contracts are unchanged
  by this intent (`git diff --stat` shows only `contracts/core/fct_trip.odcs.yaml`
  moving), so the errors come from dbt's catalog holding only dbt-built
  relations. Not proven at the merge-base (no worktree run), so reported as a
  finding about that variant's coverage, not as a certified pre-existing failure.
  Against the sandbox database the same gate exits 0.
- **`check` reports `contract/active-unbuilt` for 31 of the 34 active contracts**,
  `core.fct_trip` among them, while `check --relations` proves the relation
  exists and matches. The warning is emitted without and with `--catalog`, so it
  is a property of that heuristic in this environment, not of any contract.
- **The change-classification tool cannot see this change.** `list_changes` reads
  3 changed assets, all `additive` or `documentation_only`, `consumers_reached:
  []`, no breaking change — because the macro is not a dbt asset, so editing it is
  not fingerprinted onto the nine models that compile it. The Plan's hand-derived
  impacted set (`get_lineage` `+fct_trip+` reaches the same nine) is the operative
  one, and the breaking contract change rests on the approval recorded in the
  Case, not on this tool.
- **Sandbox run history is thin.** `list_runs target=ephemeral` returns one run
  (the guard's `dbt test`, `pass: 1`); the `dbt build` invocations are not
  recorded, and `describe_asset` returns `latest_result: null` for `fct_trip` and
  the bridge. The gates above are therefore evidence from commands run at
  `1cb2529`, not from a run record.
- **One pre-existing cosmetic typo** in `docs/design/models/core/fct_trip.md`
  History: two earlier entries begin `- - ` where the third begins `- `. Outside
  this intent's rows; left alone.

## Discovery

Design-time probes against the Domain warehouse, read-only, at `1184020`. Each
figure below is the output of the query beside it.

- The walk sums to billable revenue plus the airport fee: walk `2,641,448.07`
  against billable revenue `2,629,185.82`, a difference of `12,262.25` equal to
  `SUM(coalesce(airport_fee, 0))` over the same billable trips; the billable
  residual totals `−20,376.50`, so the fixed residual would total `−32,638.75`.
  — `select (select round(sum(component_amount), 2) from finance.mart_revenue_component_bridge) as walk_total, (select round(sum(total_amount), 2) from core.fct_trip where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01') as billable_revenue, (select round(sum(coalesce(airport_fee, 0)), 2) from core.fct_trip where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01') as airport_fee, (select round(sum(fare_residual), 2) from core.fct_trip where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01') as residual_total`
- The walk is out of balance in 9 of its 44 groups today, by `12,262.25` in
  total; under the corrected residual all 44 balance, worst gap `0.0`. So the
  test this case adds returns 9 rows before the fix and 0 after.
  — `with base as (select date_trunc('month', f.pickup_datetime) as trip_month, f.service_type_key, z.borough_name, coalesce(sum(f.fare_amount),0)+coalesce(sum(f.tip_amount),0)+coalesce(sum(f.tolls_amount),0)+coalesce(sum(f.extra),0)+coalesce(sum(f.mta_tax),0)+coalesce(sum(f.improvement_surcharge),0)+coalesce(sum(f.congestion_surcharge),0)+coalesce(sum(coalesce(f.airport_fee,0)),0)+coalesce(sum(f.fare_residual),0) as walk_sum, sum(f.total_amount) as total_amount from core.fct_trip f join core.dim_zone z on f.pickup_zone_key = z.zone_key where f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01' and f.is_billable group by 1,2,3) select count(*) as groups, count(*) filter (where abs(walk_sum - total_amount) > 0.01) as groups_unbalanced, round(sum(walk_sum - total_amount), 2) as total_gap from base`
  → `44 | 9 | 12262.25`; the same query with `sum(f.fare_residual - coalesce(f.airport_fee,0))` as the residual → `44 | 0 | 0.0`
- The zone join drops no billable trip, so after the fix the walk total is
  billable revenue exactly, not a partly-joined subset.
  — `select (select count(*) from core.fct_trip where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01') as billable_trips, (select count(*) from core.fct_trip f join core.dim_zone z on f.pickup_zone_key = z.zone_key where f.is_billable and f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01') as billable_joined, (select count(*) from core.fct_trip where is_billable and pickup_zone_key is null and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01') as billable_null_zone`
  → `95958 | 95958 | 0`
- `mart_trip_quality_scorecard.unbalanced_total_count` moves: `31,869` in-window
  trips carry `|fare_residual| > 0.01` today, `26,457` would after the fix, and
  `5,942` are explained by the airport fee alone.
  — `select count(*) as trips_in_window, count(*) filter (where fare_residual is not null and abs(fare_residual) > 0.01) as unbalanced_now, count(*) filter (where abs(fare_residual - coalesce(airport_fee,0)) > 0.01) as unbalanced_after, count(*) filter (where fare_residual is not null and abs(fare_residual) > 0.01 and abs(fare_residual - coalesce(airport_fee,0)) <= 0.01) as fixed_by_change from core.fct_trip where pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'`
  → `97184 | 31869 | 26457 | 5942`
- The residual that survives the fix is a separate signal, not the airport fee:
  `−32,648.75` over all in-window trips (yellow `−32,346.50`, green `−302.25`),
  concentrated on `±2.50` (`18,153` trips at `−2.50`, `6,745` at `+2.50`, the
  rest at `±1.00`–`±4.50`), and `ehail_fee` is `0.00` on every one of the
  `97,184` trips so it is not an unmodelled column.
  — `select service_type_key, count(*) as trips, round(sum(fare_residual - coalesce(airport_fee, 0)), 2) as residual_after_fix, count(*) filter (where abs(fare_residual - coalesce(airport_fee,0)) > 0.01) as unbalanced_after_fix, round(sum(coalesce(ehail_fee, 0)), 2) as ehail_fee, count(*) filter (where coalesce(ehail_fee,0) <> 0) as trips_with_ehail from core.fct_trip where pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01' group by 1 order by 1`
  and `select round(fare_residual - coalesce(airport_fee,0), 2) as new_residual, count(*) as trips from core.fct_trip where pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01' and abs(fare_residual - coalesce(airport_fee,0)) > 0.01 group by 1 order by trips desc limit 12`
- No dbt run history for the Domain warehouse could be read: `describe_run`
  returns one `dlt pipeline tlc` audit run and no dbt artifact, so "the build
  was green" is evidence from the models and tests as authored, not from a run
  record.
  — `describe_run(target=domain)`
