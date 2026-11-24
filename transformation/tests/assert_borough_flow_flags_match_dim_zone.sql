-- The flags come from dim_zone, not from the borough name (D-04, D-07): each
-- row's unresolved flags match is_unresolved_zone for its borough, and
-- is_cross_borough holds exactly when both ends are resolved and differ
-- (ADR 0019).
with zone_flags as (
    select
        z.borough_name,
        bool_or(z.is_unresolved_zone) as is_unresolved
    from {{ ref('dim_zone') }} z
    group by 1
)

select
    a.month_start_date,
    a.origin_borough,
    a.dest_borough,
    a.origin_is_unresolved,
    o.is_unresolved as expected_origin_is_unresolved,
    a.dest_is_unresolved,
    d.is_unresolved as expected_dest_is_unresolved,
    a.is_cross_borough,
    (
        not o.is_unresolved and not d.is_unresolved and a.origin_borough != a.dest_borough
    ) as expected_is_cross_borough
from {{ ref('agg_borough_flow_monthly') }} a
join zone_flags o on a.origin_borough = o.borough_name
join zone_flags d on a.dest_borough = d.borough_name
where
    a.origin_is_unresolved is distinct from o.is_unresolved
    or a.dest_is_unresolved is distinct from d.is_unresolved
    or a.is_cross_borough is distinct from (
        not o.is_unresolved and not d.is_unresolved and a.origin_borough != a.dest_borough
    )
