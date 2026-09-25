# MFGPulse AI — One-Shot Deployment Guide

*Deploy the entire platform from zero to running in a single session.*

---

## Recommended: One-Time Deployment Script

For the fastest, most reliable deployment, use:

```
sql/deploy_one_time_consolidated.sql    — Orchestration script with 14 checkpoints, timing, and credit logging
sql/deployment_report.sql  — Post-deployment report (run after deploy_one_time.sql)
sql/credit_consumption_report.sql — Credit usage analysis and monthly cost projections (run after deploy_one_time_consolidated.sql)
```

`deploy_one_time_consolidated.sql` creates a `DEPLOYMENT_LOG` table that tracks each phase with start/end time, credits consumed, objects created, and pass/fail validation. After completion, run `deployment_report.sql` for a full health check.

> **Note on stub scripts**: Scripts 07, 08, 09, 10, 12, 16 (before this update), and 17 were description-only stubs with no executable DDL. The actual DDL lives in `docs/full_ddl_export.sql`. The `deploy_one_time_consolidated.sql` script references the correct source files for each phase. Script `16_procurement_views.sql` now contains complete executable DDL for all 5 procurement views.

---

## Prerequisites

| Requirement | Details |
|---|---|
| **Snowflake account** | Any edition (Standard, Enterprise, Business Critical) |
| **Role** | `ACCOUNTADMIN` (or a custom role with CREATE DATABASE, CREATE WAREHOUSE, CREATE RESOURCE MONITOR, CREATE INTEGRATION privileges) |
| **ACCOUNT_USAGE access** | The deploying role must have access to `SNOWFLAKE.ACCOUNT_USAGE` views (granted by default to ACCOUNTADMIN). Required for the FinOps dashboard in the Admin Panel. |
| **Warehouse** | Will be created by the scripts (`COMPUTE_WH`, X-SMALL) |
| **Compute pool** | `SYSTEM_COMPUTE_POOL_CPU` must exist (required for Streamlit in Snowflake) |
| **Cortex AI** | Account must have Cortex Complete, Cortex Search, Cortex Agent, and Semantic Views enabled |
| **Email notifications** (optional) | Account must support `SYSTEM$SEND_SNOWFLAKE_NOTIFICATION` for email delivery |

---

## Deployment Overview

```
Phase 1: Infrastructure     (Script 01)          ~5 seconds
Phase 2: Base tables         (Scripts 02-03)      ~5 seconds
Phase 3: Seed data           (Scripts 04-06)      ~2 minutes
Phase 4: Dynamic tables      (Scripts 07-09)      ~3 minutes (DT initial refresh)
Phase 5: ML models           (Scripts 10-11)      ~1 minute
Phase 6: Analytics           (Script 12)          ~1 minute (DT initial refresh)
Phase 7: Cortex Search       (Script 13)          ~30 seconds
Phase 8: Automation          (Script 14)          ~5 seconds
Phase 9: Procurement         (Scripts 15-17)      ~30 seconds
Phase 10: Validation         (Script 18)          ~10 seconds
Phase 11: Notifications      (Script 19)          ~10 seconds
Phase 12: Cortex Agent       (Manual deploy)      ~2 minutes
Phase 13: Streamlit app      (Open in Snowsight)  ~1 minute
                                                  ──────────
                                        Total:    ~12 minutes
```

---

## Step-by-Step Deployment

### Phase 1 — Infrastructure

Open a SQL worksheet in Snowsight. Set role to `ACCOUNTADMIN`.

Run `sql/01_infrastructure.sql`:

```sql
-- Creates: MFGPULSE_DB, 7 schemas, COMPUTE_WH, MFGPULSE_CREDIT_GUARD, MFGPULSE_AUTOMATION_WH, MFGPULSE_AUTOMATION_GUARD
-- Expected output: All statements succeed
```

**Verify:**
```sql
SHOW SCHEMAS IN DATABASE MFGPULSE_DB;
-- Should return 7 schemas: RAW_OT, RAW_IT, CURATED, ML_FEATURES, ML_MODELS, ANALYTICS, AGENT
-- (plus INFORMATION_SCHEMA and PUBLIC)
```

