-- The matrix closes against the fact: every billable in-window trip is in
-- exactly one cell, and the revenue agrees at the cent (DuckDB float sums are
-- not bit-reproducible, so money is compared rounded). A LEFT join keeps a trip
-- whose zone key matches no dim_zone row, so a drop shows up here as a trip
-- count short of the fact's.
with matrix as (
    select
        sum(billable_trip_count) as trips,
        round(sum(total_revenue), 2) as revenue
    from {{ ref('agg_borough_flow_monthly') }}
),

fact as (
    select
        count(*) as trips,
        round(sum(f.total_amount), 2) as revenue
    from {{ ref('fct_trip') }} f
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
)

select
    m.trips as matrix_trips,
    f.trips as fact_trips,
    m.revenue as matrix_revenue,
    f.revenue as fact_revenue
from matrix m
cross join fact f
where
    m.trips is distinct from f.trips
    or m.revenue is distinct from f.revenue
