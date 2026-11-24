# Verification: SS · borough flow

## Discovery

Design-time discovery for `agg_borough_flow_monthly`. Every query ran read-only against the Domain warehouse (`target: domain`); the sandbox is a copy taken at activation and holds the same relations, so nothing here needed the sandbox.

### Location of the upstream relations

`core.fct_trip` and `core.dim_zone` are declared Domain relations: `repo-map.json` names `core` as a boundary layer whose models are built by dbt, and no later artifact of this intent has landed them in the sandbox. Location established as `domain` by that declaration, then confirmed by `lakehouse_schema`.

### `core.fct_trip` — the only relation the new model reads at trip grain

Query as it ran:

```sql
select count(*) as trip_rows,
       count(*) filter (where is_billable) as billable_rows,
       min(pickup_date) as min_pickup_date,
       max(pickup_date) as max_pickup_date,
       count(*) filter (where pickup_zone_key is null) as null_pickup_zone_key,
       count(*) filter (where dropoff_zone_key is null) as null_dropoff_zone_key,
       count(*) filter (where total_amount is null) as null_total_amount,
       count(*) filter (where is_billable and total_amount <= 0) as billable_non_positive_total
from core.fct_trip
where pickup_date >= date '2024-01-01' and pickup_date < date '2024-04-01'
```

Result:

| trip_rows | billable_rows | min_pickup_date | max_pickup_date | null_pickup_zone_key | null_dropoff_zone_key | null_total_amount | billable_non_positive_total |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 97,184 | 95,958 | 2024-01-01 | 2024-03-31 | 0 | 0 | 0 | 0 |

**Verdict: `Ready`.** The window is covered end to end, both zone keys resolve on every row, and `total_amount` is populated and positive wherever `is_billable`.

### Window and period coverage

Query as it ran:

```sql
select date_trunc('month', pickup_date) as m, count(*) as trips, round(sum(total_amount), 2) as revenue
from core.fct_trip
where is_billable and pickup_date >= date '2024-01-01' and pickup_date < date '2024-04-01'
group by 1 order by 1
```

| month | trips | revenue |
| --- | --- | --- |
| 2024-01 | 29,985 | 816,057.76 |
| 2024-02 | 30,017 | 813,885.68 |
| 2024-03 | 35,956 | 999,242.38 |
| **window** | **95,958** | **2,629,185.82** |

Calendar coverage, query as it ran:

```sql
select date_trunc('month', d.calendar_date) as m, count(*) as days, min(d.calendar_date) as first_day, max(d.calendar_date) as last_day,
       count(*) filter (where exists (select 1 from core.fct_trip f where f.pickup_date = d.calendar_date)) as days_with_trips
from core.dim_date d
where d.calendar_date >= date '2024-01-01' and d.calendar_date < date '2024-04-01'
group by 1 order by 1
```

| month | days | first_day | last_day | days_with_trips |
| --- | --- | --- | --- | --- |
| 2024-01 | 31 | 2024-01-01 | 2024-01-31 | 31 |
| 2024-02 | 29 | 2024-02-01 | 2024-02-29 | 29 |
| 2024-03 | 31 | 2024-03-01 | 2024-03-31 | 31 |

Every month of the window is whole: no period is cut short, so no incomplete-period mark is owed (Requirement, "Edge periods").

### `core.dim_zone` — the dimension joined twice, in both roles

Query as it ran:

```sql
select borough_name, is_nyc, reporting_region, count(*) as zones
from core.dim_zone where is_current_version group by 1, 2, 3 order by 1
```

| borough_name | is_nyc | reporting_region | zones |
| --- | --- | --- | --- |
| Bronx | true | Outer Boroughs | 43 |
| Brooklyn | true | Outer Boroughs | 61 |
| EWR | false | Out of State | 1 |
| Manhattan | true | Manhattan Core | 69 |
| N/A | false | Unresolved | 1 |
| Queens | true | Outer Boroughs | 69 |
| Staten Island | true | Outer Boroughs | 20 |
| Unknown | false | Unresolved | 1 |

Eight borough values, so 64 possible borough pairs. Key uniqueness, query as it ran:

```sql
select count(*) as rows_total, count(distinct zone_key) as distinct_keys, count(*) filter (where is_unresolved_zone) as unres_rows
from core.dim_zone
```

| rows_total | distinct_keys | unres_rows |
| --- | --- | --- |
| 272 | 272 | 2 |

