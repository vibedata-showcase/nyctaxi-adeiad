-- The billable measures must equal a recomputation from the fact, group by
-- group. A full outer join so a zone-day present on one side only is a failure
-- too: an inner join reports a missing row as absent, not as wrong.
--
-- Money is compared at the cent (.agents/skills/dbt-testing, "Comparing
-- values"): DuckDB float aggregation is not reproducible bit for bit. A null on
-- both sides is equal; a null on one side is not.
with from_agg as (

    select
        pickup_location_id,
        pickup_date,
        billable_trip_count,
        billable_fare_revenue,
        billable_tip_revenue,
        billable_surcharge_revenue,
        billable_toll_revenue,
        billable_total_revenue
    from {{ ref('agg_trip_zone_daily') }}

),

from_fact as (

    select
        z.zone_natural_key as pickup_location_id,
        f.pickup_date,
        count(*) filter (where f.is_billable) as billable_trip_count,
        sum(f.fare_amount) filter (where f.is_billable) as billable_fare_revenue,
        sum(f.tip_amount) filter (where f.is_billable) as billable_tip_revenue,
        sum(f.total_surcharges) filter (where f.is_billable) as billable_surcharge_revenue,
        sum(f.tolls_amount) filter (where f.is_billable) as billable_toll_revenue,
        sum(f.total_amount) filter (where f.is_billable) as billable_total_revenue
    from {{ ref('fct_trip') }} f
    join {{ ref('dim_zone') }} z on f.pickup_zone_key = z.zone_key
    where {{ in_report_window('f.pickup_datetime') }}
    group by 1, 2

),

joined as (

    select
        coalesce(a.pickup_location_id, b.pickup_location_id) as pickup_location_id,
        coalesce(a.pickup_date, b.pickup_date) as pickup_date,
        a.pickup_location_id is null as missing_from_agg,
        b.pickup_location_id is null as missing_from_fact,
        a.billable_trip_count as agg_trips,
        b.billable_trip_count as fact_trips,
        a.billable_fare_revenue as agg_fare,
        b.billable_fare_revenue as fact_fare,
        a.billable_tip_revenue as agg_tip,
        b.billable_tip_revenue as fact_tip,
        a.billable_surcharge_revenue as agg_surcharge,
        b.billable_surcharge_revenue as fact_surcharge,
        a.billable_toll_revenue as agg_toll,
        b.billable_toll_revenue as fact_toll,
        a.billable_total_revenue as agg_total,
        b.billable_total_revenue as fact_total
    from from_agg a
    full outer join from_fact b
        on
            a.pickup_location_id = b.pickup_location_id
            and a.pickup_date = b.pickup_date

)

select *
from joined
where
    missing_from_agg
    or missing_from_fact
    or agg_trips is distinct from fact_trips
    or round(agg_fare, 2) is distinct from round(fact_fare, 2)
    or round(agg_tip, 2) is distinct from round(fact_tip, 2)
    or round(agg_surcharge, 2) is distinct from round(fact_surcharge, 2)
    or round(agg_toll, 2) is distinct from round(fact_toll, 2)
    or round(agg_total, 2) is distinct from round(fact_total, 2)
