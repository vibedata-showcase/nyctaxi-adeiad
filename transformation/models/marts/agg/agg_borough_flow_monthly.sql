-- Borough-to-borough flow by month, with the share of each origin borough's
-- traffic that crosses a borough line.
--
-- Two populations live here on purpose. The pair rows are published only for
-- borough pairs carrying at least 25 billable trips in their month (ADR 0018),
-- the same floor agg_od_flow_matrix applies to zone pairs, so summing them
-- undercuts the network. The crossing share beside them is taken over the
-- origin borough-month's whole billable traffic, published pair or not
-- (ADR 0019): it answers how much of a borough's traffic leaves it, which is
-- a fact about the traffic and not about the rows the floor publishes. That is
-- why the share does not reconcile with the pair rows, and why a borough-month
-- with no qualifying pair still carries a row, with a null dest_borough and a
-- zero trip and revenue total, rather than losing its share.
--
-- Unresolved zones are kept as their own N/A and Unknown borough groups
-- (ADR 0012), so every borough on dim_zone can appear on either side.
with pairs as (
    select
        cast(date_trunc('month', f.pickup_datetime) as date) as trip_month,
        o.borough_name as origin_borough,
        d.borough_name as dest_borough,
        count(*) as trip_count,
        sum(f.total_amount) as total_revenue
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1, 2, 3
),

origins as (
    select
        trip_month,
        origin_borough,
        sum(trip_count) as origin_departing_trip_count,
        -- coalesce: a borough whose every trip stays inside it has no row the
        -- filter keeps, and sum over no rows is null, not the zero it measured.
        coalesce(sum(trip_count) filter (where origin_borough <> dest_borough), 0) as origin_crossing_trip_count
    from pairs
    group by 1, 2
),

published_pairs as (
    select
        p.trip_month,
        p.origin_borough,
        p.dest_borough,
        p.trip_count,
        p.total_revenue,
        x.origin_departing_trip_count,
        x.origin_crossing_trip_count,
        {{ safe_divide('x.origin_crossing_trip_count', 'x.origin_departing_trip_count') }} as origin_crossing_trip_share
    from pairs p
    join origins x on p.trip_month = x.trip_month and p.origin_borough = x.origin_borough
    where p.trip_count >= 25
),

no_pair_origins as (
    select
        x.trip_month,
        x.origin_borough,
        cast(null as varchar) as dest_borough,
        0 as trip_count,
        0.0 as total_revenue,
        x.origin_departing_trip_count,
        x.origin_crossing_trip_count,
        {{ safe_divide('x.origin_crossing_trip_count', 'x.origin_departing_trip_count') }} as origin_crossing_trip_share
    from origins x
    where not exists (
        select 1
        from pairs p
        where
            p.trip_month = x.trip_month
            and p.origin_borough = x.origin_borough
            and p.trip_count >= 25
    )
)

select
    cast(trip_month as date) as trip_month,
    cast(origin_borough as varchar) as origin_borough,
    cast(dest_borough as varchar) as dest_borough,
    cast(trip_count as bigint) as trip_count,
    cast(total_revenue as double) as total_revenue,
    cast(origin_departing_trip_count as bigint) as origin_departing_trip_count,
    cast(origin_crossing_trip_count as bigint) as origin_crossing_trip_count,
    cast(origin_crossing_trip_share as double) as origin_crossing_trip_share
from published_pairs
union all
select
    cast(trip_month as date) as trip_month,
    cast(origin_borough as varchar) as origin_borough,
    cast(dest_borough as varchar) as dest_borough,
    cast(trip_count as bigint) as trip_count,
    cast(total_revenue as double) as total_revenue,
    cast(origin_departing_trip_count as bigint) as origin_departing_trip_count,
    cast(origin_crossing_trip_count as bigint) as origin_crossing_trip_count,
    cast(origin_crossing_trip_share as double) as origin_crossing_trip_share
from no_pair_origins
