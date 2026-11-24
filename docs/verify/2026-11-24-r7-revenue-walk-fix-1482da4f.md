# Verification: R7 · revenue walk fix

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
