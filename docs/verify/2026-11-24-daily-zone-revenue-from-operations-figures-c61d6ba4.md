# Verification: Daily zone revenue from operations figures

## Verification

`verdict: ` at ``:

## Coverage

| Item | Evidence | Result | At |
| --- | --- | --- | --- |

## Gate results

| Gate | Command | Exit | Outcome |
| --- | --- | --- | --- |

## Discovery

Written by designing. Each result below is the design's input-adequacy evidence; the
queries ran read-only against the Domain warehouse at commit `1184020`. Measurements
live here, never in a design record.

- **Relations are located on `domain`**: `finance.mart_daily_zone_revenue`,
  `agg.agg_trip_zone_daily` and `core.fct_trip` were read through `lakehouse_schema`
  on target `domain` with `schemaName` and `tableName` set, which found each on that
  target. The sandbox holds the same 102 relations and is a copy taken at activation.

- **Input adequacy: `Ready` for `agg_trip_zone_daily`.** Its upstream `core.fct_trip`
  is non-empty and complete for the window; the sandbox `fct_trip` holds 9,722,362
  rows in total and 9,722,336 inside the reporting window, with 9,604,511 billable.
  No required field is absent and no join key is null. — `select count(*) from core.fct_trip`

- **Zone join drops no row and has no null key in the window.** `fct_trip` in the
  window: 0 null `pickup_zone_key`, 0 `pickup_zone_key` with no `dim_zone` row,
  262 distinct `pickup_zone_key` values. — `select ... from core.fct_trip where
  pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'`

- **Every money and count column the mart needs is populated on billable trips.**
  Among in-window billable trips: 0 null `total_amount`, 0 null `fare_amount`,
  0 null `tip_amount`, 0 null `total_surcharges`, 0 null `tolls_amount`. —
  `select count(*) filter (where <col> is null) ... where is_billable and <window>`

- **Zone attributes are functionally determined by `zone_natural_key`, so adding
  `reporting_region` to the agg cannot split a group.** `dim_zone` has 272 rows over
  265 distinct `zone_natural_key` values; 7 zones carry two versions, and for every
  one of them `zone_name`, `borough_name` and `reporting_region` are identical across
  the versions. Queried as: 0 zones with more than one `zone_name`, 0 with more than
  one `borough_name`, 0 with more than one `reporting_region`. — `select ... from
  core.dim_zone group by zone_natural_key`

- **Adding `reporting_region` to the agg's group-by leaves its row set identical.**
  Today's `agg.agg_trip_zone_daily` has 20,771 rows; the same grouping plus
  `reporting_region` returns 20,771 rows with 0 rows on either side of a full outer
  join. — `with abs as (...) ... full outer join`

- **Adding billable measures does not add rows either.** A group-by at zone × day
  with `count(*) filter (where is_billable)` and the billable sums returns 20,771
  rows, the same set. — `with filtersum as (...) ...`

- **The mart's row set is a strict subset of the agg's: 20,770 of 20,771.** The one
  extra agg row is `2024-02-12`, zone `175`, with `trip_count` 1 and
  `total_revenue` 0.0 — a trip with a zero total, so no billable trip on that
  zone-day. This is the row the user's "publish 0" answer covers. — `full outer join`
  of `finance.mart_daily_zone_revenue` against `agg.agg_trip_zone_daily`

- **The consolidated build reproduces the mart's numbers at cent precision.**
  Rebuilding the mart's six numeric columns from `fct_trip` at zone × day with
  `filter (where is_billable)` and comparing row by row against today's mart over
  20,770 rows: 0 differing `trip_count`, 0 differing money values at `round(x, 2)`,
  and 0 differing `borough`/`zone_name`/`reporting_region`. — `with new_mart as
  (...) select count(*) filter (where round(n.total_revenue,2) <> round(o.total_revenue,2)) ...`

- **Money sums are not bit-reproducible, which is why the acceptance is cent
  precision.** The same comparison without rounding differs in the last float bits
  on 9,836 of 20,770 rows, max absolute delta 2.97e-9. The cause is not the
  restructuring: recomputing `agg.agg_trip_zone_daily`'s own stored `total_revenue`
  and `total_miles` from `fct_trip` with its own SQL shape differs from the stored
  values on 9,877 of 20,771 rows, max absolute delta 3.49e-9. Exact
  `DECIMAL(18,2)` summation then cast back to `DOUBLE` also differs from the stored
  mart on 7,652 of 20,770 rows, so decimal arithmetic is not a route to bit equality
  either. — two queries: the unrounded form of the comparison above, and
  `with recomputed as (...) join agg.agg_trip_zone_daily`

- **Ravi's acceptance figures are today's mart, and the two candidate "operations"
  sources are different populations.** Over Q1 2024:
  `finance.mart_daily_zone_revenue` gives 9,604,511 trips and 263,480,834.99
  revenue, JFK (zone 132) 416,460 and 33,881,378.28;
  `agg.agg_trip_zone_daily` gives 9,722,336 and 260,487,920.62, JFK 429,806 and
  33,140,983.67; `ops_raw.trip_assignment` joined to `fct_trip` for billable
  in-window trips gives 457,991 and 12,639,955.27, JFK 20,713 and 1,679,105.07. The
  agg carries no billable revenue column at all. — three aggregate queries, one per
  relation

- **The operator's records match `fct_trip` exactly on the trips they cover, and
  cover only the fleet.** `ops_raw.trip_assignment` has 463,848 rows, all of which
  match a `fct_trip` row by `trip_key`; on those, `pickup_location_id`,
  `total_amount` and pickup time are identical to `fct_trip`, and 5,857 are
  non-billable. `fct_trip` has 463,848 `is_fleet_attributed` rows out of 9,722,362,
  all of them yellow. — `with m as (...) select count(*), sum(...) ...`

- **The data covers every day of Q1, so no period is cut short.** `fct_trip` spans
  2002-12-31 to 2024-04-01, and inside the window it has 91 distinct `pickup_date`
  values from 2024-01-01 to 2024-03-31, which is every day of the quarter. — `select
  min(pickup_date), max(pickup_date), count(distinct pickup_date) ...`

- **DuckDB concurrency**: the sandbox admits one writer, and the Domain file is
  read-only to this work; all queries above are `select` only.
