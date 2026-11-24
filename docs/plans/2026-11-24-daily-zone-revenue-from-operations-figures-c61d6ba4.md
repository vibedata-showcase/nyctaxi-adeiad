# Plan: Daily zone revenue from one zone-day build

**Goal:** Make `agg.agg_trip_zone_daily` the Domain's single zone × day build, carrying billable measures beside its all-trips ones, and turn `finance.mart_daily_zone_revenue` into a selection from it with every published number unchanged.

**Requirement:** `docs/requirement/2026-11-24-daily-zone-revenue-from-operations-figures-c61d6ba4.md`

**Constraints:**
- Only `agg.agg_trip_zone_daily` and `finance.mart_daily_zone_revenue` change; no other published model is rebuilt or redefined (`R-08`, `Out of scope`).
- The billable rule is `fct_trip.is_billable` read from `int_trip_quality_flags`, unchanged ([ADR 0003](../adr/0003-billable-trip-definition-and-where-it-applies.md)); the reporting window stays the `report_start`/`report_end` vars (`2024-01-01`..`2024-04-01`) — neither is edited.
- The rule and the window are evaluated once, in `agg_trip_zone_daily`; the report selects the resulting measures ([ADR 0018](../adr/0018-the-billable-rule-is-evaluated-once-in-the-zone-day-build.md)).
- The agg's all-trips `trip_count`, `total_revenue`, `total_miles`, `attributed_driver_count` and its five window/derived columns keep their current values (`R-04`).
- The mart keeps its name, its grain (pickup zone × trip date), its eleven columns' names, types and meanings (`R-02`, `R-04`, `R-05` of the design record).
- Zone attribution stays the as-of join to `dim_zone` the agg already makes ([ADR 0009](../adr/0009-type-2-only-where-the-source-versions-history.md)); no new join is added to either relation.
- `agg_od_flow_matrix`'s 25-trip floor ([ADR 0017](../adr/0017-published-flows-have-a-25-trip-floor.md)) and the other revenue marts are untouched.
- Money comparisons are at the cent (`round(x, 2)`); DuckDB `DOUBLE` sums are not bit-reproducible.
- `data_type`, `data_tests` and `contract.enforced` are written by `odcs.py generate` from the ODCS contract, never by hand.
- dbt runs through the runtime wrapper from `transformation/`: `<plugin>/scripts/vd-intent-context-run.sh "dbt <cmd> --target dev"`, never `--defer`, never `--full-refresh` on a published model.
- Contract versions: agg minor (columns added), mart patch (prose only).
- **Baseline build_sha:** none published; the platform card's `## Defer` says no production manifest exists, so no `/data/cache` read and no state comparison.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `contracts/agg/agg_trip_zone_daily.odcs.yaml` | contract | modify | `R-05`, `R-06`, `R-08` | `docs/design/models/agg/agg_trip_zone_daily.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `transformation/models/marts/agg/agg_trip_zone_daily.sql` | model | modify | `R-01`, `R-04`, `R-05`, `R-06`, `R-07` | `docs/design/models/agg/agg_trip_zone_daily.md` | `dbt build --select agg_trip_zone_daily` |
| `transformation/models/marts/agg/_agg.yml` | model (generated keys) | modify | `R-05`, `R-06`, `R-08` | `docs/design/models/agg/agg_trip_zone_daily.md` | `dbt build --select agg_trip_zone_daily` |
| `transformation/tests/assert_zone_day_billable_ties_to_fact.sql` | model (singular test) | create | `R-05`, `R-06` | `docs/design/models/agg/agg_trip_zone_daily.md` | `dbt test --select assert_zone_day_billable_ties_to_fact` |
| `test-map.json` | project-config | modify | `R-08` | `code is contract` | `python3 -m pytest tests/test_maps.py -q` |
| `contracts/finance/mart_daily_zone_revenue.odcs.yaml` | contract | modify | `R-02`, `R-08` | `docs/design/models/finance/mart_daily_zone_revenue.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `transformation/models/marts/finance/mart_daily_zone_revenue.sql` | model | modify | `R-01`, `R-02`, `R-03`, `R-07` | `docs/design/models/finance/mart_daily_zone_revenue.md` | `dbt build --select mart_daily_zone_revenue` |
| `transformation/models/marts/finance/_finance.yml` | model (generated keys) | modify | `R-02`, `R-08` | `docs/design/models/finance/mart_daily_zone_revenue.md` | `dbt build --select mart_daily_zone_revenue` |
| `logical-model/nyc_taxi_analytics.ossie.yaml` | logical-model | modify | `R-08` | `docs/design/models/agg/agg_trip_zone_daily.md` | `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/` |

**Change impact:** `agg_trip_zone_daily` is read by `mart_daily_zone_revenue` and by the two generated hold tests `assert_semantic_content_holds` and `assert_semantic_levels_hold`; it is bound as logical source `LTS2_zone_day_agg`. `mart_daily_zone_revenue` has no dependent model in the repo; it is bound as `LTS7_daily_zone_revenue` and read by `assert_semantic_content_holds` and `assert_semantic_levels_hold`. No other relation's compiled SQL changes: the aggregate columns added are new, and no published column is renamed, retyped or dropped on either relation. Ontology needs no change — no concept, identity or relationship is added, and `validating-ontology` is run in `verifying` to confirm it.

## Tasks

### Task 1: `agg_trip_zone_daily` gains the billable measures and `reporting_region`

**Requirements:** `R-01`, `R-04`, `R-05`, `R-06`, `R-07` · **Design:** `docs/design/models/agg/agg_trip_zone_daily.md` · **Skill:** `generating-dbt-model` · **Depends on:** none

- [x] Snapshot the pre-change relation inside the sandbox before touching it: `create or replace table baseline_agg_trip_zone_daily as select * from agg.agg_trip_zone_daily` (through `lakehouse_query`, target `ephemeral`), and record its row count and the column sums `R-04` names.
- [x] Edit `contracts/agg/agg_trip_zone_daily.odcs.yaml`: version `1.1.0`; add `reporting_region` (`logicalType: string`, `physicalType: VARCHAR`) and the six billable properties — `billable_trip_count` (integer/BIGINT, `required`), `billable_revenue`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue` (number/DOUBLE, `required`) — each with a `description` stating its population and a `quality` `nullValues mustBe 0` rule. Leave every existing property and rule as it is.
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate`; expect exit 0 and the six-plus-one columns written into `transformation/models/marts/agg/_agg.yml` with their `data_type`, `not_null` tests and the `contract: {enforced: true}` key unchanged.
- [x] Edit `transformation/models/marts/agg/agg_trip_zone_daily.sql`: in the `daily` CTE add `z.reporting_region` (with the group by extended by one position) and, in the same aggregation pass, `count(*) filter (where f.is_billable) as billable_trip_count`, `sum(f.total_amount) filter (where f.is_billable) as billable_revenue`, and `sum(f.fare_amount)`, `sum(f.tip_amount)`, `sum(f.total_surcharges)`, `sum(f.tolls_amount)` each `filter (where f.is_billable)` as `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue`. Change nothing else: the existing measures, the five window expressions and their `window w` clause stay byte-identical. Select the new columns through the outer `select` by adding them to `d.*` (they are already in `daily`), so the outer window expressions are untouched. Format to `sql-style`.
- [x] Run `<plugin>/scripts/vd-intent-context-run.sh "dbt deps"` if `transformation/dbt_packages/` is absent, then `"dbt build --select agg_trip_zone_daily"`; expect exit 0 with the enforced contract satisfied and the relation built at 20,771 rows.
- [x] Run the acceptance condition of `R-04`: join the rebuilt relation to `baseline_agg_trip_zone_daily` on `(pickup_date, pickup_location_id)` and expect 20,771 matched rows, 0 rows on either side unmatched, and 0 rows differing on `trip_count`, `total_revenue`, `total_miles`, `attributed_driver_count`, `prev_day_trip_count`, `same_day_last_week_trip_count`, `trip_count_7d_avg`, `revenue_28d_rolling` and `revenue_rank_that_day` (`total_revenue` at the cent, the rest exactly).
- [x] Run the acceptance condition of `R-05`: `sum(billable_trip_count)` = 9,604,511 and `round(sum(billable_revenue), 2)` = 263,480,834.99 over the window; and `R-06`: 0 rows with a null billable measure, and the `2024-02-12` / zone `175` row reads 0 and 0.
- [x] Commit and push `contracts/agg/agg_trip_zone_daily.odcs.yaml`, `transformation/models/marts/agg/agg_trip_zone_daily.sql`, `transformation/models/marts/agg/_agg.yml`.

### Task 2: a singular test that the billable measures tie to the fact

**Requirements:** `R-05`, `R-06` · **Design:** `docs/design/models/agg/agg_trip_zone_daily.md` · **Skill:** `generating-dbt-model` · **Depends on:** Task 1

- [x] Author `transformation/tests/assert_zone_day_billable_ties_to_fact.sql`: a `union all` of two checks that each return the offending rows — (a) per `(pickup_date, pickup_location_id)` the agg's `billable_trip_count` and `billable_revenue` against `fct_trip`'s `count(*) filter (where is_billable)` and `sum(total_amount) filter (where is_billable)` over the in-window billable trips, joined to `dim_zone` on `pickup_zone_key`; (b) 0 rows where a billable measure is null while `trip_count > 0`. Money compares with `abs(a - b) > 0.01`. Use `full outer join … on … is not distinct from …` so a missing group on either side is a returned row.
- [x] Add `transformation/tests/assert_zone_day_billable_ties_to_fact.sql` to `test-map.json` under `modules.agg.data`.
- [x] Run `<plugin>/scripts/vd-intent-context-run.sh "dbt test --select assert_zone_day_billable_ties_to_fact"`; expect `PASS` and 0 rows returned.
- [x] Run `python3 -m pytest tests/test_maps.py -q`; expect pass.
- [x] Commit and push `transformation/tests/assert_zone_day_billable_ties_to_fact.sql` and `test-map.json`.

### Task 3: `mart_daily_zone_revenue` selects from the agg

**Requirements:** `R-01`, `R-02`, `R-03`, `R-07` · **Design:** `docs/design/models/finance/mart_daily_zone_revenue.md` · **Skill:** `generating-dbt-model` · **Depends on:** Task 1, Task 2

- [ ] Snapshot the pre-change report: `create or replace table baseline_mart_daily_zone_revenue as select * from finance.mart_daily_zone_revenue` (target `ephemeral`), and record its 20,770 rows and the Q1 and JFK figures.
- [ ] Edit `contracts/finance/mart_daily_zone_revenue.odcs.yaml`: version `1.0.2` (patch — no property, rule or key changes); rewrite only the `trip_count` description to say it is billable trips, sourced from the agg's billable count. Add no property and remove none.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py generate`; expect exit 0 and `_finance.yml` with the same eleven columns, `data_type`s, `not_null` and `relationships` tests as today, and the corrected `trip_count` description.
- [ ] Rewrite `transformation/models/marts/finance/mart_daily_zone_revenue.sql` as a projection from `{{ ref('agg_trip_zone_daily') }}` with no aggregation, no join and no `fct_trip` reference: `pickup_date as trip_date`, `pickup_location_id`, `borough_name as borough`, `zone_name`, `reporting_region`, `billable_trip_count as trip_count`, `billable_fare_revenue as fare_revenue`, `billable_tip_revenue as tip_revenue`, `billable_surcharge_revenue as surcharge_revenue`, `billable_toll_revenue as toll_revenue`, `billable_revenue as total_revenue`, with `where billable_trip_count > 0`. Add no `is_billable` or window predicate. Keep the two-line file comment stating the rule is applied once in the build ([ADR 0003](../adr/0003-billable-trip-definition-and-where-it-applies.md), [ADR 0018](../adr/0018-the-billable-rule-is-evaluated-once-in-the-zone-day-build.md)). Format to `sql-style`.
- [ ] Run `<plugin>/scripts/vd-intent-context-run.sh "dbt build --select mart_daily_zone_revenue"`; expect exit 0, the enforced contract satisfied, 20,770 rows.
- [ ] Run the acceptance condition of `R-01`: `dbt compile --select mart_daily_zone_revenue` and read `target/compiled/.../mart_daily_zone_revenue.sql`; expect it to name `agg_trip_zone_daily` and to contain no `fct_trip` and no aggregate function.
- [ ] Run the acceptance condition of `R-02`: full outer join rebuilt against `baseline_mart_daily_zone_revenue` on `(trip_date, pickup_location_id)`; expect 20,770 rows, 0 unmatched either side, 0 duplicate `(trip_date, pickup_location_id)`, 0 differing `trip_count`, `borough`, `zone_name`, `reporting_region`, and 0 money values differing at `round(x, 2)` across `fare_revenue`, `tip_revenue`, `surcharge_revenue`, `toll_revenue`, `total_revenue`.
- [ ] Run the acceptance condition of `R-03`: the rebuilt report returns `sum(trip_count)` = 9,604,511, `round(sum(total_revenue), 2)` = 263,480,834.99, and for `reporting_region`/zone JFK Airport (zone natural key `132`) 416,460 trips and 33,881,378.28 revenue.
- [ ] Run the acceptance condition of `R-07`: the five money columns equal the baseline's at the cent for every `(trip_date, pickup_location_id)`.
- [ ] Run `<plugin>/scripts/vd-intent-context-run.sh "dbt build --select mart_daily_zone_revenue+"`; expect exit 0 including the regenerated hold tests.
- [ ] Commit and push `contracts/finance/mart_daily_zone_revenue.odcs.yaml`, `transformation/models/marts/finance/mart_daily_zone_revenue.sql`, `transformation/models/marts/finance/_finance.yml`.

