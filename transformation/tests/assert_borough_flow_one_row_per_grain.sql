-- The grain the model's description states: one row per month, origin borough
-- and destination borough. `group by all` groups the null destination of a
-- no-pair row as one group, so a duplicated borough-month is caught too.
select trip_month, origin_borough, dest_borough, count(*) as n
from {{ ref('agg_borough_flow_monthly') }}
group by all
having count(*) > 1
