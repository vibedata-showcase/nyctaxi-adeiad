-- The share is the origin month's cross-borough trips over its own trips, and
-- the denominator is the whole origin month, not just the cells that carry
-- traffic. Two things are asserted: each row's share equals the value its own
-- published numerator and denominator give, and an origin's rows sum to the
-- denominator they divide by.
select
    trip_month,
    origin_borough,
    destination_borough,
    'share does not recompute' as failure
from {{ ref('agg_borough_flow_monthly') }}
where
    abs(
        outbound_cross_borough_share
        - cast(cross_borough_trip_count as double) / nullif(cast(origin_trip_count as double), 0)
    ) > 1e-9
    or outbound_cross_borough_share < 0
    or outbound_cross_borough_share > 1

union all

select
    trip_month,
    origin_borough,
    null as destination_borough,
    'cells do not sum to the origin denominator' as failure
from {{ ref('agg_borough_flow_monthly') }}
group by trip_month, origin_borough, origin_trip_count, cross_borough_trip_count
having
    sum(trip_count) <> origin_trip_count
    or sum(case when is_cross_borough then trip_count else 0 end) <> cross_borough_trip_count
