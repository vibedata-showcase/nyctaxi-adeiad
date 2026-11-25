-- Every borough the relation reports is a borough dim_zone names. The unresolved
-- zones are real rows (ADR 0012), so their N/A and Unknown groups belong here;
-- anything else is a name invented by a join or a literal.
select distinct borough
from (
    select origin_borough as borough from {{ ref('agg_borough_flow_monthly') }}
    union all
    select dest_borough from {{ ref('agg_borough_flow_monthly') }}
)
where
    borough is not null
    and borough not in (select borough_name from {{ ref('dim_zone') }})
