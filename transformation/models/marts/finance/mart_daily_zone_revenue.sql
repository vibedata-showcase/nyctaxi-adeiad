-- Daily revenue by pickup zone, projected from the Domain's single zone x day
-- build. The billable rule (ADR 0003) and the reporting window are applied once,
-- there and nowhere else (ADR 0018), so this report and Operations' daily zone
-- figures cannot disagree.
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
    cast(a.billable_revenue as double) as total_revenue
from {{ ref('agg_trip_zone_daily') }} a
where a.billable_trip_count > 0
