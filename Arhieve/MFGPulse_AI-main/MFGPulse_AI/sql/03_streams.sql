-- ============================================================================
-- MFGPulse AI: 03 Streams
-- Change tracking streams for real-time pipeline
-- ============================================================================

USE DATABASE MFGPULSE_DB;

CREATE OR REPLACE STREAM RAW_OT.SENSOR_READINGS_STREAM ON TABLE RAW_OT.SENSOR_READINGS APPEND_ONLY = TRUE;
CREATE OR REPLACE STREAM RAW_IT.MAINTENANCE_LOGS_STREAM ON TABLE RAW_IT.MAINTENANCE_LOGS APPEND_ONLY = TRUE;
CREATE OR REPLACE STREAM RAW_IT.WORK_ORDERS_STREAM ON TABLE RAW_IT.WORK_ORDERS;
