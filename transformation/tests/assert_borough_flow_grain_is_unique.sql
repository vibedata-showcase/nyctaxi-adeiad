-- The grain is the three columns together, and no dbt_utils is installed to
-- assert a composite key, so it is proven here: one row per month, origin
-- borough and destination borough.
select
    trip_month,
    origin_borough,
    destination_borough,
    count(*) as row_count
from {{ ref('agg_borough_flow_monthly') }}
group by 1, 2, 3
having count(*) > 1
