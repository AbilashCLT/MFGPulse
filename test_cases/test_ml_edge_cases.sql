-- ============================================================================
-- MFGPulse AI: test_ml_edge_cases.sql — TC-11: ML UDF Edge Case Tests
-- ============================================================================
-- Tests UDFs with boundary, null, zero, and extreme inputs.
-- Run from Admin Panel or SQL worksheet.

USE DATABASE MFGPULSE_DB;

-- TC-11-01: COMPUTE_FATIGUE_SCORE with all zeros (UDF has baseline offset)
SELECT 'TC-11-01' AS TEST_ID, 'Fatigue score with all zeros' AS TEST_NAME,
    '<=0.3' AS EXPECTED,
    ML_MODELS.COMPUTE_FATIGUE_SCORE(0,0,0,0,0,0,0,0,0)::VARCHAR AS ACTUAL,
    CASE WHEN ML_MODELS.COMPUTE_FATIGUE_SCORE(0,0,0,0,0,0,0,0,0) <= 0.3 THEN 'PASS' ELSE 'FAIL' END AS STATUS;

-- TC-11-02: COMPUTE_FATIGUE_SCORE with max inputs (all 10.0)
SELECT 'TC-11-02' AS TEST_ID, 'Fatigue score capped at 1.0' AS TEST_NAME,
    '<=1.0' AS EXPECTED,
    ML_MODELS.COMPUTE_FATIGUE_SCORE(10,10,10,10,10,10,10,10,100)::VARCHAR AS ACTUAL,
    CASE WHEN ML_MODELS.COMPUTE_FATIGUE_SCORE(10,10,10,10,10,10,10,10,100) <= 1.0 THEN 'PASS' ELSE 'FAIL' END AS STATUS;

-- TC-11-03: PREDICT_RUL with zero degradation velocity
SELECT 'TC-11-03' AS TEST_ID, 'RUL with zero degradation returns 2000h' AS TEST_NAME,
    '2000' AS EXPECTED,
    (ML_MODELS.PREDICT_RUL(2.0, 0, 0, 0, 0, 0.1, 80, 0.1)):predicted_rul_hours::VARCHAR AS ACTUAL,
    CASE WHEN (ML_MODELS.PREDICT_RUL(2.0, 0, 0, 0, 0, 0.1, 80, 0.1)):predicted_rul_hours = 2000 THEN 'PASS' ELSE 'FAIL' END AS STATUS;

-- TC-11-04: PREDICT_RUL returns non-negative
SELECT 'TC-11-04' AS TEST_ID, 'RUL never negative' AS TEST_NAME,
    '>=0' AS EXPECTED,
    (ML_MODELS.PREDICT_RUL(50, 5, 5, 10, 5000, 1.0, 5, 0.99)):predicted_rul_hours::VARCHAR AS ACTUAL,
    CASE WHEN (ML_MODELS.PREDICT_RUL(50, 5, 5, 10, 5000, 1.0, 5, 0.99)):predicted_rul_hours >= 0 THEN 'PASS' ELSE 'FAIL' END AS STATUS;

-- TC-11-05: PREDICT_DEGRADATION_STAGE with healthy inputs
SELECT 'TC-11-05' AS TEST_ID, 'Healthy inputs produce Healthy stage' AS TEST_NAME,
    'Healthy' AS EXPECTED,
    (ML_MODELS.PREDICT_DEGRADATION_STAGE(1.0, 0.5, 0.05, 95, 0, NULL, 0)):predicted_stage::VARCHAR AS ACTUAL,
    CASE WHEN (ML_MODELS.PREDICT_DEGRADATION_STAGE(1.0, 0.5, 0.05, 95, 0, NULL, 0)):predicted_stage = 'Healthy' THEN 'PASS' ELSE 'FAIL' END AS STATUS;

-- TC-11-06: PREDICT_DEGRADATION_STAGE with extreme inputs
SELECT 'TC-11-06' AS TEST_ID, 'Extreme inputs produce Critical stage' AS TEST_NAME,
    'Critical' AS EXPECTED,
    (ML_MODELS.PREDICT_DEGRADATION_STAGE(50, 10, 1.0, 10, 5, 5000, 100)):predicted_stage::VARCHAR AS ACTUAL,
    CASE WHEN (ML_MODELS.PREDICT_DEGRADATION_STAGE(50, 10, 1.0, 10, 5, 5000, 100)):predicted_stage = 'Critical' THEN 'PASS' ELSE 'FAIL' END AS STATUS;

-- TC-11-07: PREDICT_FAILURE_MODE with normal/healthy inputs
SELECT 'TC-11-07' AS TEST_ID, 'Normal inputs predict normal mode' AS TEST_NAME,
    'normal' AS EXPECTED,
    (ML_MODELS.PREDICT_FAILURE_MODE(1,0.1,1.5,1.0,0.5,1.0,0.1, 40,1, 10,0.5, 1,0.1,1.0,1.0, 40,10,60, 0,0, 0.1,0.5,7.0,0.5,15, 0.05,1.0,90)):predicted_failure_mode::VARCHAR AS ACTUAL,
    CASE WHEN (ML_MODELS.PREDICT_FAILURE_MODE(1,0.1,1.5,1.0,0.5,1.0,0.1, 40,1, 10,0.5, 1,0.1,1.0,1.0, 40,10,60, 0,0, 0.1,0.5,7.0,0.5,15, 0.05,1.0,90)):predicted_failure_mode = 'normal' THEN 'PASS' ELSE 'FAIL' END AS STATUS;

-- TC-11-08: SIMULATE_FAILURE_TWIN returns 100 simulations
SELECT 'TC-11-08' AS TEST_ID, 'Simulation always returns 100 paths' AS TEST_NAME,
    '100' AS EXPECTED,
    (ML_MODELS.SIMULATE_FAILURE_TWIN(5.0, 0.1, 0.5, 0, 7, 0)):num_simulations::VARCHAR AS ACTUAL,
    CASE WHEN (ML_MODELS.SIMULATE_FAILURE_TWIN(5.0, 0.1, 0.5, 0, 7, 0)):num_simulations = 100 THEN 'PASS' ELSE 'FAIL' END AS STATUS;

-- TC-11-09: SIMULATE_FAILURE_TWIN with healthy asset = low failure probability
SELECT 'TC-11-09' AS TEST_ID, 'Healthy asset has <50% 14d failure prob' AS TEST_NAME,
    '<0.5' AS EXPECTED,
    (ML_MODELS.SIMULATE_FAILURE_TWIN(1.5, 0.001, 0.05, 0, 14, 0)):failure_prob_day_14::VARCHAR AS ACTUAL,
    CASE WHEN (ML_MODELS.SIMULATE_FAILURE_TWIN(1.5, 0.001, 0.05, 0, 14, 0)):failure_prob_day_14 < 0.5 THEN 'PASS' ELSE 'FAIL' END AS STATUS;

-- TC-11-10: Degradation score bounded 0-1
SELECT 'TC-11-10' AS TEST_ID, 'Degradation score in [0,1]' AS TEST_NAME,
    '[0,1]' AS EXPECTED,
    (ML_MODELS.PREDICT_DEGRADATION_STAGE(50, 10, 1.0, 10, 5, 5000, 100)):degradation_score::VARCHAR AS ACTUAL,
    CASE WHEN (ML_MODELS.PREDICT_DEGRADATION_STAGE(50, 10, 1.0, 10, 5, 5000, 100)):degradation_score BETWEEN 0 AND 1 THEN 'PASS' ELSE 'FAIL' END AS STATUS;
