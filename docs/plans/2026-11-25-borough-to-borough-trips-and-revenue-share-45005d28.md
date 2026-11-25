# Plan: Borough-to-borough trips and revenue share

**Goal:** A monthly origin-borough × destination-borough table of trips and revenue, with each origin borough's crossing share published beside it.

**Requirement:** `docs/requirement/2026-11-25-borough-to-borough-trips-and-revenue-share-45005d28.md`

**Constraints:**
- Billable trips only, inside the reporting window through the `in_report_window('pickup_datetime')` macro (ADR 0003).
- A pair is published only at 25 billable trips in its calendar month; below that it is not published (ADR 0018).
- The crossing share's numerator and denominator both come from the origin borough-month's full billable population, floored or not; the three share columns repeat on every row of that borough-month (ADR 0019).
- An origin borough-month with no qualifying pair is published with a null `dest_borough` and a zero `trip_count` and `total_revenue` (design `D-05`).
- Unresolved zones stay in the rollup as their own `N/A` and `Unknown` borough groups; no zone or trip is filtered or remapped (ADR 0012).
- Every rate goes through `safe_divide`, so a zero denominator gives null, never zero (ADR 0016).
- Model name `agg_borough_flow_monthly` in `transformation/models/marts/agg/`, logical schema `agg`, materialised as a table, explicit columns and no `select *` (`dbt-models` B8, B15).
- Properties in `_agg.yml` with `contract: {enforced: true}`, matching the sibling entries; unit tests in `transformation/models/marts/agg/_unit_tests.yml`; singular tests named `assert_<what_must_hold>.sql` in `transformation/tests/`.
- The relation is excluded from the semantic model through `repo-map.json` `semantic_exclusions` (design `D-09`), and owes an ODCS contract at `contracts/agg/agg_borough_flow_monthly.odcs.yaml` (design `D-10`).
- No edit to any published model, to the reporting window, or to `agg_od_flow_matrix`.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `agg_borough_flow_monthly` | model | create | `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-06`, `R-07`, `R-08` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `dbt build --select agg_borough_flow_monthly --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` |
| `agg_borough_flow_monthly` tests | model | create | `R-01`, `R-03`, `R-04`, `R-05`, `R-06`, `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `dbt test --select agg_borough_flow_monthly --exclude test_type:unit` and `dbt test --select agg_borough_flow_monthly,test_type:unit` |
| `contracts/agg/agg_borough_flow_monthly.odcs.yaml` | contract | create | `R-01`, `R-02`, `R-03`, `R-04`, `R-05` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `repo-map.json` `semantic_exclusions` | project-config | modify | `R-01`, `R-04` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 -m pytest tests/test_maps.py -q` |
| `test-map.json` `agg.data` | project-config | modify | `R-01`, `R-03`, `R-04`, `R-05`, `R-06`, `R-07` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 -m pytest tests/test_maps.py -q` |

**Change impact:** none downstream. `agg_borough_flow_monthly` is a new leaf relation: no existing model, test, contract or Ossie document reads it, and it reads only `fct_trip` and `dim_zone` without changing either. `agg_od_flow_matrix` and ADR 0017's zone-pair floor are untouched. `repo-map.json` and `test-map.json` are read by `tests/test_maps.py`, which runs as a gate here.

## Tasks

### Task 1: agg_borough_flow_monthly, its contract, its tests and its map entries

**Requirements:** `R-01`, `R-02`, `R-03`, `R-04`, `R-05`, `R-06`, `R-07`, `R-08` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `generating-dbt-model`, with `data-contract` for the contract and `semantic-model` for the exclusion · **Depends on:** none

- [ ] **Contract first**, through `data-contract` step 4 and 6: author `contracts/agg/agg_borough_flow_monthly.odcs.yaml` with `status: proposed`, version `1.0.0`, server `type: duckdb` (from `repo-map.json` `data_platform`, `duckdb_local`), schema `agg`, and these properties with their `logicalType` and `physicalType`:

  | Property | logicalType | physicalType | Promise |
  | --- | --- | --- | --- |
  | `trip_month` | date | DATE | First day of the calendar month the trips were picked up in. Primary key part 1, `required`. |
  | `origin_borough` | string | VARCHAR | Borough of the pickup zone. Primary key part 2, `required`. |
  | `dest_borough` | string | VARCHAR | Borough of the dropoff zone; null only on a borough-month row that has no published pair. Primary key part 3. |
  | `trip_count` | integer | BIGINT | Billable trips on the pair in the month; 0 on a no-pair row. `required`, minimum 0. |
  | `total_revenue` | number | DOUBLE | Sum of `total_amount` over the pair's billable trips, no-charge and dispute payments included; 0 on a no-pair row. `required`. |
  | `origin_departing_trip_count` | integer | BIGINT | Every billable trip departing the origin borough in the month, published pairs or not. `required`. |
  | `origin_crossing_trip_count` | integer | BIGINT | Every departing billable trip of that borough-month whose destination borough differs from the origin borough. `required`. |
  | `origin_crossing_trip_share` | number | DOUBLE | `origin_crossing_trip_count / origin_departing_trip_count`, null on a zero denominator. |

  State the grain in `dataGranularityDescription`: one row per month, origin borough and destination borough that clears the 25-trip floor, plus one row per origin borough-month that clears none, with a null `dest_borough`. Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0 with the contract reported as proposed.
- [ ] Author `repo-map.json` `semantic_exclusions`: add `{"relation": "agg.agg_borough_flow_monthly", "reason": "<the design's D-09 reason: a HAVING floor keeps only borough pairs at or above 25 trips, and a borough-month with no such pair adds a second grain to the same relation, so no logical source answers from it honestly>"}`. Add nothing to `logical-model/` or `ontology/`.
- [ ] Author `transformation/models/marts/agg/agg_borough_flow_monthly.sql` in the repo's SQL style, with explicit columns cast to the contract's types:
  - A `pairs` CTE grouping `fct_trip` joined to `dim_zone` twice (`pickup_zone_key` as origin, `dropoff_zone_key` as destination) by `date_trunc('month', pickup_datetime)`, `origin.borough_name`, `destination.borough_name`, filtered on `in_report_window('f.pickup_datetime')` and `f.is_billable`, selecting `count(*)` and `sum(f.total_amount)`. `trip_month` is `cast(date_trunc('month', f.pickup_datetime) as date)`, because `date_trunc` returns `TIMESTAMP` and DuckDB does not coerce to a contract's declared type. Both joined borough names are non-null on every zone, `N/A` and `Unknown` included, so the crossing test is a plain `<>` and no row is dropped or misfiled by a null comparison.
  - An `origins` CTE over the same join at `(month, origin borough)` grain carrying `sum` of trips as the denominator and `sum(trips) filter (where origin_borough <> dest_borough)` as the numerator, built from the unfloored `pairs` grain so the share covers every billable trip.
  - The published pairs: `pairs` where `trip_count >= 25`, left-joined to `origins` on month and origin borough, with `safe_divide` for the share.
  - The no-pair rows: `origins` where no floored pair exists for that month and origin borough, with `dest_borough` null, `trip_count` and `total_revenue` 0.
  - A `union all` of the two, with the three share columns on every row.
  - A leading comment stating both populations and citing ADR 0018 and ADR 0019, as `agg_od_flow_matrix.sql` cites its ADR.
- [ ] Author `transformation/models/marts/agg/_agg.yml` entry: `name: agg_borough_flow_monthly`, a description stating the grain, the floor (ADR 0018), that the share covers the full borough-month population and so does not reconcile with the rows beside it (ADR 0019), and that a `dest_borough`-null row is a borough-month with no published pair; then one column entry per property with its `data_type` and a description. Generic tests: `not_null` on `trip_month`, `origin_borough`, `trip_count`, `total_revenue`, `origin_departing_trip_count`, `origin_crossing_trip_count`.
- [ ] Author `transformation/models/marts/agg/_unit_tests.yml`, two unit tests with `overrides: {vars: {report_start: '2024-01-01', report_end: '2024-04-01'}}` and `given` rows on `ref('fct_trip')` and `ref('dim_zone')`:
  - `borough_flow_publishes_pairs_at_the_floor_and_drops_the_rest`: one borough pair at 25 trips (published) and a second destination at 24 (not published), in the same month and origin borough; expect one pair row for the 25-trip destination, no row for the 24-trip one, and the share's numerator counting both.
  - `borough_flow_publishes_a_row_for_a_borough_with_no_qualifying_pair`: an origin borough whose only pair carries 5 crossing trips; expect a single row with a null `dest_borough`, `trip_count` 0, `total_revenue` 0 and a share of 1.0.
- [ ] Author the singular tests in `transformation/tests/`, each returning the rows that violate it:
  - `assert_borough_flow_one_row_per_grain.sql` — `group by trip_month, origin_borough, dest_borough having count(*) > 1` (as `assert_daypart_cube_one_row_per_grain.sql` does, so the null `dest_borough` groups correctly).
  - `assert_borough_flow_floor.sql` — published pairs (`dest_borough is not null`) with `trip_count < 25`, and no-pair rows whose `trip_count` or `total_revenue` is not 0.
  - `assert_borough_flow_share_constant_per_borough_month.sql` — any `(trip_month, origin_borough)` whose rows disagree on `origin_crossing_trip_count`, `origin_departing_trip_count` or `origin_crossing_trip_share`.
  - `assert_borough_flow_boroughs_exist_on_dim_zone.sql` — any non-null `origin_borough` or `dest_borough` absent from `dim_zone.borough_name`.
  - `assert_borough_flow_trips_reconcile.sql` — recompute the month × origin × destination pairs, their sub-25 remainder and the billable fact total from `fct_trip` and `dim_zone` independently, and return a row when the model's `sum(trip_count)` plus that remainder differs from the fact total, or when the same holds for revenue at the cent (`round(x, 2)`).
- [ ] Author `test-map.json`: add the five singular test paths to `modules.agg.data`.
- [ ] Run `cd transformation && dbt deps` once for the session, then `cd transformation && dbt build --select agg_borough_flow_monthly --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}' --target dev`; expect exit 0 with the relation created in `agg`, then run `python "/data/default-plugins/vibedata-data-engineering/0.148.28/scripts/assert_dbt_destination.py"` and expect exit 0.
- [ ] Set the contract to `status: active`, run `python3 .agents/skills/data-contract/scripts/odcs.py generate`, and re-run the build so the enforced contract is exercised; expect exit 0 and `generate` writing the `data_type`, tests and descriptions into `_agg.yml`.
- [ ] Run the acceptance conditions, each as its own query against the sandbox, and record the observed values: 56 pair rows with 18/19/19 by month and a minimum `trip_count` of 26 (`R-01`); pair revenue 2,609,219.76 with the 19,966.06 remainder against the fact (`R-02`); the twelve borough-month shares reading Bronx 59.26/65.06/50.99, Brooklyn 37.54/40.68/43.36, Manhattan 6.01/5.78/5.97, Queens 71.54/73.10/73.96 with numerators summing to 12,214 and denominators to 95,958 (`R-03`); exactly 9 no-pair rows and EWR 0.00, N/A 30.77, Staten Island 45.45 in January (`R-04`); 65 rows in total (`R-05`); no borough outside `dim_zone`'s 8 and 14 published rows touching `N/A` or `Unknown` (`R-06`); 95,705 + 253 = 95,958 trips (`R-07`); the months 2024-01, 2024-02, 2024-03 (`R-08`).
- [ ] Run `cd transformation && dbt test --select agg_borough_flow_monthly --exclude test_type:unit --target dev` and `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit --target dev`; expect exit 0 from both.
- [ ] Run the semantic chain: `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/`, `coverage logical-model/ transformation/models/marts/core transformation/models/marts/agg transformation/models/marts/finance transformation/models/marts/ops --exclude agg.agg_od_flow_matrix --exclude finance.mart_revenue_component_bridge --exclude core.dim_fare_regime --exclude agg.agg_borough_flow_monthly`, `suppliers logical-model/`, `notes logical-model/ transformation/tests docs/adr`, `generate-tests logical-model/ transformation/tests --check`; expect `0 coverage error(s)` and exit 0 from each, the new exclusion named in `coverage --exclude`. Then load `validating-semantic-model` and record its report.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`, `check --relations` and `profile --relation agg.agg_borough_flow_monthly`, then load `validating-data-contract` and record its report; a `profile/unchecked` or `engine/unavailable` is recorded unproven, never passing.
- [ ] Run `python3 -m pytest tests/test_maps.py -q`, `python3 -m pytest tests -q`, `ruff check .`, `sqlfluff lint transformation/models`; expect exit 0 from each.
- [ ] Commit and push the model SQL, `_agg.yml`, `_unit_tests.yml`, the five singular tests, the contract, `repo-map.json` and `test-map.json` together with this task's evidence.

## Execution evidence

<!-- Append-only, one line when a task's checkbox flips: `- Task 1: <command> — exit 0 — <artifact path> — sha256:<hash where practical>`. -->
