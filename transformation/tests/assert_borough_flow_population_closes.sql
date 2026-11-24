-- The table's trips and revenue are the window's billable trips that touch
-- neither EWR, no more and no less, and every combination of the spine is
-- published.
--
-- Recomputed from fct_trip and the two dimensions here rather than trusted
-- from the model, so a filter that drifted -- a missing is_billable, an EWR
-- member that slipped back in, a member group that split -- shows as a
-- mismatch instead of a green build. The row count is derived from the window
-- and the members, not written as a constant, so moving the reporting window
-- or re-designating a borough does not fail a test that is still right.
-- Money is compared at the cent, because DuckDB float aggregation is not
-- reproducible bit for bit.
with fact as (
    select
        count(*) as trip_count,
        round(sum(f.total_amount), 2) as revenue
    from {{ ref('fct_trip') }} f
    inner join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    inner join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
        and (o.is_nyc or o.is_unresolved_zone)
        and (d.is_nyc or d.is_unresolved_zone)
),

months as (
    select distinct m.month_start_date
    from {{ ref('dim_date') }} m
    where {{ in_report_window('m.calendar_date') }}
),

members as (
    select distinct
        case when z.is_unresolved_zone then 'unresolved' else z.borough_name end as member
    from {{ ref('dim_zone') }} z
    where z.is_nyc or z.is_unresolved_zone
),

expected_spine as (
    select count(*) as row_count
    from months
    cross join members as origins
    cross join members as destinations
),

published as (
    select
        sum(trip_count) as trip_count,
        round(sum(revenue), 2) as revenue,
        count(*) as row_count,
        count(*) filter (where trip_count = 0) as zero_rows,
        count(*) filter (where trip_count > 0) as populated_rows
    from {{ ref('agg_borough_flow_matrix') }}
)

select
    f.trip_count as fact_trips,
    p.trip_count as published_trips,
    f.revenue as fact_revenue,
    p.revenue as published_revenue,
    s.row_count as expected_rows,
    p.row_count as published_rows,
    p.zero_rows,
    p.populated_rows
from fact f
cross join published p
cross join expected_spine s
where
    f.trip_count is distinct from p.trip_count
    or f.revenue is distinct from p.revenue
    or p.row_count is distinct from s.row_count
    or p.zero_rows + p.populated_rows != p.row_count
