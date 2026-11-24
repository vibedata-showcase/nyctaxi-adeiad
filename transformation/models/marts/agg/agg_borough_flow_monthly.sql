-- Borough-to-borough flow, one row per month, origin borough and destination
-- borough. The borough-grain companion to agg_od_flow_matrix: the same zone
-- dimension joined twice in its two roles, rolled up from zone pairs to
-- boroughs.
--
-- It publishes no trip floor (ADR 0018). A floor is a property of the zone-pair
-- surface, and here it would silently drop thin destinations, so no per-origin
-- borough total would close to the star and the share of traffic leaving a
-- borough could not be read off the table (ADR 0019).
--
-- A zone the master data places in no borough is real traffic (ADR 0012) and a
-- null zone key is a real trip (ADR 0015), so both zone joins are LEFT joins and
-- either end groups as 'unresolved'. Such a trip is neither in-borough nor
-- cross-borough: is_cross_borough is null on it, and the share counts it in
-- neither of its two counts.
--
-- The share is a ratio of two sums (ADR 0016), never a mean of per-destination
-- shares, so both counts ship beside it. They repeat across the destination rows
-- of one origin borough and month, which is why they are not additive.
with cells as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as month_start_date,
        case
            when o.zone_key is null or o.is_unresolved_zone then 'unresolved'
            else o.borough_name
        end as origin_borough,
        case
            when d.zone_key is null or d.is_unresolved_zone then 'unresolved'
            else d.borough_name
        end as dest_borough,
        count(*) as trip_count,
        sum(f.total_amount) as total_revenue
    from {{ ref('fct_trip') }} f
    left join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    left join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1, 2, 3
),

placed as (
    select
        c.month_start_date,
        c.origin_borough,
        c.dest_borough,
        c.trip_count,
        c.total_revenue,
        case
            when c.origin_borough = 'unresolved' or c.dest_borough = 'unresolved' then null
            else c.origin_borough <> c.dest_borough
        end as is_cross_borough,
        -- The two sums the share is built from, at cell grain; zero rather than
        -- null so the window sums need no coalesce.
        case
            when c.origin_borough = 'unresolved' or c.dest_borough = 'unresolved' then 0
            else c.trip_count
        end as located_trip_count,
        case
            when c.origin_borough = 'unresolved' or c.dest_borough = 'unresolved' then 0
            when c.origin_borough <> c.dest_borough then c.trip_count
            else 0
        end as cross_trip_count
    from cells c
),

origin_totals as (
    select
        p.month_start_date,
        p.origin_borough,
        p.dest_borough,
        p.trip_count,
        p.total_revenue,
        p.is_cross_borough,
        -- cast because a window sum over BIGINT widens to HUGEINT, and the
        -- published column is a plain count.
        cast(sum(p.located_trip_count) over w as bigint) as origin_located_trip_count,
        cast(sum(p.cross_trip_count) over w as bigint) as origin_cross_borough_trip_count
    from placed p
    window w as (partition by p.month_start_date, p.origin_borough)
)

select
    t.month_start_date,
    t.origin_borough,
    t.dest_borough,
    t.trip_count,
    t.total_revenue,
    t.is_cross_borough,
    case
        when t.origin_borough = 'unresolved' then null
        else t.origin_located_trip_count
    end as origin_located_trip_count,
    case
        when t.origin_borough = 'unresolved' then null
        else t.origin_cross_borough_trip_count
    end as origin_cross_borough_trip_count,
    case
        when t.origin_borough = 'unresolved' then null
        else {{ safe_divide('t.origin_cross_borough_trip_count', 't.origin_located_trip_count') }}
    end as cross_borough_trip_share
from origin_totals t
