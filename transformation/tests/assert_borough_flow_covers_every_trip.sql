-- The table publishes the whole billable population, not a subset of it: no
-- traffic floor, and no trip lost to a join, a group or a dropped pair. A row
-- returned means the table's totals and the fact's disagree.
with totals as (
    select
        cast(sum(trip_count) as bigint) as table_trips,
        sum(total_revenue) as table_revenue
    from {{ ref('agg_borough_flow_monthly') }}
),

fact as (
    select
        cast(count(*) as bigint) as fact_trips,
        sum(f.total_amount) as fact_revenue
    from {{ ref('fct_trip') }} f
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
)

select
    t.table_trips,
    f.fact_trips,
    t.table_revenue,
    f.fact_revenue
from totals t
cross join fact f
where
    t.table_trips is distinct from f.fact_trips
    or round(t.table_revenue, 2) is distinct from round(f.fact_revenue, 2)
