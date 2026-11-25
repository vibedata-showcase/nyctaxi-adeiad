-- The published pairs plus the pairs the floor removes account for every
-- billable trip and every dollar of billable revenue, recalculated here from
-- fct_trip and dim_zone rather than read back through the model's own CTEs
-- (ADR 0018 states the partiality; this proves its size). Revenue compares at
-- the cent, because DuckDB float aggregation is not bit for bit reproducible.
with fact_pairs as (
    select
        cast(date_trunc('month', f.pickup_datetime) as date) as trip_month,
        o.borough_name as origin_borough,
        d.borough_name as dest_borough,
        count(*) as trip_count,
        sum(f.total_amount) as total_revenue
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1, 2, 3
),

expected as (
    select
        sum(trip_count) filter (where trip_count >= 25) as published_trips,
        sum(trip_count) filter (where trip_count < 25) as floored_out_trips,
        round(sum(total_revenue) filter (where trip_count >= 25), 2) as published_revenue,
        round(sum(total_revenue) filter (where trip_count < 25), 2) as floored_out_revenue,
        sum(trip_count) as fact_trips,
        round(sum(total_revenue), 2) as fact_revenue
    from fact_pairs
),

built as (
    select
        sum(trip_count) as model_trips,
        round(sum(total_revenue), 2) as model_revenue
    from {{ ref('agg_borough_flow_monthly') }}
)

select
    e.published_trips as expected_trips,
    b.model_trips,
    e.fact_trips,
    e.floored_out_trips as expected_remainder,
    e.published_revenue as expected_revenue,
    b.model_revenue,
    e.fact_revenue,
    e.floored_out_revenue as expected_revenue_remainder
from expected e
cross join built b
where
    b.model_trips is distinct from e.published_trips
    or e.published_trips + e.floored_out_trips is distinct from e.fact_trips
    or b.model_revenue is distinct from e.published_revenue
    or e.published_revenue + e.floored_out_revenue is distinct from e.fact_revenue
