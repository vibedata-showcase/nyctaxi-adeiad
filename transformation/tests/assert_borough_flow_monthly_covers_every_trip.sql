-- Publishing every borough pair (ADR 0018) means each month's totals equal the
-- star's billable totals for that month. Money is compared at the cent, because
-- a double sum is not reproducible bit for bit. `is distinct from` keeps the
-- check honest when a month is missing on either side, where a bare `<>` on
-- NULLs would pass.
with published as (
    select
        trip_month,
        sum(trip_count) as trip_count,
        sum(total_revenue) as total_revenue
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1
),

fact as (
    select
        cast(date_trunc('month', pickup_date) as date) as trip_month,
        count(*) as trip_count,
        sum(total_amount) as total_revenue
    from {{ ref('fct_trip') }}
    where
        {{ in_report_window('pickup_datetime') }}
        and is_billable
    group by 1
)

select
    coalesce(p.trip_month, f.trip_month) as trip_month,
    p.trip_count as published_trips,
    f.trip_count as fact_trips,
    p.total_revenue as published_revenue,
    f.total_revenue as fact_revenue
from published p
full outer join fact f on p.trip_month = f.trip_month
where
    p.trip_count is distinct from f.trip_count
    or round(p.total_revenue, 2) is distinct from round(f.total_revenue, 2)
