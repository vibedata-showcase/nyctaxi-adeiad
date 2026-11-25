-- The share's parts add up: resolved plus unresolved destination trips equal
-- the origin's whole billable count, on every row, and the cross-borough
-- numerator can never exceed the denominator it divides by.
with checks as (
    select
        month_start_date,
        origin_borough,
        dest_borough,
        origin_resolved_trip_count,
        origin_unresolved_trip_count,
        origin_trip_count,
        cross_borough_trip_count,
        cross_borough_share,
        trip_count,
        is_dest_borough_resolved,
        case when is_dest_borough_resolved then trip_count else 0 end as resolved_trips,
        case when not is_dest_borough_resolved then trip_count else 0 end as unresolved_trips
    from {{ ref('agg_borough_flow_monthly') }}
),

origin_sums as (
    select
        month_start_date,
        origin_borough,
        sum(resolved_trips) as summed_resolved,
        sum(unresolved_trips) as summed_unresolved,
        sum(trip_count) as summed_trips,
        max(origin_resolved_trip_count) as published_resolved,
        max(origin_unresolved_trip_count) as published_unresolved,
        max(origin_trip_count) as published_total,
        max(cross_borough_trip_count) as published_numerator,
        max(cross_borough_share) as published_share
    from checks
    group by 1, 2
)

select
    month_start_date,
    origin_borough,
    summed_trips,
    published_total,
    summed_resolved,
    published_resolved,
    summed_unresolved,
    published_unresolved,
    published_numerator
from origin_sums
where
    summed_resolved + summed_unresolved <> published_total
    or published_resolved + published_unresolved <> published_total
    or summed_resolved <> published_resolved
    or summed_unresolved <> published_unresolved
    or published_numerator > published_resolved
