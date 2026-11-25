-- Daily revenue by pickup zone.
--
-- The billable rule (ADR 0003) and the reporting window are applied once, in
-- agg_trip_zone_daily, and this mart selects them: the operations aggregate and
-- this report read one build instead of each scanning the trip fact.
--
-- The only filter here is billable_trip_count > 0. A zone-day whose trips are
-- all non-billable is in the aggregate with zeros and is not part of this
-- report, which publishes a row only where a billable trip was picked up. The
-- columns keep the report's own names, so no consumer's query changes.
select
    cast(a.pickup_date as date) as trip_date,
    cast(a.pickup_location_id as bigint) as pickup_location_id,
    cast(a.borough_name as varchar) as borough,
    cast(a.zone_name as varchar) as zone_name,
    cast(a.reporting_region as varchar) as reporting_region,
    cast(a.billable_trip_count as bigint) as trip_count,
    cast(a.billable_fare_revenue as double) as fare_revenue,
    cast(a.billable_tip_revenue as double) as tip_revenue,
    cast(a.billable_surcharge_revenue as double) as surcharge_revenue,
    cast(a.billable_toll_revenue as double) as toll_revenue,
    cast(a.billable_total_revenue as double) as total_revenue
from {{ ref('agg_trip_zone_daily') }} a
where a.billable_trip_count > 0
