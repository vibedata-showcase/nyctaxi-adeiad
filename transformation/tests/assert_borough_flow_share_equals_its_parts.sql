-- The crossing share is its own numerator over its own denominator, and the
-- numbers repeated on a row agree with the pairs that row's month and origin
-- borough carry. ADR 0016: a rate is rebuilt from summed counts, never averaged
-- from a lower level, and a zero denominator gives null rather than zero.
--
-- Two failures this catches that a null check cannot: a share computed from one
-- population while the pairs below it carry another, and a share rounded or
-- stored as a percentage instead of a fraction.
with per_origin as (
    select
        month_start_date,
        origin_borough,
        sum(billable_trip_count) as pair_trips,
        -- an origin borough whose pairs are all intra-borough has no crossing
        -- rows, and a filtered sum of no rows is null rather than zero
        coalesce(sum(billable_trip_count) filter (where is_cross_borough), 0) as crossing_trips,
        max(origin_month_trip_count) as origin_month_trip_count,
        max(origin_month_crossing_trip_count) as origin_month_crossing_trip_count,
        max(origin_month_crossing_share) as crossing_share,
        count(distinct origin_month_trip_count) as trip_count_variants,
        count(distinct origin_month_crossing_trip_count) as crossing_count_variants,
        count(distinct origin_month_crossing_share) as share_variants
    from {{ ref('agg_borough_flow_monthly') }}
    group by 1, 2
)

select
    month_start_date,
    origin_borough,
    pair_trips,
    origin_month_trip_count,
    crossing_trips,
    origin_month_crossing_trip_count,
    crossing_share
from per_origin
where
    -- the repeated values really are one value per origin borough and month
    trip_count_variants > 1
    or crossing_count_variants > 1
    or share_variants > 1
    -- the pairs add up to the denominator
    or pair_trips is distinct from origin_month_trip_count
    -- the crossing pairs add up to the numerator
    or crossing_trips is distinct from origin_month_crossing_trip_count
    -- the share is the fraction, to floating point
    or abs(crossing_share - origin_month_crossing_trip_count::double / origin_month_trip_count::double) > 1e-9
    -- a zero denominator would be null, and this relation never has one
    or crossing_share is null
