-- Daily zone demand, with period-over-period context computed once here rather
-- than in every consuming report. The window functions are the point: a raw
-- daily count answers "how many", and the lag and rolling average answer "is
-- that normal", which is the question anyone actually asks next.
--
-- The billable measures (ADR 0003) are aggregated here, in one scan with the
-- all-trips ones, so the revenue report and the demand aggregate read one
-- build. A zone-day whose trips are all non-billable keeps its row with zeros:
-- the trips happened, none of them is billable, and a consumer summing the
-- column needs no coalesce.
with daily as (
    select
        f.pickup_date_key,
        f.pickup_date,
        z.zone_natural_key as pickup_location_id,
        z.zone_name,
        z.borough_name,
        z.reporting_region,
        cast(count(*) as bigint) as trip_count,
        cast(sum(f.total_amount) as double) as total_revenue,
        cast(coalesce(
            count(*) filter (where f.is_billable), 0
        ) as bigint) as billable_trip_count,
        cast(coalesce(
            sum(f.fare_amount) filter (where f.is_billable), 0
        ) as double) as billable_fare_revenue,
        cast(coalesce(
            sum(f.tip_amount) filter (where f.is_billable), 0
        ) as double) as billable_tip_revenue,
        cast(coalesce(
            sum(f.total_surcharges) filter (where f.is_billable), 0
        ) as double) as billable_surcharge_revenue,
        cast(coalesce(
            sum(f.tolls_amount) filter (where f.is_billable), 0
        ) as double) as billable_toll_revenue,
        cast(coalesce(
            sum(f.total_amount) filter (where f.is_billable), 0
        ) as double) as billable_total_revenue,
        cast(sum(f.trip_distance) as double) as total_miles,
        cast(count(distinct f.driver_key) as bigint) as attributed_driver_count
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} z on f.pickup_zone_key = z.zone_key
    where {{ in_report_window('f.pickup_datetime') }}
    group by 1, 2, 3, 4, 5, 6
)

select
    d.pickup_date_key,
    d.pickup_date,
    d.pickup_location_id,
    d.zone_name,
    d.borough_name,
    d.reporting_region,
    d.trip_count,
    d.total_revenue,
    d.billable_trip_count,
    d.billable_fare_revenue,
    d.billable_tip_revenue,
    d.billable_surcharge_revenue,
    d.billable_toll_revenue,
    d.billable_total_revenue,
    d.total_miles,
    d.attributed_driver_count,
    lag(d.trip_count, 1) over w as prev_day_trip_count,
    lag(d.trip_count, 7) over w as same_day_last_week_trip_count,
    avg(d.trip_count) over (
        partition by d.pickup_location_id
        order by d.pickup_date
        rows between 6 preceding and current row
    ) as trip_count_7d_avg,
    sum(d.total_revenue) over (
        partition by d.pickup_location_id
        order by d.pickup_date
        rows between 27 preceding and current row
    ) as revenue_28d_rolling,
    rank() over (
        partition by d.pickup_date order by d.total_revenue desc
    ) as revenue_rank_that_day
from daily d
window w as (partition by d.pickup_location_id order by d.pickup_date)
