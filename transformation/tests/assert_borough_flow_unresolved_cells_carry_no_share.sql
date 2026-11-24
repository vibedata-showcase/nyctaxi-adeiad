-- A cell whose origin or destination is unresolved carries no share: a trip to
-- or from Unknown or N/A did not leave a borough, so counting it would inflate
-- the rate (R-05, ADR 0019). The row itself stays published with its trip_count,
-- so a row whose trips vanished is a violation too.
with flagged as (
    select
        month_start_date,
        origin_borough,
        dest_borough,
        trip_count,
        cross_borough_share_pct
    from {{ ref('agg_borough_flow_monthly') }}
    where origin_is_unresolved or dest_is_unresolved
),

unresolved_trips as (
    select
        cast(date_trunc('month', f.pickup_datetime) as date) as month_start_date,
        o.borough_name as origin_borough,
        dz.borough_name as dest_borough,
        count(*) as trip_count
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    join {{ ref('dim_zone') }} dz on f.dropoff_zone_key = dz.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
        and (o.is_unresolved_zone or dz.is_unresolved_zone)
    group by 1, 2, 3
)

select month_start_date, origin_borough, dest_borough, trip_count, cross_borough_share_pct
from flagged
where cross_borough_share_pct is not null

union all

select
    f.month_start_date,
    f.origin_borough,
    f.dest_borough,
    f.trip_count,
    f.cross_borough_share_pct
from flagged f
left join unresolved_trips e
    on
        f.month_start_date = e.month_start_date
        and f.origin_borough = e.origin_borough
        and f.dest_borough = e.dest_borough
where f.trip_count is distinct from coalesce(e.trip_count, 0)
