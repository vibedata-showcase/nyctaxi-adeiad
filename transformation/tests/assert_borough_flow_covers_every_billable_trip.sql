-- The borough matrix loses no trip between the star and the aggregate: every
-- billable trip in the reporting window lands in exactly one borough pair, and
-- the pair counts add back to the star's billable count for the same month.
--
-- This is a population test, so it recomputes the star's population directly
-- rather than reusing the model's own filter chain.
with star as (
    select
        cast(date_trunc('month', pickup_datetime) as date) as month_start_date,
        count(*) as billable_trips
    from {{ ref('fct_trip') }}
    where
        pickup_datetime >= timestamp '{{ var("report_start") }}'
        and pickup_datetime < timestamp '{{ var("report_end") }}'
        and is_billable
    group by 1
),

matrix as (
    select
        month_start_date,
        sum(trip_count) as matrix_trips
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1
)

select
    coalesce(s.month_start_date, m.month_start_date) as month_start_date,
    s.billable_trips,
    m.matrix_trips
from star s
full outer join matrix m on s.month_start_date = m.month_start_date
where s.billable_trips is distinct from m.matrix_trips
