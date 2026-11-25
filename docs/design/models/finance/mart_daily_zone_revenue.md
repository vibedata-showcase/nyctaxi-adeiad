---
artifacts: [mart_daily_zone_revenue]
---

# mart_daily_zone_revenue

Daily revenue by pickup zone.

## Grain

One row per pickup zone and trip date.

## Schema

- `transformation/models/marts/finance/`: `finance` (default). Source: user answer (application-owner accepted the folder's current schema).

## Decisions

- `D-01` Apply the billable rule and the reporting window here, in gold, and nowhere upstream, so quality work can still see the rows this excludes ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: docs/requirement/2026-08-29-the-trip-fact.md R-03, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-02` Read `agg.agg_trip_zone_daily` and no other relation, so the zone aggregation and the billable rule are computed once instead of twice. The mart becomes a projection of the aggregate: it renames columns and applies the population requirement below, and adds no aggregation of its own. Source: R-01, request ("so that there is one source").
- `D-03` Supersedes `D-01` on where the rule is applied: the rule now runs in `agg_trip_zone_daily` (its `D-04`), and this mart inherits it through the billable-only columns rather than filtering `f.is_billable` itself, which it cannot do because the aggregate holds no per-trip flag. The rule's substance — a positive total, inside the reporting window — is unchanged, and the reporting window still bounds this mart's population through the aggregate's own window. Source: R-09, user answer on ADR 0003.
- `D-04` Publish a row only where the zone-day has at least one billable trip, so the report keeps the row count and every cell Finance reads today. The aggregate deliberately keeps the zone-days whose trips are all non-billable, and this mart is where the narrower population is applied. The row counts of the two populations sit in the intent's Verification. Source: R-05, user answer.
- `D-05` Publish the 11 columns under their existing names and types, reading `borough` from `borough_name` and `trip_count` from `billable_trip_count`. Each measure is compared to the shipped mart at the cent and each count exactly, per the Domain's testing convention: DuckDB float aggregation is not reproducible bit for bit, so a rebuild must be compared with an explicit precision and never by hashing raw values. Source: R-02, R-05, `dbt-testing` convention.
- `D-06` Correct the `trip_count` description: the column counts billable trips, not "trips, billable or not" as the properties file says today. The value is unchanged; only the published wording was wrong. Source: R-05, R-07.
- `D-07` Corrects the precision claim in the first version of `D-05`: the design asserted bit-identical floats, which the Domain's testing convention forbids relying on across builds. The decision to reproduce every number is unchanged; only the comparison precision is stated. Source: `dbt-testing` convention, R-02.
- `D-08` Supersedes `D-06`, which could not be carried out. `odcs.py generate` owns the dbt `description` of a star member's column and derives it from the Ossie field the column binds; it overwrites a hand-written description and ignores one added to the contract, so the wording cannot be corrected in `_finance.yml`. The generated text reads `Trips, billable or not.` on a column that counts billable trips only, because the column name `trip_count` resolves to the population-wide `trip_count` metric ahead of `LTS7_daily_zone_revenue`'s honest binding of that column to `billable_trip_count`. The value is right and the sentence is wrong. Correcting it is a semantic-model decision about how a column name shared by this relation and `agg_trip_zone_daily` resolves to a metric, and is recorded as an open question in the intent's Verification rather than settled here. Source: R-05, `odcs.py generate` behaviour observed in this intent.

## Rejected

- Applying the rule in silver: the excluded rows would be invisible to quality work.
- Keeping a second aggregation in this mart over `core.fct_trip`: it recovers the rule locally but reinstates exactly the duplicate build the request removes.
- Emitting a zero row for a zone-day with no billable trip: it would change the row count of the morning report without changing a total, and the aggregate already publishes that population.
- Building on `agg.agg_trip_zone_daypart_dow`, the finer-grain published cube: it carries no date column, so it cannot answer a daily grain, and its revenue columns are population-wide, so it cannot supply billable revenue without the same extension.

## Consumers

None in this repo: the dbt graph shows no model downstream, only this model's own column tests and the two singular semantic tests.

Outside the repository, the finance team reads it every morning as the daily zone revenue report.

## History

- - 2026-10-14 — trip-fact — design record written; audience wording removed from the model description — D-01
- - 2026-11-25 — lfq-2 — re-sourced from `agg.agg_trip_zone_daily`; the billable rule moves upstream, the population and every published number stay — D-02, D-03, D-04, D-05, D-06 — terms: none new
