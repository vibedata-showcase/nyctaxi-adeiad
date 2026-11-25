-- Monthly borough-to-borough flow, with each origin borough's cross-borough
-- share. Answers "how much of our traffic crosses borough lines": for every
-- month, the trips and revenue from each borough to each borough, and the
-- share of a borough's outbound trips that end somewhere else.
--
-- Grain: one row per month, origin borough and destination borough, for every
-- pair that carries at least one billable trip. No 25-trip floor: that rule
-- (ADR 0017) exists to keep a 265 x 265 zone cross product from publishing
-- noise, and at borough grain the pairs are few and each one is a real route.
--
-- Population: billable trips inside the reporting window (ADR 0003), the same
-- rule every revenue and flow mart applies. Revenue is sum(total_amount), so
-- no-charge and dispute trips count, as they do in the other revenue marts
-- (ADR 0013).
--
-- The share is computed per origin borough per month over the trips whose
-- destination borough is resolved. A trip that ends in an unresolved borough
-- ("Unknown", "N/A": ADR 0012) is still published as its own row, but it is
-- not evidence that traffic crossed a borough line, so it leaves the
-- denominator and its count is published beside it.
--
-- Both zones are left-joined: a trip whose zone key is null keeps its row with
-- a null borough rather than vanishing (ADR 0015). Such a row counts as an
-- unresolved origin or destination, which is the honest reading of a borough
-- the warehouse cannot name.
with trip_pairs as (
    select
        d.month_start_date,
        o.borough_name as origin_borough,
        coalesce(o.is_unresolved_zone, true) as is_origin_borough_unresolved,
        z.borough_name as dest_borough,
        coalesce(z.is_unresolved_zone, true) as is_dest_borough_unresolved,
        f.total_amount
    from {{ ref('fct_trip') }} f
    left join {{ ref('dim_date') }} d on f.pickup_date = d.calendar_date
    left join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    left join {{ ref('dim_zone') }} z on f.dropoff_zone_key = z.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
),

pair_totals as (
    select
        month_start_date,
        origin_borough,
        is_origin_borough_unresolved,
        dest_borough,
        is_dest_borough_unresolved,
        count(*) as trip_count,
        count(total_amount) as trips_with_revenue,
        sum(total_amount) as total_revenue
    from trip_pairs
    group by 1, 2, 3, 4, 5
),

origin_totals as (
    select
        month_start_date,
        origin_borough,
        sum(trip_count) as origin_trip_count,
        sum(case when not is_dest_borough_unresolved then trip_count else 0 end)
            as origin_resolved_trip_count,
        sum(case when is_dest_borough_unresolved then trip_count else 0 end)
            as origin_unresolved_trip_count,
        sum(
            case
                when
                    not is_dest_borough_unresolved
                    and dest_borough is distinct from origin_borough
                    then trip_count
                else 0
            end
        ) as cross_borough_trip_count
    from pair_totals
    group by 1, 2
)

select
    cast(p.month_start_date as date) as month_start_date,
    p.origin_borough,
    p.dest_borough,
    cast(p.dest_borough is distinct from p.origin_borough as boolean) as is_cross_borough,
    cast(not p.is_origin_borough_unresolved as boolean) as is_origin_borough_resolved,
    cast(not p.is_dest_borough_unresolved as boolean) as is_dest_borough_resolved,
    cast(p.trip_count as bigint) as trip_count,
    cast(p.trips_with_revenue as bigint) as trips_with_revenue,
    cast(p.total_revenue as double) as total_revenue,
    cast(o.origin_trip_count as bigint) as origin_trip_count,
    cast(o.origin_resolved_trip_count as bigint) as origin_resolved_trip_count,
    cast(o.origin_unresolved_trip_count as bigint) as origin_unresolved_trip_count,
    cast(o.cross_borough_trip_count as bigint) as cross_borough_trip_count,
    -- A share is a property of a borough. An unresolved origin is not one, so
    -- its share is null rather than a construction artefact of every
    -- destination differing from 'Unknown'.
    cast(
        case
            when p.is_origin_borough_unresolved then null
            else {{ safe_divide('o.cross_borough_trip_count', 'o.origin_resolved_trip_count') }}
        end
        as double
    ) as cross_borough_share
from pair_totals as p
inner join origin_totals as o
    on
        p.month_start_date = o.month_start_date
        and p.origin_borough is not distinct from o.origin_borough
