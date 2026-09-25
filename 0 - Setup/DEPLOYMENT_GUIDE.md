# MFGPulse AI — One-Shot Deployment Guide

*Deploy the entire platform from zero to running in a single session.*

---

## Recommended: One-Time Deployment Script

For the fastest, most reliable deployment, use the consolidated script:

```
0 - Setup/scripts/deploy_one_time_consolidated.sql
```

This single, fully self-contained script creates everything from zero: 1 database, 7 schemas, 2 warehouses, 23+ tables, 13 dynamic tables, 30+ views, 5 UDFs, 21+ procedures, 10 DAG tasks, 1 Cortex Search service, and all seed data (~175K+ rows). It includes a `DEPLOYMENT_LOG` table that tracks each phase with start/end time, credits consumed, objects created, and pass/fail validation. Run top-to-bottom in Snowsight with ACCOUNTADMIN role.

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

All phases below are handled by `0 - Setup/scripts/deploy_one_time_consolidated.sql` except Phases 12-13 (Cortex Agent and Streamlit).

```
Phase 1: Infrastructure     (Checkpoint 1)       ~5 seconds
Phase 2: Base tables         (Checkpoint 2)       ~5 seconds
Phase 3: Seed data           (Checkpoints 3-4)    ~2 minutes
Phase 4: Dynamic tables      (Checkpoints 5-6)    ~3 minutes (DT initial refresh)
Phase 5: ML models           (Checkpoints 7-8)    ~1 minute
Phase 6: Analytics           (Checkpoint 9)       ~1 minute (DT initial refresh)
Phase 7: Cortex Search       (Checkpoint 10)      ~30 seconds
Phase 8: Automation          (Checkpoint 11)      ~5 seconds
Phase 9: Procurement         (Checkpoint 12)      ~30 seconds
Phase 10: Validation         (Checkpoint 13)      ~10 seconds
Phase 11: Notifications      (Checkpoint 14)      ~10 seconds
Phase 12: Cortex Agent       (Manual deploy)      ~2 minutes
Phase 13: Streamlit app      (Open in Snowsight)  ~1 minute
                                                  ──────────
                                        Total:    ~12 minutes
```

---

## Step-by-Step Phase Reference

> The phases below describe what each section of `deploy_one_time_consolidated.sql` creates. Run the consolidated script top-to-bottom — these are reference descriptions, not separate scripts to execute individually.

### Phase 1 — Infrastructure

Open a SQL worksheet in Snowsight. Set role to `ACCOUNTADMIN`.

The consolidated script creates:

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

Creates 19 base tables across RAW_OT and RAW_IT:
```sql
-- Creates 19 base tables across RAW_OT and RAW_IT
-- Tables: ASSET_MASTER, SENSOR_METADATA, SENSOR_READINGS, AMBIENT_CONDITIONS,
--         WORK_ORDERS, MAINTENANCE_LOGS, PARTS_INVENTORY, PRODUCTION_OUTPUT,
--         SHIFT_SCHEDULE, USERS, SUPPLIERS, PART_SUPPLIERS, PURCHASE_ORDERS,
--         PURCHASE_ORDER_LINES, PART_RESERVATIONS, MODEL_REGISTRY,
--         FATIGUE_SCORES, ANOMALY_SCORES
```

Creates 3 CDC streams:
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

Populates reference data:
```sql
-- Populates reference data:
--   10 assets, 23 sensors, 15 parts, 9 users (6 personas),
--   22 work orders, 78 maintenance logs, ~1710 shift records,
--   ~3330 production records, 5 suppliers, 16 part-supplier mappings,
--   10 model registry entries
```

Generates synthetic sensor data:
```sql
-- Generates 172K+ sensor readings (30-day history, 15-min intervals, 10 assets)
-- This is the largest data generation step — may take 1-2 minutes
```

**Note**: Fatigue scoring depends on UDFs and Dynamic Tables created in later phases — the consolidated script handles this ordering automatically.

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

