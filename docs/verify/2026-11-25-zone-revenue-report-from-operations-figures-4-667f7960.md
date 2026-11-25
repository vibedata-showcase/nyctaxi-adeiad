# Verification: Zone revenue report from operations figures 4

## Coverage

| Item | Evidence | Result | At |
| --- | --- | --- | --- |
| `R-01` billable measures beside the all-trip ones | | | |
| `R-02` report built from the aggregate only | | | |
| `R-03` no number changes | | | |
| `R-04` report keeps its shape | | | |
| `R-05` no other consumer sees a changed number | | | |
| `R-06` contracts and documentation carry the change | | | |
| `agg_trip_zone_daily` | | | |
| `mart_daily_zone_revenue` | | | |

## Gate results

| Gate | Command | Exit | Outcome |
| --- | --- | --- | --- |
| Build and data tests, `agg_trip_zone_daily` and its parents | - | - | unrun until execution |
| Build and data tests, `mart_daily_zone_revenue` | - | - | unrun until execution |
| Unit tests | - | - | unrun until execution |
| Semantic model gates | - | - | unrun until execution |
| Contract check | - | - | unrun until execution |
| Project audit | - | - | unrun until execution |

## Discovery

- The aggregate is already one row per zone-day with no null key, no null zone name or borough, and spans the whole reporting window — `select count(*) as rows, count(distinct (pickup_date, pickup_location_id)) as distinct_grain, count(*) filter (where pickup_location_id is null) as null_loc, count(*) filter (where pickup_date is null) as null_date, count(*) filter (where zone_name is null) as null_zone_name, count(*) filter (where borough_name is null) as null_borough, min(pickup_date) as d0, max(pickup_date) as d1, count(distinct pickup_location_id) as zones from agg.agg_trip_zone_daily` → 7,997 rows, 7,997 distinct (pickup_date, pickup_location_id), 0 null in each of the three, 2024-01-01 to 2024-03-31, 262 zones.

- The fact carries every measure the report publishes, non-null, in the window, and splits cleanly into billable and non-billable — `select count(*) filter (where is_billable) as billable_trips, count(*) filter (where not is_billable) as nonbillable_trips, round(sum(fare_amount) filter (where is_billable),2) as billable_fare, round(sum(tip_amount) filter (where is_billable),2) as billable_tip, round(sum(total_surcharges) filter (where is_billable),2) as billable_surcharge, round(sum(tolls_amount) filter (where is_billable),2) as billable_toll, round(sum(total_amount) filter (where is_billable),2) as billable_total, count(*) filter (where is_billable and pickup_zone_key is null) as billable_null_zone from core.fct_trip where pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'` → 95,958 billable and 1,226 non-billable; billable fare 1,802,576.08, tip 313,865.43, surcharge 481,752.42, toll 51,368.39, total 2,629,185.82; 0 billable trips with a null zone key.

- Every measure column is non-null on every in-window trip, so no null reaches a billable sum — `select ... count(*) filter (where total_amount is null) as null_total, count(*) filter (where fare_amount is null) as null_fare, count(*) filter (where tip_amount is null) as null_tip, count(*) filter (where total_surcharges is null) as null_surcharge, count(*) filter (where tolls_amount is null) as null_tolls ... from core.fct_trip where pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'` → 97,184 rows, 0 null in each of the five.

- The aggregate and the report disagree, and the disagreement is exactly the non-billable population: 36 zone-days exist in the aggregate with no row in the report, carrying 37 trips and −545.10 revenue, and every one of them has zero billable trips — `select a.pickup_date, a.pickup_location_id, a.trip_count, a.total_revenue ... from agg.agg_trip_zone_daily a left join finance.mart_daily_zone_revenue m on m.trip_date=a.pickup_date and m.pickup_location_id=a.pickup_location_id where m.pickup_location_id is null` → 36 rows, all with a zero-billable recomputation from the fact; aggregate totals 7,997 rows / 97,184 / 2,597,120.92 against the report's 7,961 / 95,958 / 2,629,185.82.