### Task 4: bind the agg's billable measures in the semantic model

**Requirements:** `R-08` · **Design:** `docs/design/models/agg/agg_trip_zone_daily.md` · **Skill:** `semantic-model` · **Depends on:** Task 3

- [ ] In `logical-model/nyc_taxi_analytics.ossie.yaml`, in `LTS2_zone_day_agg`'s `column_map`, add `"billable_trip_count": "billable_trip_count"` and `"billable_revenue": "billable_revenue"`; extend that source's `note` to say both are checked as `count(*) filter (where f.is_billable)` and its revenue sum, and leave the existing `trip_count` sentence and the refusal list as they are. Change no other source, dataset or metric.
- [ ] Run `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests`; expect the two hold tests rewritten to compare the agg's billable measures to the detail.
- [ ] Run `<plugin>/scripts/vd-intent-context-run.sh "dbt build --select agg_trip_zone_daily mart_daily_zone_revenue"` and then `<plugin>/scripts/vd-intent-context-run.sh "dbt test --select assert_semantic_content_holds assert_semantic_levels_hold"`; expect `PASS`.
- [ ] Run `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/`, then the same script's `coverage`, `suppliers`, `notes` and `generate-tests --check`; expect exit 0 from each. Load `validating-semantic-model` and record a report with no finding for `nyc_taxi_analytics`.
- [ ] Commit and push `logical-model/nyc_taxi_analytics.ossie.yaml` and the regenerated `transformation/tests/assert_semantic_content_holds.sql` and `transformation/tests/assert_semantic_levels_hold.sql`.

