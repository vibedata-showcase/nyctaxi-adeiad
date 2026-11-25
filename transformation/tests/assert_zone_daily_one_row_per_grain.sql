-- The grain of the daily zone figure, as a singular test because the key is
-- composite and so carries no per-column generic test. Two rows for one zone
-- and day would double the revenue the finance report reads.
select
    pickup_date,
    pickup_location_id,
    count(*) as rows_at_grain
from {{ ref('agg_trip_zone_daily') }}
group by 1, 2
having count(*) > 1
