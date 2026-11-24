-- Trips and revenue per pair-month are the billable, in-window trips between
-- those two boroughs (R-03, R-07). Recomputed here straight from fct_trip and
-- dim_zone, independent of the model's own CTEs; revenue is compared at the cent
-- and a zero cell counts as zero on both sides.
with expected as (
    select
        cast(date_trunc('month', f.pickup_datetime) as date) as month_start_date,
        o.borough_name as origin_borough,
        dz.borough_name as dest_borough,
        count(*) as trip_count,
        sum(f.total_amount) as total_revenue
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    join {{ ref('dim_zone') }} dz on f.dropoff_zone_key = dz.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1, 2, 3
),

actual as (
    select month_start_date, origin_borough, dest_borough, trip_count, total_revenue
    from {{ ref('agg_borough_flow_monthly') }}
    where trip_count > 0
)

select
    coalesce(a.month_start_date, e.month_start_date) as month_start_date,
    coalesce(a.origin_borough, e.origin_borough) as origin_borough,
    coalesce(a.dest_borough, e.dest_borough) as dest_borough,
    e.trip_count as expected_trips,
    a.trip_count as actual_trips,
    e.total_revenue as expected_revenue,
    a.total_revenue as actual_revenue
from actual a
full outer join expected e
    on
        a.month_start_date = e.month_start_date
        and a.origin_borough = e.origin_borough
        and a.dest_borough = e.dest_borough
where
    coalesce(a.trip_count, 0) is distinct from coalesce(e.trip_count, 0)
    or abs(coalesce(a.total_revenue, 0) - coalesce(e.total_revenue, 0)) >= 0.01
