-- Borough-to-borough flow: how much traffic crosses borough lines, and where it
-- crosses. The same zone dimension joined twice, as origin and destination, and
-- then collapsed from zones to borough groups on both sides.
--
-- The grid is the full month x group x group product, so a pair with no trips is
-- published as a zero row rather than left out: a reader comparing boroughs needs
-- the empty cells to see that the traffic is zero, not unknown. Flows carry no
-- trip floor (ADR 0018) -- the floor exists for zone pairs, where a handful of
-- trips is noise, not for seven groups that each carry thousands.
--
-- 'unresolved' collects every trip no zone places in a borough: the lookup's
-- Unknown and N/A boroughs (ADR 0012) and a trip whose zone key matched no zone
-- version (ADR 0015). It is a group of the grid, never a borough, so a row that
-- touches it carries no leaving-borough share.
--
-- The share divides by the month's trips from that origin to its borough
-- destinations, summed from trips (ADR 0016), so within a month a borough's
-- shares over the other boroughs add up to 1. A borough with no borough
-- destination that month has no denominator and publishes null, not zero.

with months as (
    select distinct month_start_date
    from {{ ref('dim_date') }}
    where {{ in_report_window('calendar_date') }}
),

borough_groups as (
    select distinct
        case
            when borough_name in ('Unknown', 'N/A') then 'unresolved'
            else borough_name
        end as borough_group
    from {{ ref('dim_zone') }}

    union

    select 'unresolved' as borough_group
),

grid as (
    select
        m.month_start_date as trip_month,
        o.borough_group as origin_borough,
        d.borough_group as dest_borough
    from months m
    cross join borough_groups o
    cross join borough_groups d
),

observed as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as trip_month,
        case
            when o.borough_name is null or o.borough_name in ('Unknown', 'N/A') then 'unresolved'
            else o.borough_name
        end as origin_borough,
        case
            when d.borough_name is null or d.borough_name in ('Unknown', 'N/A') then 'unresolved'
            else d.borough_name
        end as dest_borough,
        count(*) as trip_count,
        sum(f.total_amount) as total_revenue
    from {{ ref('fct_trip') }} f
    left join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    left join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1, 2, 3
),

flow as (
    select
        g.trip_month,
        g.origin_borough,
        g.dest_borough,
        g.origin_borough = g.dest_borough as is_intra_borough,
        coalesce(x.trip_count, 0) as trip_count,
        coalesce(x.total_revenue, 0) as total_revenue,
        case
            when g.dest_borough = 'unresolved' then 0
            else coalesce(x.trip_count, 0)
        end as trips_to_borough_destinations
    from grid g
    left join observed x
        on
            g.trip_month = x.trip_month
            and g.origin_borough = x.origin_borough
            and g.dest_borough = x.dest_borough
),

with_share as (
    select
        trip_month,
        origin_borough,
        dest_borough,
        is_intra_borough,
        trip_count,
        total_revenue,
        sum(trips_to_borough_destinations) over (
            partition by trip_month, origin_borough
        ) as origin_borough_trips
    from flow
)

select
    trip_month,
    origin_borough,
    dest_borough,
    is_intra_borough,
    trip_count,
    total_revenue,
    case
        when origin_borough = 'unresolved' or dest_borough = 'unresolved' then null
        else {{ safe_divide('trip_count', 'origin_borough_trips') }}
    end as share_of_origin_borough_trips
from with_share
