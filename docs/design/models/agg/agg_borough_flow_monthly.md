---
artifacts: [agg_borough_flow_monthly]
---

# agg_borough_flow_monthly

Monthly trips and revenue from each borough to each borough, with the share of a borough's trips that leave it.

## Grain

One row per (trip month, origin borough, destination borough) that carries at least one billable trip picked up inside the reporting window. A pair-month with no billable trips has no row.

## Schema

- `transformation/models/marts/agg/` → `agg` (default). Source: user answer, design stop 2026-11-24.

## Decisions

- `D-01` The month is the trip's pickup month, emitted as `trip_month` on the first day of the month, and it is the reporting-window month. Source: docs/requirement/2026-11-24-ss-borough-flow-4ba22d8f.md R-03.
- `D-02` Billable trips only, inside the reporting window, applied here in gold ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: docs/requirement/2026-11-24-ss-borough-flow-4ba22d8f.md R-02.
- `D-03` The origin and destination groups are the boroughs the TLC names, with `EWR` among them, and the two labels its unresolved zones carry merged into one `Unresolved` group ([ADR 0018](../../../adr/0018-only-tlc-named-boroughs-count-and-unresolved-zones-form-one-group.md)). The merge is what keeps the table's borough columns from publishing a value that is not a borough. Source: user answer; [ADR 0018](../../../adr/0018-only-tlc-named-boroughs-count-and-unresolved-zones-form-one-group.md).
- `D-04` Built from `fct_trip` with `dim_zone` joined twice, once per role, rather than from `agg_od_flow_matrix`. That table publishes only zone pairs at or above the 25-trip floor of [ADR 0017](../../../adr/0017-published-flows-have-a-25-trip-floor.md), so its population is narrower than the billable trips this table must account for. Source: user answer (no floor at this grain); docs/requirement/2026-11-24-ss-borough-flow-4ba22d8f.md R-02, R-07.
- `D-05` The unresolved group stands outside the borough counts: a trip that touches it is neither in-borough nor a crossing ([ADR 0018](../../../adr/0018-only-tlc-named-boroughs-count-and-unresolved-zones-form-one-group.md)). Its rows are published so its trips remain visible. Source: user answer; [ADR 0018](../../../adr/0018-only-tlc-named-boroughs-count-and-unresolved-zones-form-one-group.md).
- `D-06` `origin_leaving_trip_share` is the share of the origin borough's trips in that month that end in a different named borough, and it repeats on every row of that origin borough and month, the row whose destination is `Unresolved` included: the share belongs to the origin, and that row is not part of its denominator. It is null only where the origin borough has no trip resolved to a named borough. Its denominator is the origin's trips that resolved to a named borough at both ends, so a trip that touches `Unresolved` at either end is in neither the numerator nor the denominator. Source: user answer; docs/requirement/2026-11-24-ss-borough-flow-4ba22d8f.md R-05.
- `D-07` `destination_trip_share` is the pair's own share of the same denominator, and it is null on a row whose destination is `Unresolved`. Over one origin borough and month the shares of the named-borough destinations sum to 1, and the ones whose destination differs from the origin sum to the leaving share. Source: user answer; docs/requirement/2026-11-24-ss-borough-flow-4ba22d8f.md R-06.
- `D-08` No minimum pair size: every borough pair with billable trips is published. The 25-trip floor of [ADR 0017](../../../adr/0017-published-flows-have-a-25-trip-floor.md) is a rule about published zone-pair flows and is not carried to this grain. Source: user answer; docs/requirement/2026-11-24-ss-borough-flow-4ba22d8f.md R-07.
- `D-09` A pair-month with no billable trips is omitted, never emitted as a zero row. Source: user answer; docs/requirement/2026-11-24-ss-borough-flow-4ba22d8f.md R-07.
- `D-10` Both shares are ratios of summed counts, computed inside the model over the origin-borough-month, so no consumer rebuilds them ([ADR 0016](../../../adr/0016-rates-are-rebuilt-from-summed-numerators-and-denominators.md)); a zero denominator gives null through `safe_divide`. Source: [ADR 0016](../../../adr/0016-rates-are-rebuilt-from-summed-numerators-and-denominators.md), R-05.
- `D-11` `trip_month` is a `DATE` on the month's first day, so it joins `dim_date.month_start_date` directly and needs no cast at the consumer. Source: repository (`transformation/models/marts/core/dim_date.sql`), R-03.
- `D-12` The relation is excluded from the semantic layer, with the reason recorded in the repo map. Its borough columns publish the merged `Unresolved` group ([ADR 0018](../../../adr/0018-only-tlc-named-boroughs-count-and-unresolved-zones-form-one-group.md)), which is no member of the zone dimension's borough level, so no aggregate binding can name the population honestly; the guarded alternative and why it was refused are in `## Rejected`. Source: user answer 2026-11-24.
- `D-13` Materialised as a table with an enforced dbt contract and an ODCS contract, in `agg`, because it is a boundary relation. Source: docs/requirement/2026-11-24-ss-borough-flow-4ba22d8f.md R-09, `repo-map.json` `layers.agg`.
- `D-14` The relation carries seven columns and no others: `trip_month` (`DATE`), `origin_borough` (`VARCHAR`), `destination_borough` (`VARCHAR`), `trip_count` (`BIGINT`), `total_revenue` (`DOUBLE`), `destination_trip_share` (`DOUBLE`) and `origin_leaving_trip_share` (`DOUBLE`). A crossing flag, a per-row average fare or a zone-level column is not carried: the request asks for trips, revenue and the two shares. Source: docs/requirement/2026-11-24-ss-borough-flow-4ba22d8f.md R-01, R-05, R-06, R-08.
- `D-15` The two borough columns carry no `relationships` test against `dim_zone.borough_name`, and the model carries no crossing flag. No test may claim `Unresolved` is a zone-dimension member ([ADR 0018](../../../adr/0018-only-tlc-named-boroughs-count-and-unresolved-zones-form-one-group.md)); a singular test asserts instead that no row carries `Unknown` or `N/A` and that exactly one `Unresolved` label exists. Source: user answer; `docs/adr/0018-...md`, `.agents/skills/dbt-testing/SKILL.md`.
- `D-16` Both share columns are nullable by contract: `origin_leaving_trip_share` is null when the origin borough has no trip resolved to a named borough in that month (`D-06`), and `destination_trip_share` is null on an `Unresolved` destination row (`D-07`). Neither column is declared required. Source: docs/requirement/2026-11-24-ss-borough-flow-4ba22d8f.md R-05, R-06.

