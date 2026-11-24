-- Zones the TLC cannot place in a borough are not boroughs (ADR 0018): their
-- trips report in one Unresolved group, and the raw labels never reach a
-- consumer. A merge that went too far would also swallow a named borough, so
-- EWR must still be published as an origin and as a destination.
select
    origin_borough as offending_origin,
    destination_borough as offending_destination,
    'raw unresolved label published' as finding
from {{ ref('agg_borough_flow_monthly') }}
where
    origin_borough in ('Unknown', 'N/A')
    or destination_borough in ('Unknown', 'N/A')

union all

select
    'EWR' as offending_origin,
    null as offending_destination,
    'EWR missing as an origin' as finding
from (
    select count(*) as n
    from {{ ref('agg_borough_flow_monthly') }}
    where origin_borough = 'EWR'
) e
where e.n = 0

union all

select
    null as offending_origin,
    'EWR' as offending_destination,
    'EWR missing as a destination' as finding
from (
    select count(*) as n
    from {{ ref('agg_borough_flow_monthly') }}
    where destination_borough = 'EWR'
) e
where e.n = 0