---

### Phase 2 — Base Tables & Streams

Run `sql/02_base_tables.sql`:
```sql
-- Creates 19 base tables across RAW_OT and RAW_IT
-- Tables: ASSET_MASTER, SENSOR_METADATA, SENSOR_READINGS, AMBIENT_CONDITIONS,
--         WORK_ORDERS, MAINTENANCE_LOGS, PARTS_INVENTORY, PRODUCTION_OUTPUT,
--         SHIFT_SCHEDULE, USERS, SUPPLIERS, PART_SUPPLIERS, PURCHASE_ORDERS,
--         PURCHASE_ORDER_LINES, PART_RESERVATIONS, MODEL_REGISTRY,
--         FATIGUE_SCORES, ANOMALY_SCORES
```

Run `sql/03_streams.sql`:
```sql
-- Creates 3 CDC streams:
--   SENSOR_READINGS_STREAM, MAINTENANCE_LOGS_STREAM, WORK_ORDERS_STREAM
```

**Verify:**
```sql
SELECT TABLE_SCHEMA, COUNT(*) AS TABLES
FROM MFGPULSE_DB.INFORMATION_SCHEMA.TABLES
WHERE TABLE_TYPE = 'BASE TABLE' AND TABLE_SCHEMA IN ('RAW_OT', 'RAW_IT')
GROUP BY TABLE_SCHEMA;
-- RAW_OT: 4 tables, RAW_IT: ~15 tables
```

---

### Phase 3 — Seed Data

Run `sql/04_seed_data.sql`:
```sql
-- Populates reference data:
--   10 assets, 23 sensors, 15 parts, 9 users (6 personas),
--   22 work orders, 78 maintenance logs, ~1710 shift records,
--   ~3330 production records, 5 suppliers, 16 part-supplier mappings,
--   10 model registry entries
```

Run `sql/05_generate_sensor_data.sql`:
```sql
-- Generates 172K+ sensor readings (30-day history, 15-min intervals, 10 assets)
-- This is the largest data generation step — may take 1-2 minutes
```

**Do NOT run `sql/06_fatigue_scores.sql` here** — it depends on UDFs and Dynamic Tables
created in later phases. It runs in Phase 5 after ML models are deployed.

**Verify:**
```sql
SELECT COUNT(*) AS SENSOR_ROWS FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS;
-- Should return >= 172,000

SELECT COUNT(DISTINCT ASSET_ID) AS ASSETS_WITH_FATIGUE
FROM MFGPULSE_DB.ML_MODELS.FATIGUE_SCORES;
-- Should return 10
```

---

### Phase 4 — Dynamic Tables (Feature Engineering)

Run `sql/07_curated_dynamic_tables.sql`:
```sql
-- Creates 3 curated DTs:
--   SENSOR_WITH_CONTEXT (172K rows) — OT sensors + IT metadata joined
--   ASSET_HEALTH_CURRENT (10 rows) — Latest reading per asset + 24h stats
--   FAILURE_HISTORY (12 rows) — Pre-failure sensor patterns
-- All with TARGET_LAG = '1 hour', WAREHOUSE = COMPUTE_WH
```

Run `sql/08_ml_feature_dynamic_tables.sql`:
```sql
-- Creates 7 feature engineering DTs:
--   LABELED_DATA, ROLLING_STATS, SENSOR_INTERACTIONS,
--   TEMPORAL_MEMORY, CROSS_DOMAIN, PHYSICS_COMPOSITE (INCREMENTAL),
--   FLEET_COMPARISON
-- Wait for initial refresh to complete (~2-3 minutes)
```

Run `sql/09_ml_feature_views.sql`:
```sql
-- Creates 11 ML feature views (used for model training)
```

**Verify:**
```sql
SELECT NAME, SCHEDULING_STATE, ROWS_INSERTED
FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
    NAME_PREFIX => 'MFGPULSE_DB'
))
ORDER BY DATA_TIMESTAMP DESC
LIMIT 15;
-- All DTs should show SUCCEEDED status
```

---

