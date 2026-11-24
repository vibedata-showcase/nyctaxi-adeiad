-- Borough-to-borough flow, one row per month and origin-destination pair.
--
-- The same zone dimension joined twice, as in agg_od_flow_matrix, but rolled to
-- the borough and published on a spine rather than filtered: every month of the
-- reporting window crossed with every member on each side, so a pair that
-- carried no trip keeps its row at zero and a reader never has to read a
-- missing row as "no traffic" (ADR 0018).
--
-- The members are the five New York City boroughs plus one unresolved group on
-- each side. Membership is decided by dim_zone's own flags, never by the
-- borough labels: `is_unresolved_zone` marks the zones TLC cannot place in a
-- borough, and the two such zones form the one unresolved member (ADR 0012);
-- `is_nyc` keeps EWR, a borough value for a place outside the city, out of the
-- table entirely (ADR 0018).
--
-- Each trip is attributed through its own zone surrogate key, the version in
-- force on its pickup date, so a re-designation does not reassign history
-- (ADR 0009). No quality verdict is read and no trip is dropped for one: the
-- billable rule is the only verdict this population applies (ADR 0003, ADR
-- 0004).
with window_months as (
    select distinct
        d.month_start_date
    from {{ ref('dim_date') }} d
    where {{ in_report_window('d.calendar_date') }}
),

members as (
    select
        case when z.is_unresolved_zone then 'unresolved' else z.borough_name end as borough_name,
        bool_or(z.is_nyc) as is_city_borough
    from {{ ref('dim_zone') }} z
    where z.is_nyc or z.is_unresolved_zone
    group by 1
),

spine as (
    select
        m.month_start_date,
        o.borough_name as origin_borough,
        o.is_city_borough as origin_is_city_borough,
        d.borough_name as destination_borough,
        d.is_city_borough as destination_is_city_borough
    from window_months m
    cross join members o
    cross join members d
),

trips as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as month_start_date,
        case when o.is_unresolved_zone then 'unresolved' else o.borough_name end as origin_borough,
        o.is_nyc as origin_is_city_borough,
        case when d.is_unresolved_zone then 'unresolved' else d.borough_name end as destination_borough,
        d.is_nyc as destination_is_city_borough,
        f.total_amount
    from {{ ref('fct_trip') }} f
    inner join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    inner join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
        and (o.is_nyc or o.is_unresolved_zone)
        and (d.is_nyc or d.is_unresolved_zone)
),

pairs as (
    select
        month_start_date,
        origin_borough,
        destination_borough,
        count(*) as trip_count,
        sum(total_amount) as revenue
    from trips
    group by 1, 2, 3
),

-- The share is one value per origin and month, rebuilt from summed trips
-- rather than averaged across pairs (ADR 0016), and carried on every row of
-- that origin's month. Its denominator is the origin's trips whose destination
-- borough is known: a trip to the unresolved group leaves no borough to
-- measure against, so it is in neither term (ADR 0018).
origin_share as (
    select
        month_start_date,
        origin_borough,
        origin_is_city_borough,
        count(*) filter (
            where
            origin_is_city_borough
            and destination_is_city_borough
            and origin_borough <> destination_borough
        ) as cross_borough_trips,
        count(*) filter (where destination_is_city_borough) as trips_to_known_destination
    from trips
    group by 1, 2, 3
)

select
    s.month_start_date,
    s.origin_borough,
    s.destination_borough,
    case
        when not s.origin_is_city_borough or not s.destination_is_city_borough then 'unresolved'
        when s.origin_borough = s.destination_borough then 'in_borough'
        else 'cross_borough'
    end as flow_class,
    cast(coalesce(p.trip_count, 0) as bigint) as trip_count,
    cast(coalesce(p.revenue, 0) as double) as revenue,
    -- The unresolved group is no borough to leave, so it carries no share at
    -- all: null reads as not applicable where 0 would read as a measured zero
    -- (ADR 0016, ADR 0018). A city borough always carries its two counts, at 0
    -- when it sent nothing, and its share is null exactly when the denominator
    -- is zero -- an empty denominator is not a measured zero.
    case
        when s.origin_is_city_borough then cast(coalesce(sh.cross_borough_trips, 0) as bigint)
    end as origin_cross_borough_trips,
    case
        when s.origin_is_city_borough then cast(coalesce(sh.trips_to_known_destination, 0) as bigint)
    end as origin_trips_to_known_destination,
    case
        when s.origin_is_city_borough
            then {{ safe_divide(
                'cast(coalesce(sh.cross_borough_trips, 0) as double)',
                'cast(coalesce(sh.trips_to_known_destination, 0) as double)'
            ) }}
    end as cross_borough_share
from spine s
left join pairs p
    on
        s.month_start_date = p.month_start_date
        and s.origin_borough = p.origin_borough
        and s.destination_borough = p.destination_borough
left join origin_share sh
    on
        s.month_start_date = sh.month_start_date
        and s.origin_borough = sh.origin_borough
