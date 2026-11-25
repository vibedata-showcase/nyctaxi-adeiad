# Verification: Borough-to-borough trips and revenue, Q1 2024 3

## Verification

`verdict: blocked` pending build: design discovery recorded, no model authored yet.

## Coverage

| Item | Evidence | Result | At |
| --- | --- | --- | --- |
| `R-01` grain | | | |
| `R-02` trip count closes to the star | | | |
| `R-03` revenue closes to the star | | | |
| `R-04` cross-borough share | | | |
| `R-05` every borough group retained | | | |
| `R-06` boundary artifacts | | | |
| `agg_borough_flow_monthly` model | | | |

## Gate results

| Gate | Command | Exit | Outcome |
| --- | --- | --- | --- |
| Data and unit tests | - | - | unrun (nothing built) |
| Project audit | - | - | unrun (nothing built) |
| Python tests | - | - | unrun (nothing built) |
| Python lint | - | - | unrun (nothing built) |
| sqlfluff | - | - | unrun (nothing built) |

## Discovery

All probes read `target: domain`, established by configuration: `_sources.yml` and
`dbt_project.yml` declare `core`/`agg` relations, and the Requirement names no
sandbox relation. Nothing this Intent built exists yet, so no relation was read
from `target: ephemeral`.

- **`core.fct_trip` — Ready.** Billable rows in the window: 95,958 (2024-01 29,985, 2024-02 30,017, 2024-03 35,956). No billable row has a null `pickup_zone_key`, null `dropoff_zone_key` or null `total_amount`; no row has `pickup_datetime::date <> pickup_date`, so `pickup_date` bounds and `pickup_datetime` bounds select the same rows. — `select count(*) as billable_trips, sum(case when pickup_zone_key is null then 1 else 0 end) as null_pickup_zone, sum(case when dropoff_zone_key is null then 1 else 0 end) as null_dropoff_zone, sum(case when total_amount is null then 1 else 0 end) as null_total from core.fct_trip where is_billable and pickup_date >= date '2024-01-01' and pickup_date < date '2024-04-01'` → 95958 / 0 / 0 / 0; and `select count(*) as rows, ... sum(case when pickup_datetime::date <> pickup_date then 1 else 0 end) as date_mismatch from core.fct_trip where is_billable` → 95958, 0.
- **Calendar coverage per month — no cut-short period.** Every day of every month in the window carries billable trips: 31 days in 2024-01, 29 in 2024-02, 31 in 2024-03, spanning 2024-01-01 to 2024-03-31. — `select strftime(pickup_date,'%Y-%m') as mth, count(distinct pickup_date) as days_present, count(*) as billable_trips from core.fct_trip where is_billable and pickup_date>=date '2024-01-01' and pickup_date<date '2024-04-01' group by 1 order by 1` → 2024-01 31 29985 / 2024-02 29 30017 / 2024-03 31 35956.
- **`core.dim_zone` — Ready.** 272 rows, 272 distinct `zone_key`, 265 distinct `zone_natural_key` (a zone may version), no null `zone_key`, no null `borough_name`. Eight borough groups, two of them unresolved (`N/A`, `Unknown`); `EWR` is out-of-state but not unresolved. — `select count(*) as rows_total, count(distinct zone_key) as distinct_zone_key, sum(case when zone_key is null then 1 else 0 end) as null_zone_key, sum(case when borough_name is null then 1 else 0 end) as null_borough, count(distinct zone_natural_key) as distinct_location_id, min(valid_from_date) as min_from, max(valid_to_date) as max_to from core.dim_zone` → 272 / 272 / 0 / 0 / 265 / 2019-01-01 / 2099-12-31; and `select borough_name, is_unresolved_zone, count(*) as zone_versions from core.dim_zone group by 1,2 order by 1` → Bronx 45, Brooklyn 64, EWR 1, Manhattan 71, N/A 1 (unresolved), Queens 69, Staten Island 20, Unknown 1 (unresolved).
- **The borough rollup closes to the star.** Summing month × origin borough × destination borough over billable trips reproduces the star's billable totals exactly, both trips and revenue, with both zone joins inner: 122 month × pair rows, 3 months. — `with b as (select strftime(f.pickup_datetime,'%Y-%m') as mth, o.borough_name as ob, d.borough_name as db, count(*) as trips, sum(f.total_amount) as rev from core.fct_trip f join core.dim_zone o on f.pickup_zone_key=o.zone_key join core.dim_zone d on f.dropoff_zone_key=d.zone_key where f.is_billable and f.pickup_date>=date '2024-01-01' and f.pickup_date<date '2024-04-01' group by 1,2,3), t as (select strftime(pickup_datetime,'%Y-%m') as mth, count(*) as trips, sum(total_amount) as rev from core.fct_trip where is_billable and pickup_date>=date '2024-01-01' and pickup_date<date '2024-04-01' group by 1) select t.mth, t.trips as star_trips, sum(b.trips) as matrix_trips, round(t.rev,2) as star_rev, round(sum(b.rev),2) as matrix_rev from t join b on t.mth=b.mth group by 1, t.trips, t.rev order by 1` → 2024-01 29985 29985 816057.76 816057.76; 2024-02 30017 30017 813885.68 813885.68; 2024-03 35956 35956 999242.38 999242.38.
- **Per-origin monthly cross-borough shares (the population `R-04` checks).** 24 origin × month groups. Shares range from 0 (EWR, which has no cross-borough departure) to 0.7396 (Queens in 2024-03). — `select strftime(f.pickup_datetime,'%Y-%m') as mth, o.borough_name as ob, count(*) as trips, sum(case when d.borough_name <> o.borough_name then 1 else 0 end) as outbound_cross, round(sum(case when d.borough_name <> o.borough_name then 1 else 0 end)::double / count(*), 6) as share from core.fct_trip f join core.dim_zone o on f.pickup_zone_key=o.zone_key join core.dim_zone d on f.dropoff_zone_key=d.zone_key where f.is_billable and f.pickup_date>=date '2024-01-01' and f.pickup_date<date '2024-04-01' group by 1,2 order by 1,2`.
- **`agg.agg_od_flow_matrix` cannot serve this grain.** 1,055 published rows covering 68,513 trips of the window's 95,958 billable trips; it has no month column (it totals the reporting window) and applies ADR 0017's floor. — `select count(*) as rows_published, sum(trip_count) as trips_covered from agg.agg_od_flow_matrix` → 1055 / 68513.
- **The 25-trip floor's effect at this grain (asked at the requirement stop, declined in favour of publishing every pair).** Applied to month × borough pairs it would keep 56 of the 122 rows and drop 253 trips. — `with b as (... group by 1,2,3) select count(*) as pairs_total, sum(case when trips>=25 then 1 else 0 end) as pairs_ge25, sum(trips) as trips_total, sum(case when trips>=25 then trips else 0 end) as trips_ge25 from b` → 122 / 56 / 95958 / 95705.
- **Recognised versus gross billable revenue (asked at the requirement stop; gross chosen).** Recognised revenue (payment method `counts_as_revenue`) is $31,310.45 below gross over the quarter: 797 billable dispute trips worth $20,431.24 and 490 no-charge trips worth $10,879.21 carry `counts_as_revenue = false`. — `select round(sum(case when p.counts_as_revenue then f.total_amount else 0 end),2) as recognised, round(sum(f.total_amount),2) as gross, round(sum(f.total_amount) - sum(case when p.counts_as_revenue then f.total_amount else 0 end),2) as diff from core.fct_trip f join core.dim_payment_method p on f.payment_method_key=p.payment_method_key where f.is_billable and f.pickup_date>=date '2024-01-01' and f.pickup_date<date '2024-04-01'` → 2594324.30 / 2625634.75 / 31310.45.
