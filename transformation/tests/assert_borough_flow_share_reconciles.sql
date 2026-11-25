-- The share reconciles against the rows it sits on. For every origin-month: the
-- rows sum to origin_billable_trip_count, the crossing rows sum to
-- cross_borough_billable_trip_count, and the share is their ratio, with one value
-- repeated on the group's rows. `is distinct from` keeps the comparison honest
-- when a side is null, where a bare `!=` would pass.
--
-- The population is not restated here: this test checks the arithmetic of the
-- published table, and an independent recomputation of the population lives in
-- the intent's verification.
with rolled as (
    select
        trip_month,
        origin_borough,
        sum(billable_trip_count) as row_trip_total,
        sum(case when is_cross_borough then billable_trip_count else 0 end) as crossing_rows,
        max(origin_billable_trip_count) as claimed_origin_billable_trip_count,
        max(cross_borough_billable_trip_count) as claimed_cross_borough_billable_trip_count,
        max(cross_borough_share) as claimed_share,
        min(origin_billable_trip_count) as min_origin_billable_trip_count,
        min(cross_borough_billable_trip_count) as min_cross_borough_billable_trip_count,
        min(cross_borough_share) as min_share
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1, 2
)

select *
from rolled
where
    row_trip_total is distinct from claimed_origin_billable_trip_count
    or crossing_rows is distinct from claimed_cross_borough_billable_trip_count
    or claimed_origin_billable_trip_count is distinct from min_origin_billable_trip_count
    or claimed_cross_borough_billable_trip_count is distinct from min_cross_borough_billable_trip_count
    or claimed_share is distinct from min_share
    or claimed_share is distinct from (
        claimed_cross_borough_billable_trip_count * 1.0 / nullif(claimed_origin_billable_trip_count, 0)
    )
