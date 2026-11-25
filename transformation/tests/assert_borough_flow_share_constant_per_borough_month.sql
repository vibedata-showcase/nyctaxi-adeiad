-- The crossing share belongs to the borough-month, not to a pair (ADR 0019), so
-- the three origin_* columns must read the same on every row of a borough-month.
-- A row that disagrees was computed from its pair rather than from the whole
-- traffic, which is the mistake this relation exists to avoid.
select
    trip_month,
    origin_borough,
    count(distinct origin_departing_trip_count) as departing_values,
    count(distinct origin_crossing_trip_count) as crossing_values,
    count(distinct origin_crossing_trip_share) as share_values
from {{ ref('agg_borough_flow_monthly') }}
group by 1, 2
having
    count(distinct origin_departing_trip_count) > 1
    or count(distinct origin_crossing_trip_count) > 1
    or count(distinct origin_crossing_trip_share) > 1