### Phase 5 — ML Models & Predictions

Run `sql/10_udfs_live_predictions.sql`:
```sql
-- Creates 5 UDFs:
--   PREDICT_FAILURE_MODE (M1), PREDICT_RUL (M2),
--   PREDICT_DEGRADATION_STAGE (M3), COMPUTE_FATIGUE_SCORE (M4),
--   SIMULATE_FAILURE_TWIN (M6)
-- Creates 3 procedures:
--   ANALYZE_ROOT_CAUSE (M5), PRESCRIBE_MAINTENANCE (M7), PREDICT_ALL
-- Creates LIVE_PREDICTIONS dynamic table (calls M1-M3 UDFs on refresh)
```

Run `sql/11_native_ml_models.sql` (optional but recommended):
```sql
-- Trains 4 Snowflake-native ML models using corrected training views.
-- IMPORTANT: Training views were fixed on 2026-09-13:
--   - TRAIN_FAILURE_MODE: Normal class sampling 15% → 50% (reduces failure bias)
--   - TRAIN_TRAJECTORY_3CLASS: Numeric labels (0/1/2) → text ('Healthy'/'Warning'/'Critical')
-- Also creates drift detection + closed-loop ML objects:
--   DRIFT_COMPARISON table, DRIFT_METRICS view, FEEDBACK_LOG table,
--   MODEL_ACCURACY_LIVE view, COMPUTE_NATIVE_PREDICTIONS proc,
--   RETRAIN_IF_NEEDED proc, LOG_FEEDBACK proc, DAG_CHECK_DRIFT task
-- Note: Training may take 10-20 minutes and consume ~0.5-2 credits
-- For initial setup or retraining, use sql/retrain_and_validate.sql
```

**Verify:**
```sql
SELECT ASSET_ID, STAGE_PRED, RUL_HOURS, DEGRADATION_SCORE, FAILURE_MODE_PRED
FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS
ORDER BY RUL_HOURS ASC;
-- Should return 10 rows (1 per asset) with predictions populated
```

---

### Phase 6 — Analytics Layer

Run `sql/12_analytics_layer.sql`:
```sql
-- Creates 2 dynamic tables:
--   ACTIVE_ALERTS — Multi-signal alert engine (Critical/Warning/Watch/Info)
--   OEE_METRICS — Per-asset-per-shift OEE calculation
-- Creates 6 views:
--   EXECUTIVE_SUMMARY, PREDICTIONS_WITH_COST, COST_IMPACT, COST_IMPACT_BY_ASSET,
--   SHIFT_HANDOVER_VIEW, ALERT_SUMMARY
-- Creates 6 procedures:
--   GENERATE_WORK_ORDER, AUTO_GENERATE_WORK_ORDERS,
--   GENERATE_SHIFT_HANDOVER_SUMMARY, CREATE_PURCHASE_ORDER,
--   APPROVE_PURCHASE_ORDER, RECEIVE_PURCHASE_ORDER
```

**Verify:**
```sql
SELECT * FROM MFGPULSE_DB.ANALYTICS.EXECUTIVE_SUMMARY;
-- Should return 1 row with TOTAL_ASSETS=10, PLANT_OEE, TOTAL_COST_AVOIDED, etc.

SELECT SEVERITY, COUNT(*) FROM MFGPULSE_DB.ANALYTICS.ACTIVE_ALERTS GROUP BY SEVERITY;
-- Should return alerts across severity levels
```

---

### Phase 7 — Cortex Search

Run `sql/13_cortex_search.sql`:
```sql
-- Creates MAINTENANCE_SEARCH Cortex Search service
-- Indexes 78 maintenance documents (log entries joined with asset + WO context)
-- TARGET_LAG = '1 day'
```

**Verify:**
```sql
SHOW CORTEX SEARCH SERVICES IN SCHEMA MFGPULSE_DB.ML_MODELS;
-- Should show MAINTENANCE_SEARCH with status = ACTIVE
```

---

### Phase 8 — Automation Tasks

