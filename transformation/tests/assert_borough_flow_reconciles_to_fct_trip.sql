-- The table reconciles to the fact over the whole window, and carries no volume
-- floor at borough grain (R-06, R-08). `sum(trip_count)` must equal the window's
-- billable trips and `round(sum(total_revenue), 2)` its billable revenue; a
-- second check returns a row when no pair holds between 1 and 24 trips, which is
-- what ADR 0017's floor would remove.
with actual as (
    select
        sum(trip_count) as trips,
        round(sum(total_revenue), 2) as revenue,
        count(*) filter (where trip_count between 1 and 24) as thin_pairs
    from {{ ref('agg_borough_flow_monthly') }}
),

expected as (
    select
        count(*) as trips,
        round(sum(f.total_amount), 2) as revenue
    from {{ ref('fct_trip') }} f
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
)

select
    'window total' as check_name,
    a.trips as actual_trips,
    e.trips as expected_trips,
    a.revenue as actual_revenue,
    e.revenue as expected_revenue
from actual a
cross join expected e
where a.trips is distinct from e.trips or a.revenue is distinct from e.revenue

union all

select
    'no volume floor' as check_name,
    a.thin_pairs as actual_trips,
    null as expected_trips,
    null as actual_revenue,
    null as expected_revenue
from actual a
where a.thin_pairs = 0
