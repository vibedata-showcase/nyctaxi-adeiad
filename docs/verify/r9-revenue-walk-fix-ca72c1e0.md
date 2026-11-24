# Verification: R9 · revenue walk fix

## Verification

`verdict: pending` at `1184020d14`: discovery for the revenue-walk case; no gate has run yet.

## Coverage

| Item | Evidence | Result | At |
| --- | --- | --- | --- |
| — | — | discovery only | `1184020d14` |

## Gate results

| Gate | Command | Exit | Outcome |
| --- | --- | --- | --- |
| — | — | - | unrun (design stage) |

## Discovery

<!-- Written by designing: each discovery result, and any slice with its limits. Keep as found. -->

- Canonical billable revenue for Q1 2024 is 2,629,185.82 on `core.fct_trip`, unchanged by the fix because it reads `total_amount` and not the residual. — `semantic_query{metrics:["billable_revenue"], mode:"run", target:"domain"}` → `LTS1_detail`, `{"billable_revenue":2629185.819999848}`
- The revenue walk overstates by exactly the airport fee, per month. — `select trip_month, sum(case when component_name = 'c_fare' then total_amount else 0 end) as walk_total, sum(component_amount) as component_sum, sum(case when component_name = 'c_airport_fee' then component_amount else 0 end) as airport_fee, sum(case when component_name = 'c_residual' then component_amount else 0 end) as residual from finance.mart_revenue_component_bridge group by 1 order by 1` → 2024-01: 816057.76 / 820054.76 / 3997.00 / -8851.50; 2024-02: 813885.68 / 817436.43 / 3550.75 / -7930.75; 2024-03: 999242.38 / 1003956.88 / 4714.50 / -3594.25. Component sum 2,641,448.07 against walk total 2,629,185.82; difference 12,262.25 = fee total.
- The walk's `total_amount` read once per group equals billable revenue and covers every billable trip, so the discrepancy is only in the component rows. — `with g as (select trip_month, service_type_key, borough_name, total_amount, trip_count from finance.mart_revenue_component_bridge group by all) select sum(total_amount) as walk_total_once_per_group, sum(trip_count) as walk_trips, (select count(*) from core.fct_trip where is_billable and pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01') as billable_trips from g` → 2629185.82 / 95958 / 95958
- Airport-fee trips carry the fee inside `total_amount`, so the fee must leave the residual rather than be added on top. — `select count(*) filter (where coalesce(airport_fee,0) <> 0) as fee_trips, count(*) filter (where coalesce(airport_fee,0) <> 0 and abs(fare_residual - airport_fee) <= 0.01) as fee_trips_residual_equals_fee, sum(coalesce(airport_fee,0)) filter (where coalesce(airport_fee,0) <> 0) as fee_total, count(*) filter (where abs(fare_residual) > 0.01) as unbalanced_before, count(*) filter (where abs(fare_residual - coalesce(airport_fee,0)) > 0.01) as unbalanced_after from core.fct_trip where pickup_datetime >= timestamp '2024-01-01' and pickup_datetime < timestamp '2024-04-01'` → 7184 / 5942 / 11952.50 / 31869 / 26457. Over billable trips only the fee total is 12,262.25 on 7,007 trips, 5,765 of them residual-equals-fee.
- Blast radius on the quality scorecard: 5,412 in-window trips move from unbalanced to balanced (31,869 → 26,457), so `mart_trip_quality_scorecard.unbalanced_total_count` falls in the vendor and month groups those trips sit in.
- Adjacent, not this defect: the monthly service summary is 3,551.07 below billable revenue because its inner join to the payment-method dimension drops 106 billable trips. — `select (select sum(total_revenue) from finance.mart_daily_zone_revenue) as daily_zone_total, (select sum(total_revenue) from finance.mart_monthly_service_summary) as monthly_service_total, (select sum(component_amount) from finance.mart_revenue_component_bridge) as bridge_component_sum` → 2629185.82 / 2625634.75 / 2641448.07
- The deployed numbers come from the branch's base commit, not a stale build. — `select load_id, pipeline_name, status, started_at, git_sha from bronze.audit_runs order by started_at desc limit 2` (same on `ops_raw`, `mdm_raw`) → `1795505036.578122, tlc, completed, 2026-11-24T07:23:56Z, 1184020d14474dceb6e933849792bff9033070f3`
- Gap: no dbt or Elementary test history was reachable — `transformation/target/` does not exist in this clone and the database has no Elementary schema — so the run history plane rests on the dlt `audit_runs` pin above.
