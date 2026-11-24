-- The share on every row is the ratio of the two counts published beside it
-- (ADR 0016), and it is one value per origin and month: a reader taking any
-- row of an origin's month must get the same number, so the share cannot be
-- an average of the pair-level rates.
--
-- Recomputed from the published columns rather than from the model's own
-- expression. The tolerance is relative, since the share is a double.
with per_row as (
    select
        month_start_date,
        origin_borough,
        destination_borough,
        origin_cross_borough_trips,
        origin_trips_to_known_destination,
        cross_borough_share,
        case
            when origin_trips_to_known_destination = 0 then null
            else origin_cross_borough_trips * 1.0 / origin_trips_to_known_destination
        end as expected_share
    from {{ ref('agg_borough_flow_matrix') }}
),

wrong_ratio as (
    select
        month_start_date,
        origin_borough,
        destination_borough,
        'ratio' as check_name,
        cross_borough_share as actual,
        expected_share as expected
    from per_row
    where
        expected_share is not null
        and (
            cross_borough_share is null
            or abs(cross_borough_share - expected_share) > 1e-9 * greatest(abs(expected_share), 1)
        )
),

-- A null share is only legal where the denominator is empty.
null_with_a_denominator as (
    select
        month_start_date,
        origin_borough,
        destination_borough,
        'null-share' as check_name,
        cross_borough_share as actual,
        expected_share as expected
    from per_row
    where cross_borough_share is null and origin_trips_to_known_destination > 0
),

-- The share is a fraction, not a percentage or an out-of-range number.
outside_the_unit_interval as (
    select
        month_start_date,
        origin_borough,
        destination_borough,
        'range' as check_name,
        cross_borough_share as actual,
        expected_share as expected
    from per_row
    where cross_borough_share < 0 or cross_borough_share > 1
),

-- One value per origin and month, across all of that origin's destination rows.
origin_month_disagreement as (
    select
        month_start_date,
        origin_borough,
        'one-value' as destination_borough,
        'one-per-origin' as check_name,
        count(distinct cross_borough_share) as actual,
        1 as expected
    from {{ ref('agg_borough_flow_matrix') }}
    group by 1, 2
    having count(distinct cross_borough_share) > 1
)

select * from wrong_ratio
union all
select * from null_with_a_denominator
union all
select * from outside_the_unit_interval
union all
select * from origin_month_disagreement