- The reporting window is whole: the fact holds nothing outside it and covers every day of it — `select count(*) as total_rows, min(pickup_datetime) as first_ts, max(pickup_datetime) as last_ts, count(*) filter (where pickup_datetime < timestamp '2024-01-01' or pickup_datetime >= timestamp '2024-04-01') as outside_window from core.fct_trip` → 97,184 rows, 2024-01-01T00:05:25 to 2024-03-31T23:56:17, 0 outside. The report spans 91 trip dates, so no period is cut short.

- The report's cells are exactly the billable recomputation of the fact — cell-level full outer join of a billable-only recomputation against `finance.mart_daily_zone_revenue` on `(trip_date, pickup_location_id)` → 7,961 cells compared, 0 differing on `trip_count`, `fare_revenue`, `tip_revenue`, `surcharge_revenue`, `toll_revenue` or `total_revenue`, and 0 cells on either side absent from the other.

- Simulating the designed aggregate (billable measures added by `filter (where is_billable)` inside the existing group by) and rebuilding the report from it with `billable_trip_count > 0` reproduces today's report exactly — `with billable as (... count(*) filter (where f.is_billable) as billable_trip_count, sum(f.fare_amount) filter (where f.is_billable) as billable_fare_revenue, ... group by 1,2), agg_new as (...), report_new as (...) select count(*) as new_rows, ... from report_new n join finance.mart_daily_zone_revenue m on n.trip_date=m.trip_date and n.pickup_location_id=m.pickup_location_id` → 7,961 rows, 0 in the old report missing from the new one, 0 in the new one missing from the old, 0 cells differing on any of the six measures, 0 cells differing on `zone_name`, `borough` or `reporting_region`.

- The aggregate's own as-of zone join yields one `reporting_region` per zone-day and the same value the report publishes — `with as_of as (select z.zone_natural_key as loc, f.pickup_date, z.reporting_region from core.fct_trip f join core.dim_zone z on f.pickup_zone_key = z.zone_key where ... group by 1,2,3) select count(*) as matched_cells, count(*) filter (where a.reporting_region is distinct from m.reporting_region) as region_differs from as_of a join finance.mart_daily_zone_revenue m on m.trip_date = a.pickup_date and m.pickup_location_id = a.loc` → 7,961 matched cells, 0 differing; and 7,997 as-of zone-days with 0 carrying more than one region.

- Carrying `reporting_region` on the aggregate bounds the choice between reading it there and re-joining the dimension, because an unfiltered natural-key join fans out: `select count(*) as naive_join_rows from agg.agg_trip_zone_daily a join core.dim_zone z on z.zone_natural_key = a.pickup_location_id` → 8,220 rows for 7,997 aggregate rows. `core.dim_zone` holds 272 rows over 265 natural keys, 7 keys with two versions, so a join must carry the date and be half-open (ADR 0009).

- An as-of join from the aggregate to the dimension reproduces the report exactly where it is used — the same simulation with `left join core.dim_zone z on z.zone_natural_key = n.pickup_location_id and n.pickup_date >= z.valid_from_date and n.pickup_date < z.valid_to_date` → 7,961 rows, 0 null `reporting_region`, 0 cells missing from either side, 0 cells differing on measure or region.

- A filtered sum returns NULL where the count returns zero: on the 36 zone-days with no billable trip the count is 0 and each of the five money columns is NULL — `with billable as (... count(*) filter (where f.is_billable) as billable_trip_count, sum(f.fare_amount) filter (where f.is_billable) as billable_fare_revenue, sum(f.total_amount) filter (where f.is_billable) as billable_total_revenue ... group by 1,2) select count(*) as zone_days, count(*) filter (where billable_trip_count = 0) as zero_count_rows, count(*) filter (where billable_trip_count is null) as null_count_rows, count(*) filter (where billable_fare_revenue is null) as null_fare_rows, count(*) filter (where billable_total_revenue is null) as null_total_rows from billable` → 7,997 zone-days, 36 with a zero count, 0 with a null count, 36 with a null fare and 36 with a null total.

- Aggregating those NULLs changes no total: the billable sum over the whole window equals the report's, because a sum ignores NULL — the billable profile above returns 95,958 trips / 2,629,185.82 total, matching the report's published figures.
