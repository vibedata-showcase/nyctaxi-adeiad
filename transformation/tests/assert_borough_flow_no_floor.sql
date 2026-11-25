-- This surface publishes every pair that carries a billable trip, however thin
-- (ADR 0018): the zone-pair matrix's 25-trip floor belongs to that surface and
-- must not be applied here. The check is at pair level, so a floor shows up as
-- missing pairs even when the surviving pairs are large: every (month, origin
-- group, destination group) the fact holds is present and non-zero.
with held_pairs as (
    select
        date_trunc('month', f.pickup_date)::date as trip_month,
        coalesce(o.borough_name, 'unresolved') as origin_borough,
        coalesce(d.borough_name, 'unresolved') as dest_borough
    from {{ ref('fct_trip') }} f
    left join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    left join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1, 2, 3
)

select h.trip_month, h.origin_borough, h.dest_borough
from held_pairs h
left join {{ ref('agg_borough_flow_monthly') }} a
    on h.trip_month = a.trip_month
    and h.origin_borough = a.origin_borough
    and h.dest_borough = a.dest_borough
where a.trip_month is null or a.trip_count = 0
