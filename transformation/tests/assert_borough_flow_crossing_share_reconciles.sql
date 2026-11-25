-- The crossing columns are recomputed from the fact, not from the model's own
-- grouping, and each must agree per (month, origin group): the counts, the
-- origin's rows adding up to the totals carried on them, the share as numerator
-- over denominator, and the nulls an unplaceable origin carries. "Resolved"
-- means placed in a borough by the TLC, which Unknown and N/A are not. The
-- per-row crossing flag is checked separately. A row returned is a mismatch.
with model_origin as (
    select
        trip_month,
        origin_borough,
        origin_is_unresolved,
        origin_trip_count,
        resolved_destination_trip_count,
        unresolved_destination_trip_count,
        crossing_trip_count,
        crossing_share,
        cast(sum(trip_count) as bigint) as row_trip_count,
        cast(sum(trip_count) filter (where not dest_is_unresolved) as bigint) as row_resolved_trip_count,
        cast(sum(trip_count) filter (
            where not dest_is_unresolved and is_cross_borough
        ) as bigint) as row_crossing_trip_count
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1, 2, 3, 4, 5, 6, 7, 8
),

recount as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as trip_month,
        coalesce(o.borough_name, 'unresolved') as origin_borough,
        coalesce(o.is_unresolved_zone, true) as origin_is_unresolved,
        cast(count(*) as bigint) as origin_trip_count,
        cast(count(*) filter (
            where not coalesce(d.is_unresolved_zone, true)
        ) as bigint) as resolved_destination_trip_count,
        cast(count(*) filter (
            where coalesce(d.is_unresolved_zone, true)
        ) as bigint) as unresolved_destination_trip_count,
        case
            when coalesce(o.is_unresolved_zone, true) then null
            else cast(count(*) filter (
                where not coalesce(d.is_unresolved_zone, true) and d.borough_name <> o.borough_name
            ) as bigint)
        end as crossing_trip_count
    from {{ ref('fct_trip') }} f
    left join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    left join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1, 2, 3
),

origin_mismatch as (
    select
        coalesce(m.trip_month, r.trip_month) as trip_month,
        coalesce(m.origin_borough, r.origin_borough) as origin_borough,
        m.origin_trip_count as model_origin_trips,
        r.origin_trip_count as recount_origin_trips,
        m.crossing_trip_count as model_crossing,
        r.crossing_trip_count as recount_crossing,
        m.crossing_share as model_share
    from model_origin m
    full join recount r
        on
            m.trip_month = r.trip_month
            and m.origin_borough = r.origin_borough
    where
        -- The model is a grid, so it may hold an origin group the fact has no
        -- trip for; that row must be all zeros against a missing recount. The
        -- other direction is a defect: a group with trips the model omits.
        m.trip_month is null
        -- an origin group the fact has no trip for carries all zeros and no
        -- share, which is what the grid is for: compare it against zeros.
        -- A filtered sum over no rows is null, so zero stands in for it.
        or m.origin_is_unresolved is distinct from coalesce(r.origin_is_unresolved, m.origin_is_unresolved)
        or m.origin_trip_count is distinct from coalesce(r.origin_trip_count, 0)
        or m.resolved_destination_trip_count is distinct from coalesce(r.resolved_destination_trip_count, 0)
        or m.unresolved_destination_trip_count is distinct from coalesce(r.unresolved_destination_trip_count, 0)
        or m.crossing_trip_count is distinct from r.crossing_trip_count
        or m.row_trip_count is distinct from m.origin_trip_count
        or coalesce(m.row_resolved_trip_count, 0) is distinct from m.resolved_destination_trip_count
        -- the origin's rows sum only the crossing trips it can attribute, so a
        -- null numerator (an unplaceable origin) reconciles with zero such rows
        or coalesce(m.row_crossing_trip_count, 0) is distinct from coalesce(m.crossing_trip_count, 0)
        or m.origin_trip_count is distinct from
        m.resolved_destination_trip_count + m.unresolved_destination_trip_count
        or case
            when m.origin_is_unresolved then m.crossing_share is not null
            when m.resolved_destination_trip_count = 0 then m.crossing_share is not null
            else abs(m.crossing_share - m.crossing_trip_count * 1.0 / m.resolved_destination_trip_count) > 1e-9
        end
)

select
    trip_month,
    origin_borough,
    model_origin_trips,
    recount_origin_trips,
    model_crossing,
    recount_crossing,
    model_share
from origin_mismatch

union all

-- The per-row crossing flag states an answer only where both ends resolve, and
-- its answer is the comparison of the two borough groups.
select
    trip_month,
    origin_borough,
    origin_trip_count,
    trip_count,
    crossing_trip_count,
    resolved_destination_trip_count,
    crossing_share
from {{ ref('agg_borough_flow_monthly') }}
where
    case
        when origin_is_unresolved or dest_is_unresolved then is_cross_borough is not null
        else is_cross_borough is distinct from (dest_borough <> origin_borough)
    end