Run `sql/14_automation.sql`:
```sql
-- Creates 3 scheduled tasks (all SUSPENDED by default):
--   SIMULATE_SENSOR_FEED (every 720 min) — generates new sensor readings
--   SIMULATE_PRODUCTION (every 720 min) — generates production records
--   AUTO_PROCUREMENT_REVIEW (every 720 min) — auto-generates POs
-- Resume tasks only when you want continuous data simulation
```

> **Note**: The automation runs as a Task DAG. Resume children first (bottom-up), then root:
> ```sql
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_CONVERT_PPOS RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_GENERATE_POS RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_GENERATE_WOS RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_REFRESH_DTS RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_REFRESH_FATIGUE RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.MFGPULSE_AUTOMATION_DAG RESUME;
> ```
> This starts the full chain: sensor data → fatigue → DT refresh → WO gen → PO gen → PPO conversion (every 12h).

---

### Phase 9 — Procurement System

Run `sql/15_procurement_tables.sql`:
```sql
-- Creates procurement-specific table structures (if not already created in 02)
```

Run `sql/16_procurement_views.sql`:
```sql
-- Creates: PARTS_AVAILABLE_TO_PROMISE, PROCUREMENT_RECOMMENDATIONS views
```

Run `sql/17_procurement_procedures.sql`:
```sql
-- Creates: AUTO_GENERATE_PURCHASE_ORDERS procedure
```

**Verify:**
```sql
SELECT PART_NAME, AVAILABLE_TO_PROMISE, PROCUREMENT_RISK
FROM MFGPULSE_DB.ANALYTICS.PROCUREMENT_RECOMMENDATIONS
ORDER BY RUL_HOURS ASC
LIMIT 5;
-- Should return parts with risk levels: CRITICAL_SHORTAGE, EXPEDITE, ORDER_NOW, NO_RISK
```

---

### Phase 10 — Validation

Run `sql/18_validation.sql`:
```sql
-- Runs full verification suite:
--   1. Schema existence (7 schemas)
--   2. Row count validation (10 tables)
--   3. Date range validation
--   4. Referential integrity (SENSOR→ASSET, WO→ASSET)
--   5. ML pipeline (LIVE_PREDICTIONS, FATIGUE, ANOMALY, MODEL_REGISTRY)
--   6. Prediction range validation (RUL>=0, degradation 0-1, fatigue 0-1)
--   7. Analytics layer (ACTIVE_ALERTS, OEE_METRICS, PROCUREMENT, ATP)
--   8. UDF smoke test (COMPUTE_FATIGUE_SCORE)
--   9. Persona validation
--  10. Final summary counts
```

**Expected output**: All STATUS columns should show `PASS`.

---

### Phase 11 — Notifications

Run `sql/19_notifications.sql`:
```sql
-- Creates: NOTIFICATION_SETTINGS table (16 event types, admin-configurable)
-- Creates: APP_NOTIFICATIONS table (in-app notification store)
-- Creates: MFGPULSE_EMAIL notification integration (TYPE=EMAIL)
-- Creates: SEND_MFGPULSE_EMAIL wrapper procedure
-- Creates: LOG_APP_NOTIFICATION central dispatcher
```

**Verify:**
```sql
SELECT EVENT_TYPE, EMAIL_ENABLED, IN_APP_ENABLED, NOTIFY_PERSONAS
FROM MFGPULSE_DB.RAW_IT.NOTIFICATION_SETTINGS
ORDER BY EVENT_TYPE;
-- Should return 16 event types with sensible defaults
```

---

### Phase 12 — Cortex Semantic View & Agent

This step deploys the Cortex AI components from the `cortex_project/` directory.

**Option A — Using CoCo (Cortex Code)**:
```
cortex agent-studio sv-deploy cortex_project/MAINTENANCE_SEMANTIC_VIEW.sv.yaml
cortex agent-studio agent-deploy cortex_project/MAINTENANCE_COPILOT_agent.yaml
```

**Option B — Using Snowsight UI**:
1. Navigate to **AI & ML > Cortex AI** in Snowsight
2. Create a new Semantic View using `MAINTENANCE_SEMANTIC_VIEW.sv.yaml`
   - Target: `MFGPULSE_DB.AGENT.MAINTENANCE_SEMANTIC_VIEW`
    - 6 tables, 21 VQRs
