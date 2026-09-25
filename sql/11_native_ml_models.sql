-- ============================================================================
-- MFGPulse AI: 11 Native ML Models + Drift Detection + Closed-Loop ML
-- Trains 4 Snowflake-native ML models using the ML Feature training views.
-- Prerequisites: DTs must have completed initial refresh (CP7-CP8).
--
-- IMPORTANT: Training views were corrected on 2026-09-13:
--   - TRAIN_FAILURE_MODE: Normal class sampling increased from 15% to 50%
--     (was ~447K normal vs ~3M per failure class; now ~1.5M normal)
--   - TRAIN_TRAJECTORY_3CLASS: Stage labels changed from numeric (0/1/2)
--     to text ('Healthy'/'Warning'/'Critical') to match rule-based output
-- ============================================================================

USE DATABASE MFGPULSE_DB;

-- N1: Native Failure Mode Classifier
-- Training data: ~14.5M rows, 5 classes (bearing_wear, thermal_degradation,
--   imbalance, misalignment, normal). 28 sensor features + physics composites.
CREATE OR REPLACE SNOWFLAKE.ML.CLASSIFICATION('MFGPULSE_DB.ML_MODELS.NATIVE_FAILURE_MODE_CLASSIFIER',
    'MFGPULSE_DB.ML_FEATURES.TRAIN_FAILURE_MODE', 'FAILURE_MODE');

-- N2: Native Degradation Stager (3-class: Healthy/Warning/Critical)
-- Training data: ~107M rows (non-normal only), 3 text-label classes.
-- Labels now match LIVE_PREDICTIONS.STAGE_PRED for direct drift comparison.
CREATE OR REPLACE SNOWFLAKE.ML.CLASSIFICATION('MFGPULSE_DB.ML_MODELS.NATIVE_DEGRADATION_STAGER',
    'MFGPULSE_DB.ML_FEATURES.TRAIN_TRAJECTORY_3CLASS', 'STAGE_3CLASS');

-- N3: Native RUL Forecaster
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST('MFGPULSE_DB.ML_MODELS.NATIVE_RUL_FORECASTER',
    INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'MFGPULSE_DB.ML_FEATURES.TRAIN_RUL'),
    SERIES_COLNAME => 'ASSET_ID', TIMESTAMP_COLNAME => 'TIMESTAMP', TARGET_COLNAME => 'HOURS_TO_FAILURE');

-- N4: Native Anomaly Detector
CREATE OR REPLACE SNOWFLAKE.ML.ANOMALY_DETECTION('MFGPULSE_DB.ML_MODELS.NATIVE_ANOMALY_DETECTOR',
    INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'MFGPULSE_DB.ML_FEATURES.TRAIN_ANOMALY_SMALL'),
    SERIES_COLNAME => 'ASSET_ID', TIMESTAMP_COLNAME => 'TIMESTAMP', TARGET_COLNAME => 'COMPOSITE_HEALTH_SCORE');

-- After training, run drift comparison:
-- CALL MFGPULSE_DB.ML_MODELS.COMPUTE_NATIVE_PREDICTIONS();
-- SELECT * FROM MFGPULSE_DB.ML_MODELS.DRIFT_METRICS;
