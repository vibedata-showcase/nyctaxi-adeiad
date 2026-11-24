---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Monthly billable trips and revenue from each origin borough to each destination borough, with the share of the origin borough's traffic that ends in another borough. The borough-grain sibling of `agg_od_flow_matrix`, without that surface's trip floor (ADR 0018).

## Grain

One row per (month, origin borough, destination borough) for every pair with at least one billable trip. `month_start_date` is the month the trip was picked up in.

The month is derived with `date_trunc('month', f.pickup_date)`, as `mart_monthly_service_summary` derives `trip_month`, and not by joining `dim_date`: the calendar would add a join that can only ever drop a trip whose date key it does not hold, and the table's closure to `fct_trip` matters more than a calendar attribute no row needs.

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer at the schema question; the folder's `+schema` in `dbt_project.yml` is unchanged, so no model already in the folder moves.

## Input adequacy

`Ready` for both inputs, `fct_trip` and `dim_zone`: the fact closes to its own billable totals, `dim_zone` has one row per zone key in each role, and every billable in-window trip resolves both keys. The measurements, their queries and the anchors they set are in `docs/verify/2026-11-24-ss-borough-flow-951b6777.md` `## Discovery`.

## Output contract

Relation `agg.agg_borough_flow_monthly`, columns in this order:

| Column | Type | Meaning |
| --- | --- | --- |
| `month_start_date` | DATE | The month the trips were picked up in, `date_trunc('month', pickup_date)`. |
| `origin_borough` | VARCHAR | Pickup borough, or `unresolved` (D-05). |
| `dest_borough` | VARCHAR | Dropoff borough, or `unresolved` (D-05). |
| `trip_count` | BIGINT | Billable trips in the cell. |
| `total_revenue` | DOUBLE | Sum of `total_amount` over the cell's trips (D-09). |
| `is_cross_borough` | BOOLEAN | Null when either side is `unresolved`, else `origin_borough <> dest_borough` (D-06). |
| `origin_located_trip_count` | BIGINT | The origin borough-month's trips with a located destination; repeats across the month's destination rows; null on an `unresolved` origin (D-07). |
| `origin_cross_borough_trip_count` | BIGINT | Those of them that end elsewhere; repeats likewise; null on an `unresolved` origin (D-07). |
| `cross_borough_trip_share` | DOUBLE | The two counts divided, null when the denominator is zero (D-07). |

## Decisions