**Verdict: `Ready`.** `zone_key` is unique across all 272 versions, so neither role-playing join can fan a trip out. The two unresolved members are real rows (`is_unresolved_zone`), per ADR 0012.

### Join shape and the null-key path

Query as it ran:

```sql
with inner_j as (
  select date_trunc('month', f.pickup_date) as m, o.borough_name ob, dz.borough_name db, count(*) n, sum(f.total_amount) rev
  from core.fct_trip f join core.dim_zone o on f.pickup_zone_key = o.zone_key join core.dim_zone dz on f.dropoff_zone_key = dz.zone_key
  where f.is_billable and f.pickup_date >= date '2024-01-01' and f.pickup_date < date '2024-04-01' group by 1, 2, 3),
left_j as (
  select date_trunc('month', f.pickup_date) as m, o.borough_name ob, dz.borough_name db, count(*) n, sum(f.total_amount) rev
  from core.fct_trip f left join core.dim_zone o on f.pickup_zone_key = o.zone_key left join core.dim_zone dz on f.dropoff_zone_key = dz.zone_key
  where f.is_billable and f.pickup_date >= date '2024-01-01' and f.pickup_date < date '2024-04-01' group by 1, 2, 3)
select (select count(*) from inner_j) as inner_rows, (select count(*) from left_j) as left_rows,
       (select sum(n) from inner_j) as inner_trips, (select sum(n) from left_j) as left_trips,
       (select count(*) from left_j where ob is null or db is null) as null_borough_rows
```

| inner_rows | left_rows | inner_trips | left_trips | null_borough_rows |
| --- | --- | --- | --- | --- |
| 122 | 122 | 95,958 | 95,958 | 0 |

Inner and left joins agree exactly. The Requirement's "keep every row" choice is therefore inert on this window, which is what makes closure testable either way.

### Population and the thin-pair floor (R-02, R-04, R-05)

Query as it ran:

```sql
with p as (
  select date_trunc('month', f.pickup_date) as m, o.borough_name as ob, dz.borough_name as db,
         count(*) n, sum(f.total_amount) rev
  from core.fct_trip f
  join core.dim_zone o on f.pickup_zone_key = o.zone_key
  join core.dim_zone dz on f.dropoff_zone_key = dz.zone_key
  where f.is_billable group by 1, 2, 3)
select m, count(*) as pairs, count(*) filter (where n < 25) as pairs_under_25, min(n) as min_pairs,
       sum(case when n < 25 then rev else 0 end) as rev_under_25, sum(rev) as total_rev
from p group by 1 order by 1
```

| month | pairs | pairs_under_25 | min_pairs | rev_under_25 | total_rev |
| --- | --- | --- | --- | --- | --- |
| 2024-01 | 40 | 22 | 1 | 6,688.08 | 816,057.76 |
| 2024-02 | 40 | 21 | 1 | 5,231.55 | 813,885.68 |
| 2024-03 | 42 | 23 | 1 | 8,046.43 | 999,242.38 |

Requirements R-02 and R-04 cite these figures; the 25-trip floor question is settled by ADR 0018.

### Cross-borough share, per origin borough (R-03)

Query as it ran:

```sql
with p as (
  select date_trunc('month', f.pickup_date) as m, o.borough_name as ob, dz.borough_name as db,
         count(*) as trips, sum(f.total_amount) as rev
  from core.fct_trip f
  join core.dim_zone o on f.pickup_zone_key = o.zone_key
  join core.dim_zone dz on f.dropoff_zone_key = dz.zone_key
  where f.is_billable group by 1, 2, 3
), t as (select m, ob, sum(trips) as origin_trips, sum(case when ob <> db then trips else 0 end) as leaving from p group by 1, 2)
select m, ob, origin_trips, leaving, round(100.0 * leaving / origin_trips, 2) as share_leaving_pct from t order by m, ob
```

January 2024 rows (the other two months are recorded in the same run):

| origin borough | origin_trips | leaving | share_leaving_pct |
| --- | --- | --- | --- |
| Bronx | 108 | 64 | 59.26 |
| Brooklyn | 349 | 131 | 37.54 |
| EWR | 6 | 0 | 0.00 |
| Manhattan | 26,593 | 1,598 | 6.01 |
| N/A | 13 | 4 | 30.77 |
| Queens | 2,807 | 2,008 | 71.54 |
| Staten Island | 11 | 5 | 45.45 |
| Unknown | 98 | 24 | 24.49 |

R-03 cites January Manhattan 6.01% and Queens 71.54%; ADR 0019 records the choice of basis.

