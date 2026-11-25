-- The cross-borough share equals its own published numerator over denominator
-- (ADR 0016): a rate rebuilt from a different denominator, or carried across
-- rows that disagree, must not pass.
--
-- A resolved origin must carry a non-null share whenever its denominator is
-- positive; an unresolved origin ("Unknown", "N/A", or a trip with no zone at
-- all) is not a borough, so its share is null by design rather than every
-- destination differing from it.
with recomputed as (
    select
        month_start_date,
        origin_borough,
        dest_borough,
        is_origin_borough_resolved,
        cross_borough_share as actual,
        case
            when not is_origin_borough_resolved then null
            when origin_resolved_trip_count = 0 then null
            else cross_borough_trip_count::double / origin_resolved_trip_count
        end as expected
    from {{ ref('agg_borough_flow_monthly') }}
),

per_origin as (
    select
        month_start_date,
        origin_borough,
        count(distinct cross_borough_share) as distinct_shares,
        count(distinct cross_borough_trip_count) as distinct_numerators,
        count(distinct origin_resolved_trip_count) as distinct_denominators,
        count(distinct origin_trip_count) as distinct_origin_totals
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1, 2
)

select
    month_start_date,
    origin_borough,
    dest_borough,
    actual,
    expected
from recomputed
where
    expected is not null
    and (actual is null or abs(actual - expected) > 1e-9)

union all

select
    month_start_date,
    origin_borough,
    'UNRESOLVED ORIGIN CARRIED A SHARE' as dest_borough,
    actual,
    null as expected
from recomputed
where not is_origin_borough_resolved and actual is not null

union all

select
    month_start_date,
    origin_borough,
    'ORIGIN SERIES DISAGREES' as dest_borough,
    distinct_shares::double as actual,
    1 as expected
from per_origin
where
    distinct_shares > 1
    or distinct_numerators > 1
    or distinct_denominators > 1
    or distinct_origin_totals > 1
