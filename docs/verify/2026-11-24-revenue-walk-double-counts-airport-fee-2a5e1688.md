# Verification: SS · revenue walk fix

## Discovery

Every probe below ran read-only against the Domain warehouse (`domain`, the Q1 2024 reporting window, repo at `1184020`), unless it says otherwise.

- The walk exceeds billable revenue by exactly the airport-fee component, over 44 bridge groups and 95,958 billable trips.

  ```sql
  select
    (select sum(component_amount) from finance.mart_revenue_component_bridge) as walk_total,
    (select sum(total_amount) from core.fct_trip where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01') as billable_revenue,
    (select sum(component_amount) from finance.mart_revenue_component_bridge where component_name = 'c_airport_fee') as airport_fee_component,
    (select sum(component_amount) from finance.mart_revenue_component_bridge where component_name = 'c_residual') as residual_component,
    (select count(*) from core.fct_trip where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01') as trips,
    (select count(distinct (trip_month, service_type_key, borough_name)) from finance.mart_revenue_component_bridge) as bridge_groups
  ```

  → `walk_total` 2,641,448.07; `billable_revenue` 2,629,185.82; `airport_fee_component` 12,262.25; `residual_component` -20,376.50; `trips` 95,958; `bridge_groups` 44.

- Dropping `c_airport_fee` balances every group, so the fee is the only term out of place.

  ```sql
  select trip_month, service_type_key, borough_name, total_amount,
    sum(case when component_name <> 'c_airport_fee' then component_amount else 0 end) as walk_ex_fee,
    sum(component_amount) as walk_all,
    sum(case when component_name = 'c_airport_fee' then component_amount else 0 end) as airport_fee,
    count(*) as component_rows
  from finance.mart_revenue_component_bridge
  group by 1,2,3,4
  having abs(sum(case when component_name <> 'c_airport_fee' then component_amount else 0 end) - total_amount) > 0.01
  order by 1,2,3
  ```

  → 0 rows. The 9 groups that miss balance do so by their own `c_airport_fee`:

  ```sql
  select trip_month, service_type_key, borough_name, count(*) as rows_in_group, max(total_amount) as total_amount,
         round(sum(component_amount),2) as walk, round(sum(component_amount)-max(total_amount),2) as gap
  from finance.mart_revenue_component_bridge
  group by 1,2,3
  having abs(sum(component_amount)-max(total_amount)) > 0.01 or count(*) < 9
  order by 1,2,3
  ```

  → 10 rows: 9 yellow groups with gaps 5.25, 3,984.75, 7.00 (Jan), 3.50, 3,543.75, 3.50 (Feb), 1.75, 4,705.75, 7.00 (Mar), summing to 12,262.25; and one green / N-A / Feb group with 8 component rows and gap 0.00 (the cosmetic finding, no value effect).

- Per trip the nine components equal the total plus the fee, on every one of the 95,958 billable trips.

  ```sql
  select count(*) as trips,
   count(*) filter (where abs(
     coalesce(fare_amount,0)+coalesce(tip_amount,0)+coalesce(tolls_amount,0)+coalesce(extra,0)
     +coalesce(mta_tax,0)+coalesce(improvement_surcharge,0)+coalesce(congestion_surcharge,0)
     +coalesce(airport_fee,0)+coalesce(fare_residual,0) - coalesce(total_amount,0) - coalesce(airport_fee,0)
   ) > 0.01) as breaks_identity
  from core.fct_trip
  where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'
  ```

  → 95,958 trips, 0 breaks. So `fare_residual` = total − (all nine components − residual), i.e. it already absorbs the fee that the bridge publishes separately.

- The source shape explains why the fee total is the whole difference: the fee is inside the total on 5,765 billable trips, outside it on 530, and on 712 the total matches neither.

  ```sql
  with t as (
    select coalesce(airport_fee,0) as fee,
      coalesce(fare_amount,0)+coalesce(tip_amount,0)+coalesce(tolls_amount,0)+coalesce(extra,0)
        +coalesce(mta_tax,0)+coalesce(improvement_surcharge,0)+coalesce(congestion_surcharge,0) as parts,
      coalesce(total_amount,0) as total, fare_residual
    from core.fct_trip
    where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'
  )
  select case
      when fee = 0 then 'no fee'
      when abs(parts + fee - total) <= 0.01 then 'fee inside total'
      when abs(parts - total) <= 0.01 then 'fee outside total'
      else 'total matches neither' end as shape,
    count(*) as trips, round(sum(fee),2) as fee_total, round(sum(fare_residual),2) as residual_total,
    round(sum(total),2) as total_sum, round(sum(parts),2) as parts_sum
  from t group by 1 order by 2 desc
  ```

  → no fee 88,951 trips (residual -28,685.25); fee inside total 5,765 (+10,088.75, residual +10,088.75); total matches neither 712 (fee 1,246.00, residual -1,780.00); fee outside total 530 (fee 927.50, residual 0.00).

