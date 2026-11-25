-- The grid is the full cross product of the window's months and the nine
-- borough groups, so a pair that carried no billable trip is a zero row, not an
-- absent one. A missing row means the grid shrank and a zero pair can no longer
-- be told from an omitted one.
with months as (
    select distinct date_trunc('month', calendar_date)::date as trip_month
    from {{ ref('dim_date') }}
    where {{ in_report_window('calendar_date') }}
),

groups as (
    select borough_name from {{ ref('dim_zone') }}

    union

    select 'unresolved' as borough_name
),

expected as (
    select m.trip_month, o.borough_name as origin_borough, d.borough_name as dest_borough
    from months m
    cross join groups o
    cross join groups d
)

select e.trip_month, e.origin_borough, e.dest_borough
from expected e
left join {{ ref('agg_borough_flow_monthly') }} a
    on e.trip_month = a.trip_month
    and e.origin_borough = a.origin_borough
    and e.dest_borough = a.dest_borough
where a.trip_month is null

union all

select a.trip_month, a.origin_borough, a.dest_borough
from {{ ref('agg_borough_flow_monthly') }} a
left join expected e
    on e.trip_month = a.trip_month
    and e.origin_borough = a.origin_borough
    and e.dest_borough = a.dest_borough
where e.trip_month is null
