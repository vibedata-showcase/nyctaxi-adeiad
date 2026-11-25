-- Borough-to-borough flow, monthly.
--
-- The same zone dimension twice, once per role, rolled up to borough. Built from
-- the fact and not from agg_od_flow_matrix, because that matrix is cut by ADR
-- 0017's floor: its totals are a subset of the fact, and a rollup of it would
-- drop exactly the thin cross-borough pairs this table exists to show.
--
-- The grid is the whole cross product of the window's months and the nine
-- borough groups, so a pair with no billable trip in a month is a zero row
-- rather than an absent one, and a borough's row set is the same every month.
--
-- A trip whose zone key matches no dim_zone row groups as 'unresolved'. The
-- roles are LEFT joins and the borough is coalesced, so no trip leaves the
-- table unexplained (ADR 0015), and the eight TLC boroughs keep their own
-- groups, unresolved zones included (ADR 0012).
--
-- "Resolved" means placed in a borough by the TLC, which Unknown and N/A are
-- not: they are borough values, but they say the source could not place the
-- zone. Both leave the crossing share's numerator and denominator rather than
-- counting as a borough someone crossed into.
--
-- The crossing columns are properties of (month, origin group): they repeat on
-- every destination row of that origin and are never summed across them.
with window_months as (
    select distinct
        cast(date_trunc('month', calendar_date) as date) as trip_month
    from {{ ref('dim_date') }}
    where {{ in_report_window('calendar_date') }}
),

borough_groups as (
    select
        borough_name as borough_group,
        bool_or(is_unresolved_zone) as is_unresolved_group
    from {{ ref('dim_zone') }}
    group by 1

    union all

    select 'unresolved' as borough_group, true as is_unresolved_group
),

grid as (
    select
        m.trip_month,
        o.borough_group as origin_borough,
        o.is_unresolved_group as origin_is_unresolved,
        d.borough_group as dest_borough,
        d.is_unresolved_group as dest_is_unresolved
    from window_months m
    cross join borough_groups o
    cross join borough_groups d
),

trips as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as trip_month,
        coalesce(o.borough_name, 'unresolved') as origin_borough,
        o.borough_name is null or o.is_unresolved_zone as origin_is_unresolved,
        coalesce(d.borough_name, 'unresolved') as dest_borough,
        d.borough_name is null or d.is_unresolved_zone as dest_is_unresolved,
        f.total_amount
    from {{ ref('fct_trip') }} f
    left join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    left join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
),

pair_counts as (
    select
        trip_month,
        origin_borough,
        dest_borough,
        count(*) as trip_count,
        sum(total_amount) as total_revenue
    from trips
    group by 1, 2, 3
),

origin_totals as (
    select
        trip_month,
        origin_borough,
        cast(count(*) as bigint) as origin_trip_count,
        cast(count(*) filter (where not dest_is_unresolved) as bigint) as resolved_destination_trip_count,
        cast(count(*) filter (where dest_is_unresolved) as bigint) as unresolved_destination_trip_count,
        -- No crossing is attributable to an origin the source cannot place, so
        -- the numerator is null there rather than a zero that would read as
        -- "none of its trips crossed".
        case
            when bool_or(origin_is_unresolved) then null
            else cast(count(*) filter (
                where not dest_is_unresolved and dest_borough <> origin_borough
            ) as bigint)
        end as crossing_trip_count
    from trips
    group by 1, 2
)

select
    g.trip_month,
    g.origin_borough,
    g.dest_borough,
    g.origin_is_unresolved,
    g.dest_is_unresolved,
    -- Null when an end does not resolve: a trip touching a zone the TLC cannot
    -- place is not evidence of crossing either way, so the flag states unknown
    -- rather than inventing an answer, exactly as the crossing share does.
    case
        when g.origin_is_unresolved or g.dest_is_unresolved then null
        else g.dest_borough <> g.origin_borough
    end as is_cross_borough,
    cast(coalesce(p.trip_count, 0) as bigint) as trip_count,
    cast(coalesce(p.total_revenue, 0) as double) as total_revenue,
    coalesce(t.origin_trip_count, 0) as origin_trip_count,
    coalesce(t.resolved_destination_trip_count, 0) as resolved_destination_trip_count,
    coalesce(t.unresolved_destination_trip_count, 0) as unresolved_destination_trip_count,
    case
        when g.origin_is_unresolved then null
        else coalesce(t.crossing_trip_count, 0)
    end as crossing_trip_count,
    case
        when g.origin_is_unresolved then null
        else cast(
            {{ safe_divide('coalesce(t.crossing_trip_count, 0)', 'coalesce(t.resolved_destination_trip_count, 0)') }}
            as double
        )
    end as crossing_share
from grid g
left join pair_counts p
    on
        g.trip_month = p.trip_month
        and g.origin_borough = p.origin_borough
        and g.dest_borough = p.dest_borough
left join origin_totals t
    on
        g.trip_month = t.trip_month
        and g.origin_borough = t.origin_borough
