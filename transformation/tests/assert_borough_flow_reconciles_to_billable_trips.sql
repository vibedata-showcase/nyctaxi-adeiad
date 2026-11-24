-- The flow grid must carry every billable trip picked up in the reporting
-- window exactly once, month by month. A pair with no trips is a zero row, so a
-- missing trip shows up here as a smaller month total, and a duplicated one as a
-- larger total. Rows are keyed on trip_month with no assumption about which trip
-- pair they came from.
with report_trips as (
    select
        cast(date_trunc('month', pickup_date) as date) as trip_month,
        count(*) as trip_count
    from {{ ref('fct_trip') }}
    where
        {{ in_report_window('pickup_datetime') }}
        and is_billable
    group by 1
),

flow_trips as (
    select
        trip_month,
        sum(trip_count) as trip_count
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1
)

select
    coalesce(r.trip_month, f.trip_month) as trip_month,
    r.trip_count as report_trip_count,
    f.trip_count as flow_trip_count
from report_trips r
full outer join flow_trips f on r.trip_month = f.trip_month
where r.trip_count is distinct from f.trip_count
