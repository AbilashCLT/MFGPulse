-- ============================================================================
-- MFGPulse AI: Credit Consumption Report
-- Generated: 2026-09-13 (updated with live account data)
-- Account: bb99219 | Role: ACCOUNTADMIN | Warehouse: COMPUTE_WH (XSMALL)
-- ============================================================================


-- ============================================================================
-- SECTION 1: ACTUAL ACCOUNT USAGE (Last 30 Days — as of 2026-09-13)
-- ============================================================================
--
-- Service Type              | Credits  | Period
-- ========================= | ======== | =================
-- SNOWFLAKE_COCO_SNOWSIGHT  | 137.9039 | 2026-08-30 → 09-11
-- WAREHOUSE_METERING        |  15.2023 | 2026-08-30 → 09-13
-- SNOWPARK_CONTAINER_SVCS   |   6.6814 | 2026-09-10 → 09-13
-- AI_FUNCTIONS               |   0.0105 | 2026-09-10
-- TELEMETRY_DATA_INGEST     |   0.0096 | 2026-09-10 → 09-13
-- CORTEX_SEARCH              |   0.0000 | 2026-09-10 → 09-13
-- ========================= | ======== |
-- TOTAL (all services)      | ~159.81  |
--
-- Note: CoCo (Cortex Code) is by far the largest cost — this is development
-- session usage, not MFGPulse operational cost.

-- 1a. Total credits by service type
SELECT
    SERVICE_TYPE,
    ROUND(SUM(CREDITS_USED), 4) AS TOTAL_CREDITS,
    MIN(USAGE_DATE) AS FIRST_USAGE,
    MAX(USAGE_DATE) AS LAST_USAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
--WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_DATE())
GROUP BY SERVICE_TYPE
ORDER BY TOTAL_CREDITS DESC;

-- 1b. Daily warehouse credit trend
SELECT
    DATE_TRUNC('day', START_TIME)::DATE AS USAGE_DATE,
    WAREHOUSE_NAME,
    ROUND(SUM(CREDITS_USED), 6) AS CREDITS_USED,
    COUNT(*) AS ACTIVE_SESSIONS
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY 1, 2
ORDER BY 1 DESC;


-- ============================================================================
-- SECTION 2: ACTUAL WAREHOUSE USAGE (MFGPulse-specific)
-- ============================================================================
--
-- Warehouse                | Credits | Period             | Notes
-- ======================== | ======= | ================== | =====
-- COMPUTE_WH               | 14.0397 | 08-30 → 09-12     | Deployment + interactive
-- MFGPULSE_AUTOMATION_WH   |  1.2946 | 09-10 → 09-12     | DAG automation runs
-- ======================== | ======= |                    |
-- TOTAL MFGPulse warehouses| 15.3343 |                    |
--
-- Deployment day (09-10) was the largest: 9.5 credits on COMPUTE_WH
-- (initial DT refresh, sensor data generation, ML model training).
-- Steady-state is ~2 credits/day (COMPUTE_WH) + ~0.2 credits/day (AUTOMATION_WH).

SELECT
    WAREHOUSE_NAME,
    ROUND(SUM(CREDITS_USED), 4) AS TOTAL_CREDITS,
    MIN(START_TIME)::DATE AS FIRST_USAGE,
    MAX(START_TIME)::DATE AS LAST_USAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE WAREHOUSE_NAME IN ('COMPUTE_WH', 'MFGPULSE_AUTOMATION_WH')
  AND START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY WAREHOUSE_NAME;


-- ============================================================================
-- SECTION 3: DAG TASK EXECUTION (Last 7 Days)
-- ============================================================================
--
-- Task                       | Runs (OK) | Runs (Fail) | Avg Duration
-- ========================== | ========= | =========== | ============
-- MFGPULSE_AUTOMATION_DAG    | 8         | 1           | 73s
-- DAG_REFRESH_DTS             | 6         | 0           | 35s
-- DAG_CHECK_DRIFT             | 4         | 1           | 44s
-- DAG_REFRESH_FATIGUE         | 6         | 1           | 3s
-- DAG_GENERATE_WOS            | 6         | 0           | 4s
-- DAG_GENERATE_POS            | 6         | 0           | 5s
-- DAG_CONVERT_PPOS            | 6         | 0           | 5s
-- DAG_CHECK_FRESHNESS         | 5         | 0           | 2s
-- DAG_SNAPSHOT_KPIS           | 5         | 0           | 4s
-- DAG_ARCHIVE_ALERTS          | 4         | 1           | 3s
--
-- DAG_CHECK_DRIFT failure: expected — COMPUTE_NATIVE_PREDICTIONS was a stub.
-- Now fixed with full procedure body.

SELECT
    NAME AS TASK_NAME,
    STATE,
    COUNT(*) AS RUNS,
    AVG(DATEDIFF('second', SCHEDULED_TIME, COMPLETED_TIME)) AS AVG_DURATION_SEC
FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
WHERE DATABASE_NAME = 'MFGPULSE_DB'
  AND SCHEDULED_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY NAME, STATE
ORDER BY NAME;


-- ============================================================================
-- SECTION 4: ESTIMATED DEPLOYMENT COST (One-Time)
-- ============================================================================
-- Based on COMPUTE_WH (XSMALL = 1 credit/hour) and MFGPULSE_AUTOMATION_WH (XSMALL)
--
-- Phase                              | Warehouse      | Est. Duration | Est. Credits
-- -----------------------------------|----------------|---------------|-------------
-- 01: Infrastructure (DB, schemas)   | COMPUTE_WH     | ~10 sec       | 0.003
-- 02: Base tables (22 CREATE TABLE)  | COMPUTE_WH     | ~10 sec       | 0.003
-- 03: Streams (3 streams)            | COMPUTE_WH     | ~5 sec        | 0.002
-- 04: Seed data (all INSERTs)        | COMPUTE_WH     | ~30 sec       | 0.008
-- 05: Sensor data generation         | COMPUTE_WH     | ~90 sec       | 0.025
-- DDL: UDFs, procedures, views       | COMPUTE_WH     | ~30 sec       | 0.008
-- DDL: Dynamic tables (13 DTs)       | COMPUTE_WH     | ~15 sec       | 0.004
-- DT: Initial refresh (4 layers)    | COMPUTE_WH     | ~3-5 min      | 0.080
-- 13: Cortex Search creation         | COMPUTE_WH     | ~30 sec       | 0.008
-- 14: Automation DAG (10 tasks)      | AUTOMATION_WH  | ~10 sec       | 0.003
-- 19: Notifications (tables + proc)  | COMPUTE_WH     | ~10 sec       | 0.003
-- 20: Simulation config              | COMPUTE_WH     | ~5 sec        | 0.002
-- 18: Validation suite               | COMPUTE_WH     | ~15 sec       | 0.004
-- Native ML training (N1-N4)         | COMPUTE_WH     | ~10-20 min    | 0.500
-- -----------------------------------|----------------|---------------|-------------
-- TOTAL ONE-TIME DEPLOYMENT          |                | ~20-30 min    | ~0.65 credits
--
-- Actual deployment day (2026-09-10): 9.5 credits on COMPUTE_WH + 0.9 on AUTOMATION_WH
-- = 10.4 credits total (includes interactive queries during development).


