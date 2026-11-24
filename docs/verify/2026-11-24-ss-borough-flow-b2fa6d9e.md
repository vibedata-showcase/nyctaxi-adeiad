# Verification: SS · borough flow

## Verification

`verdict: —` Not yet run: the Plan is not executed.

## Coverage

| Item | Evidence | Result | At |
| --- | --- | --- | --- |
| `R-01` grain and row count | — | — | — |

## Gate results

| Gate | Command | Exit | Outcome |
| --- | --- | --- | --- |
| data and unit tests | — | `-` | unrun |
| acceptance checks | — | `-` | unrun |
| project audit | — | `-` | unrun |
| semantic model gates | — | `-` | unrun |
| dev-artifact scan | — | `-` | unrun |

## Discovery

Written by `designing` for `2026-11-24-ss-borough-flow-b2fa6d9e`. Every figure below comes from a query run this session against the Domain warehouse (`core.fct_trip`, `core.dim_zone`, `mdm_raw.borough_master`, target `domain`); none is a prediction.

**Input adequacy: `Ready`.** Both upstream relations exist in the sandbox as copies of the Domain database, carry the columns the model needs, and are fully populated for the window.

### `core.fct_trip` — `Ready`

- 97,184 trips, 97,184 distinct `trip_key`, 0 null `trip_key`.
  `select count(*) as trips, count(distinct trip_key) as distinct_trips, count(*) filter (where pickup_zone_key is null) as null_pu, count(*) filter (where dropoff_zone_key is null) as null_do, count(*) filter (where pickup_datetime is null) as null_dt, min(pickup_date) as min_d, max(pickup_date) as max_d, typeof(min(pickup_date)) as dt_type, typeof(sum(total_amount)) as tot_type from core.fct_trip`
  → 97184 / 97184 / 0 / 0 / 0 / 2024-01-01 / 2024-03-31 / DATE / DOUBLE
- The window is complete: 2024-01-01 to 2024-03-31, with 31, 29 and 31 distinct pickup dates per month, so no month is cut short.
  `select date_trunc('month', pickup_date) as m, count(distinct pickup_date) as days_present, min(pickup_date) as first_d, max(pickup_date) as last_d from core.fct_trip where pickup_date >= date '2024-01-01' and pickup_date < date '2024-04-01' group by 1 order by 1`
  → (2024-01: 31, 2024-01-01, 2024-01-31), (2024-02: 29, 2024-02-01, 2024-02-29), (2024-03: 31, 2024-03-01, 2024-03-31)
- In the window, 97,184 trips of which 95,958 are billable and 0 carry a null or non-positive-only `total_amount` path that would make revenue undefined: `total_amount` is never null and 1,226 trips have a non-positive total.
  `select count(*) as trips, count(*) filter (where total_amount is null) as null_total, count(*) filter (where total_amount <= 0) as nonpositive, count(*) filter (where is_billable) as billable from core.fct_trip where pickup_date >= date '2024-01-01' and pickup_date < date '2024-04-01'`
  → 97184 / 0 / 1226 / 95958

### `core.dim_zone` — `Ready`

- 272 rows, 272 distinct `zone_key`, 0 null `zone_key`, 265 distinct `zone_natural_key` (a zone can have several versions).
  `select count(*) as zones, count(distinct zone_key) as distinct_keys, count(*) filter (where zone_key is null) as null_keys, count(distinct zone_natural_key) as distinct_naturals from core.dim_zone`
  → 272 / 272 / 0 / 265
- Eight distinct borough labels, `borough_name` never null and never empty. Five are city boroughs (`is_nyc` true); `EWR` is out of state; `N/A` and `Unknown` are the unresolved zones (`is_unresolved_zone` true, reporting region `Unresolved`).
  `select borough_name, is_nyc, reporting_region, count(*) as zones from core.dim_zone where is_current_version group by 1,2,3 order by 1`
  → Bronx(true, Outer Boroughs, 43), Brooklyn(true, Outer Boroughs, 61), EWR(false, Out of State, 1), Manhattan(true, Manhattan Core, 69), N/A(false, Unresolved, 1), Queens(true, Outer Boroughs, 69), Staten Island(true, Outer Boroughs, 20), Unknown(false, Unresolved, 1)
- `select count(*) as zones, count(*) filter (where borough_name is null) as null_borough, count(*) filter (where borough_name = '') as empty_borough from core.dim_zone` → 272 / 0 / 0
- `mdm_raw.borough_master` agrees with the labels: 8 rows, the same eight names, `Unknown` and `N/A` sharing borough code `XX` and `EWR` carrying code `NJ` (`select * from mdm_raw.borough_master`).

### The settled population, measured

Recomputed as the designed model will compute it: billable trips in the window, each zone joined through its own surrogate key, `unresolved` as one member, EWR dropped on both sides, month × origin × destination spine.

- Row count under the settled population: 108 rows (6 members × 6 members × 3 months), of which 15 carry no trips. A variant that keeps EWR gives 147 rows / 43 zero rows.
  `with groups as (select unnest(['Bronx','Brooklyn','Manhattan','Queens','Staten Island','unresolved']) as g), months as (select unnest([date '2024-01-01', date '2024-02-01', date '2024-03-01']) as m0), spine as (select m0, o.g as ob, d.g as db from months cross join groups o cross join groups d), trips as (select date_trunc('month', f.pickup_date) as m, case when o.is_unresolved_zone then 'unresolved' else o.borough_name end as ob, case when d.is_unresolved_zone then 'unresolved' else d.borough_name end as db, count(*) as trips, sum(f.total_amount) as rev from core.fct_trip f join core.dim_zone o on f.pickup_zone_key = o.zone_key join core.dim_zone d on f.dropoff_zone_key = d.zone_key where f.is_billable and f.pickup_date >= date '2024-01-01' and f.pickup_date < date '2024-04-01' and (o.is_nyc or o.is_unresolved_zone) and (d.is_nyc or d.is_unresolved_zone) group by 1,2,3), f as (select s.m0, s.ob, s.db, coalesce(t.trips,0) as trips, coalesce(t.rev,0) as rev from spine s left join trips t on t.m=s.m0 and t.ob=s.ob and t.db=s.db) select (select count(*) from f) as rows_total, (select count(*) from f where trips=0) as zero_rows, (select sum(trips) from f) as total_trips, (select round(sum(rev),2) from f) as total_rev ...`
  → 108 rows, 15 zero rows, 95,723 trips, 2,599,668.55 revenue