3. Create a new Cortex Agent using `MAINTENANCE_COPILOT_agent.yaml`
   - Target: `MFGPULSE_DB.AGENT.MAINTENANCE_COPILOT`
   - 5 tools: maintenance_analytics, maintenance_history, predict_all, simulate_scenario, generate_work_order

**Verify:**
```sql
-- Semantic View
SHOW SEMANTIC VIEWS IN SCHEMA MFGPULSE_DB.AGENT;
-- Should show MAINTENANCE_SEMANTIC_VIEW

-- Agent
SHOW CORTEX AGENTS IN SCHEMA MFGPULSE_DB.AGENT;
-- Should show MAINTENANCE_COPILOT

-- Test agent
SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN(
    'MFGPULSE_DB.AGENT.MAINTENANCE_COPILOT',
    'What is the current plant OEE?'
) AS RESPONSE;
-- Should return a response with OEE data
```

---

### Phase 13 — Streamlit App

1. Open the workspace in Snowsight containing the `MFGPulse_AI_App/` directory
2. The app is defined by `snowflake.yml` with:
   - Main file: `streamlit_app.py`
   - Compute pool: `SYSTEM_COMPUTE_POOL_CPU`
   - Query warehouse: `COMPUTE_WH`
3. Click **Run** to launch the Streamlit app
4. Select a user profile to log in — the app filters navigation by persona

**Verify**: Log in as each persona and confirm page access:

| Persona | Expected Pages |
|---|---|
| Technician | Maintenance, WO/PO, Operations, Procurement, Copilot (5) |
| Reliability Engineer | Maintenance, Digital Twin, WO/PO, Operations, Procurement, Copilot (6) |
| Shift Supervisor | Operations, WO/PO, Maintenance, Procurement, Executive, Copilot (6) |
| Plant Manager | Executive, Operations, WO/PO, Maintenance, Procurement, Admin, Copilot (7) |
| Procurement Admin | Procurement, WO/PO, Maintenance, Operations, Copilot (5) |
| App Admin | All 9 pages |

---

## Post-Deployment Checklist

Run this after all 13 phases are complete:

```sql
USE DATABASE MFGPULSE_DB;

-- Final object counts
SELECT 'Schemas' AS OBJECT, COUNT(*) AS COUNT FROM INFORMATION_SCHEMA.SCHEMATA
    WHERE SCHEMA_NAME IN ('RAW_OT','RAW_IT','CURATED','ML_FEATURES','ML_MODELS','ANALYTICS','AGENT')
UNION ALL
SELECT 'Base Tables + DTs', COUNT(*) FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_TYPE = 'BASE TABLE' AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','PUBLIC')
UNION ALL
SELECT 'Views', COUNT(*) FROM INFORMATION_SCHEMA.TABLES
    WHERE TABLE_TYPE = 'VIEW' AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','PUBLIC')
UNION ALL
SELECT 'Sensor Readings', COUNT(*) FROM RAW_OT.SENSOR_READINGS
UNION ALL
SELECT 'Live Predictions', COUNT(*) FROM ML_MODELS.LIVE_PREDICTIONS
UNION ALL
SELECT 'Active Alerts', COUNT(*) FROM ANALYTICS.ACTIVE_ALERTS
UNION ALL
SELECT 'ML Models', COUNT(*) FROM ML_MODELS.MODEL_REGISTRY
UNION ALL
SELECT 'Active Users', COUNT(*) FROM RAW_IT.USERS WHERE ACTIVE = TRUE
UNION ALL
SELECT 'Notification Events', COUNT(*) FROM RAW_IT.NOTIFICATION_SETTINGS
ORDER BY OBJECT;
```

**Expected results:**

| Object | Expected Count |
|---|---|
| Schemas | 7 |
| Base Tables + DTs | 34 |
| Views | 21 |
| Sensor Readings | >= 172,000 |
| Live Predictions | 10 |
| Active Alerts | >= 6 |
| ML Models | 12 |
| Active Users | 9 |
| Notification Events | 9 |

