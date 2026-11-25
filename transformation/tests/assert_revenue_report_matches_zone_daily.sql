-- Every published cell must equal the billable cell the aggregate holds for the
-- same zone and day: the report is a projection of that relation and nothing
-- else (ADR 0018), so a difference means a mapping error the reader would see
-- as a changed number. Money is compared at the cent, because DuckDB float
-- aggregation is not reproducible bit for bit.
--
-- The two directions are checked together: a published row the aggregate does
-- not carry would be invented, and an aggregate row with a billable trip the
-- report dropped would be a silent loss.
with published as (
    select * from {{ ref('mart_daily_zone_revenue') }}
),

expected as (
    select
        pickup_date as trip_date,
        pickup_location_id,
        borough_name as borough,
        zone_name,
        reporting_region,
        billable_trip_count as trip_count,
        billable_fare_revenue as fare_revenue,
        billable_tip_revenue as tip_revenue,
        billable_surcharge_revenue as surcharge_revenue,
        billable_toll_revenue as toll_revenue,
        billable_revenue as total_revenue
    from {{ ref('agg_trip_zone_daily') }}
    where
        {{ in_report_window('pickup_date') }}
        and billable_trip_count > 0
)

select
    coalesce(p.trip_date, e.trip_date) as trip_date,
    coalesce(p.pickup_location_id, e.pickup_location_id) as pickup_location_id,
    case
        when p.pickup_location_id is null then 'missing from the report'
        when e.pickup_location_id is null then 'not in the aggregate'
        else 'values differ'
    end as failure,
    p.trip_count as published_trip_count,
    e.trip_count as expected_trip_count,
    p.total_revenue as published_total_revenue,
    e.total_revenue as expected_total_revenue
from published p
full outer join expected e
    on
        p.trip_date = e.trip_date
        and p.pickup_location_id = e.pickup_location_id
where
    p.pickup_location_id is null
    or e.pickup_location_id is null
    or p.trip_count is distinct from e.trip_count
    or round(p.total_revenue, 2) is distinct from round(e.total_revenue, 2)
    or round(p.fare_revenue, 2) is distinct from round(e.fare_revenue, 2)
    or round(p.tip_revenue, 2) is distinct from round(e.tip_revenue, 2)
    or round(p.surcharge_revenue, 2) is distinct from round(e.surcharge_revenue, 2)
    or round(p.toll_revenue, 2) is distinct from round(e.toll_revenue, 2)
    or p.borough is distinct from e.borough
    or p.zone_name is distinct from e.zone_name
    or p.reporting_region is distinct from e.reporting_region
