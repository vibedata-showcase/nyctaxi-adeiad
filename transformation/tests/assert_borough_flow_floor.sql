-- A published borough pair is a pair with at least 25 billable trips in its
-- month (ADR 0018), and the row that stands in for a borough-month with no
-- qualifying pair carries no trips and no revenue. Either violation means a
-- third population slipped into the relation.
select trip_month, origin_borough, dest_borough, trip_count, total_revenue
from {{ ref('agg_borough_flow_monthly') }}
where
    (dest_borough is not null and trip_count < 25)
    or (dest_borough is null and (trip_count <> 0 or total_revenue <> 0))
