---
artifacts: [mart_daily_zone_revenue]
---

# mart_daily_zone_revenue

Daily revenue by pickup zone.

## Grain

One row per pickup zone and trip date.

## Decisions

- `D-01` Apply the billable rule and the reporting window here, in gold, and nowhere upstream, so quality work can still see the rows this excludes ([ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md)). Source: docs/requirement/2026-08-29-the-trip-fact.md R-03, [ADR 0003](../../../adr/0003-billable-trip-definition-and-where-it-applies.md).
- `D-02` This is the Domain's only published daily zone revenue relation; the near-duplicate `agg.agg_trip_zone_daily` is retired rather than this mart being rebuilt from it, so the daily zone revenue figure stays the billable one and its numbers do not move ([ADR 0018](../../../adr/0018-one-published-daily-zone-revenue-figure.md)). Source: user answer to the requirement's opening question, docs/requirement/2026-11-25-zone-revenue-report-from-operations-figures-3-ac8b102d.md R-02.
- `D-03` The mart's own SQL, properties and contract are unchanged by that retirement: it already reads `fct_trip` and `dim_zone` directly, and rebuilding it as a projection of another relation would be a second build, not one source. Source: R-04.

## Rejected

- Applying the rule in silver: the excluded rows would be invisible to quality work.
- Deriving this mart from `agg.agg_trip_zone_daily`: that relation applies no billable rule and carries none of the four revenue components or `reporting_region`, so deriving from it either changes every number or adds a second copy of the rule inside one relation ([ADR 0018](../../../adr/0018-one-published-daily-zone-revenue-figure.md)).

## Consumers

None in this repo.

## History

- - 2026-10-14 — trip-fact — design record written; audience wording removed from the model description — D-01
- - 2026-11-25 — zone-revenue-report-from-operations-figures-3 — recorded as the only daily zone revenue relation after the aggregate duplicate is retired — D-02, D-03 — terms: none new
