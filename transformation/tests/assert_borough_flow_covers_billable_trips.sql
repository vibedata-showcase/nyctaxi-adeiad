-- Every billable trip in the window is accounted for, month by month: the pairs
-- published plus the trips no zone version places are the month's billable
-- trips, and the revenue closes at the cent. This is the population check behind
-- ADR 0019: with no floor the matrix must reconcile to the star, and a month
-- that drifts means either a pair was dropped or the unplaced count stopped
-- meaning what its column says.
--
-- `is distinct from` keeps the comparison honest when a month is missing from
-- either side, where a bare `!=` on NULLs would pass.
with flow as (
    select
        month_start_date,
        sum(billable_trip_count) as flow_trips,
        round(sum(billable_revenue), 2) as flow_revenue,
        max(month_unplaced_billable_trip_count) as unplaced_trips
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1
),

fact as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as month_start_date,
        count(*) as fact_trips,
        round(sum(f.total_amount), 2) as fact_revenue,
        count(*) filter (
            where f.pickup_zone_key is null or f.dropoff_zone_key is null
        ) as unplaced_trips
    from {{ ref('fct_trip') }} f
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1
)

select
    coalesce(f.month_start_date, fl.month_start_date) as month_start_date,
    f.fact_trips,
    f.fact_revenue,
    f.unplaced_trips as fact_unplaced_trips,
    fl.flow_trips,
    fl.flow_revenue,
    fl.unplaced_trips as flow_unplaced_trips
from fact f
full outer join flow fl on f.month_start_date = fl.month_start_date
where
    f.fact_trips is distinct from coalesce(fl.flow_trips, 0) + coalesce(fl.unplaced_trips, 0)
    or f.unplaced_trips is distinct from fl.unplaced_trips
    or f.fact_revenue is distinct from fl.flow_revenue
