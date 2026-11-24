-- The walk's component lines add back to the group's total, at the cent.
--
-- The residual is total minus every component the warehouse models, so the walk
-- balances by construction -- until a component is published on its own line
-- and left out of that subtraction. The airport fee sat in both at once and the
-- walk summed to total_amount + airport_fee. A component whose group aggregate
-- is NULL emits no row and contributes nothing to either side either, so a
-- group may carry fewer than nine lines and still balance.
select
    trip_month,
    service_type_key,
    borough_name,
    count(*) as component_lines,
    round(sum(component_amount), 2) as component_sum,
    round(max(total_amount), 2) as total_amount
from {{ ref('mart_revenue_component_bridge') }}
group by 1, 2, 3
having abs(sum(component_amount) - max(total_amount)) > 0.01
