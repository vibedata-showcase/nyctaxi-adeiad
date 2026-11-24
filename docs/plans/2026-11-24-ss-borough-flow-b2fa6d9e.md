# Plan: SS · borough flow

**Goal:** Publish `agg_borough_flow_matrix` — trips and revenue from each city borough to each city borough for every month of Q1 2024, with the `unresolved` group in its own row and column, and each city borough's share of its trips that left it.

**Requirement:** `docs/requirement/2026-11-24-ss-borough-flow-b2fa6d9e.md` (requirement approved `2026-11-24T14:13:23Z`, design approved `2026-11-24T14:22:01Z`)

**Design record:** `docs/design/models/agg/agg_borough_flow_matrix.md` (`D-01` … `D-18`)

**Business decision recorded on the requirement's behalf:** `docs/adr/0018-borough-flows-publish-every-pair-with-unresolved-in-its-own-group.md`

## Constraints

- New model `agg_borough_flow_matrix` in `transformation/models/marts/agg/`; schema `agg` (the folder's existing default); materialised as `table`; `access: public` with `contract: {enforced: true}` (D-01, D-13).
- Built from `fct_trip` with `dim_zone` joined **twice**, on `pickup_zone_key` and `dropoff_zone_key` — the zone version resolved as of each trip's own pickup date, never the current version (D-02, ADR 0009).
- Population: `in_report_window('f.pickup_datetime')` **and** `f.is_billable` (D-03, ADR 0003).
- Members: `dim_zone.is_unresolved_zone` true → one `unresolved` group; otherwise the city borough. Never match on the literal labels `'Unknown'` / `'N/A'` (D-04).
- EWR excluded on both sides by `dim_zone.is_nyc`, never by a literal `'EWR'` (D-05).
- A month × member × member spine, left-joined to trips; zero-trip pairs carry `trip_count` 0 and `revenue` 0 (D-06).
- No `having` clause and no threshold of any kind (D-08, D-15).
- The share is a ratio of sums through the `safe_divide` macro; a zero denominator gives null, never 0 (D-09, D-18).
- `cross_borough_share` is a fraction in [0, 1], not a percentage (D-10).
- The `unresolved` origin's three share columns are null on all of its rows (D-11, D-16).
- No quality verdict is read and no trip is removed for one; `is_billable` is the only verdict the population applies (D-17, ADR 0004).
- No column is added to, removed from or retyped in any existing model; `fct_trip`, `dim_zone` and `agg_od_flow_matrix` are read only.
- No Ossie document, ontology or `semantic_exclusions` change: the exclusion for this relation is already in `repo-map.json` (D-14).
- Month is `month_start_date`, a `DATE` at the first of the month (D-12).

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `transformation/models/marts/agg/agg_borough_flow_matrix.sql` | model | create | `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-06`, `R-07`, `R-08`, `R-09` | `docs/design/models/agg/agg_borough_flow_matrix.md` | `cd transformation && dbt build --select agg_borough_flow_matrix --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` |
| `transformation/models/marts/agg/_agg.yml` (entry for the new model) | model | modify | `R-01`, `R-03`, `R-04`, `R-05`, `R-09` | `docs/design/models/agg/agg_borough_flow_matrix.md` | `cd transformation && dbt test --select agg_borough_flow_matrix --exclude test_type:unit --target dev` |
| `transformation/models/marts/agg/_unit_tests.yml` | model | create | `R-02`, `R-04`, `R-06`, `R-07` | `docs/design/models/agg/agg_borough_flow_matrix.md` | `cd transformation && dbt test --select agg_borough_flow_matrix,test_type:unit --target dev` |
| `contracts/agg/agg_borough_flow_matrix.odcs.yaml` | contract | create | `R-09` | `docs/design/models/agg/agg_borough_flow_matrix.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `transformation/tests/assert_borough_flow_one_row_per_grain.sql` | model | create | `R-01` | `docs/design/models/agg/agg_borough_flow_matrix.md` | `cd transformation && dbt test --select assert_borough_flow_one_row_per_grain --target dev` |
| `transformation/tests/assert_borough_flow_population_closes.sql` | model | create | `R-02`, `R-03`, `R-06`, `R-07` | `docs/design/models/agg/agg_borough_flow_matrix.md` | `cd transformation && dbt test --select assert_borough_flow_population_closes --target dev` |
| `transformation/tests/assert_borough_flow_share_is_its_ratio.sql` | model | create | `R-04`, `R-05` | `docs/design/models/agg/agg_borough_flow_matrix.md` | `cd transformation && dbt test --select assert_borough_flow_share_is_its_ratio --target dev` |
| `transformation/tests/assert_borough_flow_has_no_floor.sql` | model | create | `R-08` | `docs/design/models/agg/agg_borough_flow_matrix.md` | `cd transformation && dbt test --select assert_borough_flow_has_no_floor --target dev` |
| `test-map.json` (`modules.agg`: add the `unit` selector and command; Task 2 adds the four singular tests to `data`) | project-config | modify | `R-01`, `R-09` | `code is contract` | `python3 -m pytest tests/test_maps.py -q` |

**Change impact:** `none downstream`. No existing artifact is modified, so the impacted set is the new relation and its own tests. Nothing in `transformation/`, `contracts/`, `logical-model/` or `ontology/` refs `agg_borough_flow_matrix` today (checked across `*.sql`, `*.yml`, `*.yaml`, `*.json` outside `docs/`): the only occurrence is its `semantic_exclusions` entry in `repo-map.json`, which was recorded at design and binds nothing. Its own upstreams, `fct_trip` and `dim_zone`, are read only and keep their columns, types and rows.

**Baseline build_sha:** not applicable — the DuckDB `## Defer` section says no production manifest is published, so `/data/cache` is never read and no `state:modified` comparison runs.

## Tasks

### Task 1: The model, its contract and its unit tests

**Requirements:** `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-06`, `R-07`, `R-08`, `R-09` · **Design:** `docs/design/models/agg/agg_borough_flow_matrix.md` · **Skill:** `generating-dbt-model`, with the contract taken through `data-contract` · **Depends on:** none

Files:
- Create `contracts/agg/agg_borough_flow_matrix.odcs.yaml` (`status: proposed` first, `active` after the build)
- Create `transformation/models/marts/agg/agg_borough_flow_matrix.sql`
- Modify `transformation/models/marts/agg/_agg.yml` (append one model entry; change no existing entry)
- Create `transformation/models/marts/agg/_unit_tests.yml`
- Modify `test-map.json` (`modules.agg`: the `unit` selector, file list and command)

The model's columns, in this order, are fixed by the design record; do not add or drop one:

| Column | Type | Source decision |
| --- | --- | --- |
| `month_start_date` | `DATE` | D-12 |
| `origin_borough` | `VARCHAR` | D-04 |
| `destination_borough` | `VARCHAR` | D-04 |
| `flow_class` | `VARCHAR` | D-08 |
| `trip_count` | `BIGINT` | D-07 |
| `revenue` | `DOUBLE` | D-07 |
| `origin_cross_borough_trips` | `BIGINT` | D-09 |
| `origin_trips_to_known_destination` | `BIGINT` | D-09 |
| `cross_borough_share` | `DOUBLE` | D-09, D-10 |

`flow_class` takes exactly three values: `cross_borough` (both sides city boroughs and they differ), `in_borough` (the same city borough on both sides), `unresolved` (either side is the unresolved group).

- [x] Write the contract at `status: proposed` first, through `data-contract`: one property per column above with its `logicalType`, `physicalType` and a description that states the population and the ADR(s) behind it, plus a `dataGranularityDescription` naming the grain. Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0.
- [x] Author `agg_borough_flow_matrix.sql`: the month spine from `dim_date` inside `in_report_window(calendar_date)`, the member spine from `dim_zone` (city boroughs by `is_nyc`, plus the one `unresolved` member, `distinct`), `cross join` the two, `left join` the trips aggregated by month × origin member × destination member. Resolve each trip's two members with a `case` on `is_unresolved_zone`/`is_nyc`, never on a borough label. Compute the per-(month, origin) share in a `CTE` over the aggregated trips and join it back, so `cross_borough_share` = `safe_divide(origin_cross_borough_trips, origin_trips_to_known_destination)`. No `having`, no threshold.
- [x] Author the `_agg.yml` entry: `contract: {enforced: true}`, every column with its `data_type`, a real description on every column, `not_null` on `month_start_date`, `origin_borough`, `destination_borough`, `flow_class`, `trip_count`, `revenue`, `origin_cross_borough_trips`, `origin_trips_to_known_destination`, and `accepted_values` on `flow_class` (`cross_borough`, `in_borough`, `unresolved`). Follow the `dbt-testing` skill: the grain is composite, so its `unique`/`not_null` proof is the singular test in Task 2, not a column test; the borough columns are labels rather than dimension keys, so they carry no `relationships` test.
- [x] Author `_unit_tests.yml` with one unit test per branch, each failing on a plausible broken implementation:
  - `borough_flow_classifies_the_three_flow_classes` — one fixture row per arm of the `flow_class` `case`.
  - `borough_flow_keeps_a_pair_with_no_trips_at_zero` — a month × member pair absent from the fixtures returns `trip_count` 0 and `revenue` 0, not a missing row.
  - `borough_flow_excludes_ewr_on_either_side` — an origin-EWR and a destination-EWR fixture row both disappear.
  - `borough_flow_groups_both_unresolved_zones_into_one_member` — two zones flagged `is_unresolved_zone` with different `borough_name` values collapse to one `unresolved` member on their side.
  - `borough_flow_share_is_null_for_the_unresolved_origin` — the `unresolved` origin's `cross_borough_share` is null while its `trip_count` is not.
  - `borough_flow_share_ignores_unresolved_destinations` — an origin's share numerator and denominator exclude a row whose destination is unresolved, while that row's `trip_count` still counts.
- [x] Run `cd transformation && dbt deps`; expect exit 0.
- [x] Run `cd transformation && dbt build --select agg_borough_flow_matrix --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'`; expect exit 0 and 108 rows.
- [x] Run `python "/data/default-plugins/vibedata-data-engineering/0.148.28/skills/generating-dbt-model/../../scripts/assert_dbt_destination.py"` as its own command; expect exit 0, not 1 or 2.
- [x] Set the contract to `status: active`, run `python3 .agents/skills/data-contract/scripts/odcs.py generate`, then `python3 .agents/skills/data-contract/scripts/odcs.py check` and `python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main`; expect exit 0 from both. Rebuild the model so the enforced contract is covered by the gate.
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py check --relations` and `python3 .agents/skills/data-contract/scripts/odcs.py profile --relation agg.agg_borough_flow_matrix`; expect exit 0, or record the exact `engine/unavailable` / `catalog/missing` code as unrun. Load `validating-data-contract` and record a passing report.
- [x] Run `cd transformation && dbt test --select agg_borough_flow_matrix --exclude test_type:unit --target dev`; expect exit 0.
- [x] Run `cd transformation && dbt test --select agg_borough_flow_matrix,test_type:unit --target dev`; expect exit 0 with all six unit tests passing.
- [x] Refresh the docs site per `generating-dbt-model` → `artifact-kinds.md` § Docs site, or record `DOCS_PUBLISH_SKIPPED` / `DOCS_GENERATE_FAILED`.
- [x] Register the unit tests in `test-map.json` `modules.agg`, mirroring `modules.intermediate` exactly: add `"unit": ["transformation/models/marts/agg/_unit_tests.yml"]`, add `"unit": "path:models/marts/agg"` under `selectors`, and add `"unit": "cd transformation && dbt test --select path:models/marts/agg,test_type:unit"` under `commands`. Leave `data` alone; Task 2 owns it. Then run `python3 -m pytest tests/test_maps.py -q`; expect exit 0, including `test_test_map_dbt_selectors_resolve_to_at_least_one_test[agg-unit]` now that the model carries six unit tests.
- [x] Record every command verbatim with its exit code in `docs/plans/2026-11-24-ss-borough-flow-b2fa6d9e.md` → `## Execution evidence`.
- [x] Commit and push the five files plus the evidence.

### Task 2: The acceptance tests and their registration

**Requirements:** `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-06`, `R-07`, `R-08` · **Design:** `docs/design/models/agg/agg_borough_flow_matrix.md` · **Skill:** `generating-dbt-model` (tests step) with the `dbt-testing` convention · **Depends on:** Task 1

Files:
- Create `transformation/tests/assert_borough_flow_one_row_per_grain.sql`
- Create `transformation/tests/assert_borough_flow_population_closes.sql`
- Create `transformation/tests/assert_borough_flow_share_is_its_ratio.sql`
- Create `transformation/tests/assert_borough_flow_has_no_floor.sql`
- Modify `test-map.json` (`modules.agg.data`)

Each test returns the rows that violate its assertion, so an empty result is a pass. Expected figures come from the Verification's `## Discovery`, never from the model's own SQL.

- [ ] `assert_borough_flow_one_row_per_grain.sql`: group by `month_start_date, origin_borough, destination_borough` with `having count(*) > 1`. Expect no rows (R-01 grain).
- [ ] `assert_borough_flow_population_closes.sql`: recompute from `fct_trip` independently — billable trips in the window whose pickup and drop-off zones are both `is_nyc` or unresolved — and compare against the table's `sum(trip_count)` and `round(sum(revenue), 2)`. Expect 95,723 trips and 2,599,668.55 revenue on both sides, and no row with a null `revenue`; also assert 108 total rows and 15 rows with `trip_count` 0 (R-02, R-03, R-07).
- [ ] `assert_borough_flow_share_is_its_ratio.sql`: recompute `cross_borough_share` from the two counts published beside it with a `1e-6` relative tolerance, and assert that the share takes exactly one value per (month, origin) across that origin's rows. Expect no rows (R-04, R-05).
- [ ] `assert_borough_flow_has_no_floor.sql`: assert no populated row falls below a published threshold — i.e. the thinnest city-to-city rows survive, including Bronx → Brooklyn in January at 11 trips — and that every `flow_class` value is one of the three named ones (R-08).
- [ ] Run `cd transformation && dbt test --select assert_borough_flow_one_row_per_grain assert_borough_flow_population_closes assert_borough_flow_share_is_its_ratio assert_borough_flow_has_no_floor --target dev`; expect exit 0 with 4 passing tests.
- [ ] Add the four files to `test-map.json` `modules.agg.data`, then run `python3 -m pytest tests/test_maps.py -q`; expect exit 0.
- [ ] Record every command verbatim with its exit code in `## Execution evidence`.
- [ ] Commit and push the five files plus the evidence.

## Execution evidence
- Task 1 review (`validating-data-contract`) — verdict **passed with two findings carried, one unjudged item**. Items judged from the built relation and the files: (1) key is the grain — no contract in this repo declares a `primaryKey`, grain is stated in `dataGranularityDescription`, and mine states the three columns the SQL groups by; a direct query shows 0 duplicate (month, origin, destination) grains. (2) descriptions actionable and true — each states a rule with its ADR and the reader's consequence. (3) quality rules encode the business answer — the `nullValues` and `invalidValues` rules render as `not_null` and `accepted_values` in `_agg.yml` (confirmed present) and are non-vacuous: they are the checks that would fail if a borough label leaked into `flow_class` or a member went missing. (4) contract means what its Ossie document means — `not applicable`, no document names the relation (`D-14`). (5) one key one type — **finding carried**: `month_start_date` is `date`/`DATE` in `dim_date` and in this contract, but `timestamp`/`TIMESTAMP` in `agg_driver_monthly`, `agg_garage_monthly` and `agg_vehicle_monthly`. That divergence is real in the data too (`date_trunc('month', shift_date)` returns `TIMESTAMP`), and it predates this intent. `D-12` chose `DATE` deliberately to match `dim_date`, so this contract is not the defect; the three siblings are. Recorded here for triage; the review queue is outside this Plan's scope rows, so no file was written for it. **Unjudged**: `profile` refused (`catalog/missing`, then `catalog/unreadable`), so "the key does not repeat, `required` holds no null, values stay inside `invalidValues`" rests on the direct `lakehouse_query` above, not on the tool.
- Task 1 deviation, recorded rather than silently applied: the Task 1 checkbox asked for `not_null` on `origin_cross_borough_trips` and `origin_trips_to_known_destination`. Those columns are null on the unresolved origin's rows by `D-11`, so `not_null` would contradict the approved design and fail the build. They carry no null test; `cross_borough_share` never does. The three columns the design does constrain are all still asserted: the counts are null exactly where the share is, which the unit test `borough_flow_share_is_null_for_the_unresolved_origin` pins.

- Task 1: `cd transformation && dbt deps` — exit 0
- Task 1: `cd transformation && dbt build --select agg_borough_flow_matrix --target dev --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` — exit 0 — `PASS=14 WARN=0 ERROR=0 SKIP=0 NO-OP=0 TOTAL=14` (1 table model, 7 data tests, 6 unit tests) — `transformation/models/marts/agg/agg_borough_flow_matrix.sql` — sha256:7e1f414e9f433aeea602077c35d973ebfa5c35e60fe88d5e3d2d837d6b5305f0
- Task 1: `python3 /data/default-plugins/vibedata-data-engineering/0.148.28/scripts/assert_dbt_destination.py` — exit 0 — `DESTINATION_OK: 1 built relation(s) landed in the sandbox ephm_nyc-taxi-analytics_ss-borough-flow-b2fa6d9e`
- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py generate` — exit 0 — no diagnostics; wrote the enforcement keys into `_agg.yml`
- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py check` — exit 0 — no errors; the only warnings are `contract/active-unbuilt` for the 30 other contracts, which this sandbox has not built (pre-existing, not introduced here)
- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py diff origin/main` — exit 0 — `[]`
- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py check --relations --catalog transformation/target/catalog.json` — exit 1 — the only errors are `relations/mismatch` for the six `*_raw`/`bronze` audit tables the catalog does not hold (sources, pre-existing); nothing names `agg_borough_flow_matrix`
- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py profile --relation agg.agg_borough_flow_matrix` — **unrun**: exit reports `catalog/missing` (no Intent context names a warehouse) and `catalog/unreadable` for dbt's `catalog.json` ("profile queries rows, so it reads a database, not dbt's catalog.json"). The same claims were checked directly against the built relation instead, below.
- Task 1: `lakehouse_query` on the built sandbox relation (`target: ephemeral`), contract rules recomputed: 108 rows, 0 null `month_start_date`/`origin_borough`/`destination_borough`/`flow_class`/`trip_count`/`revenue`, 0 `flow_class` values outside the three accepted, 0 duplicate (month, origin, destination) grains — every rule the contract asserts holds
- Task 1: `lakehouse_query` totals — 108 rows, 15 zero-trip rows, 3 months, 6 origin members, 6 destination members, `sum(trip_count)`=95,723, `round(sum(revenue),2)`=2,599,668.55, 33 unresolved rows, 18 null-share rows — all equal to `docs/verify/2026-11-24-ss-borough-flow-b2fa6d9e.md` `## Discovery`
- Task 1: `cd transformation && dbt test --select agg_borough_flow_matrix --exclude test_type:unit --target dev` — exit 0 — `PASS=7 WARN=0 ERROR=0`
- Task 1: `cd transformation && dbt test --select agg_borough_flow_matrix,test_type:unit --target dev` — exit 0 — `PASS=6 WARN=0 ERROR=0` — sha256:2373ee715724aaf76f6551e4358c3ff21b282ee79ffe92c7085c4a9f00f86585
- Task 1: `sqlfluff lint transformation/models/marts/agg/agg_borough_flow_matrix.sql` — exit 0 — clean
- Task 1: `dbt docs generate --static --target dev` then `mv` onto `/data/ephm_dbt_docs/static_index.html` — exit 0 — `DOCS_PUBLISHED` (4,507,140 bytes)
- Task 1: `python3 -m pytest tests/test_maps.py -q` — exit 0 — 31 passed, including `test_test_map_dbt_selectors_resolve_to_at_least_one_test[agg-unit]`
- Task 1: `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/` — exit 0
- Task 1: `python3 .agents/skills/semantic-model/scripts/ossie.py coverage ... --exclude agg.agg_borough_flow_matrix` — exit 0. Without that `--exclude` the same command exits 1 with `coverage/unmapped` naming `agg_borough_flow_matrix`, which is the exclusion in `repo-map.json` doing its job (`D-14`); no Ossie document was changed, by design.
- Task 1 correction: `docs/verify/2026-11-24-ss-borough-flow-b2fa6d9e.md` `## Discovery` carried a false claim that the `unresolved` origin's share denominator was empty. It is not: that origin sent 27, 33 and 38 trips a month to a known city borough (98 over the quarter). The earlier check was self-confirming because it filtered on `ob_nyc`, which excludes the unresolved origin by construction. The Discovery line is corrected in place with the true measurement and its query. The design rule (`D-11`: the unresolved group carries no share, ADR 0018) is unchanged and the model implements it explicitly rather than relying on an empty denominator, so the unit test guarding it has real teeth.
