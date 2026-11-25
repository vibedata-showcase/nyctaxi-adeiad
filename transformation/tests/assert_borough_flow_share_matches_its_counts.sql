-- The share is a ratio of two sums (ADR 0016), so it must agree with the two
-- counts published beside it, and those counts must agree with the table's own
-- rows for that origin borough and month. A mean of row-level shares, a count
-- taken at the wrong grain, or a verdict left populated on a trip that touches
-- an unplaced zone shows here.
--
-- An unresolved origin has no located base to take a share over, so its counts
-- and its share are null (ADR 0012); every origin is compared, so a stray value
-- there fails too.
with recomputed as (
    select
        month_start_date,
        origin_borough,
        sum(case when dest_borough = 'unresolved' then 0 else trip_count end) as located_trips,
        sum(case when is_cross_borough then trip_count else 0 end) as cross_trips
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1, 2
),

expected as (
    select
        month_start_date,
        origin_borough,
        case
            when origin_borough = 'unresolved' then null
            else located_trips
        end as expected_located_trips,
        case
            when origin_borough = 'unresolved' then null
            else cross_trips
        end as expected_cross_trips,
        case
            when origin_borough = 'unresolved' or located_trips = 0 then null
            else cross_trips::double / located_trips
        end as expected_share
    from recomputed
),

checked as (
    select
        r.month_start_date,
        r.origin_borough,
        r.dest_borough,
        r.trip_count,
        r.is_cross_borough,
        r.origin_located_trip_count,
        e.expected_located_trips,
        r.origin_cross_borough_trip_count,
        e.expected_cross_trips,
        r.cross_borough_trip_share,
        e.expected_share,
        case
            when r.origin_borough = 'unresolved' or r.dest_borough = 'unresolved' then null
            else r.origin_borough <> r.dest_borough
        end as expected_cross_borough
    from {{ ref('agg_borough_flow_monthly') }} r
    join expected e
        on r.month_start_date = e.month_start_date and r.origin_borough = e.origin_borough
)

select
    month_start_date,
    origin_borough,
    dest_borough,
    trip_count,
    is_cross_borough,
    expected_cross_borough,
    origin_located_trip_count,
    expected_located_trips,
    origin_cross_borough_trip_count,
    expected_cross_trips,
    cross_borough_trip_share,
    expected_share
from checked
where
    is_cross_borough is distinct from expected_cross_borough
    or origin_located_trip_count is distinct from expected_located_trips
    or origin_cross_borough_trip_count is distinct from expected_cross_trips
    or (cross_borough_trip_share is null) <> (expected_share is null)
    or abs(cross_borough_trip_share - expected_share) > 0.000000001