## Logical Model

No Ossie document gains a dataset, metric or logical source, and no ontology concept or mapping is reached: the relation is recorded in the repo map's `semantic_exclusions` instead (`D-12`).

```yaml
documents: []
datasets: {}
metrics: {}
logical_sources: {}
ontology:
  documents: []
  concepts: {}
  mappings: {}
exclusions:
  - relation: agg.agg_borough_flow_monthly
    added: true
```

## Rejected

- **Building on `agg_od_flow_matrix`** — its 25-trip floor withholds most zone pairs, so a borough rollup of it would answer a narrower question than the requirement asks and could not close against the billable trips.
- **Binding the relation to the canonical model at month grain only** — the generated binding test would pass because it never compares the borough values, but Studio would then answer a borough question from a source that cannot name a borough level, which is the failure the test exists to prevent.
- **Publishing `Unknown` and `N/A` as separate boroughs so every value stays a zone-dimension member** — it reverses the answer recorded in ADR 0018 and reports an unplaced zone as a destination borough.
- **Emitting the full borough grid with zero rows** — 3 months × 7 groups × 7 groups against a little over a hundred populated pairs; the zero rows add nothing a reader cannot infer, and every other aggregate in `agg` omits them.
- **Storing the leaving share once per origin borough in a second table** — a consumer would have to join it back, and the requirement asks for one table.

## Consumers

None in this repo. The intended consumer is the Mobility Planning Lead and the city's question about cross-borough traffic, which reads the table directly from the warehouse.

## History

- 2026-11-24 — ss-borough-flow — design record written — D-01 to D-16 — terms: added borough crossing, unresolved group, leaving-borough share
