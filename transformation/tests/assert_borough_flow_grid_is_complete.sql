-- The grid is complete: every month of the reporting window crossed with every
-- borough the zone lookup holds, on both sides of the pair, is published (R-02).
-- A missing cell is returned here, so a pair-month that vanished is visible even
-- though it carries no trips.
with months as (
    select distinct d.month_start_date
    from {{ ref('dim_date') }} d
    where {{ in_report_window('d.calendar_date') }}
),

boroughs as (
    select distinct z.borough_name
    from {{ ref('dim_zone') }} z
),

expected as (
    select m.month_start_date, o.borough_name as origin_borough, d.borough_name as dest_borough
    from months m
    cross join boroughs o
    cross join boroughs d
)

select e.month_start_date, e.origin_borough, e.dest_borough
from expected e
left join {{ ref('agg_borough_flow_monthly') }} a
    on
        a.month_start_date = e.month_start_date
        and a.origin_borough = e.origin_borough
        and a.dest_borough = e.dest_borough
where a.month_start_date is null
