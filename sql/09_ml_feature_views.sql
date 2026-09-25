-- ============================================================================
-- MFGPulse AI: 09 ML Feature Views
-- 11 views in ML_FEATURES schema for model training datasets
-- ============================================================================
-- To get full DDL: GET_DDL('VIEW', 'MFGPULSE_DB.ML_FEATURES.<name>')

-- ALL_DERIVED_FEATURES: Union of all feature DTs joined by asset_id + timestamp.
-- ALL_DERIVED_FEATURES_INFERENCE: Latest features per asset for real-time inference.
-- FEATURE_CATALOG: Metadata catalog of all engineered features with descriptions.

-- Training views:
-- TRAIN_FAILURE_MODE: Features + failure_mode label for M1 classifier training.
-- TRAIN_RUL: Time-series features with health_score target for M2 RUL forecaster.
-- TRAIN_TRAJECTORY: Features + degradation_stage label for M3 stager (5 classes).
-- TRAIN_TRAJECTORY_3CLASS: Same as above but mapped to Healthy/Warning/Critical.
-- TRAIN_ANOMALY: Features for anomaly detection model training.
-- TRAIN_ANOMALY_SMALL: Sampled version for faster training iterations.

-- Healthy baselines:
-- HEALTHY_DERIVED_FEATURES: All features filtered to assets in healthy state.
-- HEALTHY_DERIVED_FEATURES_TRAIN: Sampled healthy data for anomaly detector training.
