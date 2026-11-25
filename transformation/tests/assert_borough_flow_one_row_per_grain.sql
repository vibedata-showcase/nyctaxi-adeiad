-- One row per month, origin borough and destination borough, with no key null.
select trip_month, origin_borough, dest_borough, count(*) as row_count
from {{ ref('agg_borough_flow_monthly') }}
group by 1, 2, 3
having count(*) > 1
    or trip_month is null
    or origin_borough is null
    or dest_borough is null