-- ============================================================================
-- SECTION 5: ESTIMATED ONGOING MONTHLY COST
-- ============================================================================
--
-- A. DAG Automation (12-hour cycle, 10 tasks)
-- -------------------------------------------------
-- Task                          | WH             | Credits/Run | Runs/Mo | Monthly
-- SIMULATE_ALL_FEEDS_RANDOM     | AUTOMATION_WH  | 0.020       | 60      | 1.20
-- REFRESH_FATIGUE_SCORES        | AUTOMATION_WH  | 0.001       | 60      | 0.06
-- REFRESH_ALL_DTS               | AUTOMATION_WH  | 0.010       | 60      | 0.60
-- COMPUTE_NATIVE_PREDICTIONS    | AUTOMATION_WH  | 0.012       | 60      | 0.72
-- AUTO_GENERATE_WORK_ORDERS     | AUTOMATION_WH  | 0.001       | 60      | 0.06
-- AUTO_GENERATE_PURCHASE_ORDERS | AUTOMATION_WH  | 0.001       | 60      | 0.06
-- AUTO_CONVERT_PLANNED_POS      | AUTOMATION_WH  | 0.001       | 60      | 0.06
-- CHECK_DATA_FRESHNESS          | AUTOMATION_WH  | 0.001       | 60      | 0.06
-- SNAPSHOT_KPIS                 | AUTOMATION_WH  | 0.001       | 60      | 0.06
-- ARCHIVE_ALERTS                | AUTOMATION_WH  | 0.001       | 60      | 0.06
-- Subtotal DAG                  |                |             |         | ~2.94
--
-- B. Dynamic Table Auto-Refresh (TARGET_LAG = 1 hour for LIVE_PREDICTIONS)
-- ---------------------------------------------------
-- 13 DTs refreshing per their target lag
-- Estimated: ~0.01 credits per refresh × ~400 refreshes/month
-- Subtotal DT Refresh: ~4.00 credits/month
--
-- C. Cortex Search Service (TARGET_LAG = 1 day)
-- ----------------------------------------------
-- Daily re-index of maintenance docs: ~0.005 credits/day
-- Subtotal Cortex Search: ~0.15 credits/month
--
-- D. Snowpark Container Services (Streamlit app runtime)
-- -------------------------------------------------
-- Active when Streamlit app is running in Snowsight
-- Actual: 6.68 credits over 3 days = ~2.2 credits/day when active
-- Subtotal SPCS: ~10-30 credits/month (depends on usage hours)
--
-- E. Interactive Usage (ad-hoc queries)
-- -------------------------------------------------
-- Estimated 50-100 queries/day × COMPUTE_WH (XS)
-- ~0.1-0.3 credits/day average
-- Subtotal Interactive: ~3-9 credits/month
--
-- F. Cortex AI Functions (LLM calls via agent/procedures)
-- -------------------------------------------------------
-- ANALYZE_ROOT_CAUSE (Cortex Search + Complete): ~0.01/call
-- PRESCRIBE_MAINTENANCE (Complete): ~0.01/call
-- Cortex Agent (Copilot): ~0.02/call
-- Executive Summaries (llama3.1-8b): ~0.005/call
-- Estimated 20-50 AI calls/day
-- Subtotal AI: ~0.5-1.5 credits/month (token-based)
--
-- G. ML Retraining (triggered by drift, estimated monthly)
-- -------------------------------------------------------
-- RETRAIN_IF_NEEDED: ~0.5-2 credits per retrain cycle
-- Estimated 0-1 retrains/month
-- Subtotal Retraining: ~0-2 credits/month
--
-- ============================================================================
-- MONTHLY COST SUMMARY
-- ============================================================================
--
-- Component                  | Low Estimate | High Estimate
-- DAG Automation             | 2.94         | 2.94
-- DT Auto-Refresh            | 4.00         | 4.00
-- Cortex Search Refresh      | 0.15         | 0.15
-- SPCS (Streamlit runtime)   | 10.00        | 30.00
-- Interactive Queries        | 3.00         | 9.00
-- Cortex AI (LLM tokens)    | 0.50         | 1.50
-- ML Retraining (if needed)  | 0.00         | 2.00
-- --------------------------------------------------------
-- TOTAL MONTHLY              | ~21 credits  | ~50 credits
--
-- With DAG suspended (demo):  ~14-40 credits/month
-- With DAG active (production): ~21-50 credits/month
--
-- ============================================================================
-- RESOURCE MONITOR HEADROOM
-- ============================================================================
--
-- Monitor                     | Quota  | Est. Usage | Headroom
-- MFGPULSE_CREDIT_GUARD       | 250/mo | 15-35      | 86-94% spare
-- MFGPULSE_AUTOMATION_GUARD   | 50/mo  | 3-5        | 90-94% spare
--
-- The resource monitors are generously sized for a demo/hackathon project.
-- For cost optimization in production, consider:
--   - Reducing MFGPULSE_CREDIT_GUARD to 75 credits/month
--   - Reducing MFGPULSE_AUTOMATION_GUARD to 15 credits/month
--   - Increasing DAG interval from 12h to 24h (halves automation cost)
--   - Suspending Streamlit SPCS when not in use


-- ============================================================================
-- SECTION 6: LIVE CREDIT QUERIES (run anytime)
-- ============================================================================

-- 6a. Total credits consumed by MFGPulse warehouses
SELECT
    WAREHOUSE_NAME,
    ROUND(SUM(CREDITS_USED), 4) AS TOTAL_CREDITS,
    MIN(START_TIME)::DATE AS FIRST_USAGE,
    MAX(START_TIME)::DATE AS LAST_USAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
WHERE WAREHOUSE_NAME IN ('COMPUTE_WH', 'MFGPULSE_AUTOMATION_WH')
  AND START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
GROUP BY WAREHOUSE_NAME;

-- 6b. Cortex AI token usage
SELECT
    SERVICE_TYPE,
    ROUND(SUM(CREDITS_USED), 4) AS CREDITS
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_DATE())
  AND SERVICE_TYPE ILIKE '%CORTEX%'
GROUP BY SERVICE_TYPE;

-- 6c. DAG task execution history
SELECT
    NAME AS TASK_NAME,
    STATE,
    COUNT(*) AS RUNS,
    AVG(DATEDIFF('second', SCHEDULED_TIME, COMPLETED_TIME)) AS AVG_DURATION_SEC
FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
WHERE DATABASE_NAME = 'MFGPULSE_DB'
  AND SCHEDULED_TIME >= DATEADD('day', -7, CURRENT_TIMESTAMP())
GROUP BY NAME, STATE
ORDER BY NAME;

-- 6d. SPCS (Streamlit) usage
SELECT
    SERVICE_TYPE,
    ROUND(SUM(CREDITS_USED), 4) AS TOTAL_CREDITS,
    MIN(USAGE_DATE) AS FIRST_USAGE,
    MAX(USAGE_DATE) AS LAST_USAGE
FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_DAILY_HISTORY
WHERE USAGE_DATE >= DATEADD('day', -30, CURRENT_DATE())
  AND SERVICE_TYPE = 'SNOWPARK_CONTAINER_SERVICES'
GROUP BY SERVICE_TYPE;
