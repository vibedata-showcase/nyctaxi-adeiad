# Verification: Daily zone revenue report from agg

## Discovery

Measurements taken while designing, on the Domain's DuckDB (`domain` target, read-only) and from the repository. These are the facts the design records rely on; the records cite this section rather than restating the numbers.

**Baseline agreement and the divergence.** The two relations do not compute the same thing today. The report's Q1 2024 figures match Ravi Menon's acceptance check exactly; agg's do not.

```sql
select
 (select count(*) from agg.agg_trip_zone_daily) as agg_rows,
 (select count(*) from finance.mart_daily_zone_revenue) as fin_rows,
 (select sum(trip_count) from finance.mart_daily_zone_revenue) as fin_trips,
 (select round(sum(total_revenue),2) from finance.mart_daily_zone_revenue) as fin_rev,
 (select sum(trip_count) from finance.mart_daily_zone_revenue where zone_name='JFK Airport') as jfk_trips,
 (select round(sum(total_revenue),2) from finance.mart_daily_zone_revenue where zone_name='JFK Airport') as jfk_rev,
 (select sum(trip_count) from agg.agg_trip_zone_daily) as agg_trips,
 (select round(sum(total_revenue),2) from agg.agg_trip_zone_daily) as agg_rev
```

Observed: `agg_rows` 7997, `fin_rows` 7961, `fin_trips` 95958, `fin_rev` 2629185.82, `jfk_trips` 4120, `jfk_rev` 337711.05, `agg_trips` 97184, `agg_rev` 2597120.92.

**Cause of the divergence** — the report filters to billable trips, agg counts all trips:

```sql
select sum(case when is_billable then 1 else 0 end) as billable_trips, count(*) as all_trips,
       sum(case when is_billable then total_amount else 0 end) as billable_revenue,
       sum(total_amount) as all_revenue
from core.fct_trip
where pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'
```

Observed: `billable_trips` 95958, `all_trips` 97184, `billable_revenue` 2629185.82, `all_revenue` 2597120.92. The billable pair equals the report's figures; the all-trip pair equals agg's.

**JFK under both populations.** `agg.agg_trip_zone_daily` for `zone_name = 'JFK Airport'` in Q1 observes 4261 trips and 329766.06 revenue, against the report's 4120 and 337711.05.

**Grain of agg, and that it is unchanged by adding `pickup_date_key`.**

```sql
select count(*) as rows,
       count(distinct (pickup_date, pickup_location_id)) as grain,
       count(distinct (pickup_date, pickup_location_id, pickup_date_key)) as grain_with_key
from agg.agg_trip_zone_daily
```

Observed: 7997 / 7997 / 7997 — the key adds no grain.

**Zone-days with no billable trip**, the population the report omits:

```sql
with b as (
  select f.pickup_date, z.zone_natural_key as zone, count(*) filter (where f.is_billable) as billable
  from core.fct_trip f join core.dim_zone z on f.pickup_zone_key = z.zone_key
  where f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01'
  group by 1,2
)
select count(*) as all_zone_days, count(*) filter (where billable = 0) as zone_days_zero_billable,
       (select count(*) from agg.agg_trip_zone_daily a join b on a.pickup_date=b.pickup_date and a.pickup_location_id=b.zone) as matched_in_agg,
       (select count(*) from agg.agg_trip_zone_daily) as agg_rows
from b
```

Observed: `all_zone_days` 7997, `zone_days_zero_billable` 36, `matched_in_agg` 7997, `agg_rows` 7997. The 36 zero-billable zone-days hold 37 non-billable trips. Every one of agg's 7997 zone-days is covered by the trip-level grouping, so the report's 7961 rows are exactly agg's rows minus these 36.

**The report's grain is a strict subset of agg's, and a same-grain recomputation is exactly equal** — this is the evidence that exact preservation (`R-04`) is achievable with no tolerance:

```sql
with expected as (
  select f.pickup_date as trip_date, z.zone_natural_key as pickup_location_id,
         count(*) filter (where f.is_billable) as trip_count,
         sum(case when f.is_billable then f.fare_amount else 0 end) as fare_revenue,
         sum(case when f.is_billable then f.tip_amount else 0 end) as tip_revenue,
         sum(case when f.is_billable then f.total_surcharges else 0 end) as surcharge_revenue,
         sum(case when f.is_billable then f.tolls_amount else 0 end) as toll_revenue,
         sum(case when f.is_billable then f.total_amount else 0 end) as total_revenue
  from core.fct_trip f join core.dim_zone z on f.pickup_zone_key = z.zone_key
  where f.pickup_datetime >= timestamp '2024-01-01' and f.pickup_datetime < timestamp '2024-04-01'
  group by 1,2
  having count(*) filter (where f.is_billable) > 0
)
select count(*) as joined_rows,
  count(*) filter (where m.trip_count is distinct from e.trip_count) as trip_count_diff,
  count(*) filter (where m.total_revenue is distinct from e.total_revenue) as total_diff,
  count(*) filter (where m.fare_revenue is distinct from e.fare_revenue) as fare_diff,
  count(*) filter (where m.tip_revenue is distinct from e.tip_revenue) as tip_diff,
  count(*) filter (where m.surcharge_revenue is distinct from e.surcharge_revenue) as surcharge_diff,
  count(*) filter (where m.toll_revenue is distinct from e.toll_revenue) as toll_diff
from expected e
left join finance.mart_daily_zone_revenue m
  on m.trip_date = e.trip_date and m.pickup_location_id = e.pickup_location_id
```

