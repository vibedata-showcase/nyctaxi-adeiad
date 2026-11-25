-- Monthly borough-to-borough flow over the billable trips of the window.
--
-- Both ends of the trip reach dim_zone through the trip's own surrogate keys,
-- so a borough is the one in force on the pickup date (ADR 0009). The joins are
-- LEFT because a trip whose zone key matches no version is still a trip: it
-- groups under the sentinel 'unresolved' instead of disappearing (ADR 0015),
-- the same convention agg_weather_demand_daily uses.
--
-- No trip floor: at borough grain a pair aggregates the zones on each side, so
-- ADR 0017's 25-trip floor stays with the zone-pair matrix (ADR 0019). Every
-- borough name is kept as its own group, the unplaceable ones included, so the
-- rows close against fct_trip's billable population (ADR 0012, ADR 0018).
with trips as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as trip_month,
        coalesce(o.borough_name, 'unresolved') as origin_borough,
        coalesce(d.borough_name, 'unresolved') as dest_borough,
        f.total_amount
    from {{ ref('fct_trip') }} f
    left join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    left join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
),

cells as (
    select
        trip_month,
        origin_borough,
        dest_borough,
        count(*) as billable_trip_count,
        sum(total_amount) as total_revenue,
        count(*) filter (
            where origin_borough is distinct from dest_borough
        ) as cross_trip_count
    from trips
    group by 1, 2, 3
),

-- The crossing question is asked of an origin borough and a month, not of a
-- pair, so both counts are windowed over the origin's own rows: every row of
-- that origin and month carries them and they are never summed across
-- destinations.
origin_month as (
    select
        trip_month,
        origin_borough,
        dest_borough,
        billable_trip_count,
        total_revenue,
        cast(sum(cross_trip_count) over (
            partition by trip_month, origin_borough
        ) as bigint) as cross_borough_trip_count,
        sum(billable_trip_count) over (
            partition by trip_month, origin_borough
        ) as origin_billable_trip_count
    from cells
)

select
    trip_month,
    origin_borough,
    dest_borough,
    billable_trip_count,
    total_revenue,
    cross_borough_trip_count,
    {{ safe_divide('cross_borough_trip_count', 'origin_billable_trip_count') }} as cross_borough_share
from origin_month
