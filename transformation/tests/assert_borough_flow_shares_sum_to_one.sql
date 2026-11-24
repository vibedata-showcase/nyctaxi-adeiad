-- The leaving-borough share is a within-month partition of one borough's trips
-- across its borough destinations, so those shares must add up to 1. A borough
-- whose month landed entirely in the unresolved group has no denominator and
-- publishes no share at all, which is why a null sum is not a failure here.
--
-- The second half holds the other rule: a row that touches the unresolved group
-- carries no share, because a trip no zone places in a borough has no borough
-- denominator, so publishing one would be a share of a total nobody can name.
with share_sums as (
    select
        trip_month,
        origin_borough,
        sum(share_of_origin_borough_trips) as share_sum
    from {{ ref('agg_borough_flow_monthly') }}
    where origin_borough <> 'unresolved'
    group by 1, 2
),

unresolved_with_a_share as (
    select distinct
        trip_month,
        origin_borough,
        dest_borough
    from {{ ref('agg_borough_flow_monthly') }}
    where
        (origin_borough = 'unresolved' or dest_borough = 'unresolved')
        and share_of_origin_borough_trips is not null
)

select
    trip_month,
    origin_borough,
    cast(null as varchar) as dest_borough,
    share_sum
from share_sums
where share_sum is not null and abs(share_sum - 1) > 0.000001

union all

select
    trip_month,
    origin_borough,
    dest_borough,
    cast(null as double) as share_sum
from unresolved_with_a_share
