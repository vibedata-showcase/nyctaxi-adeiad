-- Monthly borough-to-borough flow. The same zone dimension joined twice, as
-- `agg_od_flow_matrix` does, but rolled up to borough and split by month.
--
-- Every observed pair is published: the 25-trip floor in ADR 0017 guards the
-- zone-pair cross product, which a borough rollup does not have, so this table
-- closes exactly to the star's billable totals (ADR 0018).
--
-- `cross_borough_trip_share` is a ratio of sums over the origin borough's own
-- traffic that month, never the mean of the pair shares, and it repeats on every
-- row that origin has in that month (ADR 0016). `cross_borough_trip_count` is
-- published beside it so the ratio can be recomputed from the table alone.
with trips as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as trip_month,
        o.borough_name as origin_borough,
        d.borough_name as dest_borough,
        f.total_amount
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
),

pair_month as (
    select
        trip_month,
        origin_borough,
        dest_borough,
        cast(count(*) as bigint) as trip_count,
        cast(sum(total_amount) as double) as total_revenue,
        -- is_distinct_from keeps a null borough name from reading as "same
        -- borough"; a null that slips through counts as crossing, which the
        -- 8-group test on the column would catch as an unexpected value.
        cast(
            count(*) filter (where dest_borough is distinct from origin_borough) as bigint
        ) as cross_borough_trip_count
    from trips
    group by 1, 2, 3
)

select
    trip_month,
    origin_borough,
    dest_borough,
    trip_count,
    total_revenue,
    cross_borough_trip_count,
    cast(
        {{ safe_divide(
            'sum(cross_borough_trip_count) over (partition by trip_month, origin_borough)',
            'sum(trip_count) over (partition by trip_month, origin_borough)'
        ) }} as double
    ) as cross_borough_trip_share
from pair_month
