-- Every borough that carries in-window billable trips appears in the matrix as
-- the role it plays, and no published cell is empty.
with sides as (
    select
        o.borough_name as borough,
        'origin' as role,
        count(*) as trips
    from {{ ref('fct_trip') }} f
    inner join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1

    union all

    select
        d.borough_name,
        'destination',
        count(*)
    from {{ ref('fct_trip') }} f
    inner join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1
),

published as (
    select distinct origin_borough from {{ ref('agg_borough_flow_monthly') }}
),

published_dest as (
    select distinct dest_borough from {{ ref('agg_borough_flow_monthly') }}
)

select s.role, s.borough, s.trips
from sides s
where
    s.role = 'origin' and s.borough not in (select origin_borough from published)
    or s.role = 'destination' and s.borough not in (select dest_borough from published_dest)

union all

-- A published cell holds at least one trip: no floor suppresses a thin pair
-- (ADR 0019).
select
    'cell' as role,
    origin_borough || ' -> ' || dest_borough as borough,
    trip_count as trips
from {{ ref('agg_borough_flow_monthly') }}
where trip_count < 1
