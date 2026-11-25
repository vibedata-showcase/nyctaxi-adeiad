-- The grain of agg_borough_flow_monthly is one row per month, origin borough
-- and destination borough, so a repeated triple means the group by lost a key.
select
    trip_month,
    origin_borough,
    dest_borough,
    count(*) as row_count
from {{ ref('agg_borough_flow_monthly') }}
group by 1, 2, 3
having count(*) > 1
