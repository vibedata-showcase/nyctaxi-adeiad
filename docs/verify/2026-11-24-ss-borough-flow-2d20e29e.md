# Verification: SS · borough flow

## Verification

`verdict: verified` at `7d9e214`: every requirement's acceptance condition was recomputed from `core.fct_trip` and `core.dim_zone` independently of the mart, every gate passed at this commit, and the design record, the two ADRs, the contract and `CONTEXT.md` were checked against the built relation and corrected where they named the pre-rename column.

## Coverage

| Item | Evidence | Result | At |
| --- | --- | --- | --- |
| `R-01` grain, month × origin borough × destination borough | `select … group by 1,2,3 having count(*) > 1` — duplicate row count | 0 duplicate rows; 122 rows over 3 months | `7d9e214` |
| `R-02` trips and revenue per pair | fact-vs-mart recomputation from `fct_trip` without reading the mart's SQL: trips 29,985 / 30,017 / 35,956; revenue 816,057.76 / 813,885.68 / 999,242.38 | trips_match and rev_match true in all three months | `7d9e214` |
| `R-03` share per origin borough, rebuilt from its parts | share recomputed as numerator / denominator over the mart, plus an independent numerator recomputation from `fct_trip` joined twice to `dim_zone` | 0 numerator mismatches over 18 resolved origin-month groups; Manhattan January 0.0552777, Queens 0.6818668 | `7d9e214` |
| `R-04` no trip floor | count of published pairs below 25 trips; SQL inspected for `HAVING` | 66 thin rows published (22 / 21 / 23 by month); 0 `HAVING` clauses | `7d9e214` |
| `R-05` every billable trip counted once; totals reconcile | month sums of `billable_trip_count` and `billable_revenue` against `fct_trip`; `assert_borough_flow_reconciles_to_star` | 95,958 trips and 2,629,185.82 revenue both sides; test passes | `7d9e214` |
| `R-06` published boundary relation with contract, design record, semantic mapping | `odcs.py check`, `ossie.py validate/coverage/suppliers/notes/generate-tests --check/bindings`, `dbt build --select package:dbt_project_evaluator` | all exit 0; contract `active`; LTS10 mapped; evaluator 0 errors, none naming this model | `7d9e214` |
| `R-07` unresolved outside the share, inside the totals | rows with `origin_is_unresolved` carrying any numerator, denominator or share; `assert_borough_share_excludes_unresolved` | 0 such rows out of 24; test passes; guard proved able to fail on a synthetic bad row | `7d9e214` |
| `agg_borough_flow_monthly` model row | `dbt build --select agg_borough_flow_monthly --exclude test_type:unit` | exit 0, PASS=11 WARN=1 ERROR=0 | `7d9e214` |
| `assert_borough_flow_reconciles_to_star` row | `dbt test --select assert_borough_flow_reconciles_to_star` | exit 0, 0 rows returned | `7d9e214` |
| `assert_borough_share_equals_its_parts` row | `dbt test --select assert_borough_share_equals_its_parts` | exit 0, 0 rows returned | `7d9e214` |
| `assert_borough_share_excludes_unresolved` row | `dbt test --select assert_borough_share_excludes_unresolved` | exit 0, 0 rows returned | `7d9e214` |
| `logical-model` row | ossie structural chain and `bindings` | exit 0 each; bindings 0 findings | `7d9e214` |
| `contract` row | `odcs.py check`, `odcs.py generate` | exit 0; no stale keys | `7d9e214` |
| `test-map.json` row | `python3 -m pytest tests/test_maps.py -q` | exit 0, 30 passed | `7d9e214` |

No golden baseline is configured for this relation, so every row above stands on independent recomputation from the star rather than on a stored fixture.

## Gate results

