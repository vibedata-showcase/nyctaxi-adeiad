-- The share is the origin borough's cross-borough trips over all its trips in
-- the month (ADR 0016), so it must equal that ratio recomputed from the table's
-- own rows, and it must be the same on every row the origin has that month. A
-- row where the two disagree means the share was averaged per pair, or computed
-- over the wrong partition.
with origin_month as (
    select
        trip_month,
        origin_borough,
        sum(cross_borough_trip_count) as cross_trips,
        sum(trip_count) as trips
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1, 2
),

mismatched as (
    select
        t.trip_month,
        t.origin_borough,
        t.dest_borough,
        t.cross_borough_trip_share as published_share,
        o.cross_trips::double / o.trips as expected_share
    from {{ ref('agg_borough_flow_monthly') }} t
    join origin_month o
        on t.trip_month = o.trip_month
        and t.origin_borough = o.origin_borough
)

select *
from mismatched
where
    published_share is distinct from expected_share
    and abs(published_share - expected_share) > 1e-9
