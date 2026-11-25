---
kinds: [transformation]
---

# Requirement: Zone revenue report single source

## Ask

Finance owner Ravi Menon: "Finance reads the daily zone revenue report every
morning. Operations keeps its own daily figures by zone in the agg schema, so we
pay for two builds that should give the same answers. Please build our report
from the operations figures, so that there is one source. No number in our
report may change. Before we accept a change, we run our usual check: for Q1
2024 the report must show 95,958 trips and 2,629,185.82 revenue in total, and
4,120 trips and 337,711.05 revenue for JFK Airport."

Consumers: the finance team's morning report, read from
`finance.mart_daily_zone_revenue`.

Two facts found while drafting this, both checked against the sandbox warehouse:

- The premise is not what it sounds like. Every relation in the `agg` schema is
  built by dbt from `core.fct_trip`, `core.fct_shift` and the status intervals,
  not from the operations source. `agg.agg_trip_zone_daily` reads
  `core.fct_trip` — the same relation `finance.mart_daily_zone_revenue` reads.
  So today there is one *source* (the TLC trip feed) and two *aggregations* of
  it; the duplicate build Ravi pays for is real, but it is not an
  operations-versus-finance split.
- The two builds do not agree, and the gap is not rounding: the agg relation
  publishes the all-trips population (`trip_count` 97,184,
  `total_revenue` 2,597,120.92 for Q1 2024; JFK 4,261 and 329,766.06), while the
  finance report publishes the billable population (95,958 and 2,629,185.82;
  JFK 4,120 and 337,711.05). The agg relation also carries no fare, tip,
  surcharge or toll split and no `reporting_region`, so it cannot serve five of
  the report's published columns. The stated acceptance figures are exactly the
  billable population: recomputed straight from `core.fct_trip` filtered to
  `is_billable` inside the window and grouped by zone and day, Q1 2024 gives
  95,958 trips and 2,629,185.82 revenue, and 4,120 and 337,711.05 for zone 132.

## Requirements

- [ ] `R-01` The finance daily zone revenue report and the agg-schema daily zone
      figures are produced by one build, so the same revenue is not aggregated
      twice — accept when the compiled lineage shows
      `finance.mart_daily_zone_revenue` reading exactly one zone-day revenue
      relation and holding no aggregation over `fct_trip` of its own — source:
      request ("so that there is one source")
