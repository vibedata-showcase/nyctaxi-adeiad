---
artifacts: [agg_trip_zone_daily]
---

# agg_trip_zone_daily

Daily zone demand with period-over-period context, extended so it also carries the billable population and its revenue components. It becomes the single daily-zone aggregation in the warehouse (ADR 0018), and the finance report builds on it.

## Grain

One row per pickup zone and pickup date, unchanged. Keys: `pickup_date` + `pickup_location_id`. The zone is the natural key the as-of join matches, not the surrogate, so a row keeps its identity across a zone re-designation.

## Schema

- `marts/agg`: `agg` (default). Accepted by the user as the folder's current schema. Source: user answer at the schema question, this intent.

## Decisions

- `D-01` Six columns are added and none of the 14 existing columns changes name, type or value: `billable_trip_count`, `billable_revenue`, `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue`, `billable_toll_revenue`. The model must keep answering "how many trips, billable or not" for demand and quality work while also supplying the revenue report, and its active contract already promises the all-trips measures. Source: R-03, R-04; ADR 0018.
- `D-02` The billable measures are computed in this model with the row-level filter `f.is_billable` and never by subtracting the all-trips measures, because a zone-day can mix billable with non-billable trips and the non-billable part cannot be recovered from a summed total. Source: R-04; ADR 0003; this intent's Verification `## Discovery`.
- `D-03` `reporting_region` is added as one further new column, taken from the `dim_zone` row the existing join already resolves. The finance report publishes `reporting_region` and this relation did not carry it; sourcing it here keeps the report reading one relation instead of joining a dimension of its own. It is a group-by key, so it cannot change a row count unless it splits an existing grain, which it does not. Source: R-01; this intent's Verification `## Discovery`.
- `D-04` The billable measures are published on every zone-day, including the ones whose billable count is zero, and a consumer filters; the model does not drop zero-billable rows. Dropping them would change this relation's own published population, which R-03 forbids, and the zero is a real measurement for demand work. Source: R-03, R-05; ADR 0018.
- `D-05` The four component measures are named `billable_fare_revenue`, `billable_tip_revenue`, `billable_surcharge_revenue` and `billable_toll_revenue`, prefixed so no reader mistakes them for the all-trips figure and every measure-based test can select the family by prefix. Source: R-04; repository naming convention (`agg` carries measure families such as `total_miles` and `attributed_driver_count`).
- `D-06` The model stays a table with no change to its materialisation or to its window functions. Source: repository convention (`dbt_project.yml` sets `marts` to table); R-03.
- `D-07` The relation's own artifacts move with it in the same change: its ODCS contract gains the seven new properties at a minor version bump (added columns only), `generate` writes the dbt keys from it, and the Ossie document changes per `## Logical Model`. The contract is edited before the SQL, as the contract skill requires on a boundary relation. Source: R-07; repository convention (`contracts/`, `logical-model/`).

## Rejected

- **Replace the all-trips measures with billable ones** — it would weaken the relation's published promise and break demand and quality consumers (R-03).
- **Build the billable measures in a second daily-zone model** — it recreates the duplication the intent removes (ADR 0018).
- **Have the finance report filter non-billable trips out of this relation** — impossible: the non-billable amounts are already summed into `total_revenue` and cannot be separated.
- **Carry `reporting_region` only in the finance report via its own `dim_zone` join** — a second join to the same dimension duplicates the version-correctness logic in two places; carrying it here resolves it once.

## Consumers

- `finance.mart_daily_zone_revenue`, which reads the billable measures and the three descriptive attributes.
- The canonical semantic model's logical source `LTS2_zone_day_agg`, which binds `trip_count` and `pickup_date` and must gain the new billable fields.
- `assert_semantic_content_holds` and `assert_semantic_levels_hold`, generated tests.
- Demand and quality analysis reading the all-trips measures; not changed by this intent.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
datasets:
  added: []
  changed:
    - trips
  retired: []
metrics:
  added:
    - billable_fare_revenue
    - billable_tip_revenue
    - billable_surcharge_revenue
    - billable_toll_revenue
  changed: []
  retired: []
logical_sources:
  added: []
  changed:
    - LTS2_zone_day_agg
  retired: []
```

`billable_trip_count` and `billable_revenue` already exist and are bound by `LTS2_zone_day_agg`; they now bind to real columns here instead of being refused. The four component metrics are new because no metric covers a fare component today; each is declared with the aggregation its column defines, and the dataset `trips` is listed `changed` because the metrics it carries grew.

Ontology: no concept or mapping changes. The added columns are measures, not identities or relationships, so `Trip`'s mapping in `ontology/nyc_taxi_analytics.mapping.yaml` is untouched.

## History

- 2026-11-25 — v-w-2-a4d2091d — six billable measures and `reporting_region` added; the relation becomes the single daily-zone aggregation — D-01, D-02, D-03, D-04, D-05, D-06 — terms: none new (ADR 0018 recorded; "billable trip" and "reporting window" already defined)