---

## Quick-Reference: Script Execution Order

Copy and paste this block into a SQL worksheet to run all scripts in sequence. Replace `@path/` with the actual stage path or run each file individually.

```
sql/01_infrastructure.sql       ← Database, schemas, warehouse, resource monitor
sql/02_base_tables.sql          ← 19 base tables
sql/03_streams.sql              ← 3 CDC streams
sql/04_seed_data.sql            ← Reference data (assets, parts, users, WOs, logs)
sql/05_generate_sensor_data.sql ← 172K sensor readings (longest step)
sql/06_fatigue_scores.sql       ← Fatigue scores + anomaly scores
sql/07_curated_dynamic_tables.sql ← 3 curated DTs (wait for refresh)
sql/08_ml_feature_dynamic_tables.sql ← 7 feature DTs (wait for refresh)
sql/09_ml_feature_views.sql     ← 11 ML feature views
sql/10_udfs_live_predictions.sql ← 5 UDFs + 3 procedures + LIVE_PREDICTIONS DT
sql/11_native_ml_models.sql     ← Optional: native ML model training
sql/12_analytics_layer.sql      ← 2 DTs + 6 views + 6 procedures
sql/13_cortex_search.sql        ← MAINTENANCE_SEARCH Cortex Search service
sql/14_automation.sql           ← 3 scheduled tasks (suspended)
sql/15_procurement_tables.sql   ← Procurement table structures
sql/16_procurement_views.sql    ← ATP + procurement recommendation views
sql/17_procurement_procedures.sql ← PO lifecycle procedures
sql/ddl_objects.sql             ← UDFs, procedures, PLANNED_PURCHASE_ORDERS view, auto-convert task
sql/18_validation.sql           ← Full verification suite
sql/19_notifications.sql        ← Notification settings + email integration
sql/20_configurable_simulation.sql ← Configurable simulation procedure + config table
```

Then deploy Cortex Semantic View + Agent from `cortex_project/`, and launch Streamlit.

---

## Troubleshooting

| Issue | Cause | Fix |
|---|---|---|
| `LIVE_PREDICTIONS has 0 rows` | Dynamic Tables haven't completed initial refresh | Wait 2-3 minutes, then `ALTER DYNAMIC TABLE MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS REFRESH` |
| `ACTIVE_ALERTS is empty` | LIVE_PREDICTIONS not yet populated, or no assets meet alert thresholds | Run `SELECT COUNT(*) FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS` — if 0, wait for DT refresh |
| `Cortex Search not found` | Search service still initializing | Wait 1-2 minutes after creation, then `SHOW CORTEX SEARCH SERVICES IN SCHEMA MFGPULSE_DB.ML_MODELS` |
| `Agent returns error` | Semantic View not deployed, or Agent references wrong object names | Verify both objects exist: `SHOW SEMANTIC VIEWS IN SCHEMA MFGPULSE_DB.AGENT` and `SHOW CORTEX AGENTS IN SCHEMA MFGPULSE_DB.AGENT` |
| `Streamlit app won't start` | Compute pool not available or `snowflake.yml` misconfigured | Ensure `SYSTEM_COMPUTE_POOL_CPU` exists and is running: `SHOW COMPUTE POOLS` |
| `Notification email not sent` | `MFGPULSE_EMAIL` integration not enabled or email not toggled on in settings | Check: `SHOW NOTIFICATION INTEGRATIONS LIKE 'MFGPULSE%'` and verify `EMAIL_ENABLED=TRUE` in `NOTIFICATION_SETTINGS` |
| `OEE_METRICS empty` | PRODUCTION_OUTPUT table has no data | Verify: `SELECT COUNT(*) FROM MFGPULSE_DB.RAW_IT.PRODUCTION_OUTPUT` — should be >= 3,330 |
| `OEE Trend chart empty` | OEE_METRICS DT hasn't refreshed | OEE Trend uses the same OEE_METRICS view — wait for DT refresh or run `ALTER DYNAMIC TABLE MFGPULSE_DB.ANALYTICS.OEE_METRICS REFRESH` |
| `Supply Chain charts empty` | Procurement views have no at-risk items | If all assets are healthy, the risk distribution donut and lead time gap charts will not render — this is expected when PROCUREMENT_RECOMMENDATIONS shows only NO_RISK items |
| `Sensor feed shows no data` | No sensor readings in the last 24 hours | Run `SELECT COUNT(*) FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS WHERE TIMESTAMP >= DATEADD('hour', -24, CURRENT_TIMESTAMP())` — if 0, resume the SIMULATE_SENSOR_FEED task or run the simulation from Admin Panel |
| `Procurement views return empty` | Procurement tables/views created before seed data | Re-run `sql/16_procurement_views.sql` after confirming PARTS_INVENTORY and ASSET_MASTER are populated |
| `DT refresh stuck in SCHEDULING` | Warehouse suspended or credits exhausted | `ALTER WAREHOUSE COMPUTE_WH RESUME` and check resource monitor: `SHOW RESOURCE MONITORS` |
| `FinOps section shows "unavailable"` | Role lacks access to SNOWFLAKE.ACCOUNT_USAGE views | Grant access: `GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE <role>` or use ACCOUNTADMIN |
| `AUTO_CONVERT_PLANNED_POS fails with invalid identifier` | Procedure uses inline `FOR rec IN (SELECT...) DO` pattern | Snowflake SQL scripting requires explicit `DECLARE CURSOR` + `OPEN` + `FOR rec IN cursor DO` with `:=` assignments for cursor fields. Redeploy from `sql/ddl_objects.sql` which uses the correct pattern. |
| `WO part badge shows EXPEDITE on in_progress WO` | Reservation exists but badge reads from PROCUREMENT_RECOMMENDATIONS | Expected: badge shows "RESERVED" (green) when active reservation exists for the WO. If not, verify `PART_RESERVATIONS` table has active rows for the WO_ID. |

