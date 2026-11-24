-- Daily zone demand, with period-over-period context computed once here rather
-- than in every consuming report. The window functions are the point: a raw
-- daily count answers "how many", and the lag and rolling average answer "is
-- that normal", which is the question anyone actually asks next.
--
-- The Domain's single zone x day build. The billable rule (ADR 0003) and the
-- reporting window are evaluated here, once, and the finance report selects the
-- billable measures rather than re-deriving them (ADR 0018). The all-trips
-- measures are unchanged: trip_count and total_revenue still count every
-- in-window trip, and the window expressions below still use them.
--
--
-- A zone-day with trips but no billable trip reads 0, not null: sum() over no
-- rows is null, and 0 unambiguously means "no billable trips" here because a
-- billable trip has a positive total by definition.
with daily as (
    select
        f.pickup_date_key,
        f.pickup_date,
        z.zone_natural_key as pickup_location_id,
        z.zone_name,
        z.borough_name,
        z.reporting_region,
        count(*) as trip_count,
        sum(f.total_amount) as total_revenue,
        sum(f.trip_distance) as total_miles,
        count(distinct f.driver_key) as attributed_driver_count,
        count(*) filter (where f.is_billable) as billable_trip_count,
        coalesce(sum(f.total_amount) filter (where f.is_billable), 0) as billable_revenue,
        coalesce(sum(f.fare_amount) filter (where f.is_billable), 0) as billable_fare_revenue,
        coalesce(sum(f.tip_amount) filter (where f.is_billable), 0) as billable_tip_revenue,
        coalesce(
            sum(f.total_surcharges) filter (where f.is_billable), 0
        ) as billable_surcharge_revenue,
        coalesce(sum(f.tolls_amount) filter (where f.is_billable), 0) as billable_toll_revenue
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} z on f.pickup_zone_key = z.zone_key
    where {{ in_report_window('f.pickup_datetime') }}
    group by 1, 2, 3, 4, 5, 6
)

select
    d.*,
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
