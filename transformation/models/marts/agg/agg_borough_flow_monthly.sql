-- Borough-to-borough flow, one row per month, origin borough and destination
-- borough. The complete grid: every borough the zone lookup holds is an origin
-- and a destination in every month of the window, and a pair-month with no
-- billable trip is a row of zero (ADR 0018). Summing trip_count over the whole
-- table therefore reproduces the window's billable trips, and an origin's rows
-- add up to that borough's monthly traffic.
--
-- The share is nulled on a row whose origin or destination is unresolved: a trip
-- to or from N/A or Unknown did not leave a borough, and counting it would
-- inflate the rate (ADR 0019). The two counts that build the rate stay published
-- on those rows so the basis is visible (ADR 0012, ADR 0016).
with months as (
    select distinct
        d.month_start_date,
        d.month_name,
        cast(d.calendar_year as integer) as calendar_year
    from {{ ref('dim_date') }} d
    where
        {{ in_report_window('d.calendar_date') }}
),

boroughs as (
    select
        z.borough_name,
        bool_or(z.is_unresolved_zone) as is_unresolved
    from {{ ref('dim_zone') }} z
    group by 1
),

pair_trips as (
    select
        cast(date_trunc('month', f.pickup_datetime) as date) as month_start_date,
        o.borough_name as origin_borough,
        dz.borough_name as dest_borough,
        count(*) as trip_count,
        sum(f.total_amount) as total_revenue
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    join {{ ref('dim_zone') }} dz on f.dropoff_zone_key = dz.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1, 2, 3
),

origin_month as (
    select
        cast(date_trunc('month', f.pickup_datetime) as date) as month_start_date,
        o.borough_name as origin_borough,
        count(*) as resolved_trip_count,
        count(*) filter (
            where not o.is_unresolved_zone and o.borough_name != dz.borough_name
        ) as cross_borough_trip_count
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    join {{ ref('dim_zone') }} dz on f.dropoff_zone_key = dz.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
        and not dz.is_unresolved_zone
    group by 1, 2
)

select
    m.month_start_date,
    cast(m.month_name as varchar) as month_name,
    m.calendar_year,
    cast(o.borough_name as varchar) as origin_borough,
    cast(o.is_unresolved as boolean) as origin_is_unresolved,
    cast(d.borough_name as varchar) as dest_borough,
    cast(d.is_unresolved as boolean) as dest_is_unresolved,
    cast(
        not o.is_unresolved and not d.is_unresolved and o.borough_name != d.borough_name as boolean
    ) as is_cross_borough,
    cast(coalesce(p.trip_count, 0) as bigint) as trip_count,
    cast(coalesce(p.total_revenue, 0) as double) as total_revenue,
    cast(coalesce(om.resolved_trip_count, 0) as bigint) as resolved_trip_count,
    cast(coalesce(om.cross_borough_trip_count, 0) as bigint) as cross_borough_trip_count,
    cast(
        case
            when o.is_unresolved or d.is_unresolved then null
            else {{ safe_divide('om.cross_borough_trip_count * 100.0', 'om.resolved_trip_count') }}
        end as double
    ) as cross_borough_share_pct
from months m
cross join boroughs o
cross join boroughs d
left join pair_trips p
    on
        p.month_start_date = m.month_start_date
        and p.origin_borough = o.borough_name
        and p.dest_borough = d.borough_name
left join origin_month om
    on
        om.month_start_date = m.month_start_date
        and om.origin_borough = o.borough_name
