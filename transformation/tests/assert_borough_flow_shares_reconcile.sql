-- Both shares are rebuilt from the origin borough's own counts, never averaged
-- across its destinations (ADR 0019). Four things must hold at once, each
-- recomputed here from the fact rather than read back from the model:
--
--   1. the leaving share is one value per origin borough and month, because it
--      belongs to the origin and repeats on every row;
--   2. the named-borough destinations' shares sum to 1 for that origin and
--      month, so the published rows account for the whole denominator;
--   3. the shares of the destinations other than the origin sum to the leaving
--      share, so the two columns cannot disagree;
--   4. the leaving share equals an independent recomputation, so a broken
--      numerator or denominator cannot pass by agreeing with itself.
with expected as (
    select
        cast(date_trunc('month', f.pickup_datetime) as date) as trip_month,
        case
            when o.borough_name in ('Unknown', 'N/A') then 'Unresolved'
            else o.borough_name
        end as origin_borough,
        case
            when dz.borough_name in ('Unknown', 'N/A') then 'Unresolved'
            else dz.borough_name
        end as destination_borough,
        count(*) as trip_count
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    join {{ ref('dim_zone') }} dz on f.dropoff_zone_key = dz.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
    group by 1, 2, 3
),

expected_origin as (
    select
        trip_month,
        origin_borough,
        sum(
            case
                when origin_borough <> 'Unresolved' and destination_borough <> 'Unresolved'
                    then trip_count
                else 0
            end
        ) as denominator,
        sum(
            case
                when
                    origin_borough <> 'Unresolved'
                    and destination_borough <> 'Unresolved'
                    and destination_borough <> origin_borough
                    then trip_count
                else 0
            end
        ) as leaving_trips
    from expected
    group by 1, 2
),

expected_share as (
    select
        trip_month,
        origin_borough,
        case
            when coalesce(denominator, 0) = 0 then null
            else cast(leaving_trips as double) / denominator
        end as leaving_share
    from expected_origin
),

model_shares as (
    select
        trip_month,
        origin_borough,
        count(distinct origin_leaving_trip_share) as distinct_leaving_shares,
        min(origin_leaving_trip_share) as leaving_share,
        sum(
            coalesce(destination_trip_share, 0)
        ) filter (where destination_borough <> 'Unresolved') as sum_of_named_shares,
        sum(
            coalesce(destination_trip_share, 0)
        ) filter (where destination_borough <> 'Unresolved' and destination_borough <> origin_borough)
            as sum_of_crossing_shares,
        count(*) filter (where destination_trip_share is not null) as rows_with_a_share
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1, 2
)

select
    m.trip_month,
    m.origin_borough,
    'the leaving share repeats with different values' as finding
from model_shares m
where m.distinct_leaving_shares > 1

union all

select
    m.trip_month,
    m.origin_borough,
    'the named-borough shares do not sum to 1' as finding
from model_shares m
where
    m.rows_with_a_share > 0
    and abs(m.sum_of_named_shares - 1.0) > 1e-9

union all

select
    m.trip_month,
    m.origin_borough,
    'the crossing shares do not sum to the leaving share' as finding
from model_shares m
where
    m.rows_with_a_share > 0
    and abs(m.sum_of_crossing_shares - coalesce(m.leaving_share, 0)) > 1e-9

union all

select
    m.trip_month,
    m.origin_borough,
    'the leaving share differs from an independent recomputation' as finding
from model_shares m
join expected_share e
    on m.trip_month = e.trip_month and m.origin_borough = e.origin_borough
where
    (m.leaving_share is null) <> (e.leaving_share is null)
    or abs(coalesce(m.leaving_share, 0) - coalesce(e.leaving_share, 0)) > 1e-9
