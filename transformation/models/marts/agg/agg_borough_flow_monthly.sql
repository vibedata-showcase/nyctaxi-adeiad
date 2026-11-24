-- Monthly trips and revenue from each borough to each borough, with the share
-- of a borough's traffic that leaves it (ADR 0018, ADR 0019).
--
-- Billable trips only, inside the reporting window; the rule is applied here in
-- gold and nowhere upstream (ADR 0003). No quality verdict filters a trip: a
-- verdict flags and never removes, and this table publishes billable revenue, so
-- a verdict filter would stop its totals equalling the metric (ADR 0004).
--
-- The zone dimension joins twice, once per role, so a trip has an origin and a
-- destination. Zones the TLC cannot place in a borough are real rows, so they
-- join like any other; their two labels merge into one Unresolved group that is
-- published but stands outside the borough counts (ADR 0012, ADR 0018). EWR is a
-- borough because the TLC names it one. Unresolved trips stay inside the totals:
-- excluding them there would break the tie to billable_revenue.
--
-- Both shares are ratios of summed counts over the origin borough's trips that
-- month whose destination resolved to a named borough, never the mean of lower
-- level rates (ADR 0019); a zero denominator gives null through safe_divide.
-- The leaving share belongs to the origin, so it repeats on every row of that
-- origin borough and month rather than being averaged across destinations.
with labelled as (
    select
        cast(date_trunc('month', f.pickup_datetime) as date) as trip_month,
        case
            when o.borough_name in ('Unknown', 'N/A') then 'Unresolved'
            else o.borough_name
        end as origin_borough,
        case
            when dz.borough_name in ('Unknown', 'N/A') then 'Unresolved'
            else dz.borough_name
        end as destination_borough,
        f.total_amount
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    join {{ ref('dim_zone') }} dz on f.dropoff_zone_key = dz.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
),

pairs as (
    select
        trip_month,
        origin_borough,
        destination_borough,
        count(*) as trip_count,
        sum(total_amount) as total_revenue
    from labelled
    group by 1, 2, 3
),

origin_totals as (
    select
        trip_month,
        origin_borough,
        sum(
            case
                when origin_borough <> 'Unresolved' and destination_borough <> 'Unresolved'
                    then trip_count
                else 0
            end
        ) as origin_resolved_trips,
        sum(
            case
                when
                    origin_borough <> 'Unresolved'
                    and destination_borough <> 'Unresolved'
                    and destination_borough <> origin_borough
                    then trip_count
                else 0
            end
        ) as origin_leaving_trips
    from pairs
    group by 1, 2
)

select
    p.trip_month,
    p.origin_borough,
    p.destination_borough,
    cast(p.trip_count as bigint) as trip_count,
    cast(p.total_revenue as double) as total_revenue,
    cast(
        case
            when p.destination_borough = 'Unresolved' then null
            else {{ safe_divide('cast(p.trip_count as double)', 't.origin_resolved_trips') }}
        end as double
    ) as destination_trip_share,
    cast(
        {{ safe_divide('cast(t.origin_leaving_trips as double)', 't.origin_resolved_trips') }} as double
    ) as origin_leaving_trip_share
from pairs p
join origin_totals t on p.trip_month = t.trip_month and p.origin_borough = t.origin_borough
