-- ============================================================================
-- MFGPulse AI: Retrain Native ML Models + Validate Drift
-- Run this script in a Snowflake SQL worksheet (not Cortex Code) as ACCOUNTADMIN.
-- Prerequisites: Training views already corrected (TRAIN_FAILURE_MODE,
--   TRAIN_TRAJECTORY_3CLASS) — done by the ML pipeline fix session.
-- COMPUTE_NATIVE_PREDICTIONS procedure is exception-safe: if models are broken,
--   it writes 'UNAVAILABLE' instead of crashing. Dedup-safe (DELETE before INSERT).
-- Estimated cost: ~0.5-2 credits for retraining on COMPUTE_WH (XS).
-- ============================================================================

USE ROLE ACCOUNTADMIN;
USE DATABASE MFGPULSE_DB;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================================
-- STEP 1: Grant ML privileges (if not already granted)
-- ============================================================================
GRANT CREATE SNOWFLAKE.ML.CLASSIFICATION ON SCHEMA ML_MODELS TO ROLE ACCOUNTADMIN;
GRANT CREATE SNOWFLAKE.ML.FORECAST ON SCHEMA ML_MODELS TO ROLE ACCOUNTADMIN;
GRANT CREATE SNOWFLAKE.ML.ANOMALY_DETECTION ON SCHEMA ML_MODELS TO ROLE ACCOUNTADMIN;


-- ============================================================================
-- STEP 2: Verify corrected training data
-- ============================================================================

-- Should show ~1.5M normal rows (was ~447K before fix)
SELECT FAILURE_MODE, COUNT(*) AS cnt
FROM ML_FEATURES.TRAIN_FAILURE_MODE
GROUP BY ALL ORDER BY cnt DESC;

-- Should show text labels: 'Healthy', 'Warning', 'Critical' (was 0, 1, 2)
SELECT STAGE_3CLASS, COUNT(*) AS cnt
FROM ML_FEATURES.TRAIN_TRAJECTORY_3CLASS
GROUP BY ALL ORDER BY STAGE_3CLASS;


-- ============================================================================
-- STEP 3: Drop broken models and retrain
-- ============================================================================

-- Drop existing (broken) models
DROP SNOWFLAKE.ML.CLASSIFICATION IF EXISTS ML_MODELS.NATIVE_FAILURE_MODE_CLASSIFIER;
DROP SNOWFLAKE.ML.CLASSIFICATION IF EXISTS ML_MODELS.NATIVE_DEGRADATION_STAGER;

-- N1: Retrain Failure Mode Classifier (~3-5 min on XS warehouse)
CREATE SNOWFLAKE.ML.CLASSIFICATION ML_MODELS.NATIVE_FAILURE_MODE_CLASSIFIER(
    INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML_FEATURES.TRAIN_FAILURE_MODE'),
    TARGET_COLNAME => 'FAILURE_MODE'
);

-- N2: Retrain Degradation Stager (~3-5 min on XS warehouse)
CREATE SNOWFLAKE.ML.CLASSIFICATION ML_MODELS.NATIVE_DEGRADATION_STAGER(
    INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML_FEATURES.TRAIN_TRAJECTORY_3CLASS'),
    TARGET_COLNAME => 'STAGE_3CLASS'
);


-- ============================================================================
-- STEP 4: Validate models work (test !PREDICT)
-- ============================================================================

-- Test failure mode classifier
CALL ML_MODELS.NATIVE_FAILURE_MODE_CLASSIFIER!SHOW_GLOBAL_EVALUATION_METRICS();

-- Test degradation stager
CALL ML_MODELS.NATIVE_DEGRADATION_STAGER!SHOW_GLOBAL_EVALUATION_METRICS();

-- Feature importance
CALL ML_MODELS.NATIVE_FAILURE_MODE_CLASSIFIER!SHOW_FEATURE_IMPORTANCE();
CALL ML_MODELS.NATIVE_DEGRADATION_STAGER!SHOW_FEATURE_IMPORTANCE();


-- ============================================================================
-- STEP 5: Run drift comparison with fresh models
-- ============================================================================

-- Clear stale drift data
DELETE FROM ML_MODELS.DRIFT_COMPARISON WHERE COMPARISON_DATE < CURRENT_DATE();

-- Run the drift comparison procedure
CALL ML_MODELS.COMPUTE_NATIVE_PREDICTIONS();


-- ============================================================================
-- STEP 6: Validate drift results
-- ============================================================================

-- Should show improved agreement rates (target: >60% FM, >70% stage)
SELECT * FROM ML_MODELS.DRIFT_METRICS ORDER BY COMPARISON_DATE DESC;

-- Per-asset detail for today
SELECT ASSET_ID, ASSET_NAME,
    RULE_FAILURE_MODE, NATIVE_FAILURE_MODE, FAILURE_MODE_AGREES,
    RULE_STAGE, NATIVE_STAGE, STAGE_AGREES
FROM ML_MODELS.DRIFT_COMPARISON
WHERE COMPARISON_DATE = CURRENT_DATE()
ORDER BY ASSET_ID;

-- Update model registry with retrain timestamp
UPDATE ML_MODELS.MODEL_REGISTRY
SET TRAINED_AT = CURRENT_TIMESTAMP()
WHERE MODEL_NAME IN ('N1_FAILURE_MODE_NATIVE', 'N2_DEGRADATION_STAGER_NATIVE');


-- ============================================================================
-- STEP 7 (Optional): Retrain RUL Forecaster and Anomaly Detector
-- ============================================================================

-- DROP SNOWFLAKE.ML.FORECAST IF EXISTS ML_MODELS.NATIVE_RUL_FORECASTER;
-- CREATE SNOWFLAKE.ML.FORECAST ML_MODELS.NATIVE_RUL_FORECASTER(
--     INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML_FEATURES.TRAIN_RUL'),
--     SERIES_COLNAME => 'ASSET_ID', TIMESTAMP_COLNAME => 'TIMESTAMP', TARGET_COLNAME => 'HOURS_TO_FAILURE');

-- DROP SNOWFLAKE.ML.ANOMALY_DETECTION IF EXISTS ML_MODELS.NATIVE_ANOMALY_DETECTOR;
-- CREATE SNOWFLAKE.ML.ANOMALY_DETECTION ML_MODELS.NATIVE_ANOMALY_DETECTOR(
--     INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'ML_FEATURES.TRAIN_ANOMALY_SMALL'),
--     SERIES_COLNAME => 'ASSET_ID', TIMESTAMP_COLNAME => 'TIMESTAMP', TARGET_COLNAME => 'COMPOSITE_HEALTH_SCORE');
