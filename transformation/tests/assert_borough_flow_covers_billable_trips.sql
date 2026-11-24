-- The table's totals close against the fact: every billable trip picked up in
-- the reporting window reaches exactly one row, whatever its boroughs resolve
-- to, and no quality verdict removes one (ADR 0004). A shortfall here means the
-- Unresolved group or a verdict filter was taken out of the totals, which breaks
-- the tie to billable_revenue.
with model_totals as (
    select
        sum(trip_count) as trips,
        sum(total_revenue) as revenue
    from {{ ref('agg_borough_flow_monthly') }}
),

fact_totals as (
    select
        count(*) as trips,
        sum(total_amount) as revenue
    from {{ ref('fct_trip') }}
    where
        {{ in_report_window('pickup_datetime') }}
        and is_billable
)

select
    m.trips as model_trips,
    f.trips as fact_trips,
    m.revenue as model_revenue,
    f.revenue as fact_revenue
from model_totals m
cross join fact_totals f
where
    m.trips is distinct from f.trips
    or abs(coalesce(m.revenue, 0) - coalesce(f.revenue, 0)) > 0.01
