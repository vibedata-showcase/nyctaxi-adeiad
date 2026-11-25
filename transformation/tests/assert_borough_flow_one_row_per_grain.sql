-- The grain, as the model's description states it: one row per trip month,
-- origin borough group and destination borough group.
select
    trip_month,
    origin_borough,
    dest_borough,
    count(*) as n
from {{ ref('agg_borough_flow_monthly') }}
group by 1, 2, 3
having count(*) > 1
