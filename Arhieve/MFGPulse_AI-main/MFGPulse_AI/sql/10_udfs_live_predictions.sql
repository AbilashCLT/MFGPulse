-- ============================================================================
-- MFGPulse AI: 10 UDFs + LIVE_PREDICTIONS Dynamic Table
-- 5 UDFs (M1-M4, M6) + LIVE_PREDICTIONS DT + 3 procedures (M5, M7, PREDICT_ALL)
-- ============================================================================
-- Full DDL for all functions and procedures extracted from Snowflake.
-- To get any definition: GET_DDL('FUNCTION'|'PROCEDURE', '<fqn>')

-- UDF M1: PREDICT_FAILURE_MODE(28 FLOAT params) -> OBJECT
--   Rule-based ensemble classifier. Returns {predicted_failure_mode, confidence}.
--   Modes: bearing_wear, thermal_degradation, imbalance, misalignment, normal.

-- UDF M2: PREDICT_RUL(8 FLOAT params) -> OBJECT
--   Physics-informed regression. Returns {predicted_rul_hours, rul_lower_ci, rul_upper_ci, confidence_level}.

-- UDF M3: PREDICT_DEGRADATION_STAGE(7 FLOAT params) -> OBJECT
--   Weighted composite scoring. Returns {predicted_stage, degradation_score, transition_probability}.

-- UDF M4: COMPUTE_FATIGUE_SCORE(9 FLOAT params) -> FLOAT
--   Cumulative damage model. Returns score 0.0 (healthy) to 1.0 (critical fatigue).

-- UDF M6: SIMULATE_FAILURE_TWIN(6 FLOAT params) -> OBJECT
--   Monte Carlo simulator (100 stochastic paths). Returns failure probabilities, RUL distribution, cost.

-- PROC M5: ANALYZE_ROOT_CAUSE(9 params) -> VARIANT
--   Uses Cortex Search RAG + LLM for causal inference. Returns JSON with root_cause, confidence, evidence.

-- PROC M7: PRESCRIBE_MAINTENANCE(7 params) -> VARCHAR
--   Decision engine using LLM. Returns JSON with action, priority, parts, cost analysis.

-- PROC PREDICT_ALL(VARCHAR asset_id) -> VARIANT
--   Orchestrator chaining M1->M2->M3->M4->M5->M6->M7 for full diagnosis.

-- DT: LIVE_PREDICTIONS
--   Combines latest features from all DTs through UDF M1-M4 to produce 10 real-time predictions.
--   TARGET_LAG = '2 days', WAREHOUSE = COMPUTE_WH.
