-- Every billable trip in the window lands in exactly one borough pair, and no
-- trip lands twice: the table applies no floor (ADR 0018), so each month's
-- trip_count must be the month's billable fact rows rather than a subset.
-- `is distinct from` keeps an empty month honest, where `!=` on NULLs passes.
with monthly as (
    select
        trip_month,
        sum(trip_count) as trips,
        sum(cross_borough_trip_count) as cross_borough_trips
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1
),

fact as (
    select
        cast(date_trunc('month', pickup_datetime) as date) as trip_month,
        count(*) as trips
    from {{ ref('fct_trip') }}
    where
        {{ in_report_window('pickup_datetime') }}
        and is_billable
        and pickup_zone_key is not null
        and dropoff_zone_key is not null
    group by 1
)

select
    coalesce(m.trip_month, f.trip_month) as trip_month,
    m.trips as table_trips,
    f.trips as fact_trips
from monthly m
full outer join fact f on m.trip_month = f.trip_month
where m.trips is distinct from f.trips
