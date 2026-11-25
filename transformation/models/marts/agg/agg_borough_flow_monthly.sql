-- Borough-to-borough flow, one row per month and borough pair.
--
-- The role-playing zone dimension joined twice, at the grain a planner asks at:
-- how much traffic crosses a borough line, and what it carried. The
-- origin-destination matrix answers the same question at zone-pair grain and
-- keeps only pairs above a floor (ADR 0017); this mart publishes every pair that
-- carries traffic, so its totals are the window's billable totals and the
-- crossing share has the whole departing population as its denominator
-- (ADR 0019).
--
-- A cross-borough trip ends outside the borough it started in, compared on every
-- borough value the zone dimension carries: the unresolved groups and EWR are
-- members, and a trip to a borough the TLC could not resolve did leave its
-- origin borough (ADR 0018, ADR 0012). Both roles are inner joined, so a borough
-- is never null here; `assert_borough_flow_covers_billable_trips` keeps it that
-- way rather than letting a null silently read as an intra-borough trip.
--
-- The share ships with its numerator and denominator on the same row, rebuilt
-- from summed counts rather than averaged from zone-pair rates (ADR 0016), so it
-- is not additive across rows. The unplaced count reads from the fact alone,
-- because the inner join to both zone roles is exactly what excludes those trips
-- (ADR 0015).
with placed as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as month_start_date,
        o.borough_name as origin_borough,
        dz.borough_name as destination_borough,
        count(*) as billable_trip_count,
        sum(f.total_amount) as billable_revenue,
        count(*) filter (where o.borough_name <> dz.borough_name) as crossing_trip_count
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
        month_start_date,
        origin_borough,
        sum(billable_trip_count) as origin_month_trip_count,
        sum(crossing_trip_count) as origin_month_crossing_trip_count
    from placed
    group by 1, 2
),

unplaced as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as month_start_date,
        count(*) as unplaced_trip_count
    from {{ ref('fct_trip') }} f
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
        and (f.pickup_zone_key is null or f.dropoff_zone_key is null)
    group by 1
)

select
    p.month_start_date,
    p.origin_borough,
    p.destination_borough,
    cast(p.origin_borough <> p.destination_borough as boolean) as is_cross_borough,
    cast(p.billable_trip_count as bigint) as billable_trip_count,
    cast(p.billable_revenue as double) as billable_revenue,
    cast(om.origin_month_trip_count as bigint) as origin_month_trip_count,
    cast(om.origin_month_crossing_trip_count as bigint) as origin_month_crossing_trip_count,
    cast(
        {{ safe_divide('om.origin_month_crossing_trip_count::double', 'om.origin_month_trip_count::double') }}
        as double
    ) as origin_month_crossing_share,
    cast(coalesce(u.unplaced_trip_count, 0) as bigint) as month_unplaced_billable_trip_count
from placed p
join origin_month om on p.month_start_date = om.month_start_date and p.origin_borough = om.origin_borough
left join unplaced u on p.month_start_date = u.month_start_date
