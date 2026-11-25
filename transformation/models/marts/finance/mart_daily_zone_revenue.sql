-- Daily revenue by pickup zone.
--
-- Reads the operations daily zone rollup rather than rebuilding the same
-- aggregation from the fact, so the warehouse holds one build of these figures
-- instead of two. The billable rule (ADR 0003) is still applied here, in gold,
-- on the rollup's billable measures: a zone-day whose trips were all refunds
-- carries no billable trip and stays out of the report.
select
    a.pickup_date as trip_date,
    a.pickup_location_id,
    a.borough_name as borough,
    a.zone_name,
    a.reporting_region,
    a.billable_trip_count as trip_count,
    a.billable_fare_revenue as fare_revenue,
    a.billable_tip_revenue as tip_revenue,
    a.billable_surcharge_revenue as surcharge_revenue,
    a.billable_toll_revenue as toll_revenue,
    a.billable_total_revenue as total_revenue
from {{ ref('agg_trip_zone_daily') }} a
where
    {{ in_report_window('a.pickup_date') }}
    and a.billable_trip_count > 0