Creates 3 curated dynamic tables:
```sql
-- Creates 3 curated DTs:
--   SENSOR_WITH_CONTEXT (172K rows) — OT sensors + IT metadata joined
--   ASSET_HEALTH_CURRENT (10 rows) — Latest reading per asset + 24h stats
--   FAILURE_HISTORY (12 rows) — Pre-failure sensor patterns
-- All with TARGET_LAG = '1 hour', WAREHOUSE = COMPUTE_WH
```

Creates 7 feature engineering dynamic tables:
```sql
-- Creates 7 feature engineering DTs:
--   LABELED_DATA, ROLLING_STATS, SENSOR_INTERACTIONS,
--   TEMPORAL_MEMORY, CROSS_DOMAIN, PHYSICS_COMPOSITE (INCREMENTAL),
--   FLEET_COMPARISON
-- Wait for initial refresh to complete (~2-3 minutes)
```

Creates 11 ML feature views:
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

Creates UDFs and prediction pipeline:
```sql
-- Creates 5 UDFs:
--   PREDICT_FAILURE_MODE (M1), PREDICT_RUL (M2),
--   PREDICT_DEGRADATION_STAGE (M3), COMPUTE_FATIGUE_SCORE (M4),
--   SIMULATE_FAILURE_TWIN (M6)
-- Creates 3 procedures:
--   ANALYZE_ROOT_CAUSE (M5), PRESCRIBE_MAINTENANCE (M7), PREDICT_ALL
-- Creates LIVE_PREDICTIONS dynamic table (calls M1-M3 UDFs on refresh)
```

Trains 4 Snowflake-native ML models (optional but recommended):
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

Creates the analytics dynamic tables and views:
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

Creates the Cortex Search service:
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

Creates the 10-task DAG (all SUSPENDED by default):
```sql
-- Creates 3 scheduled tasks (all SUSPENDED by default):
--   SIMULATE_SENSOR_FEED (every 720 min) — generates new sensor readings
--   SIMULATE_PRODUCTION (every 720 min) — generates production records
--   AUTO_PROCUREMENT_REVIEW (every 720 min) — auto-generates POs
-- Resume tasks only when you want continuous data simulation
```

> **Note**: The automation runs as a 10-task DAG. Resume children first (bottom-up), then root:
> ```sql
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_SNAPSHOT_KPIS RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_CONVERT_PPOS RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_GENERATE_POS RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_GENERATE_WOS RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_CHECK_DRIFT RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_ARCHIVE_ALERTS RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_REFRESH_DTS RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_REFRESH_FATIGUE RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.DAG_CHECK_FRESHNESS RESUME;
> ALTER TASK MFGPULSE_DB.ANALYTICS.MFGPULSE_AUTOMATION_DAG RESUME;
> ```
> This starts the full 10-task chain: sensor data → freshness check ∥ fatigue → DT refresh → alert archive ∥ drift check ∥ WO gen → PO gen → PPO conversion → KPI snapshot (every 12h).

---

### Phase 9 — Procurement System

Creates procurement-specific table structures:
```sql
-- Creates procurement-specific table structures (if not already created in 02)
```

Creates ATP and procurement views:
```sql
-- Creates: PARTS_AVAILABLE_TO_PROMISE, PROCUREMENT_RECOMMENDATIONS views
```

Creates PO lifecycle procedures:
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

The consolidated script runs a full verification suite:
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

Creates the notification infrastructure:
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
   - 7 tools: maintenance_analytics, maintenance_history, diagnose_asset, deep_analysis, simulate_scenario, generate_work_order, generate_purchase_order

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

## Quick-Reference: Deployment Script

Run the consolidated deployment script in a SQL worksheet:

```
0 - Setup/scripts/deploy_one_time_consolidated.sql  ← All DDL + seed data (14 checkpoints)
```

Then deploy Cortex Semantic View + Agent from `cortex_project/`, and launch Streamlit from `MFGPulse_AI_App/`.

Additional operational scripts in `0 - Setup/scripts/`:

