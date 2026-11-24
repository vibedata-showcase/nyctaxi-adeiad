-- Every billable trip in the reporting window appears exactly once in the
-- borough flow, and the revenue reconciles too. Recomputed from fct_trip and
-- dim_zone rather than from the mart's own filter, so a population that shrank
-- -- a trip floor, an inner join, a verdict filter -- shows up here.
--
-- The unresolved rows count: Unknown, N/A and a null borough are outside the
-- share (ADR 0020) but inside these totals.
with fact as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as month_start_date,
        count(*) as trip_count,
        sum(f.total_amount) as billable_revenue
    from {{ ref('fct_trip') }} f
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1
),

mart as (
    select
        month_start_date,
        sum(trip_count) as trip_count,
        sum(billable_revenue) as billable_revenue
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1
)

select
    coalesce(m.month_start_date, f.month_start_date) as month_start_date,
    m.trip_count as mart_trip_count,
    f.trip_count as fact_trip_count,
    m.billable_revenue as mart_billable_revenue,
    f.billable_revenue as fact_billable_revenue
from mart m
full outer join fact f on m.month_start_date = f.month_start_date
where
    m.trip_count is distinct from f.trip_count
    -- Revenue is a sum of doubles read in a different order on each side, so it
    -- is compared to a fraction of a cent rather than exactly.
    or abs(coalesce(m.billable_revenue, 0) - coalesce(f.billable_revenue, 0)) > 0.005