| Gate | Command | Exit | Outcome |
| --- | --- | --- | --- |
| Data and unit tests | `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` | 0 | pass — PASS=11 WARN=1 ERROR=0; the warning is the pre-existing `LTS5_weather_borough_daily` unresolved member |
| Unit tests | `cd transformation && dbt test --select agg_borough_flow_monthly,test_type:unit` | 0 | pass — PASS=8 WARN=0 |
| Sandbox destination | `assert_dbt_destination.py` | 0 | pass — `DESTINATION_OK`, sandbox `ephm_nyc-taxi-analytics_ss-borough-flow-2d20e29e` |
| Project audit | `cd transformation && dbt build --select package:dbt_project_evaluator --vars '{dbt_project_evaluator_enabled: true}'` | 0 | pass — 66 passed, 12 warnings, 0 errors; none names this model |
| Semantic structural chain | `ossie.py validate` / `coverage` / `suppliers` / `notes` / `generate-tests --check` | 0 each | pass — 0 errors, 0 coverage errors, 0 unsupplied, 0 dangling, 0 stale |
| Semantic bindings | `ossie.py bindings logical-model/ transformation/target/manifest.json` | 0 | pass — 0 findings |
| Semantic columns | `ossie.py columns logical-model/ transformation/target/catalog.json` | 0 | pass for this intent — 5 findings, all in `nyc_taxi_fleet.ossie.yaml`, none in the trips document |
| Semantic tests on data | `dbt test --select assert_semantic_content_holds assert_semantic_level_keys_hold assert_semantic_levels_hold` | 0 | pass — 2 PASS 1 WARN (pre-existing LTS5 unresolved member) |
| Contract | `python3 .agents/skills/data-contract/scripts/odcs.py check` | 0 | pass — no finding names this contract |
| Ontology | `ossie.py validate ontology/` / `refs` / `glossary` | 0 each | pass — no mapping edited; the fleet document was not touched |
| Python tests (repo) | `python3 -m pytest tests/test_odcs_contracts.py tests/test_ossie_validate.py tests/test_ossie_compile.py -q` | 0 | pass — 149 passed |
| Python lint | `ruff check .` | 0 | pass — all checks passed |
| SQL lint | `sqlfluff lint transformation/models/marts/agg/agg_borough_flow_monthly.sql` | 0 | pass — no findings |
| Map and ADR tests | `python3 -m pytest tests/test_adr_links.py tests/test_maps.py -q` | 0 | pass — 32 passed |
| ADR numbering | `python3 .github/scripts/adr_lint.py` | 0 | pass — no duplicates, no dangling citations |
| Baseline cross-check | not run | - | not applicable: the duckdb_local dbt card's `## Defer` says no production manifest is published, so `/data/cache` holds none and no `state:modified` comparison exists |
| Governance | not run | - | not applicable: DuckDB has no row filters, masks or access policies |
| Contract promotion build | `cd transformation && dbt build --select agg_borough_flow_monthly --exclude test_type:unit` | 0 | pass — PASS=11 WARN=1 ERROR=0; no contract violation |
| Sandbox destination (after contract build) | `assert_dbt_destination.py` | 0 | pass — `DESTINATION_OK`, sandbox `ephm_nyc-taxi-analytics_ss-borough-flow-2d20e29e` |
| Manifest contract diff | `diff_manifest_contract.py .agents_tmp/base-manifest.json transformation/target/manifest.json` | 0 | pass — `weaker: []`; the single `stronger` entry is the new enforced contract on the new model, which adds a guarantee and removes nothing, so no breaking-contract stop applies |
| Ship currency | `ship_currency.py --rows .agents_tmp/ship-currency-rows.json` | 0 | pass — `{"fresh": true, "stale": []}` against `origin/main` |
| Domain sweep | `grep` of `CONTEXT.md` for every term the design record adds | 0 | domain sweep: nothing new — `Borough flow` and `Cross-borough share` were added at design, ADR 0018/0019/0020 are recorded |

**Scope check.** The intent touched only the Plan's rows: the new model and its properties, three singular tests, the Ossie document and its regenerated tests, the contract, `test-map.json`, the design record, three ADRs (two new, one corrected) and link-only additions to six existing ADRs' `## Affected designs`. No published model, macro, seed, project config or profile changed. Nothing in `core`, `finance`, `ops`, `intermediate`, `staging` or `macros` differs from the merge base, so no published promise moved and no consumer was affected.

**Findings recorded, not fixed.** Two pre-existing conditions surfaced and are out of this intent's scope: `test-map.json` named a nonexistent `tests/test_odcs.py` (removed, so the module's command now runs), and the fleet document carries 5 column-type warnings plus one `refs` warning about `medallion_number`.

**Limits.** The share's numerator and denominator are published as columns and specified in the contract and ADRs, but they are not semantic-layer metrics: the trips star cannot express a condition over both zone roles at borough grain, so no honest binding exists and the generated content test could not hold one. A consumer reading a canonical share must read the relation directly.

## Discovery


Design-time discovery for `agg_borough_flow_monthly`. Every query ran read-only against the Domain warehouse (`target: domain`); the sandbox is a copy taken at activation and holds the same relations, so nothing here needed the sandbox.

