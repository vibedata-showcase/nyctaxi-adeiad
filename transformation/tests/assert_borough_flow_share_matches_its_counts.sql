-- The share is the origin borough's cross-borough trips over its own trips in
-- the month, so it is recomputed from the published rows rather than trusted,
-- and every row of one origin and month must carry the same two counts.
with recomputed as (
    select
        trip_month,
        origin_borough,
        sum(case when origin_borough is distinct from dest_borough then trip_count else 0 end) as cross_trips,
        sum(trip_count) as origin_trips,
        count(distinct cross_borough_trip_count) as distinct_cross_counts
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1, 2
),

disagreement as (
    select
        b.trip_month,
        b.origin_borough,
        b.dest_borough,
        b.cross_borough_trip_count as published_cross,
        r.cross_trips as recomputed_cross,
        b.cross_borough_share as published_share,
        r.cross_trips * 1.0 / nullif(r.origin_trips, 0) as recomputed_share
    from {{ ref('agg_borough_flow_monthly') }} b
    inner join recomputed r
        on
            b.trip_month = r.trip_month
            and b.origin_borough = r.origin_borough
    where
        b.cross_borough_trip_count is distinct from r.cross_trips
        or abs(coalesce(b.cross_borough_share, -1) - coalesce(r.cross_trips * 1.0 / nullif(r.origin_trips, 0), -1)) > 1e-9
)

select * from disagreement

union all

-- A row of one origin and month carrying a different count from its siblings
-- would break the sum a consumer reads off the origin.
select
    trip_month,
    origin_borough,
    null as dest_borough,
    distinct_cross_counts as published_cross,
    null as recomputed_cross,
    null as published_share,
    null as recomputed_share
from recomputed
where distinct_cross_counts > 1