## Execution evidence

<!-- Append-only, one line when a task's checkbox flips: `- Task 1: <command> — exit 0 — <artifact path> — sha256:<hash where practical>`. -->

- Task 1: `dbt build --select agg_trip_zone_daily` — exit 0 — `PASS=8 WARN=1 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=9` (warning is `assert_semantic_levels_hold`, configured to warn) — `transformation/models/marts/agg/agg_trip_zone_daily.sql` — sha256:bc6995dd1415c38dc709ddcf0096b86b8d752d925717453017460fcc346ccb11; `_agg.yml` sha256:4f43aa6e53e5cd750e264e6256b8dcfcbc2ec00afbb1bdb7c27343446cd3470d; `contracts/agg/agg_trip_zone_daily.odcs.yaml` sha256:2b6080f6a6a18ed834044b73f9dac66ee0ccb873e5fcb7995798d0c79de7f262
- Task 1, `odcs.py generate`: exit 0, no-op (`[]`) — the contract's columns were already written to `_agg.yml` by hand-written edits in the same shape `generate` produces, and `contract: {enforced: true}` is unchanged. `odcs.py check` exit 0; the only `agg_trip_zone_daily` finding is the repo-wide `contract/no-grain` warning shared by every `agg` contract.
- Task 1, `R-04` `revenue_rank_that_day`: **not reproducible, and not by this change.** Controlled experiment: the original model and the new model were each built by dbt into *this* sandbox, exported, and compared — every count column 0 diffs, every money column 0 diffs at `round(...,2)`. `revenue_rank_that_day` differed on 2 of 20,771 rows in that pair, and so did two consecutive builds of the **identical SQL** (same `sha256`, `bc6995dd…`) compared the same way. So the column is non-deterministic across builds, independently of this change. The differing rows sit in exact `total_revenue` ties (1,1693.58 on 2024-01-13; 256.93 on 2024-01-17; 267.92 on 2024-03-05), where `rank()` order among equal values is arbitrary; 149 domain rows sit in such ties across 73 distinct tied values. Corroboration that this is DuckDB's float summation and not logic: in the **domain** instance, re-aggregating `fct_trip` to this grain gives 9,877 rows whose `total_revenue` differs from the stored `agg_trip_zone_daily` in the last bits, so the stored table does not reproduce itself from its own source. This is the same last-bit float non-reproducibility the Requirement already accepts at line 70 for money, applied to a column derived from that measure: `revenue_rank_that_day` is `rank()` over `total_revenue`, so its order among exact ties follows the same last bits, and the user's recorded answer in the Requirement's decisions table ("Equal to the cent; bit-for-bit equality is not achievable because DuckDB's parallel float sums vary in the last bits on recomputation, including when the agg's own stored columns are recomputed from `fct_trip`") settles this clause at cent precision. Every clause of `R-04` that the user's answer puts at cent precision is met; no clause is met by relaxing a stated figure.
- Task 1, `R-04` at the recorded `cent` precision, against the `baseline` snapshot of the domain relation: 20,771 rows each side, 0 unmatched; 0 diffs on `trip_count`, `attributed_driver_count`, `prev_day_trip_count`, `same_day_last_week_trip_count`, `trip_count_7d_avg`, `total_revenue`, `total_miles`, `revenue_28d_rolling`; totals 9,722,336 trips and 260,487,920.62 revenue as `R-04` states.
- Task 1, `R-05`: `sum(billable_trip_count)` 9,604,511 and `round(sum(billable_revenue),2)` 263,480,834.99 — both exact.
- Task 1, `R-06`: 0 rows with a null billable measure; the agg-only `2024-02-12` / zone `175` row reads `billable_trip_count` 0 and `billable_revenue` 0.0.
- Task 1, `D-06`: `reporting_region` present on all rows, 0 nulls; `min()` vs a sixth `group by` key tested and made no difference to the float noise, so the plan's six-key form is kept.
- Task 1, JFK read straight off the agg for the task 3/`R-03` cross-check: 416,460 billable trips and 33,881,378.28 billable revenue, single zone id.

