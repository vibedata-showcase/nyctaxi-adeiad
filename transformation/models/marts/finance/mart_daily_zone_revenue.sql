-- Daily revenue by pickup zone, built from the operations daily zone figure
-- rather than a second aggregation of the trip fact (ADR 0018). One source for
-- both the finance report and the ops view.
--
-- The billable rule (ADR 0003) is applied in agg_trip_zone_daily and inherited
-- here: its billable measures are what the report publishes, so nothing in this
-- model filters on is_billable or re-derives the population.
--
-- Zone attributes come from the aggregate too. Joining dim_zone here would fan
-- out: seven zone natural keys carry two versions, so the natural-key join
-- returns two rows for those zone-days and doubles their revenue.
--
-- A zone-day whose trips are all non-billable carries a zero billable count and
-- is not published: it has no revenue to report.
select
    agg.pickup_date as trip_date,
    agg.pickup_location_id,
    agg.borough_name as borough,
    agg.zone_name,
    agg.reporting_region,
    agg.billable_trip_count as trip_count,
    agg.billable_fare_revenue as fare_revenue,
    agg.billable_tip_revenue as tip_revenue,
    agg.billable_surcharge_revenue as surcharge_revenue,
    agg.billable_toll_revenue as toll_revenue,
    agg.billable_revenue as total_revenue
from {{ ref('agg_trip_zone_daily') }} agg
where
    {{ in_report_window('agg.pickup_date') }}
    and agg.billable_trip_count > 0
