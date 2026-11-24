-- The billable measures on the zone-day build must equal the rule applied
-- directly to the fact: one count of billable trips and one sum of their total
-- amount per zone and day, and never a null measure on a zone-day that has
-- trips. This is the check that makes "the rule is applied once, here" (ADR
-- 0018) falsifiable -- an agg that drops a billable trip, double counts one
-- across the extra dimension join, or leaves a sum null shows up as a row.
--
-- The two arms are unioned so one test run reports both kinds of drift. Money
-- compares at the cent, the precision the report publishes: a recomputed double
-- sum differs in the last bits on some rows, and that is not a defect.
with from_agg as (
    select
        pickup_date,
        pickup_location_id,
        billable_trip_count,
        billable_revenue
    from {{ ref('agg_trip_zone_daily') }}
),

from_fact as (
    select
        f.pickup_date,
        z.zone_natural_key as pickup_location_id,
        count(*) filter (where f.is_billable) as billable_trip_count,
        coalesce(sum(f.total_amount) filter (where f.is_billable), 0) as billable_revenue
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} z on f.pickup_zone_key = z.zone_key
    where {{ in_report_window('f.pickup_datetime') }}
    group by 1, 2
),

mismatch as (
    select
        coalesce(a.pickup_date, b.pickup_date) as pickup_date,
        coalesce(a.pickup_location_id, b.pickup_location_id) as pickup_location_id,
        a.billable_trip_count as agg_trip_count,
        b.billable_trip_count as fact_trip_count,
        a.billable_revenue as agg_revenue,
        b.billable_revenue as fact_revenue
    from from_agg a
    full outer join from_fact b
        on
            a.pickup_date is not distinct from b.pickup_date
            and a.pickup_location_id is not distinct from b.pickup_location_id
    where
        a.billable_trip_count is distinct from b.billable_trip_count
        or abs(a.billable_revenue - b.billable_revenue) > 0.01
),

nulled as (
    select
        pickup_date,
        pickup_location_id,
        billable_trip_count as agg_trip_count,
        null as fact_trip_count,
        billable_revenue as agg_revenue,
        null as fact_revenue
    from {{ ref('agg_trip_zone_daily') }}
    where
        trip_count > 0
        and (
            billable_trip_count is null
            or billable_revenue is null
            or billable_fare_revenue is null
            or billable_tip_revenue is null
            or billable_surcharge_revenue is null
            or billable_toll_revenue is null
        )
)

select * from mismatch
union all
select * from nulled
