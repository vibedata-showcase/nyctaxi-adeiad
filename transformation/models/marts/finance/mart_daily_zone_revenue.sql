-- Daily revenue by pickup zone, for the finance team's morning report.
--
-- The billable rule (ADR 0003) is applied once, upstream in
-- `agg_trip_zone_daily`, which publishes the billable-only measures this report
-- reads. It is not applied here: the aggregate holds no per-trip verdict, and
-- applying the rule a second time is the duplicate build this report exists to
-- remove.
--
-- The one choice this model makes is its population: a zone-day reaches the
-- report only when it has at least one billable trip. The aggregate keeps the
-- zone-days whose trips were all non-billable, so operations still sees demand
-- that earned nothing; the morning report omits them, as it always has.
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
where a.billable_trip_count > 0
