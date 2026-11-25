-- The billable measures are a subset of the all-trips ones: no zone-day may
-- report more billable trips than trips, a negative billable count, or billable
-- revenue on a zone-day with no billable trip. A zone-day with no billable trip
-- keeps its row at zero (ADR 0003 applied per measure), so zero revenue there is
-- the honest value; anything else means the filter and the count disagree.
select
    pickup_date,
    pickup_location_id,
    trip_count,
    billable_trip_count,
    billable_total_revenue
from {{ ref('agg_trip_zone_daily') }}
where
    billable_trip_count < 0
    or billable_trip_count > trip_count
    or (
        billable_trip_count = 0
        and (
            billable_total_revenue <> 0
            or billable_fare_revenue <> 0
            or billable_tip_revenue <> 0
            or billable_surcharge_revenue <> 0
            or billable_toll_revenue <> 0
        )
    )