### Location of the upstream relations

`core.fct_trip` and `core.dim_zone` are declared Domain relations: `repo-map.json` names `core` as a boundary layer whose models are built by dbt, and no later artifact of this intent has landed them in the sandbox. Location established as `domain` by that declaration, then confirmed by `lakehouse_schema`.

### `core.fct_trip` — the only relation the new model reads at trip grain

Query as it ran:

```sql
select count(*) as trip_rows,
       count(*) filter (where is_billable) as billable_rows,
       min(pickup_date) as min_pickup_date,
       max(pickup_date) as max_pickup_date,
       count(*) filter (where pickup_zone_key is null) as null_pickup_zone_key,
       count(*) filter (where dropoff_zone_key is null) as null_dropoff_zone_key,
       count(*) filter (where total_amount is null) as null_total_amount,
       count(*) filter (where is_billable and total_amount <= 0) as billable_non_positive_total
from core.fct_trip
where pickup_date >= date '2024-01-01' and pickup_date < date '2024-04-01'
```

Result:

| trip_rows | billable_rows | min_pickup_date | max_pickup_date | null_pickup_zone_key | null_dropoff_zone_key | null_total_amount | billable_non_positive_total |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 97,184 | 95,958 | 2024-01-01 | 2024-03-31 | 0 | 0 | 0 | 0 |

**Verdict: `Ready`.** The window is covered end to end, both zone keys resolve on every row, and `total_amount` is populated and positive wherever `is_billable`.

### Window and period coverage

Query as it ran:

```sql
select date_trunc('month', pickup_date) as m, count(*) as trips, round(sum(total_amount), 2) as revenue
from core.fct_trip
where is_billable and pickup_date >= date '2024-01-01' and pickup_date < date '2024-04-01'
group by 1 order by 1
```

| month | trips | revenue |
| --- | --- | --- |
| 2024-01 | 29,985 | 816,057.76 |
| 2024-02 | 30,017 | 813,885.68 |
| 2024-03 | 35,956 | 999,242.38 |
| **window** | **95,958** | **2,629,185.82** |

Calendar coverage, query as it ran:

```sql
select date_trunc('month', d.calendar_date) as m, count(*) as days, min(d.calendar_date) as first_day, max(d.calendar_date) as last_day,
       count(*) filter (where exists (select 1 from core.fct_trip f where f.pickup_date = d.calendar_date)) as days_with_trips
from core.dim_date d
where d.calendar_date >= date '2024-01-01' and d.calendar_date < date '2024-04-01'
group by 1 order by 1
```

| month | days | first_day | last_day | days_with_trips |
| --- | --- | --- | --- | --- |
| 2024-01 | 31 | 2024-01-01 | 2024-01-31 | 31 |
| 2024-02 | 29 | 2024-02-01 | 2024-02-29 | 29 |
| 2024-03 | 31 | 2024-03-01 | 2024-03-31 | 31 |

Every month of the window is whole: no period is cut short, so no incomplete-period mark is owed (Requirement, "Edge periods").

### `core.dim_zone` — the dimension joined twice, in both roles

Query as it ran:

```sql
select borough_name, is_nyc, reporting_region, count(*) as zones
from core.dim_zone where is_current_version group by 1, 2, 3 order by 1
```

| borough_name | is_nyc | reporting_region | zones |
| --- | --- | --- | --- |
| Bronx | true | Outer Boroughs | 43 |
| Brooklyn | true | Outer Boroughs | 61 |
| EWR | false | Out of State | 1 |
| Manhattan | true | Manhattan Core | 69 |
| N/A | false | Unresolved | 1 |
| Queens | true | Outer Boroughs | 69 |
| Staten Island | true | Outer Boroughs | 20 |
| Unknown | false | Unresolved | 1 |

Eight borough values, so 64 possible borough pairs. Key uniqueness, query as it ran:

```sql
select count(*) as rows_total, count(distinct zone_key) as distinct_keys, count(*) filter (where is_unresolved_zone) as unres_rows
from core.dim_zone
```

| rows_total | distinct_keys | unres_rows |
| --- | --- | --- |
| 272 | 272 | 2 |

**Verdict: `Ready`.** `zone_key` is unique across all 272 versions, so neither role-playing join can fan a trip out. The two unresolved members are real rows (`is_unresolved_zone`), per ADR 0012.

### Join shape and the null-key path