Observed: `joined_rows` 7961 and 0 differences in all six measures. Exact equality, no floating-point drift, because both sides sum the same values grouped by the same keys.

**No NULL reaches a measure, and no billable trip lacks a zone.**

```sql
select count(*) as trips,
       count(*) filter (where total_amount is null) as null_total,
       count(*) filter (where fare_amount is null) as null_fare,
       count(*) filter (where tip_amount is null) as null_tip,
       count(*) filter (where total_surcharges is null) as null_surcharge,
       count(*) filter (where tolls_amount is null) as null_toll,
       count(*) filter (where pickup_zone_key is null) as null_zone
from core.fct_trip
where pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01' and is_billable
```

Observed: 95958 trips, 0 nulls in every column. So `count(...)` and `count(*) filter (...)` agree, and no billable trip is dropped by agg's inner join.

**Expected component totals for the new billable columns** (independent recomputation the verify stage can hold the built relation to):

```sql
select sum(fare_amount) as fare, sum(tip_amount) as tip, sum(total_surcharges) as surcharge,
       sum(tolls_amount) as toll, sum(total_amount) as total
from core.fct_trip
where pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01' and is_billable
```

Observed: fare 1802576.08, tip 313865.43, surcharge 481752.42, toll 51368.39, total 2629185.82.

**Zone attributes are constant per natural key**, so grouping agg by `reporting_region` does not split a zone-day:

```sql
select count(*) as mismatches from (
  select z.zone_natural_key from core.dim_zone z group by 1
  having count(distinct z.reporting_region) > 1 or count(distinct z.zone_name) > 1
      or count(distinct z.borough_name) > 1
) t
```

Observed: 0. `dim_zone` is Type 2 and 5+ natural keys carry two versions, but no version pair differs in these attributes.

**Every `pickup_location_id` in agg still resolves to `dim_zone`** (the report's `relationships` test must keep passing despite no longer joining):

```sql
select count(*) as orphan_zone_ids
from (select distinct pickup_location_id from agg.agg_trip_zone_daily) a
left join (select distinct zone_natural_key from core.dim_zone) z
  on a.pickup_location_id = z.zone_natural_key
where z.zone_natural_key is null
```

Observed: 0.

**Edge periods are not cut short**, so no incomplete-period marking is needed:

```sql
select pickup_date, count(*) as trips, count(distinct pickup_hour) as hours,
       min(pickup_hour) as first_hour, max(pickup_hour) as last_hour
from core.fct_trip
where pickup_date in (date '2024-01-01', date '2024-02-29', date '2024-03-31')
group by 1 order by 1
```

Observed: each of the three dates carries 888 / 1312 / 975 trips across `hours` = 24, `first_hour` 0, `last_hour` 23. All 91 days of the window are present.

**No zero-trip rows in the report today** (so `R-06` restates existing behaviour):

```sql
select sum(case when trip_count = 0 then 1 else 0 end) as zero_trip_rows, min(trip_count) as min_trips
from finance.mart_daily_zone_revenue
```

Observed: `zero_trip_rows` 0, `min_trips` 1. `agg_trip_zone_daily` separately carries 7 rows whose all-trip `total_revenue` is 0.0 while `trip_count` is 1 or 2 — non-billable trips with zero total — which the report legitimately omits when they leave no billable trip in the zone-day.

**Precedent for a billable count beside an all-trip count in `agg`:**

```sql
select count(*) as rows_total, count(*) filter (where billable_trip_count = 0) as rows_zero_billable,
       count(*) filter (where billable_trip_count is null) as rows_null_billable
from agg.agg_trip_zone_daypart_dow
```

Observed: 5458 rows, 34 with `billable_trip_count = 0`, 0 null. `agg_trip_zone_daypart_dow` publishes `billable_trip_count` beside an all-trip `trip_count`; its `total_revenue` is not billable-filtered. Billable *revenue* columns are new to the `agg` layer.

**Change impact, from the compiled graph** (`dbt ls`, dbt 1.12.5):

- `dbt ls --select agg_trip_zone_daily+` → `agg_trip_zone_daily`, `assert_semantic_content_holds`, `assert_semantic_levels_hold`.
- `dbt ls --select mart_daily_zone_revenue+` → `mart_daily_zone_revenue`, `assert_semantic_content_holds`, `assert_semantic_levels_hold`, plus its three column tests (`not_null_..._total_revenue`, `not_null_..._trip_date`, `relationships_..._pickup_location_id`).
- No other model reads either relation.

**Baseline defer:** none. `transformation/packages.yml` exists and `dbt deps` installed; the dbt card for `duckdb_local` (`## Defer`) states no production manifest is published, so `--defer` is never passed and every `/data/cache` check is `not applicable`.
