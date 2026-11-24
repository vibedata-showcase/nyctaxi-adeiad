---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

A monthly borough-by-borough flow: the same zone dimension joined twice, once in each role, rolled up from zones to boroughs. It answers "how much of each borough's traffic crosses a line" and publishes the share beside it.

## Grain

One row per (month, origin borough, destination borough) with at least one billable trip in the reporting window. Alternatives considered: zone-pair grain (that is `agg_od_flow_matrix`, and its floor makes it unusable for a share), and one row per month × origin borough with the destination as a nested structure (unrepresentable in a table and unqueryable by the consumer). Source: R-01, R-04.

## Schema

- `transformation/models/marts/agg/`: `agg` (default). Source: user answer, accepting the folder's current resolution (`models.nyc_taxi_analytics.marts.agg: +schema: agg` in `dbt_project.yml`).

## Decisions

- `D-01` Build from `core.fct_trip` with `core.dim_zone` joined twice — `pickup_zone_key` as the origin role and `dropoff_zone_key` as the destination role — grouping on each role's `borough_name`. The two joins are what make a matrix possible; a single zone key cannot produce both ends of one trip. Source: R-01, R-06; `agg_od_flow_matrix` D-04.
- `D-02` Apply the billable rule and the reporting window here, in gold, through the `in_report_window` macro over `pickup_datetime`, and nowhere upstream, so quality work still sees the excluded rows. Source: R-02; [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md) ("Gold marts that report revenue or flows apply it, inside the reporting window").
- `D-03` Revenue is `sum(total_amount)` over billable trips, with no payment-method join and no exclusion of no-charge or dispute payments. ADR 0013 leaves the choice to the metric; the user picked billable total, matching `mart_daily_zone_revenue` and `agg_od_flow_matrix`. A payment-method join would also drop trips whose key is null, narrowing the population the share divides by. Source: user answer; [ADR 0013](../../../adr/0013-no-charge-and-dispute-payments-are-not-excluded-by-the-billable-rule.md).
- `D-04` No trip floor and no `HAVING` clause: every borough pair carrying a billable trip in the month is a row. A floor would remove pairs from the numerator while their trips stayed in the share's denominator, so the two published numbers would describe different populations. Source: user answer; [ADR 0018](../../../adr/0018-a-borough-flow-surface-has-no-trip-floor.md).
- `D-05` The cross-borough share is per origin borough per month: `sum(leaving trips) / sum(all origin borough trips)`, in that one group. It is published on every row of the origin borough's matrix together with its numerator (`cross_borough_billable_trip_count`) and denominator (`origin_billable_trip_count`), so a reader can rebuild it and a higher grain can sum the two inputs rather than average rates. It is computed with `safe_divide`, so an empty denominator gives null rather than a measured zero. Source: R-03; [ADR 0019](../../../adr/0019-the-cross-borough-share-is-per-origin-borough.md); [ADR 0016](../../../adr/0016-rates-are-rebuilt-from-summed-numerators-and-denominators.md) ("Every rate ... is computed as a sum of numerators over a sum of denominators, through the `safe_divide` macro, which returns null when the denominator is zero").
- `D-06` The share reads only resolved boroughs at both ends. `Unknown` and `N/A` are the zone dimension's marker for a zone no borough can be placed in (ADR 0012), not borough members, so a trip touching one is neither inside nor leaving a borough: an unresolved origin contributes no numerator and no denominator and its rows carry a null share, and an unresolved destination never enters a numerator. `EWR` is a real borough on the dimension and takes part like any other. Those trips keep their own matrix rows and stay inside the published totals. Source: user answer (correcting this record's earlier draft); [ADR 0020](../../../adr/0020-unresolved-zones-are-outside-the-cross-borough-share.md); [ADR 0012](../../../adr/0012-unresolved-zones-are-retained-and-flagged.md).
- `D-06a` The share's denominator is the origin borough's whole `trip_count`, including its trips whose dropoff zone is unresolved; only the numerator narrows to trips arriving in a different resolved borough. Excluding them from the denominator would shrink the borough's own traffic and break the agreement between the share and the trips on the same rows. Source: user answer ("keep them in the totals"); [ADR 0020](../../../adr/0020-unresolved-zones-are-outside-the-cross-borough-share.md).
- `D-07` Both zone joins are `left` joins, so a trip with a null zone key is kept and groups under a null borough rather than disappearing, per the Requirement's "keep every row". Source: R-05; [ADR 0015](../../../adr/0015-unmatched-dimension-keys-stay-null.md).
- `D-08` A pair with no billable trip in a month has no row; no zero rows are emitted and the relation is not densified against a borough × month cross product. Source: user answer; every existing group-by mart does the same.
- `D-09` The month is `date_trunc('month', pickup_date)` cast to `date`, named `month_start_date`, matching `agg_driver_monthly` and `agg_vehicle_monthly`. The window is cut on `pickup_datetime` through the macro, not on the derived month, so the reporting window stays the single definition of scope. Source: repository convention (`dim_date.month_start_date`, `agg_driver_monthly.sql`).
- `D-10` No incomplete-period mark is carried: every month of the window is whole in the data, so a flag would be a column that is always the same value. The measurement that establishes this is in the Verification's `## Discovery`. Source: R-01; Requirement's "Edge periods" row.
- `D-11` Publish `origin_borough` and `destination_borough` as the borough names the zone dimension carries, with no rank, region or `is_nyc` decoration, and no surrogate keys, so the grain is readable and survives a zone re-designation. `is_intra_borough` is published as a boolean because the share's numerator is exactly its negation and a consumer should not re-derive it. Source: R-01; `agg_od_flow_matrix` D-03.
- `D-12` Materialise as a `table` in the gold layer, matching every other agg mart; `access: public` with `contract: {enforced: true}`, since a new boundary relation owes a contract. Source: R-06; `.agents/skills/dbt-models` (B15, B-safe start of gold).
- `D-13` The semantic model maps this relation as an aggregate logical source of the `trips` document, not as a new star: its rows are the fact's rows rolled up, with no new business process and no filter a predicate cannot state. Its `content_levels` name the month, the origin-borough role and the destination-borough role; its `content_filter` states the window and `is_billable`, and the null-key condition its inner-equivalent joins would drop. `billable_trip_count` and `billable_revenue` bind to its columns; the share becomes a `derived_expression` metric over a level-based numerator and the origin borough's own trip count. Source: R-06; `semantic-model` routing table ("The star's rows rolled up → An aggregate logical source").

