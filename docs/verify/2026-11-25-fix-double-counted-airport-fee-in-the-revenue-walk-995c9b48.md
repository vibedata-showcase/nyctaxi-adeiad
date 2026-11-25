# Verification: Fix double-counted airport fee in the revenue walk

No `## Verification` verdict is recorded: the design stop was asked and not answered, so no fix was built and there is nothing to verify. Only the discovery evidence below exists.

## Discovery

<!-- Written by designing: each discovery result, and any slice with its limits. Keep as found. -->

Gathered 2026-11-25 against `lakehouse_query` target `domain` at commit `1184020`, read-only. No slice was taken: the bridge is 395 rows and every probe aggregates the whole Q1 2024 window.

- **The overcount reproduces exactly, and dropping the fee line closes the walk.** grains 44, nine-line differing 9, eight-line differing 0, overcount $12,262.25, delta after fix $0.00.

  ```sql
  with walk as (
    select trip_month, service_type_key, borough_name,
           any_value(total_amount) as total_amount,
           sum(component_amount) as nine_line,
           sum(case when component_name <> 'c_airport_fee' then component_amount else 0 end) as eight_line,
           sum(case when component_name = 'c_airport_fee' then component_amount else 0 end) as fee
    from finance.mart_revenue_component_bridge
    group by 1,2,3
  )
  select count(*) as grains,
         count(*) filter (where abs(nine_line - total_amount) > 0.01) as nine_differing,
         count(*) filter (where abs(eight_line - total_amount) > 0.01) as eight_differing,
         round(sum(nine_line - total_amount),2) as overcount,
         round(sum(eight_line - total_amount),2) as delta_after_fix,
         round(sum(total_amount),2) as billable_total
  from walk;
  ```

- **Billable revenue is the same three ways, and the residual absorbs the fee.** `fct_trip` over `is_billable` $2,629,185.82 over 95,958 trips; `mart_daily_zone_revenue` $2,629,185.82; nine-line walk $2,641,448.07; eight-line walk $2,629,185.82; published `c_residual` −$20,376.50; `c_airport_fee` $12,262.25.

  ```sql
  select
    (select round(sum(total_amount),2) from core.fct_trip
       where is_billable and pickup_datetime >= timestamptz '2024-01-01 00:00:00+00'
         and pickup_datetime < timestamptz '2024-04-01 00:00:00+00') as fct_trip_billable,
    (select count(*) from core.fct_trip
       where is_billable and pickup_datetime >= timestamptz '2024-01-01 00:00:00+00'
         and pickup_datetime < timestamptz '2024-04-01 00:00:00+00') as billable_trips,
    (select round(sum(total_revenue),2) from finance.mart_daily_zone_revenue) as daily_zone_revenue,
    (select round(sum(component_amount),2) from finance.mart_revenue_component_bridge) as nine_line_walk,
    (select round(sum(component_amount),2) from finance.mart_revenue_component_bridge where component_name <> 'c_airport_fee') as eight_line_walk,
    (select round(sum(component_amount),2) from finance.mart_revenue_component_bridge where component_name = 'c_residual') as residual_published,
    (select round(sum(component_amount),2) from finance.mart_revenue_component_bridge where component_name = 'c_airport_fee') as airport_fee_line;
  ```

- **7,007 billable trips carry a fee; on 5,765 the published residual equals the fee exactly.** Net of the fee the residual is −$32,638.75.

  ```sql
  select
    count(*) filter (where f.is_billable) as billable_trips,
    count(*) filter (where f.is_billable and f.airport_fee is not null and abs(f.airport_fee) > 0) as billable_with_fee,
    count(*) filter (where f.is_billable and f.airport_fee is not null and abs(f.airport_fee) > 0
                       and abs(f.fare_residual - f.airport_fee) <= 0.01) as residual_equals_fee,
    count(*) filter (where f.is_billable and f.airport_fee is not null and abs(f.airport_fee) > 0
                       and abs(f.fare_residual) > 0.01) as fee_bearing_flagged_unbalanced,
    count(*) filter (where f.is_billable and coalesce(f.airport_fee,0) = 0
                       and abs(f.fare_residual) > 0.01) as no_fee_flagged_unbalanced,
    round(sum(f.fare_residual) filter (where f.is_billable),2) as residual_total,
    round(sum(f.fare_residual - coalesce(f.airport_fee,0)) filter (where f.is_billable),2) as residual_excl_fee_total
  from core.fct_trip f
  where f.pickup_datetime >= timestamptz '2024-01-01 00:00:00+00'
    and f.pickup_datetime < timestamptz '2024-04-01 00:00:00+00';
  ```

