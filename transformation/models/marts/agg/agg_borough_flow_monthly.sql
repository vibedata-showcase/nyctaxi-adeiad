-- Borough-to-borough movement, by month.
--
-- The grid is a spine, not a group-by: every origin borough is crossed with
-- every destination borough for every month of the reporting window, so a cell
-- with no trips keeps its row at zero rather than vanishing. That is what makes
-- the table a complete 5 x 5 matrix a reader can sum, and it is why no floor is
-- applied here even though the zone-grain matrix has one (ADR 0017, ADR 0018).
--
-- The population is billable trips whose pickup zone and dropoff zone are both
-- in an NYC borough (ADR 0003). The boroughs come from dim_zone.is_nyc rather
-- than a name list, so a master-data change to the borough set moves the grid
-- instead of leaving a stale literal behind. Trips touching an unresolved zone
-- or a place outside the city are outside the grid, and outside every share and
-- total it carries (ADR 0012).
--
-- The share is computed once per origin month over all of that origin's trips
-- and repeated on each of its destination rows, so it is a description of the
-- origin's month, never a per-row measure: summing it would fan out.
with months as (
    select distinct cast(date_trunc('month', calendar_date) as date) as trip_month
    from {{ ref('dim_date') }}
    where {{ in_report_window('calendar_date') }}
),

boroughs as (
    select distinct borough_name
    from {{ ref('dim_zone') }}
    where is_nyc
),

spine as (
    select
        m.trip_month,
        o.borough_name as origin_borough,
        d.borough_name as destination_borough
    from months m
    cross join boroughs o
    cross join boroughs d
),

cells as (
    select
        cast(date_trunc('month', f.pickup_datetime) as date) as trip_month,
        o.borough_name as origin_borough,
        d.borough_name as destination_borough,
        count(*) as trip_count,
        sum(f.total_amount) as total_revenue
    from {{ ref('fct_trip') }} f
    inner join {{ ref('dim_zone') }} o
        on f.pickup_zone_key = o.zone_key and o.is_nyc
    inner join {{ ref('dim_zone') }} d
        on f.dropoff_zone_key = d.zone_key and d.is_nyc
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1, 2, 3
),

grid as (
    select
        s.trip_month,
        s.origin_borough,
        s.destination_borough,
        s.origin_borough <> s.destination_borough as is_cross_borough,
        cast(coalesce(c.trip_count, 0) as bigint) as trip_count,
        cast(coalesce(c.total_revenue, 0) as double) as total_revenue
    from spine s
    left join cells c on
        s.trip_month = c.trip_month
        and s.origin_borough = c.origin_borough
        and s.destination_borough = c.destination_borough
)

select
    g.trip_month,
    g.origin_borough,
    g.destination_borough,
    g.is_cross_borough,
    g.trip_count,
    g.total_revenue,
    cast(sum(g.trip_count) over w as bigint) as origin_trip_count,
    cast(sum(case when g.is_cross_borough then g.trip_count else 0 end) over w as bigint) as cross_borough_trip_count,
    cast(
        {{ safe_divide('sum(case when g.is_cross_borough then g.trip_count else 0 end) over w',
                       'sum(g.trip_count) over w') }} as double
    ) as outbound_cross_borough_share
from grid g
window w as (partition by g.trip_month, g.origin_borough)