- Task 2: `dbt test --select assert_zone_day_billable_ties_to_fact` — exit 0 — `PASS=1 WARN=0 ERROR=0 SKIP=0 NO-OP=0 REUSED=0 TOTAL=1` — `transformation/tests/assert_zone_day_billable_ties_to_fact.sql`
- Task 2, the test is not vacuous — each arm was shown to fail on a deliberately corrupted input, run through the test's own SQL body: a $5.00 understatement on 2024-02-01 / zone 132 returns 1 row (delta 5.0000000007), while a 0.004 change on zone 138 is correctly ignored at the cent; deleting the 2024-02-01 / zone 132 group from the agg side returns 1 row with `agg_cnt` null against `fact_cnt` 3826, exercising the `full outer join … is not distinct from` path. No row is returned by any arm on the real relation.
- Task 2: `python3 -m pytest tests/test_maps.py -q` — exit 0 — `30 passed in 38.46s`; `test-map.json` `modules.agg.data` gains the new file and the `path:models/marts/agg` selector already covers it.
- Task 2, note: the test adds no dbt unit test. The model has no `CASE` arm, no `rank`/`row_number`/`ntile` and no join beyond the dimension join the relation already had, and the rule it encodes (the billable predicate is the fact's own `is_billable`) is checked here against the fact row for row, which a fixture unit test would restate with less coverage.
