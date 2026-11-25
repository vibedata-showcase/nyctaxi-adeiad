-- The morning report must be exactly the aggregate's billable population, with
-- nothing added, dropped, relabelled or re-rounded. The mart is now a
-- projection of agg_trip_zone_daily, so the two can only disagree if someone
-- changes one side's filter, grouping or arithmetic without the other.
--
-- Money is compared at the cent and counts exactly: DuckDB float aggregation is
-- not reproducible bit for bit, so a raw double comparison would report noise as
-- a defect (dbt-testing).
with mart as (
    select
        trip_date,
        pickup_location_id,
        zone_name,
        borough,
        reporting_region,
        trip_count,
        fare_revenue,
        tip_revenue,
        surcharge_revenue,
        toll_revenue,
        total_revenue
    from {{ ref('mart_daily_zone_revenue') }}
),

agg as (
    select
        pickup_date as trip_date,
        pickup_location_id,
        zone_name,
        borough_name as borough,
        reporting_region,
        billable_trip_count as trip_count,
        billable_fare_revenue as fare_revenue,
        billable_tip_revenue as tip_revenue,
        billable_surcharge_revenue as surcharge_revenue,
        billable_toll_revenue as toll_revenue,
        billable_total_revenue as total_revenue
    from {{ ref('agg_trip_zone_daily') }}
    where billable_trip_count > 0
)

select
    coalesce(m.trip_date, a.trip_date) as trip_date,
    coalesce(m.pickup_location_id, a.pickup_location_id) as pickup_location_id,
    case when m.trip_date is null then 'report row missing from the aggregate population'
        when a.trip_date is null then 'aggregate row missing from the report'
        else 'value mismatch' end as finding
from mart m
full outer join agg a
    on m.trip_date = a.trip_date and m.pickup_location_id = a.pickup_location_id
where
    m.trip_date is null
    or a.trip_date is null
    or m.zone_name is distinct from a.zone_name
    or m.borough is distinct from a.borough
    or m.reporting_region is distinct from a.reporting_region
    or m.trip_count is distinct from a.trip_count
    or abs(m.fare_revenue - a.fare_revenue) > 0.005
    or abs(m.tip_revenue - a.tip_revenue) > 0.005
    or abs(m.surcharge_revenue - a.surcharge_revenue) > 0.005
    or abs(m.toll_revenue - a.toll_revenue) > 0.005
    or abs(m.total_revenue - a.total_revenue) > 0.005
