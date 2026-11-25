---
kinds: [transformation]
---

# Requirement: Borough-to-borough trips and revenue, Q1 2024 4

## Ask

Leila Haddad, Mobility Planning Lead, was asked by the city how much of the traffic crosses borough lines. For each month of Q1 2024 she needs, from each borough to each borough, the trips and the revenue, and the share of trips that leave the borough they started in. She and the city read the result as a published table; the planning team filters and ranks it, so the numbers must reconcile to the trip fact rather than to a hand-made extract.

## Requirements

- [ ] `R-01` A published boundary table reports one row per (calendar month, origin borough, destination borough) for every month of Q1 2024, covering the full cross product: each origin borough against each destination borough in every month, including pairs that carried no trip — accept when the relation holds 3 × 8 × 8 = 192 rows, every month present is 2024-01, 2024-02 and 2024-03, and for each month the set of (origin, destination) pairs equals the borough set crossed with itself — source: request; user answer on population
- [ ] `R-02` Each row reports the trips from its origin borough to its destination borough in that month, drawn from billable trips picked up inside the Q1 2024 reporting window, and zero for a pair with none — accept when the trip counts sum over each month to that month's billable trip count in `fct_trip` (95,958 over the three months), and a sample of cells matches an independent recomputation from `fct_trip` joined twice to `dim_zone` — source: request; `docs/adr/0003-billable-trip-definition-and-where-it-applies.md`; user answer on population
- [ ] `R-03` Each row reports the revenue of those trips, and zero for a pair with none — accept when the revenue sums over each month to the month's independently recomputed total (2,629,185.82 over the three months) and a zero-trip row carries 0, not null — source: request; user answer on population
- [ ] `R-04` Each row carries the crossing share of its origin borough for that month — its cross-borough trips over all its trips — published beside both the numerator and the denominator, and identical on every destination row of that borough-month — accept when the share equals the independently recomputed ratio for each of the 24 borough-months, the numerator counts exactly those trips whose destination borough differs from the origin borough, and the share is the same value on all eight destination rows of a borough-month — source: request; user answer on share; `docs/adr/0016-rates-are-rebuilt-from-summed-numerators-and-denominators.md` for the ratio-of-sums form
- [ ] `R-05` Each row carries the row's own share of its origin borough's trips that month, so a reader can see how a borough's traffic splits between destinations — accept when the per-row shares of a borough-month sum to 1 and each equals the independently recomputed pair count over the borough count — source: user answer on share
- [ ] `R-06` The grain is unique — accept when a singular test proves exactly one row per (month, origin borough, destination borough) — source: repository convention, `transformation/tests/assert_daypart_cube_one_row_per_grain.sql`
- [ ] `R-07` The unresolved borough groups are published, like every other borough, and a consumer can tell them apart — accept when rows exist for the `Unknown` and `N/A` borough groups in every month and each row carries a column that distinguishes an unresolved group from a resolved one — source: `docs/adr/0012-unresolved-zones-are-retained-and-flagged.md`; `CONTEXT.md` (Unresolved zone)
- [ ] `R-08` The table is a boundary relation, so it carries its data contract, its dbt tests and its design record, and it is routed in the semantic model — accept when the ODCS contract checks, the model's data and unit tests pass, the design record exists, and the semantic-model gate reports the routing — source: repository convention (`repo-map.json` `artifact_paths.data_contract`, `logical-model/`)

## Business decisions

