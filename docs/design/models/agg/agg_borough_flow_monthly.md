---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Monthly trips, revenue and cross-borough share for every origin borough ×
destination borough pair. The same zone dimension joined twice, as
`agg_od_flow_matrix` is, but rolled to borough and split by month.

## Grain

One row per (month, origin borough, destination borough) that carries at least
one billable trip. Alternatives rejected: zone pair (already published as
`agg_od_flow_matrix`, and too fine for the city's question) and month × origin
borough alone (loses the destination the question asks for).

## Schema

- `agg` (dbt folder `transformation/models/marts/agg`): `agg` (default). Source: user answer at the design stop.

## Decisions

- `D-01` Grain is month × origin borough × destination borough, a calendar month being `date_trunc('month', pickup_date)`. The request asks for each month of Q1 and each borough to each borough. Source: `R-01`.
- `D-02` The population is billable trips inside the reporting window, per ADR 0003. Source: `R-02`, `R-03`; `docs/adr/0003-billable-trip-definition-and-where-it-applies.md`.
- `D-03` Revenue is gross billable `total_amount`, with no payment method excluded, so a no-charge or disputed trip that carries a positive total still contributes. Source: user answer at the requirement stop; `docs/adr/0013-no-charge-and-dispute-payments-are-not-excluded-by-the-billable-rule.md`.
- `D-04` Every borough pair is published; ADR 0017's 25-trip floor does not extend to this rollup. The floor is a statement about zone pairs on the OD matrix, and applying it here would remove the thin cross-borough flows the question is about while breaking the closure to the star. Source: user answer at the requirement stop; ADR 0018.
- `D-05` A month × pair with no billable trips is omitted rather than emitted as zero, so the table is a set of observed pairs. Source: user answer at the requirement stop.
- `D-06` `cross_borough_trip_share` is a trip share, not a revenue share, and its numerator counts every trip whose destination borough differs from its origin borough — including `EWR` and the unresolved `Unknown` / `N/A` groups, which stay in the rollup per ADR 0012. Source: `docs/adr/0018-a-borough-flow-mart-publishes-every-pair-and-counts-every-other-borough-as-crossing.md`; `R-05`.
- `D-07` The share is a ratio of sums — the origin borough's cross-borough trips over all its trips in that month — computed through `safe_divide`, never the mean of per-pair shares, per ADR 0016. It is repeated on every row the origin borough has in that month, its intra-borough row included. Source: user answer at the requirement stop; `docs/adr/0016-rates-are-rebuilt-from-summed-numerators-and-denominators.md`.
- `D-08` Both zone joins are inner joins on the surrogate `zone_key`, as in `agg_od_flow_matrix`, because a trip's borough is only knowable through the version in force at its pickup. Every billable trip in the window resolves to a zone version, so no row is dropped; `R-02` and `R-03` hold the table to that by closing it against `fct_trip`. Source: `R-02`, `R-03`.
- `D-09` The model is a `table` in the `agg` folder, materialised by the folder's `dbt_project.yml` default, and carries `contract: {enforced: true}` with every output cast to its declared type, as `agg_od_flow_matrix` does. Source: `AGENTS.md`; `.agents/skills/dbt-models/SKILL.md`.
- `D-10` The relation is a boundary model, so it pays all three boundary artifacts: a `public` dbt model with an enforced contract, an ODCS contract at `contracts/agg/agg_borough_flow_monthly.odcs.yaml`, and an aggregate logical source in `logical-model/nyc_taxi_analytics.ossie.yaml`. Source: `R-06`; `repo-map.json` `layers`.
- `D-11` The share column is not mapped to a logical-source column. It is a ratio of two aggregates over the origin borough's rows, so the semantic model expresses it as a ratio metric over a filtered numerator rather than binding it to the physical column, and the source's `note` records the refusal. Source: `D-07`; `.agents/skills/semantic-model/SKILL.md` (a rate is a `derived_expression` over its numerator and denominator metrics, bound to no column).
- `D-12` The model's trip count column is `billable_trip_count`, not `trip_count`, because the Ossie `trip_count` field reads "Trips, billable or not" and `odcs.py generate` writes that description onto any column of that name, which would misdescribe a count of billable trips only. Supersedes the column name implied by `D-02`.
- `D-13` The share and the cross-borough count are **not** semantic metrics at all, superseding `D-11`'s claim that the semantic model expresses the share as a ratio metric. `fct_trip` carries `pickup_zone_key` and `dropoff_zone_key`, not boroughs, so no detail row states whether two zones share a borough and no metric compiles against `LTS1_detail`; `generate-tests` fails with `maps no column for 'dropoff_borough'`. Both stay physical columns of the table, described in its dbt model and its contract and held by their own tests, and the logical source's `note` records the refusal and what would make a metric expressible — a fact that carries borough identity. Source: `R-06`; the `ossie.py generate-tests` failure at `e485f2f`.

## Rejected

- **Building on `agg.agg_od_flow_matrix`** — it carries no month (one row per zone pair over the whole window) and applies ADR 0017's floor, so it can neither be split by month nor made to close to the star.
- **Building on `finance.mart_daily_zone_revenue`** — pickup-side only; a destination borough cannot be reached from it.
- **A zone-pair grain with a borough rollup downstream** — the published zone-pair surface already exists, and a second mart at that grain would answer a question nobody asked.
- **Zero-filling every month × pair** — an unobserved pair is not a measured zero, and the grid would triple the row count with facts the data does not contain.
- **Revenue share instead of trip share** — the question asks what share of trips leave their origin borough.

## Logical Model

`logical-model/nyc_taxi_analytics.ossie.yaml` — the trips star gains this
relation as one more aggregate logical source, beside `LTS2_zone_day_agg` and
the other aggregates. No new document: the relation is reachable through the
star's existing `zone` dimension in two roles, so it belongs to the star that
already carries them.

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
    datasets: []
    metrics: []
    logical_sources:
      added:
        - LTS10_borough_flow_monthly
ontology:
  - ontology/nyc_taxi_analytics.mapping.yaml
    concepts: []
    mappings: []
```

- `LTS10_borough_flow_monthly` binds `billable_trip_count` to `billable_trip_count` and
  `billable_revenue` to `total_revenue`, under a content filter naming the same
  window, the billable flag and both zone keys. Its `content_grain` is the model's
  grain, and its `content_levels` reach the `month` level of `date` and the
  `borough` level of `zone` through both roles.
- **No metric is added, and the two cross-borough measures are refused.** The
  fact carries `pickup_zone_key` and `dropoff_zone_key`, not boroughs, so no
  detail row states whether two zones share a borough, and a metric over
  `cross_borough_trip_count` cannot compile against `LTS1_detail`. Superseding the
  earlier line that named the two metrics as added: the crossing subset and the
  share stay physical columns of this table, described in its dbt model and its
  contract and held by their own tests, and the source `note` records the refusal
  and what would make a metric expressible — a fact that carries borough
  identity. Source: `D-11`; the `generate-tests` failure on the detail mapping.
- No concept is added to the ontology: the relation rows are trips rolled up by
  borough, and every concept it reaches — Trip, Zone, Date — is already mapped
  on the trips document. This is recorded as `[]` rather than left out, so the
  check reads as run.

## Consumers

- Leila Haddad's Mobility Planning team, answering the city's question on cross-borough traffic.
- The semantic layer: a new aggregate logical source on this relation, so the canonical `billable_trip_count` and `billable_revenue` can be queried at borough-pair grain. The cross-borough count and share are not reachable that way: they are refused as metrics for the reason in `D-11`, so a consumer reading them queries the columns directly.

## History

- 2026-11-25 — Borough-to-borough trips and revenue, Q1 2024 3 — created with the model's design — D-01…D-11 — terms: added cross-borough trip
- 2026-11-25 — Borough-to-borough trips and revenue, Q1 2024 3 — execution: renamed the count column, refused the two metrics the fact cannot support — D-12 — terms: none new
- 2026-11-25 — Borough-to-borough trips and revenue, Q1 2024 3 — shipping: `access: public` set beside the enforced contract, and the refusal at `D-13` recorded in place of `D-11`'s plan — D-13 — terms: none new