- [ ] `R-02` No published number changes — accept when the rebuilt
      `finance.mart_daily_zone_revenue` matches the merge-base build row for row
      on (`trip_date`, `pickup_location_id`) and value for value on all eleven
      published columns, 7,961 rows, zero differences — source: request ("No
      number in our report may change")
- [ ] `R-03` The Q1 2024 acceptance figures hold — accept when a query over the
      built relation returns `sum(trip_count)` = 95,958 and
      `round(sum(total_revenue), 2)` = 2,629,185.82 over the window, and 4,120
      and 337,711.05 for `pickup_location_id` 132 (JFK Airport) — source:
      request
- [ ] `R-04` The report keeps its published shape — accept when the relation
      still carries the same eleven columns with the same names and types, and
      the ODCS contract for `finance.mart_daily_zone_revenue` is unchanged,
      still `status: active`, with no version move — source: request ("No number
      in our report may change") and the existing published contract
- [ ] `R-05` The fare, tip, surcharge and toll split stays published and
      unchanged — accept when each of `fare_revenue`, `tip_revenue`,
      `surcharge_revenue` and `toll_revenue` sums per zone-day to its merge-base
      value, so the single build must carry all four — source: request plus the
      existing published columns
- [ ] `R-06` The shared build's existing consumers see no change — accept when
      every row of the extended agg relation returns its merge-base
      `trip_count`, `total_revenue`, `total_miles`, `attributed_driver_count`
      and the six period-over-period columns unchanged (7,997 rows) — source:
      request ("No number ... may change") plus the published contract of
      `agg.agg_trip_zone_daily`
- [ ] `R-07` The models' descriptions state the source each actually reads, and
      the report's `trip_count` description stops contradicting its own SQL —
      accept when the rebuilt descriptions match the built relation:
      `trip_count` currently reads "Trips, billable or not." while the model
      filters `f.is_billable`, and the count is 95,958 billable trips — source:
      finding during this requirement (docs contradict data)

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Reading of the ask | Dedupe the two aggregations of the TLC trip fact; the report keeps its billable population and all its figures, and both relations come from one build. `ops_raw.trip_assignment` is not the source Ravi meant | user answer, after the repository showed every `agg` relation is built from `core.fct_trip` |
| Grain of `finance.mart_daily_zone_revenue` | One row per pickup zone and trip date; unchanged. Keys are the published `pickup_location_id` (a `dim_zone.zone_natural_key`) and `trip_date` | existing model and contract; request names the report, not a new grain |
| Edge periods | Not applicable: the grain is daily and the reporting window's first and last dates (2024-01-01 and 2024-03-31) sit fully inside the loaded data, so no period is cut short | query of `core.fct_trip` pickup dates inside the window |
| Population and metric definitions | Billable trips only, inside the reporting window: "A trip is **billable** when its total amount is positive. ... Gold marts that report revenue or flows apply it, inside the reporting window: `mart_daily_zone_revenue`, ...". Revenue is `sum(total_amount)` over exactly those rows; the four components are `sum()` of `fare_amount`, `tip_amount`, `total_surcharges` and `tolls_amount` over the same rows | [ADR 0003](../../adr/0003-billable-trip-definition-and-where-it-applies.md) quoted; request fixes the figures that rule produces |
| Coverage | Not applicable: no measure is added or removed, so no new coverage count is published; the published column set is fixed by `R-02` and `R-04` | `R-02`, `R-04`; playbook Coverage branch |
| Reuse | Build on the published `agg.agg_trip_zone_daily`, extended so it carries the billable revenue and the four component sums and `reporting_region`; the report then reads that one relation. Whether that is an extension of the existing relation or a new shared relation beside it, and its materialisation, are pending for design. `ops_raw.trip_assignment` is not a candidate: 4,574 trips and 120,216.19 revenue for the whole quarter against the 95,958 and 2,629,185.82 required, and no component split | playbook Reuse default plus the repository (the agg relation is the published model at this grain); figures from the sandbox warehouse |
| Unmatched and null keys | Every currently published row is kept and no other row is added: the inner join to `dim_zone` and the billable filter stay exactly as today, so the 36 zone-days whose only trips are non-billable stay out, and the all-trips rows of the agg relation stay in | existing model plus `R-02` |
| Extended scope | Not a question: no schedule is requested, so no `orchestration` kind; the report's contract keeps its version and stays `active` | playbook Extended scope |

## Out of scope

- The meanings of `agg.agg_trip_zone_daily`'s existing `trip_count` and
  `total_revenue` (all trips, unfiltered revenue). They stay as they are; the
  report may not inherit them, because doing so changes its numbers.
- `core.fct_trip`, the intermediate models, `finance.mart_monthly_service_summary`,
  `finance.mart_revenue_component_bridge`, `agg.agg_od_flow_matrix` and the
  `ops` marts.
- Ingestion: no `dlt` pipeline, source or config change.
- Any `--full-refresh` of a published model beyond the ones this change builds.
- The Ossie documents and the ontology, except where a changed description must
  agree with them.

## Open questions

1. **Which relation is the single build.** Settled as a design matter, not left
   open: extending `agg.agg_trip_zone_daily` preserves every number in both
   relations (my recommendation, and what the Reuse row records). Converting
   that relation to the billable population instead would make it and the report
   one population, but changes its published `trip_count` and `total_revenue`
   and contradicts its semantic binding. Extend-versus-new-relation and
   materialisation are design's to settle under `R-01` and `R-06`.
2. **Ravi's figures are the billable population, not the agg relation's.** If he
   is shown `agg.agg_trip_zone_daily` later, its Q1 total of 97,184 trips and
   2,597,120.92 revenue will look like a disagreement. It is not: that relation
   publishes all trips by design, and the report publishes billable ones. Worth
   one line back to him when this ships; it changes no work.

## Approvals

