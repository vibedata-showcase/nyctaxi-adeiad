-- Monthly borough-to-borough flow, with the share of an origin borough's trips
-- that leaves the borough it started in.
--
-- Two things this model decides rather than inherits:
--
-- 1. **No floor.** A pair is published from a single billable trip (ADR 0018).
--    At borough grain a minimum-trip rule would remove whole destination rows
--    and leave the share measured over a trimmed population -- the share would
--    then answer "how much of the traffic that survived the rule crosses",
--    which is not the question. ADR 0017 still governs the zone-pair matrix.
--
-- 2. **A destination with no borough counts as leaving** (ADR 0019). The
--    unresolved groups and the out-of-state one are destinations like any
--    other, so a trip to one of them is a crossing. Otherwise the share would
--    move with how often the TLC could not place a zone.
--
-- Every count here counts billable trips, so each is named for that population
-- rather than borrowing the star's `trip_count`, which counts all trips.
--
-- The origin-month total is its own aggregate joined back to the pair, not a
-- window function: the share's numerator and denominator are then plain sums a
-- reader can re-add, and the model's own SELECT aggregates every measure.
--
-- Those two counts belong to the origin-month, not to the row, so they repeat
-- across destinations and are not additive across them; the properties file
-- says so on each.

with trips as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as trip_month,
        o.borough_name as origin_borough,
        d.borough_name as dest_borough,
        f.total_amount
    from {{ ref('fct_trip') }} f
    -- Left joins keep a trip whose zone key resolves to nothing: a null borough
    -- is a real group here, not a row to drop.
    left join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    left join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
),

pairs as (
    select
        trip_month,
        origin_borough,
        dest_borough,
        count(*) as billable_trip_count,
        sum(total_amount) as billable_revenue,
        -- A plain `<>` is null when either side is null, which would silently
        -- read an unresolved destination as staying put. Both-null means one
        -- unresolved borough on each side, so it stays.
        case
            when origin_borough is null and dest_borough is null then false
            else not coalesce(origin_borough = dest_borough, false)
        end as is_cross_borough
    from trips
    group by 1, 2, 3
),

origin_month as (
    select
        trip_month,
        origin_borough,
        sum(billable_trip_count) as origin_billable_trip_count,
        sum(
            case when is_cross_borough then billable_trip_count else 0 end
        ) as cross_borough_billable_trip_count
    from pairs
    group by 1, 2
)

select
    p.trip_month,
    p.origin_borough,
    p.dest_borough,
    p.is_cross_borough,
    cast(sum(p.billable_trip_count) as bigint) as billable_trip_count,
    cast(sum(p.billable_revenue) as double) as billable_revenue,
    cast(max(t.cross_borough_billable_trip_count) as bigint) as cross_borough_billable_trip_count,
    cast(max(t.origin_billable_trip_count) as bigint) as origin_billable_trip_count,
    cast(
        {{ safe_divide(
            'max(t.cross_borough_billable_trip_count)',
            'max(t.origin_billable_trip_count)'
        ) }}
        as double
    ) as cross_borough_share
from pairs p
inner join origin_month t
    on
        p.trip_month = t.trip_month
        and p.origin_borough is not distinct from t.origin_borough
group by 1, 2, 3, 4
