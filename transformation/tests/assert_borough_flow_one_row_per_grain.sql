-- The table's grain, as its description states it: one row per month, origin
-- borough and destination borough. A repeated triple means the spine fanned
-- out, or the trips were aggregated at a coarser key.
select
    month_start_date,
    origin_borough,
    destination_borough,
    count(*) as n
from {{ ref('agg_borough_flow_matrix') }}
group by 1, 2, 3
having count(*) > 1