---

## Cross-Instance Deployment

To deploy MFGPulse AI on a **different Snowflake account** (fresh instance):

### Prerequisites (Target Instance)

| Requirement | Details |
|---|---|
| Snowflake account | Any edition (Standard, Enterprise, Business Critical) |
| Role | `ACCOUNTADMIN` |
| Cortex AI | Cortex Complete, Cortex Search, Cortex Agent, Semantic Views enabled |
| Compute pool | `SYSTEM_COMPUTE_POOL_CPU` must exist (for Streamlit) |

### Step-by-Step

**1. Copy the project files** to the target Snowflake workspace or local machine.

**2. Run infrastructure + base tables + seed data** (Phases 1-9 of `deploy_one_time_consolidated.sql`):
```sql
-- Run in a SQL worksheet on the TARGET instance with ACCOUNTADMIN:
-- Execute deploy_one_time_consolidated.sql from PHASE 1 through PHASE 9 (stop before Phase 10)
```

**3. Deploy UDFs, procedures, and key objects** using `sql/ddl_objects.sql`:
```sql
-- This file contains actual CREATE OR REPLACE statements (not GET_DDL references)
-- for all 5 UDFs, 8 key procedures, and deployment notes.
-- Execute the entire file on the target instance.
```

**4. Deploy Dynamic Tables and Views** — extract from the source instance:
```sql
-- On the SOURCE instance, run each GET_DDL command from deploy_one_time_consolidated.sql Phase 10
-- Copy the returned DDL and execute on the TARGET instance
-- Order: Curated DTs → ML_FEATURES DTs → ML_FEATURES Views → LIVE_PREDICTIONS DT
--        → Analytics DTs → Analytics Views

-- Alternatively, use docs/full_ddl_export.sql which contains all DDL (3800+ lines)
```

**5. Deploy Cortex Search, Agent, and Semantic View** (Phases 13-14 of `deploy_one_time_consolidated.sql`):
```sql
-- Cortex Search: use the CREATE CORTEX SEARCH SERVICE statement from deploy_one_time_consolidated.sql
-- Semantic View + Agent: deploy from cortex_project/ directory
```

