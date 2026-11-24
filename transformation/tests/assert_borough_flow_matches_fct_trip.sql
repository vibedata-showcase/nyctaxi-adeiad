-- The table publishes every billable trip of the reporting window, so its totals
-- equal the star's (ADR 0018). A floor, a dropped join row or a duplicated group
-- would show here. Money is compared at the cent, since two builds of a double
-- need not agree in the last bits.
with published as (
    select
        sum(trip_count) as trips,
        round(sum(total_revenue), 2) as revenue
    from {{ ref('agg_borough_flow_monthly') }}
),

fact as (
    select
        count(*) as trips,
        round(sum(total_amount), 2) as revenue
    from {{ ref('fct_trip') }}
    where
        {{ in_report_window('pickup_datetime') }}
        and is_billable
)

select
    p.trips as published_trips,
    f.trips as fact_trips,
    p.revenue as published_revenue,
    f.revenue as fact_revenue
from published p
cross join fact f
where p.trips is distinct from f.trips or p.revenue is distinct from f.revenue
