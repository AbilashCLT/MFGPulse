-- ============================================================================
-- MFGPulse AI: Share Consistency Validation
-- Run on TARGET account (QEIPXIJ.NB44213) after consuming the share.
--
-- Validates that all shared objects are accessible and data matches source.
-- Source baseline captured: 2026-09-13 from DGTEFBJ.JB14149 (BB99219)
--
-- IMPORTANT: Since Option B is a zero-copy share, the target reads the SAME
-- data as the source. Row counts and hashes should match EXACTLY because
-- there is no data copy — it's a live reference. Any mismatch indicates
-- a grant issue (object not shared) rather than data corruption.
-- ============================================================================

-- Adjust this to match the database name you created from the share:
-- CREATE DATABASE MFGPULSE_DB_SHARED FROM SHARE DGTEFBJ.JB14149.MFGPULSE_SHARE;
SET SHARED_DB = 'MFGPULSE_DB_SHARED';


-- ============================================================================
-- CHECK 1: Schema accessibility (expect 6 schemas)
-- ============================================================================
SELECT 'SCHEMA_CHECK' AS CHECK_NAME,
    COUNT(*) AS accessible_schemas,
    CASE WHEN COUNT(*) = 6 THEN 'PASS' ELSE 'FAIL — expected 6' END AS status
FROM IDENTIFIER($SHARED_DB || '.INFORMATION_SCHEMA.SCHEMATA')
WHERE "SCHEMA_NAME" IN ('RAW_OT', 'RAW_IT', 'CURATED', 'ML_FEATURES', 'ML_MODELS', 'ANALYTICS');


-- ============================================================================
-- CHECK 2: Row count validation against source baseline
-- Expected counts from source as of 2026-09-13
-- ============================================================================

-- RAW_OT tables
SELECT 'RAW_OT.ASSET_MASTER' AS tbl, COUNT(*) AS target_rows, 10 AS source_rows,
    CASE WHEN COUNT(*) = 10 THEN 'PASS' ELSE 'FAIL' END AS status
FROM IDENTIFIER($SHARED_DB || '.RAW_OT.ASSET_MASTER')
UNION ALL
SELECT 'RAW_OT.SENSOR_METADATA', COUNT(*), 23,
    CASE WHEN COUNT(*) = 23 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_OT.SENSOR_METADATA')
UNION ALL
SELECT 'RAW_OT.SENSOR_READINGS', COUNT(*), 559203,
    CASE WHEN COUNT(*) >= 559203 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_OT.SENSOR_READINGS')
UNION ALL
SELECT 'RAW_OT.AMBIENT_CONDITIONS', COUNT(*), 190,
    CASE WHEN COUNT(*) >= 190 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_OT.AMBIENT_CONDITIONS')

-- RAW_IT tables
UNION ALL
SELECT 'RAW_IT.WORK_ORDERS', COUNT(*), 32,
    CASE WHEN COUNT(*) >= 32 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.WORK_ORDERS')
UNION ALL
SELECT 'RAW_IT.MAINTENANCE_LOGS', COUNT(*), 26,
    CASE WHEN COUNT(*) >= 26 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.MAINTENANCE_LOGS')
UNION ALL
SELECT 'RAW_IT.PARTS_INVENTORY', COUNT(*), 15,
    CASE WHEN COUNT(*) = 15 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.PARTS_INVENTORY')
UNION ALL
SELECT 'RAW_IT.PRODUCTION_OUTPUT', COUNT(*), 4203,
    CASE WHEN COUNT(*) >= 4203 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.PRODUCTION_OUTPUT')
UNION ALL
SELECT 'RAW_IT.SUPPLIERS', COUNT(*), 5,
    CASE WHEN COUNT(*) = 5 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.SUPPLIERS')
UNION ALL
SELECT 'RAW_IT.USERS', COUNT(*), 9,
    CASE WHEN COUNT(*) >= 9 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.USERS')
UNION ALL
SELECT 'RAW_IT.PURCHASE_ORDERS', COUNT(*), 8,
    CASE WHEN COUNT(*) >= 8 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.PURCHASE_ORDERS')
UNION ALL
SELECT 'RAW_IT.PURCHASE_ORDER_LINES', COUNT(*), 10,
    CASE WHEN COUNT(*) >= 10 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.PURCHASE_ORDER_LINES')
UNION ALL
SELECT 'RAW_IT.SHIFT_SCHEDULE', COUNT(*), 1710,
    CASE WHEN COUNT(*) = 1710 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.SHIFT_SCHEDULE')
UNION ALL
SELECT 'RAW_IT.APP_NOTIFICATIONS', COUNT(*), 108,
    CASE WHEN COUNT(*) >= 108 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.APP_NOTIFICATIONS')
UNION ALL
SELECT 'RAW_IT.NOTIFICATION_SETTINGS', COUNT(*), 16,
    CASE WHEN COUNT(*) >= 16 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.NOTIFICATION_SETTINGS')
UNION ALL
SELECT 'RAW_IT.PART_RESERVATIONS', COUNT(*), 10,
    CASE WHEN COUNT(*) >= 10 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.PART_RESERVATIONS')
