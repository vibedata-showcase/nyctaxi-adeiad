-- The cross-borough share is numerator over denominator, rebuilt from its two
-- published inputs (ADR 0016, ADR 0019), and each origin borough's denominator
-- is the sum of its own trip_count cells. An unresolved origin carries no share
-- at all, which assert_borough_share_excludes_unresolved holds; this test reads
-- only the resolved rows.
--
-- Two ways this breaks: a share computed from anything but its parts, or a
-- denominator that disagrees with the trips published beside it.
with share_rule as (
    select
        month_start_date,
        origin_borough,
        destination_borough
    from {{ ref('agg_borough_flow_monthly') }}
    where
        not origin_is_unresolved
        and cross_borough_share is distinct from
        cross_borough_billable_trip_count * 1.0 / nullif(origin_billable_trip_count, 0)
),

denominator as (
    select
        month_start_date,
        origin_borough,
        max(origin_billable_trip_count) as published_denominator,
        sum(billable_trip_count) as summed_trips
    from {{ ref('agg_borough_flow_monthly') }}
    where not origin_is_unresolved
    group by 1, 2
),

denominator_rule as (
    select *
    from denominator
    where published_denominator is distinct from summed_trips
)

select
    'share_not_its_parts' as broken_rule,
    month_start_date,
    origin_borough,
    destination_borough
from share_rule
union all
select
    'denominator_not_the_borough_total' as broken_rule,
    month_start_date,
    origin_borough,
    null as destination_borough
from denominator_rule
