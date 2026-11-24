-- An unresolved origin (N/A, Unknown) has no borough to leave, so its share is
-- null, but the basis printed beside that null is its own resolved-destination
-- trips and its crossing count is zero: a trip from N/A or Unknown is neither
-- in-borough nor cross-borough (ADR 0019, design D-11).
with flagged as (
    select distinct
        month_start_date,
        origin_borough,
        resolved_trip_count,
        cross_borough_trip_count
    from {{ ref('agg_borough_flow_monthly') }}
    where origin_is_unresolved
),

recomputed as (
    select
        cast(date_trunc('month', f.pickup_datetime) as date) as month_start_date,
        o.borough_name as origin_borough,
        count(*) as resolved_trip_count
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    join {{ ref('dim_zone') }} dz on f.dropoff_zone_key = dz.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
        and o.is_unresolved_zone
        and not dz.is_unresolved_zone
    group by 1, 2
)

select
    f.month_start_date,
    f.origin_borough,
    f.resolved_trip_count,
    coalesce(r.resolved_trip_count, 0) as expected_resolved_trip_count,
    f.cross_borough_trip_count
from flagged f
left join recomputed r
    on
        f.month_start_date = r.month_start_date
        and f.origin_borough = r.origin_borough
where
    f.resolved_trip_count is distinct from coalesce(r.resolved_trip_count, 0)
    or f.cross_borough_trip_count != 0