- **Keeping the fee line with a fee-excluding residual also closes the walk**, at all 44 grains, max delta 2e-9, total $2,629,185.82, residual line −$32,638.75.

  ```sql
  with walk as (
    select trip_month, service_type_key, borough_name,
           any_value(total_amount) as total_amount,
           sum(component_amount) filter (where component_name <> 'c_residual') as eight_known,
           sum(component_amount) filter (where component_name = 'c_residual') as residual_pub,
           sum(component_amount) filter (where component_name = 'c_airport_fee') as fee
    from finance.mart_revenue_component_bridge
    group by 1,2,3
  )
  select count(*) as grains,
         count(*) filter (where abs(eight_known + (residual_pub - fee) - total_amount) > 0.01) as net_residual_differing,
         round(max(abs(eight_known + (residual_pub - fee) - total_amount)),9) as net_residual_max_delta,
         round(sum(eight_known + (residual_pub - fee)),2) as net_residual_walk_total,
         round(sum(eight_known + residual_pub),2) as published_walk_total,
         round(sum(total_amount),2) as billable_revenue,
         round(sum(residual_pub - fee),2) as net_residual_line
  from walk;
  ```

- **Monthly fee line, which is the monthly overcount.** January $3,997.00, February $3,550.75, March $4,714.50, sum $12,262.25.

  ```sql
  select trip_month,
    round(sum(case when component_name='c_airport_fee' then component_amount else 0 end),2) as fee_line
  from finance.mart_revenue_component_bridge
  group by 1 order by 1;
  ```

- **Billable revenue by month**, for the same window, from the bridge's per-grain `total_amount`: January $816,057.76, February $813,885.68, March $999,242.38, sum $2,629,185.82.

  ```sql
  with per_grain as (
    select trip_month, any_value(total_amount) as total_amount
    from finance.mart_revenue_component_bridge group by 1,2,3
  )
  select trip_month, round(sum(total_amount),2) as billable_revenue
  from per_grain group by 1 order by 1;
  ```

- **The adjacent quality surface absorbs the same fee.** `mart_trip_quality_scorecard` counts every trip in the window, not only billable ones, so its figures are not the bridge's: 31,869 trips carry an unbalanced residual as published, 26,457 would with the fee netted; 5,942 stop being flagged and 530 start, because netting the fee moves a residual across the $0.01 threshold in both directions. Out of this anchor's scope.

  ```sql
  with t as (
    select f.fare_residual as residual_pub,
           f.fare_residual - coalesce(f.airport_fee,0) as residual_net
    from core.fct_trip f
    where f.pickup_datetime >= timestamptz '2024-01-01 00:00:00+00'
      and f.pickup_datetime < timestamptz '2024-04-01 00:00:00+00'
  )
  select
    count(*) filter (where residual_pub is not null and abs(residual_pub) > 0.01) as scorecard_unbalanced_now,
    count(*) filter (where residual_net is not null and abs(residual_net) > 0.01) as scorecard_unbalanced_if_netted,
    count(*) filter (where residual_pub is not null and abs(residual_pub) > 0.01
                       and not (residual_net is not null and abs(residual_net) > 0.01)) as stops_flagged,
    count(*) filter (where not (residual_pub is not null and abs(residual_pub) > 0.01)
                       and residual_net is not null and abs(residual_net) > 0.01) as newly_flagged
  from t;
  ```

- **One grain has eight rows, not nine.** The bridge has 44 grains but 395 rows: `2024-02 / green / N/A` has no `c_congestion` row, because `sum()` over a grain where every trip's `congestion_surcharge` is null yields null, and the unpivot drops the null. So the walk must be summed with `coalesce`, and a test asserting "nine rows per grain" would fail. Any fix keeps this behaviour; the closing test groups and sums rather than counting rows.

  ```sql
  select trip_month, service_type_key, borough_name, count(*) as component_rows
  from finance.mart_revenue_component_bridge
  group by 1,2,3 having count(*) <> 9;
  ```

- **No downstream model or exposure in the repo**, so the consumer of the published shape is outside it: `dbt ls --select mart_revenue_component_bridge+` returns the model and its own `not_null` test only.

- **No run history for the model on this platform**: `list_runs` over 90 days returns 0 runs (`platform_job_runs` unread for `duckdb_local`), so the defect is proven from the built relation, not from a failed run.
