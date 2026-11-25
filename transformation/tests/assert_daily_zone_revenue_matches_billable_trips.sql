-- The report must still equal a billable recomputation from the fact, now that
-- it reads the aggregate instead of filtering the fact itself. This is the test
-- that catches the report drifting from the billable population, and catches the
-- zone join fanning out or dropping a zone-day.
--
-- The population is stated independently of the model: billable trips inside the
-- reporting window, mapped to their pickup zone by natural key. A zone-day with
-- no billable trip appears in neither side. Money is compared at the cent
-- (.agents/skills/dbt-testing, "Comparing values").
with from_report as (

    select
        pickup_location_id,
        trip_date,
        trip_count,
        fare_revenue,
        tip_revenue,
        surcharge_revenue,
        toll_revenue,
        total_revenue
    from {{ ref('mart_daily_zone_revenue') }}

),

from_fact as (

    select
        z.zone_natural_key as pickup_location_id,
        f.pickup_date as trip_date,
        count(*) as trip_count,
        sum(f.fare_amount) as fare_revenue,
        sum(f.tip_amount) as tip_revenue,
        sum(f.total_surcharges) as surcharge_revenue,
        sum(f.tolls_amount) as toll_revenue,
        sum(f.total_amount) as total_revenue
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} z on f.pickup_zone_key = z.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1, 2

),

joined as (

    select
        coalesce(r.pickup_location_id, b.pickup_location_id) as pickup_location_id,
        coalesce(r.trip_date, b.trip_date) as trip_date,
        r.pickup_location_id is null as missing_from_report,
        b.pickup_location_id is null as missing_from_fact,
        r.trip_count as report_trips,
        b.trip_count as fact_trips,
        r.fare_revenue as report_fare,
        b.fare_revenue as fact_fare,
        r.tip_revenue as report_tip,
        b.tip_revenue as fact_tip,
        r.surcharge_revenue as report_surcharge,
        b.surcharge_revenue as fact_surcharge,
        r.toll_revenue as report_toll,
        b.toll_revenue as fact_toll,
        r.total_revenue as report_total,
        b.total_revenue as fact_total
    from from_report r
    full outer join from_fact b
        on
            r.pickup_location_id = b.pickup_location_id
            and r.trip_date = b.trip_date

)

select *
from joined
where
    missing_from_report
    or missing_from_fact
    or report_trips is distinct from fact_trips
    or round(report_fare, 2) is distinct from round(fact_fare, 2)
    or round(report_tip, 2) is distinct from round(fact_tip, 2)
    or round(report_surcharge, 2) is distinct from round(fact_surcharge, 2)
    or round(report_toll, 2) is distinct from round(fact_toll, 2)
    or round(report_total, 2) is distinct from round(fact_total, 2)