The alternative network-wide basis, for contrast only — the same run aggregated over origin boroughs:

| month | network share, all pairs | resolved-NYC-only basis |
| --- | --- | --- |
| 2024-01 | 12.79 | 11.74 |
| 2024-02 | 12.15 | 11.24 |
| 2024-03 | 13.16 | 12.24 |

### Unresolved and out-of-state exposure (R-05)

Query as it ran:

```sql
with p as (
  select date_trunc('month', f.pickup_date) as m, o.borough_name as ob, o.is_unresolved_zone as ob_unres,
         dz.borough_name as db, dz.is_unresolved_zone as db_unres, o.is_nyc as ob_nyc, dz.is_nyc as db_nyc,
         count(*) as trips
  from core.fct_trip f join core.dim_zone o on f.pickup_zone_key = o.zone_key join core.dim_zone dz on f.dropoff_zone_key = dz.zone_key
  where f.is_billable group by 1, 2, 3, 4, 5, 6, 7)
select m, sum(trips) as all_trips, sum(case when ob_unres or db_unres then trips else 0 end) as touching_unresolved,
       sum(case when not ob_nyc or not db_nyc then trips else 0 end) as touching_non_nyc,
       sum(case when ob = db then trips else 0 end) as intra,
       sum(case when ob <> db and not db_unres then trips else 0 end) as cross_excl_unresolved_dest
from p group by 1 order by 1
```

| month | all_trips | touching_unresolved | touching_non_nyc | intra | cross_excl_unresolved_dest |
| --- | --- | --- | --- | --- | --- |
| 2024-01 | 29,985 | 336 | 417 | 26,151 | 3,608 |
| 2024-02 | 30,017 | 300 | 367 | 26,370 | 3,458 |
| 2024-03 | 35,956 | 364 | 451 | 31,223 | 4,504 |

R-05 requires these groups to be present rather than dropped; ADR 0019 records that an unresolved destination counts as leaving the origin.

### Revenue definition (R-02)

Query as it ran:

```sql
select date_trunc('month', f.pickup_date) as m,
  sum(case when p.counts_as_revenue then f.total_amount else 0 end) as recognised_rev,
  sum(case when not p.counts_as_revenue then f.total_amount else 0 end) as non_revenue_rev,
  count(*) filter (where not p.counts_as_revenue) as non_revenue_trips,
  sum(f.total_amount) as billable_total_rev
from core.fct_trip f join core.dim_payment_method p on f.payment_method_key = p.payment_method_key
where f.is_billable group by 1 order by 1
```

| month | recognised_rev | non_revenue_rev | non_revenue_trips | billable_total_rev |
| --- | --- | --- | --- | --- |
| 2024-01 | 805,326.52 | 9,454.34 | 421 | 814,780.86 |
| 2024-02 | 802,407.58 | 9,921.63 | 404 | 812,329.21 |
| 2024-03 | 986,590.20 | 11,934.48 | 462 | 998,524.68 |

The chosen definition is billable `total_amount`, so no payment-method join is needed at all. (These totals are the same population as the window table above; the two differ only in whether the payment method join is present, which drops 106 trips with a null key across the window.)

### Reuse check (`agg.agg_od_flow_matrix`)

Query as it ran:

```sql
select sum(trip_count) as trips_in_matrix,
       (select count(*) from core.fct_trip where is_billable and pickup_date >= date '2024-01-01' and pickup_date < date '2024-04-01') as billable_trips_window,
       (select count(*) from agg.agg_od_flow_matrix) as matrix_rows
from agg.agg_od_flow_matrix
```

| trips_in_matrix | billable_trips_window | matrix_rows |
| --- | --- | --- |
| 68,513 | 95,958 | 1,055 |

The zone-pair matrix carries 68,513 of the window's 95,958 billable trips — 27,445 short — because of its 25-trip floor (ADR 0017). A borough share computed over it would have a numerator and denominator from a different population, so it cannot be reused. Matches the Requirement's `Reuse` row.

### Profiling verdicts

| Relation | Location | Verdict |
| --- | --- | --- |
| `core.fct_trip` | `domain` | `Ready` |
| `core.dim_zone` | `domain` | `Ready` |
| `core.dim_date` | `domain` | `Ready` (read only to establish period coverage) |
| `core.dim_payment_method` | `domain` | `Ready` (read only to size the revenue definition) |
| `agg.agg_od_flow_matrix` | `domain` | `Ready` (read only to rule reuse out) |
