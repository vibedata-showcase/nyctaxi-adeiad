-- The grid must be complete and unique: every month of the reporting window
-- crossed with every group on both sides, once. Three ways it can go wrong, each
-- a row here: a pair the model never published (a missing cell reads as unknown
-- traffic), a pair published twice (its trips would double-count), and a pair
-- naming a group or month outside the window (a stale or invented group).
with months as (
    select distinct month_start_date as trip_month
    from {{ ref('dim_date') }}
    where {{ in_report_window('calendar_date') }}
),

boro as (
    select distinct
        case
            when borough_name in ('Unknown', 'N/A') then 'unresolved'
            else borough_name
        end as borough_group
    from {{ ref('dim_zone') }}

    union

    select 'unresolved' as borough_group
),

expected as (
    select
        m.trip_month,
        o.borough_group as origin_borough,
        d.borough_group as dest_borough
    from months m
    cross join boro o
    cross join boro d
),

actual as (
    select
        trip_month,
        origin_borough,
        dest_borough,
        count(*) as row_count
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1, 2, 3
)

select
    'missing' as finding,
    e.trip_month,
    e.origin_borough,
    e.dest_borough,
    0 as row_count
from expected e
left join actual a
    on
        e.trip_month = a.trip_month
        and e.origin_borough = a.origin_borough
        and e.dest_borough = a.dest_borough
where a.trip_month is null

union all

select
    'duplicated' as finding,
    a.trip_month,
    a.origin_borough,
    a.dest_borough,
    a.row_count
from actual a
where a.row_count > 1

union all

select
    'unexpected' as finding,
    a.trip_month,
    a.origin_borough,
    a.dest_borough,
    a.row_count
from actual a
left join expected e
    on
        e.trip_month = a.trip_month
        and e.origin_borough = a.origin_borough
        and e.dest_borough = a.dest_borough
where e.trip_month is null
