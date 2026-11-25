-- Every trip in the matrix's population lands in exactly one cell. The count
-- is recomputed from the fact and the two zone joins, not read from the model,
-- so a filter that silently drops or duplicates trips fails here.
with expected as (
    select
        cast(date_trunc('month', f.pickup_datetime) as date) as trip_month,
        count(*) as trip_count
    from {{ ref('fct_trip') }} f
    inner join {{ ref('dim_zone') }} o
        on f.pickup_zone_key = o.zone_key and o.is_nyc
    inner join {{ ref('dim_zone') }} d
        on f.dropoff_zone_key = d.zone_key and d.is_nyc
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1
),

actual as (
    select trip_month, sum(trip_count) as trip_count, count(*) as cell_count
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1
)

select
    coalesce(a.trip_month, e.trip_month) as trip_month,
    a.trip_count as matrix_trips,
    e.trip_count as expected_trips,
    a.cell_count
from actual a
full join expected e on a.trip_month = e.trip_month
where
    a.trip_count is distinct from e.trip_count
    or a.cell_count is distinct from 25