| Decision | Value | Source |
| --- | --- | --- |
| Grain | One row per (calendar month of Q1 2024, origin borough, destination borough) | request ("for each month of Q1 2024", "from each borough to each borough") |
| Period boundary | A trip belongs to the month of its pickup date; Q1 2024 is `pickup_datetime` at or after 2024-01-01 and before 2024-04-01, which is exactly the reporting window in `dbt_project.yml` | request; repository (`report_start`, `report_end`) |
| Edge periods | Not applicable: the loaded data covers every day of January (31), February (29) and March (31) 2024, so no month of the requested quarter is cut short — measured on `core.fct_trip`, `min(pickup_date)` 2024-01-01 and `max(pickup_date)` 2024-03-31 | repository data |
| Population and floor | The full borough cross product every month, no trip floor: 8 borough groups × 8 × 3 months. ADR 0017's 25-trip floor governs the zone-pair matrix and does not apply at borough grain | user answer; `docs/adr/0018-a-borough-level-flow-publishes-the-full-borough-cross-product.md` |
| Billable rule | Applied here, in gold: trips whose total amount is positive only | `docs/adr/0003-billable-trip-definition-and-where-it-applies.md` |
| Empty cells | A pair with no billable trip in the month is published with 0 trips and 0 revenue, never omitted and never null | user answer on population |
| Revenue amount | **Open** — whether "revenue" is `sum(total_amount)` (what the passenger paid, the amount every existing revenue mart publishes), `sum(fare_amount)`, or all fare components published separately beside a total. Recommendation: `sum(total_amount)`. Holds the design of the revenue columns | request (says "revenue" only); question timed out twice — see `## Open questions` |
| Crossing share | Ratio of summed counts: cross-borough trips over the origin borough's trips for that month, computed with `safe_divide` so a borough-month with no trips yields null; published beside both counts, and repeated on every destination row of the borough-month | user answer on share; `docs/adr/0016-rates-are-rebuilt-from-summed-numerators-and-denominators.md` |
| Per-row share | The row's trips over its origin borough's trips that month, by the same ratio-of-sums rule | user answer on share |
| Borough set | Every distinct borough group in `core.dim_zone`, including the unresolved `Unknown` and `N/A` groups, so the number of cells follows that dimension rather than a list in code | `docs/adr/0012-unresolved-zones-are-retained-and-flagged.md` |
| Null and unmatched keys | No trip is dropped or relabelled by the borough lookup. Every billable trip in the window resolves both a pickup and a dropoff zone key (0 null, 0 unmatched of 95,958 measured), so cell counts close to the fact | `docs/adr/0015-unmatched-dimension-keys-stay-null.md`; repository data |
| Coverage | Not applicable: `total_amount` is present on every billable trip in the window (0 nulls of 95,958), so revenue needs no coverage count beside it | repository data |
| Reuse | Built from `fct_trip` with `dim_zone` joined twice, not from `agg_od_flow_matrix`: ADR 0017's floor makes that table a partial population and it is published at zone grain, so the borough cells it omitted could not be recovered | `docs/adr/0017-published-flows-have-a-25-trip-floor.md`; repository (`agg_od_flow_matrix.sql`) |

## Out of scope

- No change to `fct_trip`, `dim_zone` or any other published model; the table is new and reads them.
- No change to the reporting window, the billable rule or ADR 0017's zone-pair floor.
- No change to the ingestion pipelines or the orchestration scripts.
- No per-zone or per-pair granularity: the table reports borough to borough only.
- No schedule: the table is a transformation deliverable and nothing new runs it.
- `agg.agg_od_flow_matrix` stays exactly as it is, floor included.

## Open questions

- **Which amount is "revenue"?** The request says only "revenue". The recommendation is `sum(total_amount)`, the amount `agg_od_flow_matrix` and `mart_daily_zone_revenue` publish as `total_revenue`; `sum(fare_amount)` and a set of separate fare components are the alternatives. Asked twice and unanswered, so it is recorded here rather than assumed. Holds the revenue columns and R-03's acceptance value.
- **Does the table follow the reporting window or stay pinned to Q1 2024?** The two agree today (the window is 2024-01-01 to 2024-04-01), but the request names a quarter. Recommendation: follow the window, as every other mart does, so the table never claims a quarter it does not report. Holds nothing until the window changes; recorded so the design stop can settle it.

## Approvals

<!-- Append-only, approvals only, one line each: `- <UTC> — <requirement | design | breaking contract | ship> approved — "<the user's literal answer>" — <commit>`. A declined stop is recorded under `## Open questions` or in the design record, never here. -->
