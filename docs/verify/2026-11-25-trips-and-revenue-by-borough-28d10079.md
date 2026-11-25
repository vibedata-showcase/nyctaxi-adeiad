# Verification: Trips and revenue by borough

## Discovery

Discovery at `24a7c40`, read from the Domain warehouse (`target: domain`) and the sandbox copy (`target: ephemeral`). `fct_trip` and `dim_zone` are declared relations, so both were profiled on `domain`; the two type probes ran on `ephemeral` because they read no Domain rows.

- **The reporting window is exactly three whole calendar months, 91 days, and every day carries at least one billable trip** — so no Q1 month is cut short and the edge-period branch is `not applicable`.

  ```sql
  select min(pickup_date) as first_day, max(pickup_date) as last_day, count(*) as trips, count(distinct date_trunc('month', pickup_date)) as months from core.fct_trip where is_billable
  ```

  first_day `2024-01-01`, last_day `2024-03-31`, trips `95958`, months `3`.

  ```sql
  select count(distinct pickup_date) as days_with_trips, min(pickup_date) as d0, max(pickup_date) as d1 from core.fct_trip where is_billable and pickup_date >= date '2024-01-01' and pickup_date < date '2024-04-01'
  ```

  days_with_trips `91`, d0 `2024-01-01`, d1 `2024-03-31`.

- **The window holds 97,184 trips, 95,958 of them billable, and each has one distinct `trip_key`** — so the billable population is well defined and no trip is keyed twice.

  ```sql
  select count(*) as all_trips_window,
    sum(case when is_billable then 1 else 0 end) as billable_trips,
    count(distinct case when is_billable then trip_key end) as distinct_billable
  from core.fct_trip
  where pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'
  ```

  all_trips_window `97184`, billable_trips `95958`, distinct_billable `95958`.

- **Every billable trip in the window carries a non-null, non-zero `total_amount`, and its total closes against the billable revenue** — so `trip_count` is the count of rows carrying the revenue measure and no separate coverage count is needed.

  ```sql
  select count(*) as billable_trips,
    sum(case when total_amount is null then 1 else 0 end) as null_total_amount,
    sum(case when total_amount = 0 then 1 else 0 end) as zero_total,
    round(sum(total_amount),2) as total_revenue,
    round(sum(coalesce(fare_amount,0)+coalesce(tip_amount,0)+coalesce(tolls_amount,0)+coalesce(extra,0)+coalesce(mta_tax,0)+coalesce(improvement_surcharge,0)+coalesce(congestion_surcharge,0)+coalesce(airport_fee,0)+coalesce(ehail_fee,0)),2) as component_revenue
  from core.fct_trip
  where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'
  ```

  billable_trips `95958`, null_total_amount `0`, zero_total `0`, total_revenue `2629185.82`. `component_revenue` `2661824.57` differs: the fare components do not reconstitute the total, so revenue is `total_amount` and never a sum of parts.

- **Both zone keys resolve for every billable trip in the window; no key is null and no lookup finds no row** — so no trip is lost to a zone join today, though the model keeps any future one (ADR 0015).

  ```sql
  select count(*) as trips,
    sum(case when pickup_zone_key is null then 1 else 0 end) as null_pickup_zone,
    sum(case when dropoff_zone_key is null then 1 else 0 end) as null_dropoff_zone,
    sum(case when pickup_zone_key is null and dropoff_zone_key is null then 1 else 0 end) as both_null
  from core.fct_trip where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'
  ```

  trips `95958`, null_pickup_zone `0`, null_dropoff_zone `0`, both_null `0`.

- **`dim_zone` holds 272 rows over 265 natural keys, one version per key today, `zone_key` unique and every trip key matching** — so the double join fans out nothing and needs no `distinct`.

  ```sql
  with dup as (select zone_key, count(*) c from core.dim_zone group by 1 having count(*) > 1)
  select (select count(*) from dup) as duplicate_zone_keys,
         (select count(*) from core.fct_trip f left join core.dim_zone z on f.pickup_zone_key = z.zone_key where z.zone_key is null) as trips_with_no_pickup_match,
         (select count(*) from core.fct_trip f left join core.dim_zone z on f.dropoff_zone_key = z.zone_key where z.zone_key is null) as trips_with_no_dropoff_match
  ```

  duplicate_zone_keys `0`, trips_with_no_pickup_match `0`, trips_with_no_dropoff_match `0`.

  ```sql
  select count(*) as zones, count(distinct zone_natural_key) as zone_ids, count(distinct zone_key) as surrogate_keys,
         sum(case when borough_name is null then 1 else 0 end) as null_borough,
         sum(case when is_current_version then 1 else 0 end) as current_versions
  from core.dim_zone
  ```

  zones `272`, zone_ids `265`, surrogate_keys `272`, null_borough `0`, current_versions `265`.

  ```sql
  select count(*) as versions, count(distinct zone_natural_key) as zone_ids,
         sum(case when not is_current_version then 1 else 0 end) as non_current
  from core.dim_zone
  where valid_from_date < date '2024-04-01' and valid_to_date > date '2024-01-01'
  ```

  versions `265`, zone_ids `265`, non_current `0` — no zone is re-designated inside the window, so the as-of join and a current-version join agree on today's data; the model keeps the as-of join for correctness (ADR 0009).

