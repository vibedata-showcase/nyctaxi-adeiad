---
name: comparing-a-rebuilt-relation
description: "Use when a rebuilt or changed relation must be proven to match a baseline: a sandbox build checked against the Domain table, a model compared across a change, or a verification record that has to state a diff count."
---

# Comparing a rebuilt relation

One question decides it: does every column of the rebuilt relation agree with the baseline under a criterion the comparison states? Not "are the two files identical" — DuckDB float aggregation is not reproducible bit for bit, so exact equality on a `double` fails on correct rebuilds.

## First: prove the two sides are different

The sandbox starts as a copy of the Domain file, so before any comparison decide whether the relation was actually rebuilt. `md5sum` both files, and `stat` their size and mtime:

```bash
vd-intent-context-run.sh 'md5sum "$VD_DOMAIN_DUCKDB_LOCAL_PATH" "$VD_EPHM_DUCKDB_LOCAL_PATH"'
```

- **Identical hashes mean the comparison is vacuous.** Every column returns zero because both sides are the same bytes, and a zero proves nothing about the build. Report it as `INCONCLUSIVE`, not a pass.
- A rebuilt relation changes the file, so the hashes differ and a zero starts to carry information.
- Record both hashes beside the verdict in the verification record, so the next reader can tell a legitimate zero from a vacuous one.

Two further guards make a zero mean something:

- **Positive control.** Perturb one row by **more than the criterion** and confirm the harness reports it. For cent comparison, move a money cell by `0.01`, not `0.001`: a thousandth of a cent is below the criterion, so `0` there is the criterion working correctly, not a broken harness. Confirm `diff_rows` becomes 1.
- **Negative control.** Confirm the harness reports 0 when nothing changed, so a green run is not a broken query.

## A rebuilt relation must have been built by *this* change

Differing hashes prove *some* write happened. They do not prove the relation was rebuilt, and neither does the repo's own build record: `tests/test_maps.py::test_compiled_references_name_no_catalog` runs `dbt compile --select int_trips_enriched`, which overwrites `transformation/target/run_results.json`. So `run_results.json` names `int_trips_enriched` and never the model you are comparing, and reading it as "my build did not run" is a false alarm; that file is trustworthy only before any Python test runs.

Establish the build from the artifact instead:

- The build's own output: `dbt build --select <model> --target dev` prints `PASS`/`WARN`/`ERROR` counts for the model and its tests, and exits 0.
- The sandbox relation's `information_schema` or `duckdb_tables()` row count and the file's mtime moving forward.
- If a build could not be run (a read-only mandate, a lock), the verdict is `INCONCLUSIVE` with that reason. Bit-identical doubles across two files is the signature of nothing having re-executed, not of a perfect rebuild.

A comparison whose "rebuild" is an unchanged copy reports the same zeros a correct rebuild would, so it cannot tell the two apart.

## The criterion, per column

| Column | Criterion |
| --- | --- |
| INTEGER, BIGINT, DATE, VARCHAR, BOOLEAN | null-safe exact equality |
| DOUBLE money (revenue, amount, fee, tip, total) | equal at the cent: `round(x, 2)` on both sides |
| other DOUBLE measures (miles, duration, distance) | `round(x, 2)`, or an absolute tolerance when the measure is coarser than a cent |
| DOUBLE averages and ratios (`avg`, a share, a rolling mean) | an explicit tolerance: `abs(a - b) <= 1e-6`. Rounding a ratio to cents hides real drift |
| rank or `row_number` **ranking a** float (its own type is an integer) | tie-driven — see below |
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

A rank over a float is not reproducible, and a differing rank is not by itself a regression: when values tie, or sit within a float delta of each other, the order `rank()` sees can differ between two correct builds.

But "the ranked value agrees at the cent on those rows" is **not** enough to call a rank diff benign. A float delta can *dissolve* an exact tie, and both rows still round to the same cent:

| Baseline | Rebuild |
| --- | --- |
| `x 100.0 rank 1`, `y 100.0 rank 1` | `x 100.0 rank 1`, `y 100.0 rank 2` |

Cent values agree on both rows; the tie is gone. That is a real change in what the column means — so it is never noise to wave through — and it is also what an unchanged model does on its own when its float input moves. Attribute it (below) before deciding which of the two it is.

So gate on **tie-group shape**, comparing baseline and rebuild at the ranking partition, with the ranked value taken at the criterion's precision:

```sql
with shape as (
    select <partition>, round(<ranked value>, 2) as ranked_cents, count(*) as group_size
    from <relation>
    group by 1, 2
)
select count(*) as groups, count(*) filter (where group_size > 1) as tie_groups
from shape
```