**6. Deploy Streamlit app**:
- Copy `MFGPulse_AI_App/` to a Snowsight workspace on the target instance
- Update `snowflake.yml` if compute pool or warehouse names differ
- Click Run

**7. Run validation**:
```sql
-- Execute the validation section from deploy_one_time_consolidated.sql (Phase 12)
-- All STATUS columns should show PASS
```

### Key Files for Cross-Instance Deployment

| File | Purpose |
|---|---|
| `sql/deploy_one_time_consolidated.sql` | Master script — phases 1-9 are fully executable, phase 10 has GET_DDL references |
| `sql/ddl_objects.sql` | **NEW** — Actual CREATE statements for UDFs, procedures, PLANNED_PURCHASE_ORDERS view, auto-convert task. Uses explicit CURSOR declarations (not inline FOR loops) for Snowflake SQL scripting compatibility. |
| `docs/full_ddl_export.sql` | Complete DDL for all custom objects including Session-4 procurement engine (procedures, views, task) |
| `cortex_project/*.yaml` | Cortex Agent + Semantic View definitions |
| `MFGPulse_AI_App/` | Streamlit app (copy entire directory) |
| `test_cases/` | Validation scripts (run post-deployment) |

### What Needs Manual Adjustment on Target

| Item | What to Change |
|---|---|
| `COMPUTE_WH` | If using a different warehouse name for interactive queries, update `deploy_one_time_consolidated.sql` and `snowflake.yml` |
| `MFGPULSE_AUTOMATION_WH` | If using a different warehouse for background tasks/DTs, update `sql/14_automation.sql` and all DT DDL |
| `SYSTEM_COMPUTE_POOL_CPU` | If compute pool name differs, update `snowflake.yml` |
| `MFGPULSE_EMAIL` | Email notification integration — create on target if email delivery is needed |
| Cortex AI models | Ensure `llama3.1-70b` and `llama3.1-8b` are available in the target region |
| User accounts | Seed data creates 9 demo users — update email addresses for target instance |

---

## Teardown

To remove the entire deployment:

```sql
-- WARNING: This drops ALL data, models, and objects permanently
DROP DATABASE IF EXISTS MFGPULSE_DB CASCADE;
DROP WAREHOUSE IF EXISTS COMPUTE_WH;
DROP WAREHOUSE IF EXISTS MFGPULSE_AUTOMATION_WH;
DROP RESOURCE MONITOR IF EXISTS MFGPULSE_CREDIT_GUARD;
DROP RESOURCE MONITOR IF EXISTS MFGPULSE_AUTOMATION_GUARD;
DROP NOTIFICATION INTEGRATION IF EXISTS MFGPULSE_EMAIL;
```

---

## Cross-Account Replication

To replicate MFGPULSE_DB (including all data) to another Snowflake account in the same organization, use `sql/replicate_to_target.sql`.

### What replicates automatically
- 40 base tables (with all data)
- 33 views, 13 dynamic tables, all procedures/UDFs
- 10 tasks (arrive suspended), 3 streams

### What must be recreated on target
| Object | Why | How |
|---|---|---|
| Snowflake.ML.Classification models (2) | ML models don't replicate | Retrain via `sql/retrain_and_validate.sql` |
| Cortex Search Service (MAINTENANCE_SEARCH) | Cortex Search doesn't replicate | DDL in `sql/replicate_to_target.sql` Step 2e |
| Cortex Agent + Semantic View | Agents don't replicate | Redeploy from `cortex_project/` YAMLs |
| Warehouses (COMPUTE_WH, MFGPULSE_AUTOMATION_WH) | Account-level objects | DDL in `sql/replicate_to_target.sql` Step 2b |
| Resource monitors | Account-level objects | DDL in `sql/replicate_to_target.sql` Step 2c |

### Steps
1. **Source account**: Run Part 1 (enable replication, create replication group)
2. **Target account**: Run Part 2 (create secondary group, refresh, recreate non-replicable objects)
3. **Target account**: Run Part 3 (validation queries)
4. **(Optional)** Promote to standalone with `ALTER REPLICATION GROUP ... PRIMARY` if you want an independent writable copy
