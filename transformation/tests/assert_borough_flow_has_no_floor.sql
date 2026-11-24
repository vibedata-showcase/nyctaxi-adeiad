-- No threshold applies at this grain (ADR 0018): a borough pair that carried a
-- single billable trip is published like any other. The thinnest city-to-city
-- corridor in the window carried 10 trips, so a floor of any size would have
-- removed it.
--
-- This asserts the invariant rather than a count: every populated pair the
-- fact can supply is present in the table. A pair missing here is a pair a
-- threshold, a join or a filter dropped. The EWR and unresolved members are
-- handled by the closure test, so this one speaks only for city-to-city pairs.
with from_fact as (
    select
        cast(date_trunc('month', f.pickup_date) as date) as month_start_date,
        o.borough_name as origin_borough,
        d.borough_name as destination_borough,
        count(*) as trip_count
    from {{ ref('fct_trip') }} f
    inner join {{ ref('dim_zone') }} o on f.pickup_zone_key = o.zone_key
    inner join {{ ref('dim_zone') }} d on f.dropoff_zone_key = d.zone_key
    where
        {{ in_report_window('f.pickup_datetime') }}
        and f.is_billable
        and o.is_nyc
        and d.is_nyc
        and not o.is_unresolved_zone
        and not d.is_unresolved_zone
    group by 1, 2, 3
),

published_city_pairs as (
    select
        month_start_date,
        origin_borough,
        destination_borough,
        trip_count
    from {{ ref('agg_borough_flow_matrix') }}
    where flow_class in ('cross_borough', 'in_borough')
)

select
    f.month_start_date,
    f.origin_borough,
    f.destination_borough,
    f.trip_count as fact_trips,
    p.trip_count as published_trips
from from_fact f
left join published_city_pairs p
    on
        f.month_start_date = p.month_start_date
        and f.origin_borough = p.origin_borough
        and f.destination_borough = p.destination_borough
where p.trip_count is null or p.trip_count != f.trip_count

union all

select
    p.month_start_date,
    p.origin_borough,
    p.destination_borough,
    null as fact_trips,
    p.trip_count as published_trips
from published_city_pairs p
left join from_fact f
    on
        p.month_start_date = f.month_start_date
        and p.origin_borough = f.origin_borough
        and p.destination_borough = f.destination_borough
where f.month_start_date is null and p.trip_count > 0
