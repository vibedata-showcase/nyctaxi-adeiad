-- On a row whose two ends are resolved, the share is the origin's cross-borough
-- trips over its resolved trips, and it is published (R-04). It must equal that
-- ratio within a relative tolerance of 1e-6, the same bound ADR 0016 puts on a
-- rebuilt rate.
with checks as (
    select
        month_start_date,
        origin_borough,
        dest_borough,
        cross_borough_share_pct as actual,
        100.0 * cross_borough_trip_count
        / nullif(resolved_trip_count, 0) as expected,
        cross_borough_trip_count,
        resolved_trip_count
    from {{ ref('agg_borough_flow_monthly') }}
    where not origin_is_unresolved and not dest_is_unresolved
)

select *
from checks
where
    actual is null
    or (
        expected is not null
        and abs(actual - expected) > 1e-6 * greatest(abs(expected), 1)
    )