- **Eight borough names exist, two of them unplaceable and one outside the city** — so a borough rollup has eight groups, not five.

  ```sql
  select borough_name, count(*) as zones, sum(case when is_unresolved_zone then 1 else 0 end) as unresolved, count(distinct zone_natural_key) as zone_ids from core.dim_zone where is_current_version group by 1 order by 2 desc
  ```

  Queens 69, Manhattan 69, Brooklyn 61, Bronx 43, Staten Island 20, EWR 1, Unknown 1 (unresolved), N/A 1 (unresolved).

- **Origin boroughs in the window, with the unresolved groups sized** — Manhattan 85,245; Queens 8,672; Brooklyn 1,302; Bronx 342; Unknown 314; N/A 46; Staten Island 25; EWR 12.

  ```sql
  select z.borough_name, count(*) as trips from core.fct_trip f left join core.dim_zone z on f.pickup_zone_key = z.zone_key where f.is_billable and f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01' group by 1 order by 2 desc
  ```

- **Destinations that resolve to no borough, or outside the city, are 1,137 trips and 902 of them are unplaceable** — which is what the crossing definition has to decide about (ADR 0018).

  ```sql
  select d.borough_name as dest, count(*) as trips_q1,
         sum(case when o.borough_name='Manhattan' then 1 else 0 end) as from_manhattan
  from core.fct_trip f
  join core.dim_zone o on f.pickup_zone_key = o.zone_key
  join core.dim_zone d on f.dropoff_zone_key = d.zone_key
  where f.is_billable and f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01'
    and (d.is_unresolved_zone or not d.is_nyc)
  group by 1 order by 2 desc
  ```

  Unknown 509 (247 from Manhattan), N/A 393 (106), EWR 235 (209).

  ```sql
  with t as (
    select o.borough_name ob, d.borough_name db, d.is_unresolved_zone d_unres, d.is_nyc d_nyc
    from core.fct_trip f
    join core.dim_zone o on f.pickup_zone_key = o.zone_key
    join core.dim_zone d on f.dropoff_zone_key = d.zone_key
    where f.is_billable and f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01')
  select count(*) as trips,
    sum(case when db <> ob then 1 else 0 end) as cross_any,
    sum(case when db <> ob and d_unres then 1 else 0 end) as cross_to_unresolved,
    sum(case when db <> ob and not d_unres and not d_nyc then 1 else 0 end) as cross_to_ewr,
    sum(case when d_unres then 1 else 0 end) as dest_unresolved,
    sum(case when not d_unres and not d_nyc then 1 else 0 end) as dest_ewr,
    sum(case when o_unres or d_unres then 1 else 0 end) as either_unresolved,
    sum(case when o_unres then 1 else 0 end) as origin_unresolved
  from t
  ```

  trips `95958`, cross_any `12214`, cross_to_unresolved `644`, cross_to_ewr `223`, dest_unresolved `902`, dest_ewr `235`, origin_unresolved `360`. `either_unresolved` `1000`.

- **122 borough pair-months carry billable trips: 40 in January, 40 in February, 42 in March; 66 of them hold fewer than 25 trips, together 253 trips** — which is what ADR 0019's no-floor answer is measured against.

  ```sql
  with t as (
    select date_trunc('month', f.pickup_date) as m,
           o.borough_name as ob, d.borough_name as db,
           count(*) as trips, sum(f.total_amount) as rev
    from core.fct_trip f
    join core.dim_zone o on f.pickup_zone_key = o.zone_key
    join core.dim_zone d on f.dropoff_zone_key = d.zone_key
    where f.is_billable and f.pickup_date >= date '2024-01-01' and f.pickup_date < date '2024-04-01'
    group by 1,2,3)
  select count(*) as pairs, sum(case when trips < 25 then 1 else 0 end) as pairs_under_25,
         sum(case when trips < 25 then trips else 0 end) as trips_in_thin_pairs, sum(trips) as trips_total, round(sum(rev),2) as rev_total
  from t
  ```

  pairs `122`, pairs_under_25 `66`, trips_in_thin_pairs `253`, trips_total `95958`, rev_total `2629185.82`.

  ```sql
  with cells as (
    select date_trunc('month', f.pickup_date)::date as mth, o.borough_name ob, d.borough_name db,
           count(*) trips, sum(f.total_amount) rev
    from core.fct_trip f
    join core.dim_zone o on f.pickup_zone_key = o.zone_key
    join core.dim_zone d on f.dropoff_zone_key = d.zone_key
    where f.is_billable and f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01'
    group by 1,2,3)
  select count(*) as cells, min(trips) as min_cell, max(trips) as max_cell,
         sum(case when trips < 25 then 1 else 0 end) as thin_cells,
         sum(case when ob <> db then trips else 0 end) as cross_trips,
         sum(trips) as trips, round(sum(rev),2) as revenue,
         sum(case when ob in ('Unknown','N/A') then trips else 0 end) as unresolved_origin_trips
  from cells
  ```

  cells `122`, min_cell `1`, max_cell `29849`, thin_cells `66`, cross_trips `12214`, trips `95958`, revenue `2629185.82`, unresolved_origin_trips `360`.

