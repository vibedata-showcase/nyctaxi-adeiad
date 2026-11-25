-- The cross-borough share is a ratio of the origin borough-month's own sums
-- (ADR 0016), and the cross-borough count is zero exactly on a same-borough
-- row. Both are recomputed here from the table's raw counts, so an average of
-- per-pair ratios, or a share partitioned by the wrong key, is caught.
with recomputed as (
    select
        trip_month,
        origin_borough,
        dest_borough,
        trip_count,
        cross_borough_trip_count,
        cross_borough_share,
        sum(cross_borough_trip_count) over w / sum(trip_count) over w as expected_share
    from {{ ref('agg_borough_flow_monthly') }}
    window w as (partition by trip_month, origin_borough)
)

select
    trip_month,
    origin_borough,
    dest_borough,
    cross_borough_trip_count,
    cross_borough_share,
    expected_share
from recomputed
where
    (origin_borough = dest_borough and cross_borough_trip_count <> 0)
    or (origin_borough <> dest_borough and cross_borough_trip_count = 0)
    or abs(cross_borough_share - expected_share) > 1e-9
