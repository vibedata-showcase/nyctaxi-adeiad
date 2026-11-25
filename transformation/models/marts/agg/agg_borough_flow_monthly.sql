-- Monthly borough-to-borough flow: how much traffic crosses a borough line.
--
-- The zone dimension is joined twice, once per role, and then rolled up from
-- the zone to the borough, so the row is a pair of boroughs rather than a pair
-- of zones. Every borough the zone master names is kept, the unresolved groups
-- and EWR included (ADR 0012): a borough rollup reports them unless its
-- consumer filters. No floor is applied (ADR 0018); the 25-trip floor belongs
-- to the zone-pair matrix (ADR 0017), and inheriting it here would narrow the
-- share's denominator as well as its numerator.
--
-- The share is one number per origin borough and month, so it is computed as a
-- ratio of sums over the borough's rows (ADR 0016) and repeated on each of
-- them; it is never an average of the pairs' own ratios.
with pairs as (
    select
        cast(date_trunc('month', f.pickup_datetime) as date) as trip_month,
        zo.borough_name as origin_borough,
        dz.borough_name as dest_borough,
        count(*) as trip_count,
        sum(f.total_amount) as total_revenue,
        count(*) filter (where zo.borough_name <> dz.borough_name) as cross_borough_trip_count
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} zo on f.pickup_zone_key = zo.zone_key
    join {{ ref('dim_zone') }} dz on f.dropoff_zone_key = dz.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1, 2, 3
)

select
    p.trip_month,
    p.origin_borough,
    p.dest_borough,
    p.trip_count,
    p.total_revenue,
    p.cross_borough_trip_count,
    {{ safe_divide('sum(p.cross_borough_trip_count) over w', 'sum(p.trip_count) over w') }}
        as cross_borough_share
from pairs p
window w as (partition by p.trip_month, p.origin_borough)