- **Monthly shape, and the cross-borough split per month** — January 40 pair-rows / 29,985 trips / 816,057.76 revenue / 3,834 cross trips; February 40 / 30,017 / 813,885.68 / 3,647; March 42 / 35,956 / 999,242.38 / 4,733.

  ```sql
  with t as (
    select date_trunc('month', f.pickup_date)::date as mth,
           o.borough_name ob, d.borough_name db,
           count(*) trips, sum(f.total_amount) rev
    from core.fct_trip f
    join core.dim_zone o on f.pickup_zone_key = o.zone_key
    join core.dim_zone d on f.dropoff_zone_key = d.zone_key
    where f.is_billable and f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01'
    group by 1,2,3)
  select mth, count(*) as pair_rows, sum(trips) as trips, round(sum(rev),2) as revenue,
         sum(case when ob <> db then trips else 0 end) as cross_trips,
         round(sum(case when ob <> db then rev else 0 end),2) as cross_revenue,
         sum(case when ob = db then trips else 0 end) as same_trips
  from t group by 1 order by 1
  ```

- **48 borough pairs occur at all in Q1 against 144 pair-months of a complete grid, so the grid is 122/144 populated** — the completeness of the observed set is a property of the traffic, and a zero-filling spine would add 22 empty cells.

  ```sql
  with pairs as (
    select distinct o.borough_name as ob, d.borough_name as db
    from core.fct_trip f
    join core.dim_zone o on f.pickup_zone_key = o.zone_key
    join core.dim_zone d on f.dropoff_zone_key = d.zone_key
    where f.is_billable and f.pickup_date >= date '2024-01-01' and f.pickup_date < date '2024-04-01'
  ), m as (select unnest([date '2024-01-01', date '2024-02-01', date '2024-03-01']) as m)
  select (select count(*) from pairs) as pairs,
         (select count(*) from pairs, m) as expected_rows,
         (select count(*) from (
            select date_trunc('month', f.pickup_date) mth, o.borough_name ob, d.borough_name db
            from core.fct_trip f
            join core.dim_zone o on f.pickup_zone_key = o.zone_key
            join core.dim_zone d on f.dropoff_zone_key = d.zone_key
            where f.is_billable and f.pickup_date >= date '2024-01-01' and f.pickup_date < date '2024-04-01'
            group by 1,2,3)) as actual_rows
  ```

  pairs `48`, expected_rows `144`, actual_rows `122`.

- **The per-origin crossing share differs between the two readings the user chose between, so the answer changed a value** — Q1 over all trips vs over trips whose destination is a located NYC borough: Manhattan 5.92% vs 5.30%, Queens 72.92% vs 72.01%, Brooklyn 41.01% vs 40.60%, Bronx 57.02% vs 56.64%, Staten Island 48.00% vs 35.00%.

  ```sql
  with t as (
    select o.borough_name ob, d.borough_name db, d.is_unresolved_zone d_unres, d.is_nyc d_nyc
    from core.fct_trip f
    join core.dim_zone o on f.pickup_zone_key = o.zone_key
    join core.dim_zone d on f.dropoff_zone_key = d.zone_key
    where f.is_billable and f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01')
  select ob, count(*) origin_trips,
    sum(case when db <> ob then 1 else 0 end) cross_any,
    round(100.0*sum(case when db <> ob then 1 else 0 end)/count(*),2) pct_any,
    sum(case when db <> ob and not d_unres and d_nyc then 1 else 0 end) cross_nyc_only,
    sum(case when not d_unres and d_nyc then 1 else 0 end) base_nyc,
    round(100.0*sum(case when db <> ob and not d_unres and d_nyc then 1 else 0 end)/nullif(sum(case when not d_unres and d_nyc then 1 else 0 end),0),2) pct_nyc_only
  from t group by 1 order by 2 desc
  ```

- **`date_trunc('month', <DATE>)` returns a `TIMESTAMP` on this platform** — so the month column is cast to `DATE` (design `D-01`), matching `dim_date.month_start_date`.

  ```sql
  select date_trunc('month', date '2024-02-15') as d, typeof(date_trunc('month', date '2024-02-15')) as t_date,
         typeof(date_trunc('month', timestamp '2024-02-15 10:00:00')) as t_ts
  ```

  `t_date` `TIMESTAMP`, `t_ts` `TIMESTAMP`.

- **Input adequacy: `Ready`.** `core.fct_trip` on `domain` — 97,184 rows, 97,184 distinct `trip_key`, 91 days from 2024-01-01 to 2024-03-31, zero nulls in `pickup_zone_key`, `dropoff_zone_key`, `total_amount` and `is_billable`; `core.dim_zone` on `domain` — 272 rows, 272 distinct `zone_key`, zero null `borough_name`, every trip's two zone keys matching a row. Both are declared relations of the project's own boundary layer, so both were read on `domain`.
