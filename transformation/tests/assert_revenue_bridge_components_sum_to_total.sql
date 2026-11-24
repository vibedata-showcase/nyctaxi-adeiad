-- The walk's component rows must sum to the group's own total_amount: that is
-- the claim the mart makes, and a component left inside the residual while it
-- also has a row of its own breaks it without failing anything. total_amount
-- repeats on every component row, so it is read once per group; max is exact
-- here because a group's nine rows carry the same value.
with component_totals as (
    select
        trip_month,
        service_type_key,
        borough_name,
        max(total_amount) as total_amount,
        sum(component_amount) as component_total
    from {{ ref('mart_revenue_component_bridge') }}
    group by 1, 2, 3
)

select
    trip_month,
    service_type_key,
    borough_name,
    total_amount,
    component_total,
    component_total - total_amount as unexplained_difference
from component_totals
where abs(coalesce(component_total, 0) - coalesce(total_amount, 0)) > 0.01