- Run it on both relations and compare: same number of groups, same number of tie groups, and the same groups tied.
- A rank diff is benign only when the tie groups are unchanged **and** the differing rows sit inside one tie group — that is an intra-tie permutation, which is exactly what `rank()` is free to choose.
- The cheap discriminator per changed row: its peer at the swapped rank must be within tolerance on both sides. Two rows a cent apart churned; two rows dollars apart mean the ranking logic changed, and the verdict flips.
- A tie group that appears, disappears or changes size is a finding: report it and do not ship it as noise.
- Never widen a benign rank diff into a licence for the rest of the table: every other column keeps its criterion.

## Attribute the diff before you accept it

A rank column can be a faithful function of its input and still churn, because the *input* moved in the last bits. Tell those apart before filing anything against the change under review:

1. **Recompute the rank from the relation's own money column.** Zero mismatches means the stored column is a deterministic function of its inputs, so any cross-build diff came in through the money value, not through the ranking logic.
2. **Rebuild the unmodified model twice.** If the same rows churn between two runs of unchanged code, the drift is inherent to the model and cannot be attributed to the change in review.
3. Only after both come back clean does a diff belong to the change.

## A published rank over a float churns forever

If the ranked value is a `double` in a published, contract-enforced boundary relation, its ties break by an ordering the model never spells out, so every rebuild can produce a one-or-two-row diff. Say so where the comparison is recorded rather than re-diagnosing it each time, and name the two honest fixes: pin the tie-break deterministically in the model (`order by round(x, 2) desc, <key>`), or keep the contract loose on that column. Do not fix it by loosening the rest of the comparison.

## The rounding trap

`round()` is itself unstable at a half-cent: `round(0.125, 2)` is `0.13`, and the same value moved by 1e-12 rounds to `0.12`. So cent comparison is sound only for a money column that cannot hold a half-cent value. Check it before trusting the rule:

```sql
select count(*) from t where abs(x * 100 - floor(x * 100) - 0.5) < 1e-6;
```

A non-zero count means the column can land on the boundary, and its criterion is an absolute tolerance (`abs(a - b) <= 0.005`) instead of rounding.

## What goes in the record

- **The verdict is one of three words: `PASS`, `FAIL`, `INCONCLUSIVE`.** A zero after a vacuous comparison is `INCONCLUSIVE`.
- Both files' `md5sum`, so a zero can be told apart from a self-comparison.
- One line per column compared, with its criterion and its diff count.
- The headline number is the rows differing **under the criterion**, plus `one_sided_rows`, out of the row count. Never quote an exact-equality diff count as the headline: it measures float noise, not the change.
- The two relations, the key and grain used, and the commit compared.
- Every figure quoted comes from this run's output. A row count, tie count or diff count remembered from an earlier intent, a design record or a memory is not evidence for this comparison — measure it, and if a remembered figure disagrees with the measurement, the measurement wins and the disagreement is worth reporting.
- The positive control you ran and what it reported.

## Common mistakes

| Mistake | Fix |
| --- | --- |
| Reporting 0 diffs without checking the two files are different | Identical `md5sum` means you compared a file to itself. Verdict is `INCONCLUSIVE` |
| Concluding "no build ran" from `target/run_results.json` | A Python test overwrites it with a `dbt compile` of `int_trips_enriched`. Read the build's own output |
| Certifying a clean run with a harness you never saw report a difference | Perturb one row by more than the criterion (`0.01` for cent) and confirm `diff_rows` becomes 1 |
| `select count(*) from a join b using (k) where a.x <> b.x` | An inner join hides one-sided rows and `<>` hides NULLs. Full outer plus `is distinct from` |
| Comparing a row hash, or `except`/`intersect` on doubles | Exact by construction, so it reports float noise as a difference |
| Using `except` to count differing rows | It also reports a row whose *other* columns changed; count per column instead |
| Quoting an exact-equality diff count as the headline | On a `double` it counts float noise. Round to the cent and quote the rows that differ under the criterion |
| Treating a rank diff as noise because the values agree at the cent | A float delta dissolves an exact tie while both rows still round the same. Compare the tie-group shape |
| Picking a tolerance that just happens to pass | State the tolerance and why it is below the smallest difference a consumer would act on |
| Blaming the change for a rank churn | Recompute the rank from the relation's own money column, and rebuild the unmodified model twice, before attributing anything |
| Declaring the baseline wrong because it "won't reproduce itself" | Check what actually failed to reproduce: a column recomputed from its own input, or from a different upstream. The first is a real finding about the model |
| Filling a record from memory or from a design record | Measure in this run. A remembered row or diff count is not evidence, and where it disagrees, the measurement wins |
