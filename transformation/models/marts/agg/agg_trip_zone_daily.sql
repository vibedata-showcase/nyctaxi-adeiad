-- Daily zone demand, with period-over-period context computed once here rather
-- than in every consuming report. The window functions are the point: a raw
-- daily count answers "how many", and the lag and rolling average answer "is
-- that normal", which is the question anyone actually asks next.
--
-- The billable measures sit beside the all-trip ones because the finance daily
-- zone revenue report reads them from here (ADR 0018). The rule cannot be
-- applied downstream: a non-billable trip carries a negative total, so billable
-- revenue is not an all-trip total minus anything recoverable (ADR 0003).
--
-- The existing columns stay the all-trip figures, in their existing positions,
-- so demand and quality work keeps seeing the trips the rule excludes.
--
-- reporting_region belongs here rather than in a re-join downstream: seven zone
-- natural keys carry two versions, so joining this grain back to dim_zone on the
-- natural key returns two rows and doubles revenue.
with daily as (
    select
        f.pickup_date_key,
        f.pickup_date,
        z.zone_natural_key as pickup_location_id,
        z.zone_name,
        z.borough_name,
        count(*) as trip_count,
        sum(f.total_amount) as total_revenue,
        sum(f.trip_distance) as total_miles,
        count(distinct f.driver_key) as attributed_driver_count,
        z.reporting_region,
        count(*) filter (where f.is_billable) as billable_trip_count,
        coalesce(sum(f.total_amount) filter (where f.is_billable), 0) as billable_revenue,
        coalesce(sum(f.fare_amount) filter (where f.is_billable), 0) as billable_fare_revenue,
        coalesce(sum(f.tip_amount) filter (where f.is_billable), 0) as billable_tip_revenue,
        coalesce(sum(f.total_surcharges) filter (where f.is_billable), 0) as billable_surcharge_revenue,
        coalesce(sum(f.tolls_amount) filter (where f.is_billable), 0) as billable_toll_revenue
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} z on f.pickup_zone_key = z.zone_key
    where {{ in_report_window('f.pickup_datetime') }}
    group by 1, 2, 3, 4, 5, 10
)

select
    d.pickup_date_key,
    d.pickup_date,
    d.pickup_location_id,
    d.zone_name,
    d.borough_name,
    d.trip_count,
    d.total_revenue,
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
    ) as revenue_rank_that_day,
    d.reporting_region,
    d.billable_trip_count,
    d.billable_revenue,
    d.billable_fare_revenue,
    d.billable_tip_revenue,
    d.billable_surcharge_revenue,
    d.billable_toll_revenue
from daily d
window w as (partition by d.pickup_location_id order by d.pickup_date)
