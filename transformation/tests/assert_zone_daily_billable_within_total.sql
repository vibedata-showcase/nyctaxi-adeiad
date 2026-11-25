-- Two invariants tie the billable measures to the all-trip ones, and both follow
-- from the definition rather than from the SQL: a billable trip is a trip whose
-- total is positive, so the billable count is a subset of the trip count, and
-- every non-billable trip carries a total of zero or less, so adding them back
-- can only lower the revenue. A violation means the filter is wrong and the
-- finance report would publish a figure its own sibling columns contradict.
--
-- `is distinct from` keeps a NULL from passing as agreement.
select
    pickup_date,
    pickup_location_id,
    trip_count,
    billable_trip_count,
    total_revenue,
    billable_revenue
from {{ ref('agg_trip_zone_daily') }}
where
    billable_trip_count is distinct from 0
    and (
        billable_trip_count > trip_count
        or billable_revenue < total_revenue
    )
