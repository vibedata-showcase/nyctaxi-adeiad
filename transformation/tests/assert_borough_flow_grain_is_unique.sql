-- The grain, as the design record states it: one row per month, origin borough
-- and destination borough.
select
    month_start_date,
    origin_borough,
    destination_borough,
    count(*) as row_count
from {{ ref('agg_borough_flow_monthly') }}
group by 1, 2, 3
having count(*) > 1
