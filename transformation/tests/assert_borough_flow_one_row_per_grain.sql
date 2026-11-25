-- The grain is unique: one row per month, origin borough and destination
-- borough. A null borough is a real group here (a trip whose zone lookup found
-- no row, ADR 0015), and GROUP BY groups nulls together, so a duplicated null
-- key is caught like any other.
with grain_counts as (
    select
        month_start_date,
        origin_borough,
        dest_borough,
        count(*) as row_count
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1, 2, 3
)

select month_start_date, origin_borough, dest_borough, row_count
from grain_counts
where row_count > 1
