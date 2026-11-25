-- The table's grain, as its description states it: one row per pickup month,
-- origin borough and destination borough.
select trip_month, origin_borough, destination_borough, count(*) as n
from {{ ref('agg_borough_flow_monthly') }}
group by 1, 2, 3
having count(*) > 1
