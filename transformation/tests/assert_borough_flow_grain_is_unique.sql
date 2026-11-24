-- One row per month, origin borough and destination borough (R-01). A repeated
-- triple means the grid spine fanned out.
select month_start_date, origin_borough, dest_borough, count(*) as row_count
from {{ ref('agg_borough_flow_monthly') }}
group by 1, 2, 3
having count(*) > 1
