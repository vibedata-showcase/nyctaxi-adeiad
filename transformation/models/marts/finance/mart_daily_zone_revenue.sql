-- Daily revenue by pickup zone, built from the operations figures in
-- agg_trip_zone_daily rather than from the trip fact, so one build answers the
-- daily zone question for finance and for operations (ADR 0018).
--
-- The billable rule (ADR 0003) and the reporting window are applied upstream by
-- that aggregate, in its billable_* columns; this model selects them. A zone-day
-- with no billable trip is absent rather than published as a zero row, which is
-- why the filter below is on the count and not on the money: such a zone-day has
-- a null sum, not a zero one.
--
-- reporting_region comes from the zone dimension, which the aggregate does not
-- carry. The join carries the date and is half-open, because the dimension is
-- versioned and a natural-key join alone multiplies the zones that have a second
-- version (ADR 0009).
select
    a.pickup_date as trip_date,
    a.pickup_location_id,
    z.borough_name as borough,
    a.zone_name,
    z.reporting_region,
    a.billable_trip_count as trip_count,
    a.billable_fare_revenue as fare_revenue,
    a.billable_tip_revenue as tip_revenue,
    a.billable_surcharge_revenue as surcharge_revenue,
    a.billable_toll_revenue as toll_revenue,
    a.billable_total_revenue as total_revenue
from {{ ref('agg_trip_zone_daily') }} a
left join {{ ref('dim_zone') }} z
    on
        z.zone_natural_key = a.pickup_location_id
        and a.pickup_date >= z.valid_from_date
        and a.pickup_date < z.valid_to_date
where a.billable_trip_count > 0