- Composition of those 95,723 trips: 11,249 cross-borough (both sides a city borough, origin ≠ destination), 83,474 in-borough (both sides the same city borough), 1,000 touching an unresolved zone and nothing else, EWR excluded. 11,249 + 83,474 = 94,723 city-to-city trips.
  `...select sum(trips) filter (where ob_nyc and db_nyc and ob<>db) as cross, sum(trips) filter (where ob_nyc and db_nyc) as resolved_denom, sum(trips) filter (where ob_nyc and db_nyc and ob=db) as intra, sum(trips) as total from trips`
  → 11249 / 94723 / 83474 / 95723
- Trips touching an unresolved zone: 1,000 in total, 360 with an unresolved origin, 902 with an unresolved destination, 262 with both.
  `...select sum(trips) filter (where ob='unresolved') as origin_unres, sum(trips) filter (where db='unresolved') as dest_unres, sum(trips) filter (where ob='unresolved' or db='unresolved') as touching, sum(trips) filter (where ob='unresolved' and db='unresolved') as both_unres, sum(trips) as total from trips`
  → 360 / 902 / 1000 / 262 / 95723
- EWR: 235 billable trips over the quarter, 12 starting there and 235 ending there, $29,517.27 of revenue — the difference between the window's 95,958 and the table's 95,723.
  `...select count(*) filter (where not ob_nyc and ob <> 'unresolved') as origin_ewr_trips, count(*) filter (where not db_nyc and db <> 'unresolved') as dest_ewr_trips, count(*) filter (where (not ob_nyc or not db_nyc) and ob <> 'unresolved' and db <> 'unresolved') as trips_with_ewr, round(sum(total_amount) filter (...),2) as rev_with_ewr, count(*) as total from base`
  → 12 / 235 / 235 / 29517.27 / 95958
- The thinnest populated city-to-city corridors per month, which the absent floor keeps: Bronx → Brooklyn 11 (January) and 13 (March), Bronx → Queens 10 (March). A 25-trip floor would have dropped 43 of the 93 populated month-pairs.
  `with trips as (... group by m, ob, db) select count(*) as observed_cells, count(*) filter (where trips >= 25) as cells_kept, count(*) filter (where trips < 25) as cells_dropped ...`
  → 93 observed / 50 kept / 43 dropped, minimum cell 1
- The share, recomputed per origin and month as summed cross-borough trips over summed trips to a resolved destination: Bronx 58.88 / 64.63 / 50.67 %, Brooklyn 37.18 / 40.21 / 42.96 %, Manhattan 5.30 / 5.21 / 5.36 %, Queens 70.52 / 72.17 / 73.13 %, Staten Island 40.00 / 0.00 / 37.50 % for January, February, March. The `unresolved` origin has no share (its denominator is empty: no trip from an unresolved zone reaches a resolved destination).
  `with trips as (... group by m, ob, ob_nyc, db, db_nyc), o as (select m, ob, ob_nyc, sum(trips) filter (where ob_nyc and db_nyc and db<>ob) as cross_trips, sum(trips) filter (where ob_nyc and db_nyc) as denom_trips from trips group by 1,2,3) select m, ob, cross_trips, denom_trips from o where denom_trips is null or denom_trips = 0`
  → the only empty-denominator origin-months are `unresolved` in all three months
- Spot-check pairs to recompute at verify: January Manhattan → Brooklyn 538 trips / $23,583.72; January Manhattan → Manhattan 24,995 / $515,753.34; January Manhattan → unresolved 128 / $6,880.39; January Bronx → Brooklyn 11 / $623.44; March Queens → Manhattan 1,825 / $147,649.07; March Queens → Queens 870 / $31,810.94.
  `...select m, ob, db, trips, round(rev,2) as rev from trips where (m=date '2024-01-01' and ob in ('Manhattan','Bronx') and db in ('Brooklyn','Manhattan','unresolved')) or (m=date '2024-03-01' and ob='Queens' and db in ('Manhattan','Queens')) order by m, ob, db`

### What the semantic layer already answers

The canonical model reaches borough-to-borough flow from the detail source today, in one query, without a new table:

`semantic_query(mode="sql", metrics=["billable_trip_count","billable_revenue"], group_by=[{via:"trips_to_pickup_zone", level:"borough"}, {via:"trips_to_dropoff_zone", level:"borough"}])`
→ source `LTS1_detail`, seven sources rejected (the two aggregate roles cannot roll a versioned `dim_zone` up without the fact's date, or hold no level of the drop-off role), SQL grouping `fct_trip` by the pickup and drop-off borough names.

That query does **not** answer this requirement: it groups by the raw `borough_name`, so `Unknown` and `N/A` stay two members rather than one `unresolved` group, it keeps EWR, it emits no zero rows, and it has no share. The table exists to fix those four things in one published relation, not to replace the star query for the questions it already answers.