UNION ALL
SELECT 'RAW_IT.SIMULATION_CONFIG', COUNT(*), 8,
    CASE WHEN COUNT(*) >= 8 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.SIMULATION_CONFIG')
UNION ALL
SELECT 'RAW_IT.PART_SUPPLIERS', COUNT(*), 16,
    CASE WHEN COUNT(*) >= 16 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.PART_SUPPLIERS')

-- ML_MODELS tables
UNION ALL
SELECT 'ML_MODELS.LIVE_PREDICTIONS', COUNT(*), 10,
    CASE WHEN COUNT(*) = 10 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ML_MODELS.LIVE_PREDICTIONS')
UNION ALL
SELECT 'ML_MODELS.FATIGUE_SCORES', COUNT(*), 8808,
    CASE WHEN COUNT(*) >= 8808 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ML_MODELS.FATIGUE_SCORES')
UNION ALL
SELECT 'ML_MODELS.MODEL_REGISTRY', COUNT(*), 12,
    CASE WHEN COUNT(*) = 12 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ML_MODELS.MODEL_REGISTRY')
UNION ALL
SELECT 'ML_MODELS.DRIFT_COMPARISON', COUNT(*), 30,
    CASE WHEN COUNT(*) >= 30 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ML_MODELS.DRIFT_COMPARISON')
UNION ALL
SELECT 'ML_MODELS.FEEDBACK_LOG', COUNT(*), 2,
    CASE WHEN COUNT(*) >= 2 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ML_MODELS.FEEDBACK_LOG')
UNION ALL
SELECT 'ML_MODELS.ANOMALY_SCORES', COUNT(*), 2520,
    CASE WHEN COUNT(*) >= 2520 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ML_MODELS.ANOMALY_SCORES')

-- CURATED dynamic tables
UNION ALL
SELECT 'CURATED.SENSOR_WITH_CONTEXT', COUNT(*), 559203,
    CASE WHEN COUNT(*) >= 559203 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.CURATED.SENSOR_WITH_CONTEXT')
UNION ALL
SELECT 'CURATED.ASSET_HEALTH_CURRENT', COUNT(*), 10,
    CASE WHEN COUNT(*) = 10 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.CURATED.ASSET_HEALTH_CURRENT')
UNION ALL
SELECT 'CURATED.FAILURE_HISTORY', COUNT(*), 19,
    CASE WHEN COUNT(*) >= 19 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.CURATED.FAILURE_HISTORY')

-- ML_FEATURES dynamic tables
UNION ALL
SELECT 'ML_FEATURES.ROLLING_STATS', COUNT(*), 559203,
    CASE WHEN COUNT(*) >= 559203 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ML_FEATURES.ROLLING_STATS')
UNION ALL
SELECT 'ML_FEATURES.PHYSICS_COMPOSITE', COUNT(*), 559203,
    CASE WHEN COUNT(*) >= 559203 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ML_FEATURES.PHYSICS_COMPOSITE')
UNION ALL
SELECT 'ML_FEATURES.LABELED_DATA', COUNT(*), 559203,
    CASE WHEN COUNT(*) >= 559203 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ML_FEATURES.LABELED_DATA')
UNION ALL
SELECT 'ML_FEATURES.FLEET_COMPARISON', COUNT(*), 1840,
    CASE WHEN COUNT(*) >= 1840 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ML_FEATURES.FLEET_COMPARISON')

-- ANALYTICS tables/DTs
UNION ALL
SELECT 'ANALYTICS.ACTIVE_ALERTS', COUNT(*), 8,
    CASE WHEN COUNT(*) >= 8 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ANALYTICS.ACTIVE_ALERTS')
UNION ALL
SELECT 'ANALYTICS.OEE_METRICS', COUNT(*), 4203,
    CASE WHEN COUNT(*) >= 4203 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ANALYTICS.OEE_METRICS')
UNION ALL
SELECT 'ANALYTICS.KPI_SNAPSHOTS', COUNT(*), 3,
    CASE WHEN COUNT(*) >= 3 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ANALYTICS.KPI_SNAPSHOTS')
UNION ALL
SELECT 'ANALYTICS.ALERT_HISTORY', COUNT(*), 43,
    CASE WHEN COUNT(*) >= 43 THEN 'PASS' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ANALYTICS.ALERT_HISTORY')

ORDER BY tbl;


-- ============================================================================
-- CHECK 3: Hash-based integrity on critical tables
-- These HASH_AGG values were captured from source on 2026-09-13.
-- For a zero-copy share, they should match exactly (same underlying data).
-- If source data changes (DAG runs, new sensor data), hashes will differ
-- — that's expected. Only a FAIL with matching row counts is suspicious.
-- ============================================================================

SELECT 'HASH: RAW_OT.ASSET_MASTER' AS check_name,
    HASH_AGG(*)::VARCHAR AS target_hash,
    '1043935236638146883' AS source_hash,
    CASE WHEN HASH_AGG(*)::VARCHAR = '1043935236638146883' THEN 'MATCH' ELSE 'DIFFERS (source may have changed)' END AS status
