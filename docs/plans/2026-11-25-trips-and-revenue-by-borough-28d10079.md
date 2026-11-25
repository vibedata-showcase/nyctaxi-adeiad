# Plan: Trips and revenue by borough

**Goal:** A monthly borough-to-borough flow table for Q1 2024 carrying billable trips, revenue and each origin borough's cross-borough trips and share, published as an `agg` boundary relation with its contract, its semantic-layer binding and its tests.

**Requirement:** `docs/requirement/2026-11-25-trips-and-revenue-by-borough-28d10079.md`

**Constraints:**
- Billable trips only, inside the reporting window (`is_billable`, `in_report_window`) — ADR 0003.
- No minimum-trip floor at borough grain — ADR 0019.
- A trip crosses when the destination borough name differs from the origin borough name; `Unknown`, `N/A` and `EWR` stay as their own groups — ADR 0018, ADR 0012.
- Both boroughs resolve through the trip's own zone surrogate keys, as of the pickup date — ADR 0009.
- A zone key that matches no row keeps its trip under the sentinel `unresolved` — ADR 0015.
- The month is a `DATE` at its first day; `date_trunc` over a `DATE` returns `TIMESTAMP` on this platform and is cast (design `D-01`).
- The new model lands in schema `agg` (the folder's `+schema`; design `## Schema`).
- `contract: {enforced: true}` in the properties file; no `access:` (no model in this repository sets one).
- Nothing existing changes: `fct_trip`, `dim_zone`, `agg_od_flow_matrix` and every other published model stay as they are.
- No production manifest is published for this Domain, so no `--defer`, no `--state`, and `/data/cache` is never read.
- Every dbt command runs against the sandbox target `dev`, followed by `assert_dbt_destination.py` as its own command.

## Scope and impact

| Artifact | Kind | Action | Requirements | Design record | Gate |
| --- | --- | --- | --- | --- | --- |
| `contracts/agg/agg_borough_flow_monthly.odcs.yaml` | contract | create | `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/data-contract/scripts/odcs.py check` |
| `transformation/models/marts/agg/agg_borough_flow_monthly.sql` | model | create | `R-01`, `R-02`, `R-03`, `R-04`, `R-05` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt build --select +agg_borough_flow_monthly --exclude test_type:unit --target dev` |
| `transformation/models/marts/agg/_agg.yml` | model | modify | `R-01`, `R-03`, `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt build --select +agg_borough_flow_monthly --exclude test_type:unit --target dev` |
| `transformation/models/marts/agg/_unit_tests.yml` | model | create | `R-03`, `R-04` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit --target dev` |
| `transformation/tests/assert_borough_flow_one_row_per_grain.sql` | model | create | `R-01` | `code is contract` | `cd transformation && dbt test --select assert_borough_flow_one_row_per_grain --target dev` |
| `transformation/tests/assert_borough_flow_reconciles_to_fct_trip.sql` | model | create | `R-02`, `R-04` | `code is contract` | `cd transformation && dbt test --select assert_borough_flow_reconciles_to_fct_trip --target dev` |
| `transformation/tests/assert_borough_flow_share_matches_its_counts.sql` | model | create | `R-03` | `code is contract` | `cd transformation && dbt test --select assert_borough_flow_share_matches_its_counts --target dev` |
| `transformation/tests/assert_borough_flow_keeps_every_borough.sql` | model | create | `R-04`, `R-05` | `code is contract` | `cd transformation && dbt test --select assert_borough_flow_keeps_every_borough --target dev` |
| `logical-model/nyc_taxi_analytics.ossie.yaml` | logical-model | modify | `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/` |
| `transformation/tests/assert_semantic_*.sql` | logical-model | modify | `R-06` | `docs/design/models/agg/agg_borough_flow_monthly.md` | `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests --check` |
| `test-map.json` | project-config | modify | `R-01`, `R-03` | `code is contract` | `python3 -m pytest tests/test_maps.py -q` |

**Change impact:** none downstream. `agg_borough_flow_monthly` is new and no dbt model refs it; `fct_trip` and `dim_zone` are read only, and neither their SQL, columns nor contracts change. `agg_od_flow_matrix`, `mart_daily_zone_revenue`, `mart_monthly_service_summary` and every other published model are untouched. The Ossie document gains one logical source on the `trips` dataset and no field, so no existing binding, metric or ontology mapping moves.

**Baseline build_sha:** not applicable — the dbt card publishes no production manifest for this Domain, so the `state:modified` comparison is unavailable and `/data/cache` is not read.

## Tasks

### Task 1: the contract, written before the SQL

**Requirements:** `R-06` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `data-contract` · **Depends on:** none

- [x] Author `contracts/agg/agg_borough_flow_monthly.odcs.yaml` with `status: proposed`, `version: 0.1.0`, and one property per published column with its description, `logicalType` and `physicalType`: `trip_month` (date / `DATE`), `origin_borough` (string / `VARCHAR`), `dest_borough` (string / `VARCHAR`), `trip_count` (integer / `BIGINT`), `total_revenue` (number / `DOUBLE`), `cross_borough_trip_count` (integer / `BIGINT`), `cross_borough_share` (number / `DOUBLE`).
- [x] State the grain as the composite key `[trip_month, origin_borough, dest_borough]` and mark `trip_month`, `origin_borough`, `dest_borough` and `trip_count` `required`; `cross_borough_share` is not required because a zero denominator yields null (`D-09`).
- [x] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0 with the shape checks passing for a `proposed` contract.
- [x] Record the `R-06` acceptance condition reached so far: `check` reports the schema block valid and no blocking finding. Its dynamic half runs in Task 3, once the relation exists.
- [x] Commit and push `contracts/agg/agg_borough_flow_monthly.odcs.yaml`.

### Task 2: the model, its properties, its unit tests and its singular tests

**Requirements:** `R-01`, `R-02`, `R-03`, `R-04`, `R-05` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `generating-dbt-model` · **Depends on:** Task 1

- [ ] Author `transformation/models/marts/agg/agg_borough_flow_monthly.sql`: `fct_trip` filtered by `{{ in_report_window('f.pickup_datetime') }}` and `f.is_billable`; `left join dim_zone` twice, on `f.pickup_zone_key = o.zone_key` and `f.dropoff_zone_key = d.zone_key`; `coalesce(o.borough_name, 'unresolved')` and `coalesce(d.borough_name, 'unresolved')`; group by `cast(date_trunc('month', f.pickup_date) as date)`, origin borough, destination borough; `count(*)` and `sum(f.total_amount)`; a window over `(trip_month, origin_borough)` giving the origin's whole monthly trip count and its cross-borough trip count, the cross test written with `IS DISTINCT FROM` (`D-07`); the share through `{{ safe_divide(...) }}` (`D-09`).
- [ ] Author the `agg_borough_flow_monthly` entry in `transformation/models/marts/agg/_agg.yml`: a description naming the grain, the billable population, ADR 0018's crossing rule and ADR 0019's no-floor rule, `contract: {enforced: true}`, and one column entry per published column with `data_type` and a description; the two origin-level columns say they repeat on every destination row of the same origin borough and month and must not be summed across destinations.
- [ ] Author `transformation/models/marts/agg/_unit_tests.yml` with unit tests on `agg_borough_flow_monthly` covering: a cross-borough trip counted in `cross_borough_trip_count` and a same-borough trip not; an origin borough whose trips split across a cross row and a same row, with the share computed from both; a trip whose `pickup_zone_key` matches no `dim_zone` row landing under `unresolved` and keeping its trip; and a month with no trips producing no row.
- [ ] Author the four singular tests:
  - `assert_borough_flow_one_row_per_grain.sql` returns any `(trip_month, origin_borough, dest_borough)` appearing more than once, or any null in the three key columns (`R-01`).
  - `assert_borough_flow_reconciles_to_fct_trip.sql` compares `sum(trip_count)` and `round(sum(total_revenue), 2)` against `fct_trip`'s billable count and revenue in the window and returns a row on any difference, and returns any in-window billable trip whose origin or destination zone key matches no `dim_zone` row that the model did not count (`R-02`, `R-04`).
  - `assert_borough_flow_share_matches_its_counts.sql` recomputes each origin-month's share as its cross-borough trips over its own trip total and returns any row differing beyond `1e-9`, plus any origin-month whose rows disagree on the two origin-level columns (`R-03`).
  - `assert_borough_flow_keeps_every_borough.sql` returns any `dim_zone` borough name that carries in-window billable trips but appears as neither an origin nor a destination, and any published row whose `trip_count` is below 1 (`R-04`, `R-05`).
- [ ] Add the four singular tests to the `agg` module's `data` list in `test-map.json`, and add the `agg` module's `unit` entry (`transformation/models/marts/agg/_unit_tests.yml`) with its selector and command.
- [ ] Run `cd transformation && dbt build --select +agg_borough_flow_monthly --exclude test_type:unit --target dev`; expect exit 0 with the model and every generic and singular test passing.
- [ ] Run `python3 /data/default-plugins/vibedata-data-engineering/0.148.28/scripts/assert_dbt_destination.py` as its own command; expect exit 0.
- [ ] Run `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit --target dev`; expect exit 0 with every unit test passing.
- [ ] Read the acceptance conditions of `R-01` to `R-05` off the built relation: 122 rows (40 in January, 40 in February, 42 in March); `sum(trip_count)` = 95,958; `round(sum(total_revenue), 2)` = 2,629,185.82; the per-origin-month `cross_borough_trip_count` sums to 12,214 without double counting; eight borough names appear as origins and eight as destinations; `min(trip_count)` = 1 and 66 rows hold fewer than 25 trips.
- [ ] Run `python3 -m pytest tests/test_maps.py -q`; expect exit 0.
- [ ] Commit and push the SQL, `_agg.yml`, `_unit_tests.yml`, the four singular tests and `test-map.json`.

### Task 3: the semantic binding, the contract turned active, and the regenerated tests

**Requirements:** `R-06` · **Design:** `docs/design/models/agg/agg_borough_flow_monthly.md` · **Skill:** `semantic-model`, then `validating-semantic-model` · **Depends on:** Task 2

- [ ] Add `LTS10_borough_flow_monthly` to the `trips` dataset's `logical_sources` in `logical-model/nyc_taxi_analytics.ossie.yaml`: `physical_table: agg_borough_flow_monthly`, `priority_group: 0`, `content_grain: ["trip_month", "origin_borough", "dest_borough"]`, `column_map` of `billable_trip_count: trip_count` and `billable_revenue: total_revenue`, `content_levels` for `trips_to_date` at `month` (`trip_month`), `trips_to_pickup_zone` at `borough` (`origin_borough`) and `trips_to_dropoff_zone` at `borough` (`dest_borough`), and a `content_filter` of the reporting window plus `is_billable`, written as the literal dates the project vars hold.
- [ ] Add a `note` on that source: `cross_borough_trip_count` and `cross_borough_share` are refused because they repeat the origin borough's total on every destination row; the binding is held by `assert_semantic_content_holds`; the population is ADR 0018's crossing definition over ADR 0019's floor-free matrix.
- [ ] Register the `physical_tables` entry (`agg_borough_flow_monthly` → `agg.agg_borough_flow_monthly`, `dbt_model: agg_borough_flow_monthly`) and the `physical_joins` the source needs to each role's table (`Pickup_Zone`, `Dropoff_Zone`, `dim_date`).
- [ ] Run `python3 .agents/skills/semantic-model/scripts/ossie.py validate logical-model/`, then `coverage logical-model/ transformation/models/marts/ --exclude agg.agg_od_flow_matrix --exclude finance.mart_revenue_component_bridge --exclude core.dim_fare_regime`, then `suppliers logical-model/`, then `notes logical-model/ transformation/tests docs/adr/`, then `generate-tests logical-model/ transformation/tests --check`; expect exit 0 from each.
- [ ] Run `python3 .agents/skills/semantic-model/scripts/ossie.py generate-tests logical-model/ transformation/tests` and keep the regenerated tests in the same commit.
- [ ] Set `contracts/agg/agg_borough_flow_monthly.odcs.yaml` to `status: active`, bump its version to `1.0.0`, then run `python3 .agents/skills/data-contract/scripts/odcs.py generate` so the properties file carries the generated `data_type`, tests and `contract` key.
- [ ] Rebuild so the gate covers the enforced contract: `cd transformation && dbt build --select +agg_borough_flow_monthly --exclude test_type:unit --target dev`, expect exit 0; then the destination assert as its own command, expect exit 0.
- [ ] Run `python3 .agents/skills/data-contract/scripts/odcs.py check`; expect exit 0, closing the static half of `R-06`.
- [ ] Invoke `validating-semantic-model` once and record its report; invoke `validating-data-contract` and record its report.
- [ ] Confirm the ontology needs no change: `ontology/nyc_taxi_analytics.mapping.yaml` maps only `Trip`'s own columns, and this change adds no field to `trips` and no concept. Record `validating-ontology` `not applicable` with that reason.
- [ ] Commit and push the Ossie document, the regenerated semantic tests and the contract's `active` status.

## Execution evidence

- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py version` — exit 0 — package `0.2.8`, spec `v3.2.0`.
- Task 1: `python3 .agents/skills/data-contract/scripts/odcs.py check` — exit 0 — three `info` `boundary/excluded` findings for existing contracts, none for `agg_borough_flow_monthly`; the proposed contract's shape passes. Artifact `contracts/agg/agg_borough_flow_monthly.odcs.yaml` — sha256:c044aa35e15d9f58ad98f3d6fc0ebb29d1445caad74eef0b12cb229a1ec85b2d
