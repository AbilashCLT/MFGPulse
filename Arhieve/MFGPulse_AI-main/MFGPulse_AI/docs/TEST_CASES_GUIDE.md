# MFGPulse AI — Test Cases Guide

## Overview
57+ automated test cases across 11 categories. Run from Admin Panel (Test suite section) or directly in SQL worksheets. Results are stored in `MFGPULSE_DB.ANALYTICS.TEST_RESULTS`.

> **Important:** All test files reference `MFGPULSE_DB` (not `FAILURE_GENOME_DB`).

## Categories

### TC-01: Data Integrity (12 tests) — `test_data_integrity.sql`
Schema existence (7 schemas), row counts (10 assets, 170K+ sensors, 9 active users), referential integrity (sensor→asset, WO→asset), null PKs, date ranges (Mar-Sep 2026), data-bearing tables have data (excludes empty operational log tables: SHIFT_HANDOVER_HISTORY, BULK_OPERATION_LOG, ALERT_HISTORY), model registry (12 models), notification settings (16 event types).

### TC-02: ML Pipeline (10 tests) — `test_ml_pipeline.sql`
Predictions count (10), RUL>=0, degradation 0-1, fatigue 0-1, health 0-100, valid stages (Healthy/Warning/Critical), simulator returns 100 paths, fatigue all 10 assets, anomaly scores >=1800, M1-M8 in registry (8 models).

### TC-03: Procurement (5 tests) — `test_procurement.sql`
ATP=on_hand-reserved, all 17 parts in ATP view, valid risk/action enums (NO_RISK, ORDER_NOW, EXPEDITE, CRITICAL_SHORTAGE, UNKNOWN), 5 active suppliers, 18 part-supplier mappings.

### TC-04: Notifications (3 tests) — `test_notifications.sql`
16 event types seeded, all have personas configured, all 16 have in-app default ON.

### TC-05: WO/PO Lifecycle (11 tests) — `test_wo_po_lifecycle.sql`
Valid WO types (emergency/corrective/preventive), valid WO statuses (open/in_progress/completed/cancelled), completed WOs have date, ROOT_CAUSE_CONFIRMED values valid (includes 'normal' for no-fault-found), PART_USED boolean valid, valid PO statuses (pending_approval/approved/cancelled/received/ordered/shipped), alerts exist (WATCH/INFO severity), OEE covers all 10 assets, rejected POs have reason, PART_RESERVATIONS table exists, active reservations have valid WO references.

### TC-06: Simulation Scenarios (4 tests) — `test_simulation_scenarios.sql`
Healthy=0% failure, healthy RUL>100d, always 100 simulations, healthy→MONITOR recommendation.

### TC-07: Copilot + Search (2+ tests) — `test_copilot_scenarios.sql`
Search asset coverage (>=8), log count=26. Full Cortex Search accuracy benchmarks (bearing→ASSET_001, thermal→ASSET_002, emergency→emergency WO) require interactive SEARCH_PREVIEW execution.

### TC-08: Persona Access (11 tests) — `test_persona_access.py`
6 personas defined, all have copilot, admin restricted to PM+AA, all have wo_po, APP_ADMIN sees all 8, per-persona page lists match expected.

### TC-09: OEE Trend & Supply Chain Visualizations (4 tests)
Manual verification via Executive Dashboard: OEE Trend chart renders with lines for each production line + "Plant avg", 85% target reference line appears, metric selector works, Supply Chain Risk Overview shows donut chart.

### TC-10: Sensor Feed & Raw Data (3 tests)
Manual verification: Sensor feed loads data for all assets within 24h window, channel time-series chart renders, raw data expander shows tabular data.

### TC-11: ML UDF Edge Cases (10 tests) — `test_ml_edge_cases.sql`
COMPUTE_FATIGUE_SCORE with all zeros (<=0.3, UDF has baseline offset), capped at 1.0 with max inputs, PREDICT_RUL with zero degradation (=2000h), RUL never negative, PREDICT_DEGRADATION_STAGE healthy inputs (=Healthy), extreme inputs (=Critical), PREDICT_FAILURE_MODE normal inputs (=normal), SIMULATE_FAILURE_TWIN 100 paths, healthy asset <50% failure prob, degradation score bounded [0,1].

## Running Tests

### Admin Panel (recommended)
Admin Panel → Test suite → Select category → Run tests. Shows progress bar, pass/fail KPIs, results table. Results are persisted to `MFGPULSE_DB.ANALYTICS.TEST_RESULTS`.

### SQL Worksheet
Open any `test_cases/test_*.sql` in Snowsight. Each SELECT returns TEST_ID, TEST_NAME, EXPECTED, ACTUAL, STATUS.

### Query Results Table
```sql
-- Summary by suite
SELECT TEST_SUITE, COUNT(*) AS TOTAL, COUNT_IF(STATUS='PASS') AS PASSED,
       COUNT_IF(STATUS='FAIL') AS FAILED,
       ROUND(COUNT_IF(STATUS='PASS') * 100.0 / COUNT(*), 1) AS PASS_PCT
FROM MFGPULSE_DB.ANALYTICS.TEST_RESULTS
GROUP BY ROLLUP(TEST_SUITE) ORDER BY GROUPING(TEST_SUITE), TEST_SUITE;
```

### Python
```
cd MFGPulse_AI/test_cases && python3 test_persona_access.py
```

## Acceptance Criteria
Pass when: TC-01 through TC-06 all PASS, TC-07 >=80% PASS, TC-08 all PASS. Target: >=95% overall (57/57 = 100% achieved).

## Data Quality Monitoring
In addition to test cases, continuous data validation is enforced via Snowflake Data Metric Functions (DMFs):

| Table | Column | Rule | Schedule |
|-------|--------|------|----------|
| WORK_ORDERS | WO_TYPE | IN (emergency, corrective, preventive) | TRIGGER_ON_CHANGES |
| WORK_ORDERS | STATUS | IN (open, in_progress, completed, cancelled) | TRIGGER_ON_CHANGES |
| WORK_ORDERS | ROOT_CAUSE_CONFIRMED | IS NULL OR IN (11 valid values) | TRIGGER_ON_CHANGES |
| PURCHASE_ORDERS | STATUS | IN (6 valid PO lifecycle values) | TRIGGER_ON_CHANGES |

Validation rules are documented in `MFGPULSE_DB.ANALYTICS.DATA_VALIDATION_RULES`. Issues are logged in `MFGPULSE_DB.ANALYTICS.DATA_QUALITY_ISSUES`.

## Test Count Summary

| Category | Tests | File |
|---|---|---|
| TC-01 Data Integrity | 12 | test_data_integrity.sql |
| TC-02 ML Pipeline | 10 | test_ml_pipeline.sql |
| TC-03 Procurement | 5 | test_procurement.sql |
| TC-04 Notifications | 3 | test_notifications.sql |
| TC-05 WO/PO Lifecycle | 11 | test_wo_po_lifecycle.sql |
| TC-06 Simulation | 4 | test_simulation_scenarios.sql |
| TC-07 Copilot + Search | 2+ | test_copilot_scenarios.sql |
| TC-08 Persona Access | 11 | test_persona_access.py |
| TC-09 OEE/Supply Chain | 4 | Manual verification |
| TC-10 Sensor Feed | 3 | Manual verification |
| TC-11 ML Edge Cases | 10 | test_ml_edge_cases.sql |
| **Total** | **57 automated + 7 manual** | |