```
Share_DB.sql                       ← Cross-account share & replication setup
Copy Share & Git.sql               ← Copy shared DB into local writable MFGPULSE_DB
Truncate and Sync Share.sql        ← Reload local tables from shared database
emergency_stop_all_credits.sql     ← Emergency suspension of all resources
```

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
| `Procurement views return empty` | Procurement tables/views created before seed data | Re-run the procurement views section of the consolidated script after confirming PARTS_INVENTORY and ASSET_MASTER are populated |
| `DT refresh stuck in SCHEDULING` | Warehouse suspended or credits exhausted | `ALTER WAREHOUSE COMPUTE_WH RESUME` and check resource monitor: `SHOW RESOURCE MONITORS` |
| `FinOps section shows "unavailable"` | Role lacks access to SNOWFLAKE.ACCOUNT_USAGE views | Grant access: `GRANT IMPORTED PRIVILEGES ON DATABASE SNOWFLAKE TO ROLE <role>` or use ACCOUNTADMIN |
| `AUTO_CONVERT_PLANNED_POS fails with invalid identifier` | Procedure uses inline `FOR rec IN (SELECT...) DO` pattern | Snowflake SQL scripting requires explicit `DECLARE CURSOR` + `OPEN` + `FOR rec IN cursor DO` with `:=` assignments for cursor fields. Redeploy from the relevant section in `deploy_one_time_consolidated.sql`. |
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

**2. Run the consolidated deployment script** on the target instance:
```sql
-- Run in a SQL worksheet on the TARGET instance with ACCOUNTADMIN:
-- Execute 0 - Setup/scripts/deploy_one_time_consolidated.sql top-to-bottom
-- This creates all infrastructure, tables, DTs, views, procedures, UDFs, seed data, and tasks
```

**3. Deploy Cortex AI components**:
- Deploy Semantic View and Agent from `cortex_project/` directory

**4. Deploy Streamlit app**:
- Copy `MFGPulse_AI_App/` to a Snowsight workspace on the target instance
- Update `snowflake.yml` if compute pool or warehouse names differ
- Click Run

**5. Run validation**:
```sql
-- Execute the validation section from deploy_one_time_consolidated.sql (Phase 12)
-- All STATUS columns should show PASS
```

### Key Files for Cross-Instance Deployment

| File | Purpose |
|---|---|
| `0 - Setup/scripts/deploy_one_time_consolidated.sql` | Master deployment script — all DDL + seed data with 14 checkpoints |
| `cortex_project/*.yaml` | Cortex Agent + Semantic View definitions |
| `MFGPulse_AI_App/` | Streamlit app (copy entire directory) |
| `test_cases/` | Validation scripts (run post-deployment) |

### What Needs Manual Adjustment on Target

| Item | What to Change |
|---|---|
| `COMPUTE_WH` | If using a different warehouse name for interactive queries, update `deploy_one_time_consolidated.sql` and `snowflake.yml` |
| `MFGPULSE_AUTOMATION_WH` | If using a different warehouse for background tasks/DTs, update `deploy_one_time_consolidated.sql` (search for MFGPULSE_AUTOMATION_WH) |
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

To replicate MFGPULSE_DB (including all data) to another Snowflake account in the same organization, use the `Share_DB.sql` script in `0 - Setup/scripts/`.

### What replicates automatically
- 40 base tables (with all data)
- 33 views, 13 dynamic tables, all procedures/UDFs
- 10 tasks (arrive suspended), 3 streams

### What must be recreated on target
| Object | Why | How |
|---|---|---|
| Snowflake.ML.Classification models (2) | ML models don't replicate | Retrain using the ML model training section of the consolidated script |
| Cortex Search Service (MAINTENANCE_SEARCH) | Cortex Search doesn't replicate | Use the Cortex Search CREATE statement from the consolidated script |
| Cortex Agent + Semantic View | Agents don't replicate | Redeploy from `cortex_project/` YAMLs |
| Warehouses (COMPUTE_WH, MFGPULSE_AUTOMATION_WH) | Account-level objects | Create manually on target |
| Resource monitors | Account-level objects | Create manually on target |

### Steps
1. **Source account**: Run Part 1 (enable replication, create replication group)
2. **Target account**: Run Part 2 (create secondary group, refresh, recreate non-replicable objects)
3. **Target account**: Run Part 3 (validation queries)
4. **(Optional)** Promote to standalone with `ALTER REPLICATION GROUP ... PRIMARY` if you want an independent writable copy