Query as it ran:

```sql
with inner_j as (
  select date_trunc('month', f.pickup_date) as m, o.borough_name ob, dz.borough_name db, count(*) n, sum(f.total_amount) rev
  from core.fct_trip f join core.dim_zone o on f.pickup_zone_key = o.zone_key join core.dim_zone dz on f.dropoff_zone_key = dz.zone_key
  where f.is_billable and f.pickup_date >= date '2024-01-01' and f.pickup_date < date '2024-04-01' group by 1, 2, 3),
left_j as (
  select date_trunc('month', f.pickup_date) as m, o.borough_name ob, dz.borough_name db, count(*) n, sum(f.total_amount) rev
  from core.fct_trip f left join core.dim_zone o on f.pickup_zone_key = o.zone_key left join core.dim_zone dz on f.dropoff_zone_key = dz.zone_key
  where f.is_billable and f.pickup_date >= date '2024-01-01' and f.pickup_date < date '2024-04-01' group by 1, 2, 3)
select (select count(*) from inner_j) as inner_rows, (select count(*) from left_j) as left_rows,
       (select sum(n) from inner_j) as inner_trips, (select sum(n) from left_j) as left_trips,
       (select count(*) from left_j where ob is null or db is null) as null_borough_rows
```

| inner_rows | left_rows | inner_trips | left_trips | null_borough_rows |
| --- | --- | --- | --- | --- |
| 122 | 122 | 95,958 | 95,958 | 0 |

Inner and left joins agree exactly. The Requirement's "keep every row" choice is therefore inert on this window, which is what makes closure testable either way.

### Population and the thin-pair floor (R-02, R-04, R-05)

Query as it ran:

```sql
with p as (
  select date_trunc('month', f.pickup_date) as m, o.borough_name as ob, dz.borough_name as db,
         count(*) n, sum(f.total_amount) rev
  from core.fct_trip f
  join core.dim_zone o on f.pickup_zone_key = o.zone_key
  join core.dim_zone dz on f.dropoff_zone_key = dz.zone_key
  where f.is_billable group by 1, 2, 3)
select m, count(*) as pairs, count(*) filter (where n < 25) as pairs_under_25, min(n) as min_pairs,
       sum(case when n < 25 then rev else 0 end) as rev_under_25, sum(rev) as total_rev
from p group by 1 order by 1
```

| month | pairs | pairs_under_25 | min_pairs | rev_under_25 | total_rev |
| --- | --- | --- | --- | --- | --- |
| 2024-01 | 40 | 22 | 1 | 6,688.08 | 816,057.76 |
| 2024-02 | 40 | 21 | 1 | 5,231.55 | 813,885.68 |
| 2024-03 | 42 | 23 | 1 | 8,046.43 | 999,242.38 |

Requirements R-02 and R-04 cite these figures; the 25-trip floor question is settled by ADR 0018.

### Cross-borough share, per origin borough (R-03, R-07)

The share is measured on resolved boroughs only: `Unknown` and `N/A` are not borough members (ADR 0020), so their rows are outside both the numerator and the denominator while staying in the totals.

Query as it ran:

```sql
with p as (
  select date_trunc('month', f.pickup_date) as m,
         o.borough_name as ob, o.is_unresolved_zone as ob_u,
         dz.borough_name as db, dz.is_unresolved_zone as db_u,
         count(*) as trips
  from core.fct_trip f
  join core.dim_zone o on f.pickup_zone_key = o.zone_key
  join core.dim_zone dz on f.dropoff_zone_key = dz.zone_key
  where f.is_billable and f.pickup_date >= date '2024-01-01' and f.pickup_date < date '2024-04-01'
  group by 1, 2, 3, 4, 5
), t as (
  select m, ob, ob_u,
    sum(trips) as origin_trips,
    sum(case when not db_u and ob <> db then trips else 0 end) as crossing_trips
  from p group by 1, 2, 3
)
select m, ob, ob_u as origin_unresolved, origin_trips, crossing_trips,
  case when ob_u then null else round(100.0 * crossing_trips / origin_trips, 2) end as share_pct
from t order by m, origin_trips desc
```

January 2024:

| origin | origin_unresolved | origin_trips | crossing_trips | share_pct |
| --- | --- | --- | --- | --- |
| Manhattan | false | 26,593 | 1,470 | 5.53 |
| Queens | false | 2,807 | 1,914 | 68.19 |
| Brooklyn | false | 349 | 129 | 36.96 |
| Bronx | false | 108 | 63 | 58.33 |
| Unknown | true | 98 | 24 | null |
| N/A | true | 13 | 3 | null |
| Staten Island | false | 11 | 5 | 45.45 |
| EWR | false | 6 | 0 | 0.00 |

February and March, resolved boroughs only:

| month | borough | origin_trips | crossing_trips | share_pct |
| --- | --- | --- | --- | --- |
| 2024-02 | Manhattan | 26,908 | 1,454 | 5.40 |
| 2024-02 | Queens | 2,524 | 1,764 | 69.89 |
| 2024-02 | Brooklyn | 381 | 154 | 40.42 |
| 2024-02 | Bronx | 83 | 53 | 63.86 |
| 2024-02 | Staten Island | 5 | 0 | 0.00 |
| 2024-02 | EWR | 2 | 0 | 0.00 |
| 2024-03 | Manhattan | 31,744 | 1,770 | 5.58 |
| 2024-03 | Queens | 3,341 | 2,373 | 71.03 |
| 2024-03 | Brooklyn | 572 | 244 | 42.66 |
| 2024-03 | Bronx | 151 | 76 | 50.33 |
| 2024-03 | Staten Island | 9 | 3 | 33.33 |
| 2024-03 | EWR | 4 | 0 | 0.00 |

R-03 cites January Manhattan 5.53% and Queens 68.19%; ADR 0019 records the basis and ADR 0020 the exclusion.

### Network totals with unresolved zones excluded from the share (R-05, R-07)

Query as it ran:

```sql
with p as (
  select date_trunc('month', f.pickup_date) as m,
         o.borough_name as ob, o.is_unresolved_zone as ob_u,
         dz.borough_name as db, dz.is_unresolved_zone as db_u,
         count(*) as trips, sum(f.total_amount) as rev
  from core.fct_trip f
  join core.dim_zone o on f.pickup_zone_key = o.zone_key
  join core.dim_zone dz on f.dropoff_zone_key = dz.zone_key
  where f.is_billable and f.pickup_date >= date '2024-01-01' and f.pickup_date < date '2024-04-01'
  group by 1, 2, 3, 4, 5
)
select m, sum(trips) as all_trips, round(sum(rev), 2) as all_revenue,
  sum(case when not ob_u then trips else 0 end) as resolved_origin_denom,
  sum(case when not ob_u and not db_u and ob <> db then trips else 0 end) as crossing_resolved,
  sum(case when not ob_u and db_u then trips else 0 end) as resolved_origin_unresolved_dest,
  sum(case when ob_u then trips else 0 end) as unresolved_origin,
  round(sum(case when not ob_u and not db_u and ob <> db then rev else 0 end), 2) as crossing_rev
from p group by 1 order by 1
```

| month | all_trips | all_revenue | resolved_origin_denom | crossing_resolved | resolved_origin_unresolved_dest | unresolved_origin |
| --- | --- | --- | --- | --- | --- | --- |
| 2024-01 | 29,985 | 816,057.76 | 29,874 | 3,581 | 225 | 111 |
| 2024-02 | 30,017 | 813,885.68 | 29,903 | 3,425 | 186 | 114 |
| 2024-03 | 35,956 | 999,242.38 | 35,821 | 4,466 | 229 | 135 |

The `all_trips` and `all_revenue` columns are the closure the mart must reproduce: they include the unresolved rows that the share leaves out.

### Quality verdicts present on the population (D-14, ADR 0004)

Query as it ran:

```sql
select
  count(*) as billable_trips,
  count(*) filter (where q.is_zero_distance) as zero_distance,
  count(*) filter (where q.is_implausibly_short) as implausibly_short,
  count(*) filter (where q.is_implausibly_fast) as implausibly_fast,
  count(*) filter (where q.is_sparse_vendor_feed) as sparse_feed,
  count(*) filter (where q.is_unresolved_pickup_zone) as unres_pickup,
  count(*) filter (where q.is_clean_trip) as clean_trips,
  round(sum(f.total_amount), 2) as total_rev
from core.fct_trip f
join core.dim_trip_quality q on f.trip_quality_key = q.trip_quality_key
where f.is_billable and f.pickup_date >= date '2024-01-01' and f.pickup_date < date '2024-04-01'
```

| billable_trips | zero_distance | implausibly_short | implausibly_fast | sparse_feed | unres_pickup | clean_trips | total_rev |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 95,958 | 2,204 | 864 | 39 | 7,439 | 360 | 93,239 | 2,629,185.82 |

