# Verification: Borough-to-borough trips and revenue share

## Verification

`verdict: unrun` — no build and no gate has run yet; this file holds the design-stage discovery recorded below.

## Coverage

| Item | Evidence | Result | At |
| --- | --- | --- | --- |
| `R-01` pair rows and floor | `dbt build` on the model, then the pair-row count per month and the minimum `trip_count` | unrun | - |
| `R-02` revenue population | recompute the pair revenue sum and the difference against `fct_trip`'s billable revenue | unrun | - |
| `R-03` crossing share | recompute each origin borough-month's share from `fct_trip` independently of the model | unrun | - |
| `R-04` no-pair borough-months | count the rows whose `dest_borough` is null and read their shares | unrun | - |
| `R-05` grain | the singular grain test over (month, origin borough, destination borough) | unrun | - |
| `R-06` unresolved zones | every borough value appears on `dim_zone`; the rows touching N/A or Unknown keep their trips | unrun | - |
| `R-07` trip and revenue closure | pairs plus floored-out pairs equal `fct_trip`'s totals | unrun | - |
| `R-08` whole months | the model's distinct months and the calendar coverage of each | unrun | - |
| `agg_borough_flow_monthly` | its gate commands | unrun | - |
| `semantic_exclusions` entry | repo map and `tests/test_maps.py` | unrun | - |
| `contracts/agg/agg_borough_flow_monthly.odcs.yaml` | `odcs.py check` | unrun | - |

## Gate results

| Gate | Command | Exit | Outcome |
| --- | --- | --- | --- |
| Data and unit tests | `dbt build --select +agg_borough_flow_monthly+ --exclude test_type:unit` then `dbt test --select agg_borough_flow_monthly,test_type:unit` | - | unrun |
| Docs match data | inspection of the model description and column descriptions against the built SQL | - | unrun |
| Project audit | `dbt build --select package:dbt_project_evaluator --vars '{dbt_project_evaluator_enabled: true}' --warn-error-options '{"error":["NoNodesForSelectionCriteria"]}'` | - | unrun |
| Semantic model | `ossie.py validate`, `coverage`, `suppliers`, `notes`, `generate-tests --check`, then `validating-semantic-model` | - | unrun |
| Ontology | `ontology.py validate`, `refs`, `glossary`, then `validating-ontology` for whatever the semantic change reaches | - | unrun |
| Contract | `odcs.py check` and a passing `validating-data-contract` report | - | unrun |
| Map guards | `python3 -m pytest tests -q` | - | unrun |
| Python lint | `ruff check .` | - | unrun |
| SQL lint | `sqlfluff lint transformation/models` | - | unrun |
| Dev-artifact scan | no `dev_mode`, hard-coded `.add_limit()`, environment id or edited profile target | - | unrun |
| Baseline cross-check | not applicable: the dbt card's `## Defer` says no production manifest is published | - | not applicable |

## Discovery

Profiled on `target: domain`, the location the platform card's `## Sandbox run` gives the sandbox as a copy of, and the Requirement's own target. Both upstream relations are published boundary relations, so the location is declared rather than searched.

- `fct_trip` carries the whole Q1 2024 window and no null zone key: `min(pickup_datetime)` 2024-01-01 00:05:25, `max(pickup_datetime)` 2024-03-31 23:56:17, 97,184 rows, 0 null `pickup_zone_key`, 0 null `dropoff_zone_key`. Verdict: **Ready** — `select min(pickup_datetime) as min_pu, max(pickup_datetime) as max_pu, count(*) as n, count(*) filter (where pickup_zone_key is null) as null_pu_key, count(*) filter (where dropoff_zone_key is null) as null_do_key from core.fct_trip`
- `dim_zone` resolves to 8 borough groups and 265 zones over 272 rows (a zone has more than one version); `N/A` and `Unknown` are the two unresolved zones (ADR 0012). Verdict: **Ready** — `select borough_name, is_unresolved_zone, count(*) as zones from core.dim_zone group by 1,2 order by 1` and `select count(*) as dim_rows, count(distinct zone_natural_key) as zones, count(distinct borough_name) as boroughs, count(distinct zone_natural_key) filter (where borough_name in ('N/A','Unknown')) as unresolved_zones from core.dim_zone`
- Billable trips: 95,958 inside Q1 2024, of which 0 carry a null total and 0 a zero total, so no billable trip is missing the revenue measure. Verdict: **Ready** — `select count(*) as billable, count(*) filter (where total_amount is null) as null_amount, count(*) filter (where total_amount = 0) as zero_amount, count(distinct date_trunc('month', pickup_datetime)) as months from core.fct_trip where pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01' and is_billable`
- The origin-borough × destination-borough cross product before any floor is 122 (month, pair) combinations over 95,958 billable trips; 66 of them carry fewer than 25 trips in their month and hold 253 trips. A floor at the whole-window grain instead keeps 22 of 48 pairs and drops 139 trips. The zone-pair floor at the window grain keeps only 71.4% of billable trips. Verdict: **Ready** — `with m as (select date_trunc('month', f.pickup_datetime) as trip_month, o.borough_name as ob, d.borough_name as db, count(*) as trips from core.fct_trip f join core.dim_zone o on f.pickup_zone_key = o.zone_key join core.dim_zone d on f.dropoff_zone_key = d.zone_key where f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01' and f.is_billable group by 1,2,3), w as (select ob, db, sum(trips) as trips from m group by 1,2) select 'per month' as basis, count(*) as pair_rows, count(*) filter (where trips >= 25) as kept, sum(trips) filter (where trips<25) as trips_dropped from m union all select 'whole window', count(*), count(*) filter (where trips >= 25), sum(trips) filter (where trips<25) from w`
- Cross-borough traffic over Q1 2024: 12,214 of 95,958 billable trips end in a different borough from the one they started in; 742 of those crossing trips touch an unresolved zone, and excluding every trip that touches one would leave 11,472. Verdict: **Ready** — `with t as (select o.borough_name as ob, d.borough_name as db, o.is_unresolved_zone as ou, d.is_unresolved_zone as du from core.fct_trip f join core.dim_zone o on f.pickup_zone_key = o.zone_key join core.dim_zone d on f.dropoff_zone_key = d.zone_key where f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01' and f.is_billable) select 'all rows' as basis, count(*) as trips, count(*) filter (where ob<>db) as leaving, count(*) filter (where ob<>db and (ou or du)) as leaving_via_unresolved from t union all select 'excluding any unresolved', count(*), count(*) filter (where ob<>db and not ou and not du), null from t where not ou and not du`
- Billable revenue over Q1 2024 is 2,629,185.82, of which 31,310.45 is on no-charge and dispute trips (797 dispute trips worth 20,431.24 and 490 no-charge trips worth 10,879.21); every other payment method is flagged as counting toward revenue. Verdict: **Ready** — `with pay as (select p.payment_method_name, p.counts_as_revenue, count(*) as trips, sum(f.total_amount) as revenue from core.fct_trip f join core.dim_payment_method p on f.payment_method_key = p.payment_method_key where f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01' and f.is_billable group by 1,2) select * from pay order by revenue desc`
- Three months, none cut short: January has trips on 31 of 31 calendar days, February on 29 of 29, March on 31 of 31, so no period the rollup emits is partial. Verdict: **Ready** — `select date_trunc('month', pickup_date) as m, count(distinct pickup_date) as days_with_trips, min(pickup_date) as first_day, max(pickup_date) as last_day, count(*) as trips from core.fct_trip where pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01' group by 1 order by 1`