- `D-14` A trip is never removed for a quality verdict. The model carries no verdict filter beyond `is_billable`: refunds, zero-distance, implausibly short or fast, sparse-feed and unresolved-zone trips all stay in the rows and in the totals, and only the share declines to read the unresolved ones (D-06). A verdict is flagged on `fct_trip` through `trip_quality_key` and a consumer chooses which to exclude and says so; this surface states that it excludes none. Source: R-05, R-07; [ADR 0004](../../../adr/0004-quality-verdicts-flag-trips-and-never-delete-them.md) ("No model removes a trip because of a verdict"). The verdicts present on this population are measured in the Verification's `## Discovery`, not restated here.
- `D-15` Nothing in this model is a mean of a rate: the only rate is the share, and it is rebuilt from its summed numerator and denominator through `safe_divide`, so a coarser grain sums the inputs rather than averaging per-pair values. No column carries a precomputed per-pair ratio for a consumer to add up. Source: R-03; [ADR 0016](../../../adr/0016-rates-are-rebuilt-from-summed-numerators-and-denominators.md).

## Rejected

- **`agg_od_flow_matrix` as the source** — its 25-trip floor publishes 68,513 of the window's 95,958 billable trips, so a share over it would divide a floored numerator by a floored denominator and describe neither the borough nor the network (ADR 0017, and the reuse measurement in the Verification).
- **A network-wide share** — one number that describes no borough and is dominated by Manhattan's volume; ADR 0019 records the trade-off.
- **A payment-method join to report recognised revenue** — it would drop trips whose payment key is null and narrow the population behind both the trips and the share.
- **A dense borough × month matrix, zero-filled** — roughly 24 of 64 cells a month carry no trip, and a zero row is indistinguishable from a pair that was filtered out.
- **An intermediate model to hold the borough attribution** — the rollup is two joins and one group by, and no other model needs the intermediate grain.

## Logical Model

```yaml
documents:
  - logical-model/nyc_taxi_analytics.ossie.yaml
    datasets: {}
    metrics:
      added:
        - cross_borough_billable_trip_count
        - origin_billable_trip_count
        - cross_borough_share
      changed: []
      retired: []
    logical_sources:
      added:
        - agg_borough_flow_monthly
      changed: []
      retired: []
ontology:
  documents: []
  concepts: []
  mappings: []
```

The document is `nyc_taxi_trips`, the trips star, which already owns both the `trips` fact dataset and the zone dimension in its two roles (`trips_to_pickup_zone`, `trips_to_dropoff_zone`). The new relation rolls that fact up, so it becomes an aggregate logical source beside `LTS2_zone_day_agg` and the rest rather than a second star — the routing rule for a table whose rows are the star's rows rolled up. Nothing in the ontology changes: no concept is added, retired or re-identified, and the mapping from `Trip` onto `trips` already reaches both zone roles.

Two metric decisions belong to the design stop rather than to authoring:

- `cross_borough_billable_trip_count` is a **level-based metric**: the trips of the origin borough that end in any other borough, pinned at the origin-borough level whatever finer or coarser role a query groups by. It is the numerator ADR 0019 needs and no existing metric states it — `billable_trip_count` filtered to `is_billable` is the whole population, not the crossing subset.
- `origin_billable_trip_count` is the denominator, the origin borough's own total, pinned the same way. `billable_revenue_pickup_borough` is the precedent for a pinned-at-borough metric, but it is a revenue sum and not a trip count.
- `cross_borough_share` is a `derived_expression` over those two, per ADR 0016, so an engine rebuilds it from summed inputs at any grain instead of averaging a published rate.

A pair with an unresolved end carries a null `cross_borough_share` and a null numerator, and still carries its `trip_count` and `billable_revenue`; the share's denominator is the origin borough's whole trip count, so `origin_billable_trip_count` is null only on unresolved-origin rows. The share column therefore needs `not_null` only where the origin borough is resolved, which a singular test holds rather than a generic one.

## Consumers

Mobility Planning reads the relation directly and through the semantic layer (`trips` document, aggregate logical source). No dbt model in this repository refs it.

## History

- 2026-11-24 — ss-borough-flow-2d20e29e — design record written — D-01…D-13 — terms: added Borough flow, Cross-borough share
- 2026-11-24 — ss-borough-flow-2d20e29e — user correction: unresolved zones are outside the share and inside the totals; D-06 replaced and D-06a, D-14, D-15 added — D-06, D-06a, D-14, D-15 — terms: none new
