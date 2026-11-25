-- The table's grain: one row per month, origin borough and destination borough.
-- No single column is unique, so the composite is proven here rather than by a
-- column test.
select
    month_start_date,
    origin_borough,
    dest_borough,
    count(*) as n
from {{ ref('agg_borough_flow_monthly') }}
group by 1, 2, 3
having count(*) > 1
