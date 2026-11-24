-- Borough-to-borough flow, one row per month and borough pair.
--
-- The same zone dimension joined twice, once as origin and once as destination,
-- rolled up from zones to boroughs. Coarser than agg_od_flow_matrix, which keeps
-- the zone pair and a 25-trip floor; a share of a borough's traffic cannot be
-- read through that floor, so this surface publishes every populated pair
-- (ADR 0018).
--
-- The joins are LEFT joins for the reason ADR 0015 gives: an unmatched zone key
-- stays null and the trip stays, grouped under a null borough, rather than
-- disappearing from a total that must reconcile to the star.
--
-- Unknown and N/A are the zone dimension's marker for a zone no borough can be
-- assigned to (ADR 0012), not boroughs. Their rows are published, but they are
-- outside the cross-borough share: no numerator, no denominator, null share
-- (ADR 0020). A trip picked up in a real borough and set down in an unresolved
-- zone stays in that borough's denominator -- it was that borough's traffic.
--
-- No verdict filter beyond is_billable: ADR 0004 says no model removes a trip
-- for a quality verdict, and the counts those verdicts touch are reported by the
-- quality marts instead.
with grouped as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as month_start_date,
        o.borough_name as origin_borough,
        dz.borough_name as destination_borough,
        -- A null borough is "no borough assigned", the same condition the
        -- Unknown/N-A members carry, so both are treated as unresolved: a trip
        -- with an unmatched zone key is kept and grouped under a null borough
        -- (ADR 0015) but is no more a borough member than an Unknown one.
        coalesce(o.is_unresolved_zone, false) or o.borough_name is null as origin_is_unresolved,
        coalesce(dz.is_unresolved_zone, false) or dz.borough_name is null as destination_is_unresolved,
        -- Both ends must be resolved: coalesce keeps the flag non-null when the
        -- destination borough is null, where `true and null` would yield null.
        coalesce(o.borough_name is not null and o.borough_name = dz.borough_name, false) as is_intra_borough,
        count(*) as trip_count,
        sum(f.total_amount) as billable_revenue
    from {{ ref('fct_trip') }} f
    left join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    left join {{ ref('dim_zone') }} dz on f.dropoff_zone_key = dz.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1, 2, 3, 4, 5, 6
),

share_inputs as (
    select
        *,
        -- The share's denominator: the origin borough's whole traffic that month,
        -- including trips set down in an unresolved zone.
        case
            when origin_is_unresolved then null
            else sum(trip_count) over (partition by month_start_date, origin_borough)
        end as origin_billable_trip_count,
        -- The share's numerator: only trips that arrived in a different, resolved
        -- borough. An unresolved destination is not another borough (ADR 0020).
        case
            when origin_is_unresolved then null
            else
                sum(
                    case
                        when not destination_is_unresolved and not is_intra_borough then trip_count
                        else 0
                    end
                ) over (partition by month_start_date, origin_borough)
        end as cross_borough_billable_trip_count
    from grouped
)

select
    month_start_date,
    origin_borough,
    destination_borough,
    origin_is_unresolved,
    destination_is_unresolved,
    is_intra_borough,
    cast(trip_count as bigint) as trip_count,
    cast(billable_revenue as double) as billable_revenue,
    cast(cross_borough_billable_trip_count as bigint) as cross_borough_billable_trip_count,
    cast(origin_billable_trip_count as bigint) as origin_billable_trip_count,
    cast(
        {{ safe_divide('cross_borough_billable_trip_count', 'origin_billable_trip_count') }} as double
    ) as cross_borough_share
from share_inputs
