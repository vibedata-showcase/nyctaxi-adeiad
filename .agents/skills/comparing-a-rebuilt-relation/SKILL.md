---
name: comparing-a-rebuilt-relation
description: "Use when a rebuilt or changed relation must be proven to match a baseline: a sandbox build checked against the Domain table, a model compared across a change, or a verification record that has to state a diff count."
---

# Comparing a rebuilt relation

One question decides it: does every column of the rebuilt relation agree with the baseline under a criterion the comparison states? Not "are the two files identical" — DuckDB float aggregation is not reproducible bit for bit, so exact equality on a `double` fails on correct rebuilds.

## The criterion, per column

| Column | Criterion |
| --- | --- |
| INTEGER, BIGINT, DATE, VARCHAR, BOOLEAN | null-safe exact equality |
| DOUBLE money (revenue, amount, fee, tip, total) | equal at the cent: `round(x, 2)` on both sides |
| other DOUBLE measures (miles, duration, distance) | `round(x, 2)`, or an absolute tolerance when the measure is coarser than a cent |
| DOUBLE averages and ratios (`avg`, a share, a rolling mean) | an explicit tolerance: `abs(a - b) <= 1e-6`. Rounding a ratio to cents hides real drift |
| rank or `row_number` over a float | tie-driven — see below |
| key column | never compared for value; it is the join |

Money is the cent because summing the same rows in a different parallel order moves the last bits of a `double`: deltas around 1e-9 on values near 1e8, with the aggregation logic unchanged.

## Compare on the declared grain, both directions

Join on the relation's key and use a **full outer** join, so a row the rebuild dropped or added is counted instead of silently dropped by the join. Join null-safely: DuckDB's `USING` does not match a NULL key to a NULL key on a full outer join, so a nullable key column needs `ON a.k IS NOT DISTINCT FROM b.k`.

```sql
with j as (
    select
        coalesce(b.pickup_date, n.pickup_date) as pickup_date,
        coalesce(b.pickup_location_id, n.pickup_location_id) as pickup_location_id,
        b.trip_count as base_trip_count,
        n.trip_count as new_trip_count,
        b.total_revenue as base_revenue,
        n.total_revenue as new_revenue
    from base b
    full outer join new n
        on b.pickup_date is not distinct from n.pickup_date
       and b.pickup_location_id is not distinct from n.pickup_location_id
)

select
    count(*) as joined_rows,
    count(*) filter (where base_trip_count is null or new_trip_count is null) as one_sided_rows,
    count(*) filter (where base_trip_count is distinct from new_trip_count) as trip_count_diff,
    count(*) filter (where round(base_revenue, 2) is distinct from round(new_revenue, 2)) as revenue_diff_cent
from j
```

`is distinct from` / `is not distinct from` throughout: plain `=` and `<>` return NULL against a NULL, so a comparison that should count a difference reports nothing.

## Reading the two relations

- **First route: the platform tools.** `summarize_data` takes the Domain and the sandbox as two `{target, sql}` aliases in one query and does the join for you; select only the columns the comparison needs, because each alias is capped at 100,000 rows and a larger relation must take the second route.
- **Second route: one read-only connection.** Run through the runtime wrapper, which loads the Intent's settings into the process:

  ```bash
  <plugin>/scripts/vd-intent-context-run.sh 'python3 compare.py'
  ```

  and inside it `ATTACH '<VD_DOMAIN_DUCKDB_LOCAL_PATH>' AS dom (READ_ONLY)` and `ATTACH '<VD_EPHM_DUCKDB_LOCAL_PATH>' AS eph (READ_ONLY)`. Resolve each path from its setting; never type it. Both attachments are read-only, and the sandbox file admits one writer at a time, so close the connection before any build.

## Tie-driven columns

A rank over a float is not reproducible, and its diff count is not a regression: when values tie, or sit within a float delta of each other, the order `rank()` sees can differ between two correct builds. Report the count and name the cause instead of filing it as drift.

- Count the tie groups at the ranking partition: `group by <partition>, <ranked value> having count(*) > 1`.
- Accept a handful of differing rows out of tens of thousands **only** when the ranked value itself agrees at the cent on those rows.
- Never widen that into a licence for the rest of the table: every other column keeps its criterion.

## The rounding trap

`round()` is itself unstable at a half-cent: `round(0.125, 2)` is `0.13`, and the same value moved by 1e-12 rounds to `0.12`. So cent comparison is sound only for a money column that cannot hold a half-cent value. Check it before trusting the rule:

```sql
select count(*) from t where abs(x * 100 - floor(x * 100) - 0.5) < 1e-6;
```

A non-zero count means the column can land on the boundary, and its criterion is an absolute tolerance (`abs(a - b) <= 0.005`) instead of rounding.

## What goes in the record

- One line per column compared, with its criterion and its diff count.
- The headline number is the rows differing **under the criterion**, plus `one_sided_rows`. Never quote an exact-equality diff count as the headline: it measures float noise, not the change.
- The two relations, the key and grain used, and the commit compared.

## Common mistakes

| Mistake | Fix |
| --- | --- |
| `select count(*) from a join b using (k) where a.x <> b.x` | An inner join hides one-sided rows and `<>` hides NULLs. Full outer plus `is distinct from` |
| Comparing a row hash, or `except`/`intersect` on doubles | Exact by construction, so it reports float noise as a difference |
| Using `except` to count differing rows | It also reports a row whose *other* columns changed; count per column instead |
| Quoting an exact-equality diff count as the headline | On a `double` it counts float noise. Round to the cent and quote the rows that differ under the criterion |
| Treating a rank diff as a regression | Check the tie groups and the ranked value first |
| Assuming the rebuild is right because the stored table does not reproduce itself | The stored Domain table is the baseline. A rebuild that disagrees with it is a finding to explain, never a pass |