- `D-01` A table in `agg`, materialised as a table like every other mart, rebuilt by the ordinary `dbt build`; no incremental strategy and no schedule of its own. The reporting window is a closed range that every run rebuilds whole, and a partial refresh would leave a month half-computed. Source: repository convention (`.agents/skills/dbt-models`, materialisation table), R-01.
- `D-02` Population: billable trips picked up inside the reporting window, filtered in gold with `in_report_window` and `fct_trip.is_billable`. Source: R-04, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-03` No trip floor and no minimum cell size: every pair with at least one billable trip is published. The OD matrix's 25-trip floor is a property of the zone-pair surface, and applying it here would drop half the cells and break every origin borough's monthly total. Source: R-05, [ADR 0018](../../../adr/0018-a-borough-flow-carries-no-trip-floor.md).
- `D-04` One row per observed pair; no spine and no zero-filled cross product. A pair with no trips in a month has no row, so no zero is confused with an absent cell. Source: R-01, user answer ("Omit pairs with no trips").
- `D-05` Both zone joins are left joins, and one unresolved group carries every trip that touches a zone the master data cannot place: a trip whose pickup or dropoff zone is null or has `is_unresolved_zone` reports `unresolved` in that role. The two unresolved borough values are merged into that one group rather than published as boroughs, because neither is a borough. Source: R-07, R-08, user answer ("Unknown and N/A are not boroughs… Keep these trips in a separate unresolved group (ADR 0012)"), [ADR 0012](../../../adr/0012-unresolved-zones-are-retained-and-flagged.md), [ADR 0015](../../../adr/0015-unmatched-dimension-keys-stay-null.md).
- `D-06` `is_cross_borough` is null when either side is `unresolved`, otherwise it is `origin <> destination`. A trip between a borough and Newark Airport crosses, because EWR is a borough value the master data carries. Source: R-06, R-08, [ADR 0019](../../../adr/0019-the-cross-borough-share-is-per-origin-borough.md), user answer.
- `D-07` The share is per origin borough and month: `origin_cross_borough_trip_count / origin_located_trip_count`, published with both counts in the same row, and null where the origin is `unresolved`. The two counts are computed in a second step over the already-grouped rows (`sum(...) over (partition by month, origin)`), because they are sums of cell counts, not of trips still at row grain. Both repeat on every destination row of that origin borough-month and are therefore not additive across destinations; the column descriptions say so. Source: R-06, [ADR 0019](../../../adr/0019-the-cross-borough-share-is-per-origin-borough.md).
- `D-08` Keys are natural values, not surrogates: the borough's name and the month's start date. A zone re-designation changes a zone's version, not a borough's or a month's identity, so a surrogate key would move a row for no business reason. Source: R-02, repository (`agg_od_flow_matrix` design D-3).
- `D-09` The revenue measure is `sum(total_amount)` over the cell's billable trips, which includes the no-charge and dispute payment methods. Source: R-01, [ADR 0013](../../../adr/0013-no-charge-and-dispute-payments-are-not-excluded-by-the-billable-rule.md), the canonical `billable_revenue` metric.
- `D-10` The composite grain is held by a singular test, because no single column is unique: the contract's `primaryKey` states the three columns and the singular test proves no triple repeats. Source: R-10, repository (`.agents/skills/dbt-testing`, `assert_daypart_cube_one_row_per_grain.sql`).
- `D-11` A singular test reconciles the table to `fct_trip`: its trip and revenue totals over the whole window equal the billable totals of the star, so a dropped or duplicated group fails the build. Source: R-04, repository (`assert_aggs_cover_every_trip.sql`).
- `D-12` The relation is excluded from the semantic layer: a `semantic_exclusions` entry in `repo-map.json` carries the reason. Its `unresolved` group merges the two unresolved borough values, so its groups can never equal the detail's groups (which hold `N/A` and `Unknown`), and the generated content test would fail — the aggregate is a relabelled population, not a roll-up of the star. The same question is answerable through the star's detail source, which reaches both zone borough roles. Source: R-09, `.agents/skills/semantic-model` ("Routing a bespoke table": a lossy relabel is excluded), R-07.
- `D-13` The excluded relation still owes a contract and is listed as `boundary/excluded` by `check`, not `boundary/undeclared`. Source: R-09, `.agents/skills/data-contract` (step 1 table).
- `D-14` The `unresolved` value is no member of the zone dimension's borough level; because the relation is excluded from the documents, no level test reports it. A consumer reading the relation directly sees one `unresolved` origin or destination group, and ADR 0012's flag behaviour is carried by `is_cross_borough` being null there. Source: R-07, [ADR 0012](../../../adr/0012-unresolved-zones-are-retained-and-flagged.md).
- `D-15` A new ODCS contract at `contracts/agg/agg_borough_flow_monthly.odcs.yaml`, version 1.0.0, `status: proposed` until the relation is built and `active` after, declaring the composite grain key; `generate` writes the dbt keys from it and nothing is hand-written on the model. Source: R-09, `.agents/skills/data-contract`.
- `D-16` The ontology gains no concept and no new mapping for this relation: an aggregate mart rolls up concepts it already maps, and it reaches no concept of its own. Source: R-09, `.agents/skills/ontology/references/classification.md` ("Aggregate or report mart: No").
- `D-17` The semantic-model coverage command in `test-map.json` gains `--exclude agg.agg_borough_flow_monthly`, so the coverage gate keeps passing with the new relation on disk and the exclusion is what the command reads. Source: R-09, repository (`test-map.json` `logical-model.commands.structural`).

## Rejected

- Build on `agg_od_flow_matrix` — it has no month grain, and its floor already removed rows, so no aggregation of it can close to the star.
- Build on `mart_daily_zone_revenue` — it carries the pickup borough only, so a destination borough is not reachable.
- Apply ADR 0017's 25-trip floor per cell — rejected with its figures in ADR 0018.
- Emit the full borough cross product with zero rows, or a date spine per borough pair — a zero and an absent month would be indistinguishable, and no other mart emits empty pairs.
- Publish `N/A` and `Unknown` as borough values beside the five city boroughs and EWR — neither is a borough, and a reader would compare them with real ones.
- Publish the share alone, leaving the counts implicit — a reader could not rebuild the number from the row, and the base a share excludes is exactly what a planning reader questions.
- Join `dim_date` to key the month by `month_start_date` — the join can only ever drop a trip, and no row needs a calendar attribute; the closure to `fct_trip` is the property this surface is checked on.
- Declare a `cross_borough_trip_share` metric — a cross-borough trip is not a row predicate on the fact: it needs both zone roles, so the metric would describe this aggregate rather than the star.
- Map the relation as an aggregate logical source on `trips` — its `unresolved` group merges two values the detail keeps apart, so the generated content test could never hold, and the same question is already answerable through the detail source.

## Logical Model

```yaml
documents: []
ontology:
  documents: []
  concepts: {}
  mappings: {}
  note: no document and no concept is touched; the relation is excluded from the semantic layer by D-12.
```

## Consumers

- Mobility Planning, who answer the city's question from it; outside this repository.
- `contracts/agg/agg_borough_flow_monthly.odcs.yaml`, the promise a consumer reads.
- Nothing in the semantic layer reads it: `semantic_exclusions` names it, so an engine never reaches it through a document (D-12).

## History

- 2026-11-24 — ss-borough-flow-951b6777 — design record written; grain, population, unresolved group, share definition, semantic exclusion and contract chosen — D-01…D-17 — terms: none new (Borough, Borough flow and Cross-borough trip were added with the requirement)