FROM IDENTIFIER($SHARED_DB || '.RAW_OT.ASSET_MASTER')
UNION ALL
SELECT 'HASH: RAW_OT.SENSOR_METADATA',
    HASH_AGG(*)::VARCHAR, '-9192553632651287819',
    CASE WHEN HASH_AGG(*)::VARCHAR = '-9192553632651287819' THEN 'MATCH' ELSE 'DIFFERS' END
FROM IDENTIFIER($SHARED_DB || '.RAW_OT.SENSOR_METADATA')
UNION ALL
SELECT 'HASH: RAW_IT.PARTS_INVENTORY',
    HASH_AGG(*)::VARCHAR, '5372991681202115931',
    CASE WHEN HASH_AGG(*)::VARCHAR = '5372991681202115931' THEN 'MATCH' ELSE 'DIFFERS' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.PARTS_INVENTORY')
UNION ALL
SELECT 'HASH: RAW_IT.SUPPLIERS',
    HASH_AGG(*)::VARCHAR, '2082416752866879225',
    CASE WHEN HASH_AGG(*)::VARCHAR = '2082416752866879225' THEN 'MATCH' ELSE 'DIFFERS' END
FROM IDENTIFIER($SHARED_DB || '.RAW_IT.SUPPLIERS')
UNION ALL
SELECT 'HASH: ML_MODELS.MODEL_REGISTRY',
    HASH_AGG(*)::VARCHAR, '-5155679205880974515',
    CASE WHEN HASH_AGG(*)::VARCHAR = '-5155679205880974515' THEN 'MATCH' ELSE 'DIFFERS' END
FROM IDENTIFIER($SHARED_DB || '.ML_MODELS.MODEL_REGISTRY')
UNION ALL
SELECT 'HASH: ML_MODELS.LIVE_PREDICTIONS',
    HASH_AGG(*)::VARCHAR, '-5391707499749081197',
    CASE WHEN HASH_AGG(*)::VARCHAR = '-5391707499749081197' THEN 'MATCH' ELSE 'DIFFERS' END
FROM IDENTIFIER($SHARED_DB || '.ML_MODELS.LIVE_PREDICTIONS')
ORDER BY 1;


-- ============================================================================
-- CHECK 4: Shared views accessibility
-- ============================================================================
SELECT 'VIEW: ML_MODELS.DRIFT_METRICS' AS check_name,
    COUNT(*) AS rows,
    CASE WHEN COUNT(*) >= 0 THEN 'ACCESSIBLE' ELSE 'FAIL' END AS status
FROM IDENTIFIER($SHARED_DB || '.ML_MODELS.DRIFT_METRICS')
UNION ALL
SELECT 'VIEW: ML_MODELS.MODEL_ACCURACY_LIVE',
    COUNT(*),
    CASE WHEN COUNT(*) >= 0 THEN 'ACCESSIBLE' ELSE 'FAIL' END
FROM IDENTIFIER($SHARED_DB || '.ML_MODELS.MODEL_ACCURACY_LIVE');


-- ============================================================================
-- CHECK 5: Data spot-checks (verify actual values, not just counts)
-- ============================================================================

-- 5a: All 10 assets present with correct names
SELECT asset_id, asset_name, asset_type, line_id
FROM IDENTIFIER($SHARED_DB || '.RAW_OT.ASSET_MASTER')
ORDER BY asset_id;

-- 5b: Predictions for all 10 assets
SELECT asset_id, asset_name, failure_mode_pred, rul_hours, stage_pred, degradation_score
FROM IDENTIFIER($SHARED_DB || '.ML_MODELS.LIVE_PREDICTIONS')
ORDER BY rul_hours ASC;

-- 5c: Sensor readings date range (should span months of data)
SELECT MIN(timestamp) AS earliest, MAX(timestamp) AS latest,
    DATEDIFF('day', MIN(timestamp), MAX(timestamp)) AS days_span,
    COUNT(DISTINCT asset_id) AS assets_with_data
FROM IDENTIFIER($SHARED_DB || '.RAW_OT.SENSOR_READINGS');


-- ============================================================================
-- CHECK 6: Summary scorecard
-- ============================================================================
-- Run Checks 1-4 above. Expected results:
--
-- | Check                    | Expected                          |
-- |--------------------------|-----------------------------------|
-- | Schemas accessible       | 6                                 |
-- | Tables with PASS         | 35 of 35                          |
-- | Hash matches (static)    | 6 of 6 MATCH (if DAG not running) |
-- | Views accessible         | 2 of 2                            |
-- | Asset master rows        | 10                                |
-- | Live predictions rows    | 10                                |
-- | Sensor readings span     | 90+ days                          |
--
-- Note: Tables updated by the DAG (SENSOR_READINGS, WORK_ORDERS, etc.)
-- may have MORE rows than the baseline if the DAG has run since capture.
-- Row counts use >= for these tables. Hash mismatches on dynamic data
-- are expected and normal — they indicate fresh data, not corruption.
