-- ============================================================================
-- MFGPulse AI: 12 Analytics Layer
-- 2 Dynamic Tables + 6 Views + 6 Procedures
-- ============================================================================
-- Full DDL extracted from deployed Snowflake objects.

-- DYNAMIC TABLES (both in ANALYTICS schema, TARGET_LAG = '2 days'):
-- ACTIVE_ALERTS: Generated from LIVE_PREDICTIONS with severity rules (CRITICAL/WARNING/WATCH/INFO).
--   Includes chronic asset detection (>2 WOs in 90 days), escalation timing. 8 rows.
-- OEE_METRICS: OEE calculation per asset per shift from PRODUCTION_OUTPUT + LIVE_PREDICTIONS.
--   Includes availability/performance/quality loss attribution. 3330 rows.

-- VIEWS:
-- ALERT_SUMMARY: Count of alerts by severity level (CRITICAL, WARNING, WATCH, INFO).
-- COST_IMPACT: Fleet-wide cost avoidance metrics, maintenance ROI, OEE improvement potential.
-- COST_IMPACT_BY_ASSET: Per-asset cost breakdown (emergency/corrective/preventive), savings potential.
-- EXECUTIVE_SUMMARY: Plant-wide KPIs (OEE, critical assets, cost avoided, ROI, detection days).
-- PREDICTIONS_WITH_COST: LIVE_PREDICTIONS enriched with failure/repair costs, parts status, open WOs.
-- SHIFT_HANDOVER_VIEW: Real-time shift handover data (critical actions, OEE, alerts, costs).

-- PROCEDURES:
-- GENERATE_WORK_ORDER(5 params): Create work order with auto-technician assignment.
-- AUTO_GENERATE_WORK_ORDERS(): Batch-create WOs for all at-risk assets.
-- GENERATE_SHIFT_HANDOVER_SUMMARY(): AI-generated shift briefing via Cortex Complete.
-- PREDICT_ALL(VARCHAR): Full 7-model diagnostic chain (in ML_MODELS schema).
-- ANALYZE_ROOT_CAUSE(9 params): RAG + LLM root cause analysis (in ML_MODELS schema).
-- PRESCRIBE_MAINTENANCE(7 params): LLM prescriptive recommendation (in ML_MODELS schema).

-- To get any full DDL:
-- SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.ANALYTICS.ACTIVE_ALERTS');
-- SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ANALYTICS.COST_IMPACT');
-- SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.ANALYTICS.GENERATE_WORK_ORDER(VARCHAR,VARCHAR,VARCHAR,VARCHAR,FLOAT)');
