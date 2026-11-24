-- Unknown and N/A are not boroughs, so they stay outside the cross-borough
-- share while staying inside the totals (ADR 0020). Two ways that breaks: a
-- row whose origin or destination is unresolved carries a numerator anyway, or
-- the numerator exceeds the trips that actually arrived in a different resolved
-- borough.
--
-- The expectation is recomputed from fct_trip and dim_zone independently of the
-- mart, using the same resolved-borough rule the dimension carries.
with expected as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as month_start_date,
        o.borough_name as origin_borough,
        count(*) filter (
            where
            not dz.is_unresolved_zone
            and dz.borough_name is not null
            and o.borough_name is not null
            and o.borough_name is distinct from dz.borough_name
        ) as crossing_trips
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    join {{ ref('dim_zone') }} dz on f.dropoff_zone_key = dz.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
        and not o.is_unresolved_zone
    group by 1, 2
),

mart as (
    select
        month_start_date,
        origin_borough,
        max(cross_borough_billable_trip_count) as published_numerator,
        max(origin_is_unresolved) as origin_is_unresolved,
        max(destination_is_unresolved) as any_destination_unresolved
    from {{ ref('agg_borough_flow_monthly') }}
    where not origin_is_unresolved
    group by 1, 2
)

select
    m.month_start_date,
    m.origin_borough,
    m.published_numerator,
    e.crossing_trips as expected_numerator
from mart m
left join expected e
    on
        m.month_start_date = e.month_start_date
        and m.origin_borough = e.origin_borough
where m.published_numerator is distinct from coalesce(e.crossing_trips, 0)

union all

-- An unresolved origin is no borough, so it carries no numerator, no
-- denominator and no share (ADR 0020). A resolved origin keeps its numerator on
-- all its rows, including the ones whose destination is unresolved.
select
    month_start_date,
    origin_borough,
    cross_borough_billable_trip_count as published_numerator,
    0 as expected_numerator
from {{ ref('agg_borough_flow_monthly') }}
where
    origin_is_unresolved
    and (
        cross_borough_billable_trip_count is not null
        or origin_billable_trip_count is not null
        or cross_borough_share is not null
    )