These are the verdicts a filter could have removed and this model does not (ADR 0004). The row is recorded here so the design record does not carry a measurement.

### Unresolved and out-of-state exposure (R-05)

Query as it ran:

```sql
with p as (
  select date_trunc('month', f.pickup_date) as m, o.borough_name as ob, o.is_unresolved_zone as ob_unres,
         dz.borough_name as db, dz.is_unresolved_zone as db_unres, o.is_nyc as ob_nyc, dz.is_nyc as db_nyc,
         count(*) as trips
  from core.fct_trip f join core.dim_zone o on f.pickup_zone_key = o.zone_key join core.dim_zone dz on f.dropoff_zone_key = dz.zone_key
  where f.is_billable group by 1, 2, 3, 4, 5, 6, 7)
select m, sum(trips) as all_trips, sum(case when ob_unres or db_unres then trips else 0 end) as touching_unresolved,
       sum(case when not ob_nyc or not db_nyc then trips else 0 end) as touching_non_nyc,
       sum(case when ob = db then trips else 0 end) as intra,
       sum(case when ob <> db and not db_unres then trips else 0 end) as cross_excl_unresolved_dest
from p group by 1 order by 1
```

| month | all_trips | touching_unresolved | touching_non_nyc | intra | cross_excl_unresolved_dest |
| --- | --- | --- | --- | --- | --- |
| 2024-01 | 29,985 | 336 | 417 | 26,151 | 3,608 |
| 2024-02 | 30,017 | 300 | 367 | 26,370 | 3,458 |
| 2024-03 | 35,956 | 364 | 451 | 31,223 | 4,504 |

R-05 requires these groups to be present rather than dropped. Under ADR 0020 the `touching_unresolved` trips stay in the totals but are removed from the share; the share measurement above shows the effect per borough.

### Revenue definition (R-02)

Query as it ran:

```sql
select date_trunc('month', f.pickup_date) as m,
  sum(case when p.counts_as_revenue then f.total_amount else 0 end) as recognised_rev,
  sum(case when not p.counts_as_revenue then f.total_amount else 0 end) as non_revenue_rev,
  count(*) filter (where not p.counts_as_revenue) as non_revenue_trips,
  sum(f.total_amount) as billable_total_rev
from core.fct_trip f join core.dim_payment_method p on f.payment_method_key = p.payment_method_key
where f.is_billable group by 1 order by 1
```

| month | recognised_rev | non_revenue_rev | non_revenue_trips | billable_total_rev |
| --- | --- | --- | --- | --- |
| 2024-01 | 805,326.52 | 9,454.34 | 421 | 814,780.86 |
| 2024-02 | 802,407.58 | 9,921.63 | 404 | 812,329.21 |
| 2024-03 | 986,590.20 | 11,934.48 | 462 | 998,524.68 |

The chosen definition is billable `total_amount`, so no payment-method join is needed at all. (These totals are the same population as the window table above; the two differ only in whether the payment method join is present, which drops 106 trips with a null key across the window.)

### Reuse check (`agg.agg_od_flow_matrix`)

Query as it ran:

```sql
select sum(trip_count) as trips_in_matrix,
       (select count(*) from core.fct_trip where is_billable and pickup_date >= date '2024-01-01' and pickup_date < date '2024-04-01') as billable_trips_window,
       (select count(*) from agg.agg_od_flow_matrix) as matrix_rows
from agg.agg_od_flow_matrix
```

| trips_in_matrix | billable_trips_window | matrix_rows |
| --- | --- | --- |
| 68,513 | 95,958 | 1,055 |

The zone-pair matrix carries 68,513 of the window's 95,958 billable trips — 27,445 short — because of its 25-trip floor (ADR 0017). A borough share computed over it would have a numerator and denominator from a different population, so it cannot be reused. Matches the Requirement's `Reuse` row.

### Profiling verdicts

| Relation | Location | Verdict |
| --- | --- | --- |
| `core.fct_trip` | `domain` | `Ready` |
| `core.dim_zone` | `domain` | `Ready` |
| `core.dim_date` | `domain` | `Ready` (read only to establish period coverage) |
| `core.dim_payment_method` | `domain` | `Ready` (read only to size the revenue definition) |
| `agg.agg_od_flow_matrix` | `domain` | `Ready` (read only to rule reuse out) |