- Excluding the fee from the residual balances the walk exactly, at the group grain.

  ```sql
  with sim as (
    select date_trunc('month', f.pickup_datetime) as trip_month, f.service_type_key, z.borough_name,
      coalesce(f.fare_amount,0)+coalesce(f.tip_amount,0)+coalesce(f.tolls_amount,0)+coalesce(f.extra,0)
        +coalesce(f.mta_tax,0)+coalesce(f.improvement_surcharge,0)+coalesce(f.congestion_surcharge,0)
        +coalesce(f.airport_fee,0) as parts,
      coalesce(f.total_amount,0) - coalesce(f.fare_amount,0)-coalesce(f.tip_amount,0)-coalesce(f.tolls_amount,0)
        -coalesce(f.extra,0)-coalesce(f.mta_tax,0)-coalesce(f.improvement_surcharge,0)
        -coalesce(f.congestion_surcharge,0)-coalesce(f.airport_fee,0) as new_residual,
      coalesce(f.total_amount,0) as total
    from core.fct_trip f join core.dim_zone z on f.pickup_zone_key = z.zone_key
    where f.is_billable and f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01'
  ), g as (
    select trip_month, service_type_key, borough_name,
      sum(parts) as parts_sum, sum(new_residual) as res_sum, sum(total) as total_sum
    from sim group by 1,2,3
  )
  select count(*) as groups, count(*) filter (where abs(parts_sum + res_sum - total_sum) > 0.01) as groups_off,
    round(sum(parts_sum + res_sum),2) as walk_total, round(sum(total_sum),2) as total_amount,
    round(sum(res_sum),2) as residual_total
  from g
  ```

  → 44 groups, 0 off, walk 2,629,185.82, total 2,629,185.82, residual -32,638.75.

- Blast radius on the quality scorecard's `unbalanced_total_count`, from `abs(fare_residual) > 0.01` today against the same test on the corrected residual: in-window trips 97,184, flagged 31,869 today and 26,457 after; 5,942 trips stop being flagged and 530 start. By month and fleet:

  ```sql
  with t as (
    select date_trunc('month', pickup_datetime) as trip_month, service_type_key,
           abs(fare_residual) > 0.01 as flagged_before,
           abs(fare_residual - coalesce(airport_fee,0)) > 0.01 as flagged_after
    from core.fct_trip where pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'
  )
  select trip_month, service_type_key,
    count(*) filter (where flagged_before) as unbalanced_before,
    count(*) filter (where flagged_after) as unbalanced_after
  from t group by 1,2 order by 1,2
  ```

  → green 102/102 (Jan), 85/85 (Feb), 100/100 (Mar); yellow 9,318/7,510 (Jan), 9,404/7,865 (Feb), 12,860/10,795 (Mar).

- The surcharge set's other consumers do not move if `surcharge_columns()` is left alone: `sum(total_surcharges)` feeds `mart_daily_zone_revenue.surcharge_revenue`, `agg_trip_zone_daypart_dow.surcharge_revenue`, `int_shift_economics.surcharge_collected` and `fct_trip.total_surcharges`. `fct_shift` already carries `airport_fee_collected` beside `surcharge_collected`, so adding the fee to the surcharge set would count it twice in that model.

- Green's fleet-specific fee is not a factor in this window: `sum(coalesce(ehail_fee,0))` and the count of trips with a non-zero `ehail_fee` are both 0 across all 97,184 in-window trips, and it is not a bridge component, so it stays in the residual.

- The surface the semantic layer reports is unchanged by the fix: `billable_revenue` reads `fct_trip.total_amount`, and `mart_daily_zone_revenue.total_revenue` already matches it at 2,629,185.82. Its four named revenue lines sum to 2,649,562.32, a -20,376.50 gap equal to today's residual total; that gap is pre-existing and outside this case.

- Repo plane: `transformation/macros/finance.sql` `surcharge_columns()` returns `extra, mta_tax, improvement_surcharge, congestion_surcharge`; `fare_residual()` subtracts exactly those plus fare, tip and tolls; `mart_revenue_component_bridge.sql` unpivots nine components including `c_airport_fee` and `c_residual`. No test asserts the components sum to the total: `transformation/tests/` holds none over the bridge.
