-- ============================================================================
-- MFGPulse AI: deploy_all.sql — Master Deployment Script
-- ============================================================================
-- One-shot deployment of the entire platform from zero to running.
-- Run in a Snowflake SQL worksheet with ACCOUNTADMIN role.
--
-- This script contains all DDL extracted from the deployed Snowflake objects.
-- Estimated execution time: ~12 minutes (sensor data generation is the longest step).
--
-- IMPORTANT: Execute statements in order. Each section depends on the prior one.
-- ============================================================================


-- ============================================================================
-- PHASE 1: INFRASTRUCTURE (database, schemas, warehouse, resource monitor)
-- ============================================================================

CREATE DATABASE IF NOT EXISTS MFGPULSE_DB;
USE DATABASE MFGPULSE_DB;

CREATE SCHEMA IF NOT EXISTS RAW_OT;
CREATE SCHEMA IF NOT EXISTS RAW_IT;
CREATE SCHEMA IF NOT EXISTS CURATED;
CREATE SCHEMA IF NOT EXISTS ML_FEATURES;
CREATE SCHEMA IF NOT EXISTS ML_MODELS;
CREATE SCHEMA IF NOT EXISTS ANALYTICS;
CREATE SCHEMA IF NOT EXISTS AGENT;

CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;

CREATE RESOURCE MONITOR IF NOT EXISTS MFGPULSE_CREDIT_GUARD
    WITH CREDIT_QUOTA = 250
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO NOTIFY
        ON 100 PERCENT DO SUSPEND;

ALTER WAREHOUSE COMPUTE_WH SET RESOURCE_MONITOR = MFGPULSE_CREDIT_GUARD;

CREATE WAREHOUSE IF NOT EXISTS MFGPULSE_AUTOMATION_WH
    WAREHOUSE_SIZE = 'XSMALL'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE
    COMMENT = 'Dedicated warehouse for MFGPulse AI tasks and dynamic table refreshes.';

CREATE OR REPLACE RESOURCE MONITOR MFGPULSE_AUTOMATION_GUARD
    WITH CREDIT_QUOTA = 50
    FREQUENCY = MONTHLY
    START_TIMESTAMP = IMMEDIATELY
    TRIGGERS
        ON 75 PERCENT DO NOTIFY
        ON 90 PERCENT DO SUSPEND
        ON 100 PERCENT DO SUSPEND_IMMEDIATE;

ALTER WAREHOUSE MFGPULSE_AUTOMATION_WH SET RESOURCE_MONITOR = MFGPULSE_AUTOMATION_GUARD;


-- ============================================================================
-- PHASE 2: BASE TABLES (19 tables across RAW_OT, RAW_IT, ML_MODELS, ANALYTICS)
-- ============================================================================

-- === RAW_OT ===
CREATE OR REPLACE TABLE RAW_OT.ASSET_MASTER (
    ASSET_ID VARCHAR(20) NOT NULL PRIMARY KEY,
    ASSET_NAME VARCHAR(100) NOT NULL,
    ASSET_TYPE VARCHAR(50) NOT NULL,
    LINE_ID VARCHAR(20) NOT NULL,
    INSTALL_DATE DATE,
    MANUFACTURER VARCHAR(100),
    MODEL_NUMBER VARCHAR(50),
    RATED_RPM FLOAT,
    RATED_TEMP_MAX FLOAT
);

CREATE OR REPLACE TABLE RAW_OT.SENSOR_METADATA (
    SENSOR_ID VARCHAR(30) NOT NULL PRIMARY KEY,
    ASSET_ID VARCHAR(20) NOT NULL,
    SENSOR_TYPE VARCHAR(50) NOT NULL,
    LOCATION VARCHAR(100),
    CALIBRATION_DATE DATE,
    SAMPLING_RATE_HZ FLOAT
);

CREATE OR REPLACE TABLE RAW_OT.SENSOR_READINGS (
    READING_ID NUMBER AUTOINCREMENT,
    ASSET_ID VARCHAR(20) NOT NULL,
    TIMESTAMP TIMESTAMP_NTZ NOT NULL,
    VIBRATION_X FLOAT, VIBRATION_Y FLOAT, VIBRATION_Z FLOAT,
    TEMPERATURE FLOAT, RPM FLOAT, PRESSURE FLOAT,
    CURRENT_AMPS FLOAT, ACOUSTIC_DB FLOAT,
    INGESTION_TS TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW_OT.AMBIENT_CONDITIONS (
    READING_DATE DATE NOT NULL,
    AMBIENT_TEMP_C FLOAT, HUMIDITY_PCT FLOAT, BAROMETRIC_PRESSURE_HPA FLOAT
);

-- === RAW_IT ===
CREATE OR REPLACE TABLE RAW_IT.WORK_ORDERS (
    WO_ID VARCHAR(50) NOT NULL PRIMARY KEY,
    ASSET_ID VARCHAR(20) NOT NULL,
    WO_TYPE VARCHAR(20) NOT NULL,
    CREATED_DATE TIMESTAMP_NTZ NOT NULL,
    COMPLETED_DATE TIMESTAMP_NTZ,
    PRIORITY VARCHAR(10), STATUS VARCHAR(20),
    ASSIGNED_TO VARCHAR(100),
    LABOR_HOURS FLOAT, PARTS_COST FLOAT, TOTAL_COST FLOAT,
    ROOT_CAUSE_CONFIRMED VARCHAR,
    PART_USED BOOLEAN DEFAULT TRUE
);

CREATE OR REPLACE TABLE RAW_IT.MAINTENANCE_LOGS (
    LOG_ID VARCHAR(20) NOT NULL PRIMARY KEY,
    WO_ID VARCHAR(20), ASSET_ID VARCHAR(20) NOT NULL,
    TIMESTAMP TIMESTAMP_NTZ NOT NULL,
    TECHNICIAN VARCHAR(100), NOTES_TEXT VARCHAR(2000)
);

CREATE OR REPLACE TABLE RAW_IT.PRODUCTION_OUTPUT (
    RECORD_ID VARCHAR(20) NOT NULL PRIMARY KEY,
    ASSET_ID VARCHAR(20) NOT NULL, SHIFT_ID VARCHAR(20),
    TIMESTAMP TIMESTAMP_NTZ NOT NULL,
    UNITS_PRODUCED INT, GOOD_UNITS INT, IDEAL_CYCLE_TIME_SEC FLOAT
);

CREATE OR REPLACE TABLE RAW_IT.SHIFT_SCHEDULE (
    SHIFT_ID VARCHAR(20) NOT NULL PRIMARY KEY,
    LINE_ID VARCHAR(20) NOT NULL,
    SHIFT_START TIMESTAMP_NTZ NOT NULL, SHIFT_END TIMESTAMP_NTZ NOT NULL,
    OPERATOR_NAME VARCHAR(100), PLANNED_PRODUCTION_TIME_MINS INT
);

CREATE OR REPLACE TABLE RAW_IT.PARTS_INVENTORY (
    PART_ID VARCHAR(20) NOT NULL PRIMARY KEY,
    PART_NAME VARCHAR(200) NOT NULL,
    COMPATIBLE_ASSETS ARRAY,
    QUANTITY_ON_HAND INT, LEAD_TIME_DAYS INT, UNIT_COST FLOAT
);

CREATE OR REPLACE TABLE RAW_IT.USERS (
    USER_ID VARCHAR(20) NOT NULL PRIMARY KEY,
    USERNAME VARCHAR(100) NOT NULL, EMAIL VARCHAR(200),
    PERSONA VARCHAR(50) NOT NULL, ROLE VARCHAR(50),
    LINE_ID VARCHAR(20),
    ACTIVE BOOLEAN DEFAULT TRUE,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW_IT.SUPPLIERS (
    SUPPLIER_ID VARCHAR(20) NOT NULL PRIMARY KEY,
    SUPPLIER_NAME VARCHAR(200) NOT NULL,
    CONTACT_EMAIL VARCHAR(200), PHONE VARCHAR(50),
    ACTIVE BOOLEAN DEFAULT TRUE,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW_IT.PART_SUPPLIERS (
    PART_ID VARCHAR(20) NOT NULL, SUPPLIER_ID VARCHAR(20) NOT NULL,
    SUPPLIER_PART_NUMBER VARCHAR(50),
    STANDARD_LEAD_TIME_DAYS INT DEFAULT 7, EXPEDITE_LEAD_TIME_DAYS INT DEFAULT 3,
    MIN_ORDER_QTY INT DEFAULT 1, UNIT_COST FLOAT,
    PREFERRED_SUPPLIER BOOLEAN DEFAULT FALSE
);

CREATE OR REPLACE TABLE RAW_IT.PART_RESERVATIONS (
    RESERVATION_ID VARCHAR(50) NOT NULL PRIMARY KEY,
    PART_ID VARCHAR(20) NOT NULL, ASSET_ID VARCHAR(20) NOT NULL,
    WO_ID VARCHAR(50), QUANTITY_RESERVED INT DEFAULT 1,
    REQUIRED_BY_DATE DATE, STATUS VARCHAR(20) DEFAULT 'active',
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE RAW_IT.PURCHASE_ORDERS (
    PO_ID VARCHAR(50) NOT NULL PRIMARY KEY,
    SUPPLIER_ID VARCHAR(20), CREATED_DATE TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    REQUIRED_BY_DATE DATE, EXPECTED_ARRIVAL_DATE DATE,
    STATUS VARCHAR(30) DEFAULT 'draft', PRIORITY VARCHAR(20) DEFAULT 'NORMAL',
    TOTAL_COST FLOAT, CREATED_BY VARCHAR(100) DEFAULT 'SYSTEM',
    SOURCE VARCHAR(30) DEFAULT 'prediction',
    REJECTION_REASON VARCHAR,
    REJECTED_BY VARCHAR,
    REJECTED_AT TIMESTAMP_NTZ
);

CREATE OR REPLACE TABLE RAW_IT.PURCHASE_ORDER_LINES (
    PO_LINE_ID VARCHAR(50) NOT NULL PRIMARY KEY,
    PO_ID VARCHAR(50) NOT NULL, PART_ID VARCHAR(20) NOT NULL,
    ASSET_ID VARCHAR(20), WO_ID VARCHAR(50),
    QUANTITY_ORDERED INT DEFAULT 1, UNIT_COST FLOAT, LINE_COST FLOAT,
    RUL_HOURS_AT_ORDER FLOAT, FAILURE_MODE_PRED VARCHAR(50),
    PROCUREMENT_RISK VARCHAR(30)
);

-- === ML_MODELS ===
CREATE OR REPLACE TABLE ML_MODELS.MODEL_REGISTRY (
    MODEL_NAME VARCHAR(100), MODEL_TYPE VARCHAR(100),
    TRAINING_DATA VARCHAR(200),
    PRECISION_SCORE FLOAT, RECALL_SCORE FLOAT, F1_SCORE FLOAT,
    TOP_FEATURES VARCHAR(500),
    TRAINED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

CREATE OR REPLACE TABLE ML_MODELS.FATIGUE_SCORES (
    ASSET_ID VARCHAR(20), TIMESTAMP TIMESTAMP_NTZ,
    FATIGUE_SCORE FLOAT, FATIGUE_LEVEL VARCHAR(20)
);

CREATE OR REPLACE TABLE ML_MODELS.ANOMALY_SCORES (
    SERIES VARIANT, TS TIMESTAMP_NTZ,
    Y FLOAT, FORECAST FLOAT, LOWER_BOUND FLOAT, UPPER_BOUND FLOAT,
    IS_ANOMALY BOOLEAN, PERCENTILE FLOAT, DISTANCE FLOAT
);

CREATE OR REPLACE TABLE ANALYTICS.SHIFT_HANDOVER_HISTORY (
    GENERATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    SUMMARY_TEXT TEXT, WOS_GENERATED INT,
    PLANT_OEE FLOAT, CRITICAL_ASSETS INT
);

-- === Notification tables ===
CREATE TABLE IF NOT EXISTS RAW_IT.NOTIFICATION_SETTINGS (
    EVENT_TYPE VARCHAR(30) NOT NULL PRIMARY KEY,
    EVENT_LABEL VARCHAR(100),
    EMAIL_ENABLED BOOLEAN DEFAULT FALSE,
    IN_APP_ENABLED BOOLEAN DEFAULT TRUE,
    EMAIL_RECIPIENTS VARCHAR(500) DEFAULT '',
    NOTIFY_PERSONAS VARCHAR(200) DEFAULT 'PLANT_MANAGER,APP_ADMIN',
    PRIORITY VARCHAR(10) DEFAULT 'NORMAL',
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    UPDATED_BY VARCHAR(100) DEFAULT CURRENT_USER()
);

CREATE TABLE IF NOT EXISTS RAW_IT.APP_NOTIFICATIONS (
    NOTIF_ID VARCHAR(200) NOT NULL PRIMARY KEY,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    EVENT_TYPE VARCHAR(50) NOT NULL,
    PERSONA_TARGET VARCHAR(50),
    TITLE VARCHAR(500),
    MESSAGE VARCHAR(2000),
    ENTITY_ID VARCHAR(100),
    PRIORITY VARCHAR(20) DEFAULT 'NORMAL',
    IS_READ BOOLEAN DEFAULT FALSE,
    DISMISSED BOOLEAN DEFAULT FALSE
);


-- ============================================================================
-- PHASE 3: STREAMS (3 CDC streams)
-- ============================================================================

CREATE OR REPLACE STREAM RAW_OT.SENSOR_READINGS_STREAM ON TABLE RAW_OT.SENSOR_READINGS APPEND_ONLY = TRUE;
CREATE OR REPLACE STREAM RAW_IT.MAINTENANCE_LOGS_STREAM ON TABLE RAW_IT.MAINTENANCE_LOGS APPEND_ONLY = TRUE;
CREATE OR REPLACE STREAM RAW_IT.WORK_ORDERS_STREAM ON TABLE RAW_IT.WORK_ORDERS;


-- ============================================================================
-- PHASE 4: SEED DATA
-- ============================================================================
-- NOTE: Seed data (assets, sensors, parts, users, work orders, maintenance logs,
-- shifts, production, suppliers, model registry) must be loaded BEFORE creating
-- dynamic tables. The seed data was populated during initial build via INSERT
-- statements that are too large to inline here.
--
-- To populate from scratch, export from the deployed database:
--   SELECT * FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER;
--   SELECT * FROM MFGPULSE_DB.RAW_OT.SENSOR_METADATA;
--   ... (see DEPLOYMENT_GUIDE.md for full list)
--
-- Or use the sensor data generation procedure below.
-- ============================================================================

-- Seed suppliers
INSERT INTO RAW_IT.SUPPLIERS (SUPPLIER_ID, SUPPLIER_NAME, CONTACT_EMAIL, PHONE) VALUES
    ('SUP-001', 'Industrial Parts Co', 'orders@indparts.com', '+1-555-0101'),
    ('SUP-002', 'Atlas Copco Parts Direct', 'parts@atlascopco.com', '+1-555-0102'),
    ('SUP-003', 'Bearing World Inc', 'sales@bearingworld.com', '+1-555-0103'),
    ('SUP-004', 'ThermalTech Supply', 'orders@thermaltech.com', '+1-555-0104'),
    ('SUP-005', 'PumpParts Global', 'sales@pumpparts.com', '+1-555-0105');

-- Seed part-supplier mappings
INSERT INTO RAW_IT.PART_SUPPLIERS (PART_ID, SUPPLIER_ID, SUPPLIER_PART_NUMBER, STANDARD_LEAD_TIME_DAYS, EXPEDITE_LEAD_TIME_DAYS, MIN_ORDER_QTY, UNIT_COST, PREFERRED_SUPPLIER) VALUES
    ('PART-001', 'SUP-003', 'BW-6205-2RS', 5, 2, 1, 45, TRUE),
    ('PART-001', 'SUP-001', 'IP-BRG-6205', 7, 3, 2, 42, FALSE),
    ('PART-002', 'SUP-003', 'BW-6308-ZZ', 7, 3, 1, 120, TRUE),
    ('PART-003', 'SUP-001', 'IP-SEAL-V100', 3, 1, 5, 15, TRUE),
    ('PART-004', 'SUP-002', 'AC-FLT-OIL-M', 2, 1, 10, 8, TRUE),
    ('PART-005', 'SUP-001', 'IP-BLT-V100', 4, 2, 3, 25, TRUE),
    ('PART-006', 'SUP-005', 'PP-IMP-CF150', 14, 7, 1, 850, TRUE),
    ('PART-007', 'SUP-005', 'PP-SEAL-MECH', 10, 5, 1, 320, TRUE),
    ('PART-008', 'SUP-001', 'IP-BRG-NUP310', 6, 3, 1, 95, TRUE),
    ('PART-009', 'SUP-004', 'TT-HTR-COIL-3K', 12, 6, 1, 280, TRUE),
    ('PART-010', 'SUP-001', 'IP-COUP-FLEX', 5, 2, 1, 180, TRUE),
    ('PART-011', 'SUP-003', 'BW-6310-2RS', 7, 3, 1, 150, TRUE),
    ('PART-012', 'SUP-001', 'IP-GEAR-SET-G1', 21, 10, 1, 1200, TRUE),
    ('PART-013', 'SUP-001', 'IP-ROLL-CONV', 3, 1, 4, 65, TRUE),
    ('PART-014', 'SUP-002', 'AC-SHAFT-SLV', 12, 5, 1, 450, TRUE),
    ('PART-015', 'SUP-004', 'TT-BLADE-STM', 28, 14, 1, 2200, TRUE);

-- Seed notification event types
MERGE INTO RAW_IT.NOTIFICATION_SETTINGS t
USING (
    SELECT * FROM VALUES
        ('WO_CREATED',   'Work order created',    FALSE, TRUE, '', 'SHIFT_SUPERVISOR,PLANT_MANAGER,APP_ADMIN', 'NORMAL'),
        ('WO_STARTED',   'Work order started',    FALSE, TRUE, '', 'SHIFT_SUPERVISOR,PLANT_MANAGER,APP_ADMIN', 'NORMAL'),
        ('WO_COMPLETED', 'Work order completed',  FALSE, TRUE, '', 'SHIFT_SUPERVISOR,PLANT_MANAGER,APP_ADMIN', 'NORMAL'),
        ('PO_CREATED',   'Purchase order created', FALSE, TRUE, '', 'PROCUREMENT_ADMIN,PLANT_MANAGER,APP_ADMIN', 'NORMAL'),
        ('PO_APPROVED',  'Purchase order approved',FALSE, TRUE, '', 'PROCUREMENT_ADMIN,PLANT_MANAGER,APP_ADMIN', 'NORMAL'),
        ('PO_REJECTED',  'Purchase order rejected',FALSE, TRUE, '', 'PROCUREMENT_ADMIN,PLANT_MANAGER,APP_ADMIN', 'HIGH'),
        ('PO_RECEIVED',  'Purchase order received',FALSE, TRUE, '', 'PROCUREMENT_ADMIN,PLANT_MANAGER,APP_ADMIN', 'NORMAL')
    AS s(EVENT_TYPE, EVENT_LABEL, EMAIL_ENABLED, IN_APP_ENABLED, EMAIL_RECIPIENTS, NOTIFY_PERSONAS, PRIORITY)
) s ON t.EVENT_TYPE = s.EVENT_TYPE
WHEN NOT MATCHED THEN INSERT (EVENT_TYPE, EVENT_LABEL, EMAIL_ENABLED, IN_APP_ENABLED, EMAIL_RECIPIENTS, NOTIFY_PERSONAS, PRIORITY)
    VALUES (s.EVENT_TYPE, s.EVENT_LABEL, s.EMAIL_ENABLED, s.IN_APP_ENABLED, s.EMAIL_RECIPIENTS, s.NOTIFY_PERSONAS, s.PRIORITY);


-- ============================================================================
-- PHASE 5: SENSOR DATA GENERATION PROCEDURE
-- ============================================================================
-- Creates the procedure and calls it to generate 172K+ sensor readings.
-- This is the longest step (~1-2 minutes).

CREATE OR REPLACE PROCEDURE RAW_OT.GENERATE_SENSOR_DATA()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS '
DECLARE
    start_date DATE := ''2026-03-01'';
    end_date DATE := ''2026-08-28'';
    row_count INTEGER := 0;
BEGIN
    INSERT INTO MFGPULSE_DB.RAW_OT.SENSOR_READINGS
        (asset_id, timestamp, vibration_x, vibration_y, vibration_z, temperature, rpm, pressure, current_amps, acoustic_db)
    WITH time_series AS (
        SELECT DATEADD(''minute'', seq4() * 15, :start_date::TIMESTAMP_NTZ) AS ts
        FROM TABLE(GENERATOR(ROWCOUNT => 17280))
    ),
    assets AS (
        SELECT asset_id, rated_rpm, rated_temp_max,
            CASE asset_id
                WHEN ''ASSET_001'' THEN ''bearing_wear'' WHEN ''ASSET_002'' THEN ''thermal_degradation''
                WHEN ''ASSET_003'' THEN ''imbalance'' WHEN ''ASSET_004'' THEN ''misalignment''
                WHEN ''ASSET_005'' THEN ''bearing_wear'' WHEN ''ASSET_006'' THEN ''thermal_degradation''
                WHEN ''ASSET_007'' THEN ''healthy'' WHEN ''ASSET_008'' THEN ''imbalance''
                WHEN ''ASSET_009'' THEN ''misalignment'' WHEN ''ASSET_010'' THEN ''healthy''
            END AS failure_mode,
            CASE asset_id
                WHEN ''ASSET_001'' THEN 0.55 WHEN ''ASSET_002'' THEN 0.60 WHEN ''ASSET_003'' THEN 0.50
                WHEN ''ASSET_004'' THEN 0.45 WHEN ''ASSET_005'' THEN 0.65 WHEN ''ASSET_006'' THEN 0.70
                WHEN ''ASSET_007'' THEN 0.99 WHEN ''ASSET_008'' THEN 0.75 WHEN ''ASSET_009'' THEN 0.40
                WHEN ''ASSET_010'' THEN 0.99
            END AS failure_start_pct
        FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER
    ),
    combined AS (
        SELECT a.asset_id, t.ts, a.rated_rpm, a.rated_temp_max, a.failure_mode, a.failure_start_pct,
            DATEDIFF(''minute'', :start_date::TIMESTAMP_NTZ, t.ts) /
                DATEDIFF(''minute'', :start_date::TIMESTAMP_NTZ, :end_date::TIMESTAMP_NTZ)::FLOAT AS timeline_pct,
            GREATEST(0, (DATEDIFF(''minute'', :start_date::TIMESTAMP_NTZ, t.ts) /
                DATEDIFF(''minute'', :start_date::TIMESTAMP_NTZ, :end_date::TIMESTAMP_NTZ)::FLOAT
                - a.failure_start_pct) / NULLIF(1 - a.failure_start_pct, 0)
            ) AS degradation_pct,
            UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS noise1,
            UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS noise2,
            UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS noise3,
            UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS missing_rnd,
            SIN(DATEDIFF(''hour'', :start_date::TIMESTAMP_NTZ, t.ts) / 500.0) * 0.3 AS sensor_drift
        FROM time_series t CROSS JOIN assets a
    )
    SELECT asset_id, ts,
        CASE WHEN missing_rnd < 0.002 THEN NULL
            WHEN failure_mode = ''bearing_wear'' THEN 2.0 + noise1*0.5 + sensor_drift + degradation_pct*8.0*(1+degradation_pct) + CASE WHEN degradation_pct > 0.8 THEN ABS(noise2)*15.0 ELSE 0 END
            WHEN failure_mode = ''misalignment'' THEN 2.5 + noise1*0.4 + sensor_drift + degradation_pct*5.0 + degradation_pct*SIN(timeline_pct*200)*3.0
            WHEN failure_mode = ''imbalance'' THEN 1.8 + noise1*0.3 + sensor_drift + degradation_pct*2.0
            ELSE 1.5 + noise1*0.4 + sensor_drift END,
        CASE WHEN missing_rnd < 0.002 THEN NULL
            WHEN failure_mode = ''bearing_wear'' THEN 1.8 + noise2*0.4 + degradation_pct*6.0*(1+degradation_pct*0.5)
            WHEN failure_mode = ''misalignment'' THEN 2.2 + noise2*0.5 + degradation_pct*6.5 + degradation_pct*COS(timeline_pct*200)*2.5
            WHEN failure_mode = ''imbalance'' THEN 1.5 + noise2*0.3 + degradation_pct*7.0*(1+degradation_pct)
            ELSE 1.3 + noise2*0.35 END,
        CASE WHEN missing_rnd < 0.002 THEN NULL
            WHEN failure_mode = ''bearing_wear'' THEN 1.5 + noise3*0.3 + degradation_pct*4.0
            WHEN failure_mode = ''misalignment'' THEN 2.0 + noise3*0.5 + degradation_pct*5.5
            WHEN failure_mode = ''imbalance'' THEN 1.2 + noise3*0.25 + degradation_pct*1.5
            ELSE 1.1 + noise3*0.3 END,
        CASE WHEN missing_rnd < 0.001 THEN NULL
            WHEN failure_mode = ''thermal_degradation'' THEN rated_temp_max*0.55 + noise1*2.0 + degradation_pct*rated_temp_max*0.40*(1+degradation_pct*0.3) + SIN(timeline_pct*48)*3.0
            WHEN failure_mode = ''bearing_wear'' THEN rated_temp_max*0.50 + noise1*1.5 + degradation_pct*rated_temp_max*0.15
            ELSE rated_temp_max*0.50 + noise1*2.0 + SIN(timeline_pct*48)*2.5 END,
        CASE WHEN failure_mode = ''imbalance'' THEN rated_rpm*(1.0 + noise1*0.005 - degradation_pct*0.08)
            ELSE rated_rpm*(1.0 + noise1*0.003) END,
        CASE WHEN failure_mode = ''bearing_wear'' THEN 6.5+noise2*0.2+degradation_pct*1.5 ELSE 6.0+noise2*0.2 END,
        CASE WHEN failure_mode = ''misalignment'' THEN 12.0 + noise3*0.5 + degradation_pct*8.0*(1+degradation_pct)
            WHEN failure_mode = ''bearing_wear'' THEN 11.5 + noise3*0.4 + degradation_pct*3.0
            ELSE 10.5 + noise3*0.4 END,
        CASE WHEN failure_mode = ''bearing_wear'' THEN 72 + noise1*2.0 + degradation_pct*18.0 + CASE WHEN degradation_pct > 0.7 THEN ABS(noise2)*8.0 ELSE 0 END
            WHEN failure_mode = ''misalignment'' THEN 70 + noise1*1.5 + degradation_pct*12.0
            ELSE 65 + noise1*2.0 END
    FROM combined WHERE missing_rnd > 0.003;
    SELECT COUNT(*) INTO :row_count FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS;
    RETURN ''Generated '' || :row_count || '' sensor readings'';
END;
';

-- Uncomment and run to generate sensor data:
-- CALL MFGPULSE_DB.RAW_OT.GENERATE_SENSOR_DATA();


-- ============================================================================
-- PHASE 10: UDFs, PROCEDURES, DYNAMIC TABLES, VIEWS
-- ============================================================================
-- Full executable DDL for all derived objects.
-- These are deployed in dependency order:
--   1. ML_FEATURES views (training views)
--   2. ML_MODELS UDFs (5)
--   3. ML_MODELS procedures (3)
--   4. ML_MODELS LIVE_PREDICTIONS DT
--   5. ANALYTICS DTs (2)
--   6. ANALYTICS views (8)
--   7. ANALYTICS procedures (6)
--   8. Notification procedures (2)
-- ============================================================================

-- For cross-instance deployment, run: sql/ddl_objects.sql
-- That file contains the full CREATE OR REPLACE statements for all objects.
-- It was extracted from the deployed database and is self-contained.
--
-- Alternatively, to extract DDL from the CURRENT deployed instance into a new
-- target, run these GET_DDL statements and execute the returned SQL:

-- CURATED DYNAMIC TABLES (3)
SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.CURATED.SENSOR_WITH_CONTEXT');
SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.CURATED.ASSET_HEALTH_CURRENT');
SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.CURATED.FAILURE_HISTORY');

-- ML_FEATURES DYNAMIC TABLES (7)
SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.ML_FEATURES.LABELED_DATA');
SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.ML_FEATURES.ROLLING_STATS');
SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS');
SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.ML_FEATURES.TEMPORAL_MEMORY');
SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.ML_FEATURES.CROSS_DOMAIN');
SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE');
SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.ML_FEATURES.FLEET_COMPARISON');

-- ML_FEATURES VIEWS (11)
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ML_FEATURES.ALL_DERIVED_FEATURES');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ML_FEATURES.ALL_DERIVED_FEATURES_INFERENCE');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ML_FEATURES.FEATURE_CATALOG');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ML_FEATURES.HEALTHY_DERIVED_FEATURES');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ML_FEATURES.HEALTHY_DERIVED_FEATURES_TRAIN');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ML_FEATURES.TRAIN_FAILURE_MODE');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ML_FEATURES.TRAIN_RUL');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ML_FEATURES.TRAIN_TRAJECTORY');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ML_FEATURES.TRAIN_TRAJECTORY_3CLASS');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ML_FEATURES.TRAIN_ANOMALY');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ML_FEATURES.TRAIN_ANOMALY_SMALL');

-- ML_MODELS UDFs (5)
SELECT GET_DDL('FUNCTION', 'MFGPULSE_DB.ML_MODELS.PREDICT_FAILURE_MODE(FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT)');
SELECT GET_DDL('FUNCTION', 'MFGPULSE_DB.ML_MODELS.PREDICT_RUL(FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT)');
SELECT GET_DDL('FUNCTION', 'MFGPULSE_DB.ML_MODELS.PREDICT_DEGRADATION_STAGE(FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT)');
SELECT GET_DDL('FUNCTION', 'MFGPULSE_DB.ML_MODELS.COMPUTE_FATIGUE_SCORE(FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT)');
SELECT GET_DDL('FUNCTION', 'MFGPULSE_DB.ML_MODELS.SIMULATE_FAILURE_TWIN(FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT)');

-- ML_MODELS PROCEDURES (3)
SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.ML_MODELS.ANALYZE_ROOT_CAUSE(VARCHAR,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,VARCHAR,FLOAT,VARCHAR)');
SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.ML_MODELS.PRESCRIBE_MAINTENANCE(VARCHAR,VARCHAR,FLOAT,VARCHAR,FLOAT,VARCHAR,VARCHAR)');
SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.ML_MODELS.PREDICT_ALL(VARCHAR)');

-- ML_MODELS DYNAMIC TABLE (1)
SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS');

-- ANALYTICS DYNAMIC TABLES (2)
SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.ANALYTICS.ACTIVE_ALERTS');
SELECT GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.ANALYTICS.OEE_METRICS');

-- ANALYTICS VIEWS (6)
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ANALYTICS.COST_IMPACT');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ANALYTICS.COST_IMPACT_BY_ASSET');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ANALYTICS.EXECUTIVE_SUMMARY');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ANALYTICS.PREDICTIONS_WITH_COST');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ANALYTICS.SHIFT_HANDOVER_VIEW');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ANALYTICS.ALERT_SUMMARY');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ANALYTICS.PARTS_AVAILABLE_TO_PROMISE');
SELECT GET_DDL('VIEW', 'MFGPULSE_DB.ANALYTICS.PROCUREMENT_RECOMMENDATIONS');

-- ANALYTICS PROCEDURES (6)
SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.ANALYTICS.GENERATE_WORK_ORDER(VARCHAR,VARCHAR,VARCHAR,VARCHAR,FLOAT)');
SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.ANALYTICS.AUTO_GENERATE_WORK_ORDERS()');
SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.ANALYTICS.GENERATE_SHIFT_HANDOVER_SUMMARY()');
SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.ANALYTICS.RESERVE_PART_FOR_WORK_ORDER(VARCHAR,VARCHAR,VARCHAR,NUMBER,DATE)');
SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.ANALYTICS.GENERATE_PURCHASE_ORDER(VARCHAR,VARCHAR,NUMBER,DATE,VARCHAR,VARCHAR)');
SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.ANALYTICS.AUTO_GENERATE_PURCHASE_ORDERS()');

-- NOTIFICATION PROCEDURES (2)
SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.RAW_IT.SEND_MFGPULSE_EMAIL(VARCHAR,VARCHAR,VARCHAR)');
SELECT GET_DDL('PROCEDURE', 'MFGPULSE_DB.RAW_IT.LOG_APP_NOTIFICATION(VARCHAR,VARCHAR,VARCHAR,VARCHAR)');


-- ============================================================================
-- PHASE 13: CORTEX SEARCH SERVICE
-- ============================================================================

CREATE OR REPLACE CORTEX SEARCH SERVICE ML_MODELS.MAINTENANCE_SEARCH
    ON search_text
    ATTRIBUTES asset_id, wo_type
    WAREHOUSE = COMPUTE_WH
    TARGET_LAG = '1 day'
    AS (
        SELECT
            ml.LOG_ID AS doc_id,
            ml.ASSET_ID,
            wo.WO_TYPE,
            CONCAT(
                'Asset: ', am.ASSET_NAME, ' (', ml.ASSET_ID, '). ',
                'Work order: ', ml.WO_ID, ' [', wo.WO_TYPE, ', ', wo.PRIORITY, ']. ',
                'Date: ', ml.TIMESTAMP::VARCHAR, '. ',
                'Technician: ', ml.TECHNICIAN, '. ',
                'Notes: ', ml.NOTES_TEXT
            ) AS search_text
        FROM RAW_IT.MAINTENANCE_LOGS ml
        JOIN RAW_OT.ASSET_MASTER am ON ml.ASSET_ID = am.ASSET_ID
        LEFT JOIN RAW_IT.WORK_ORDERS wo ON ml.WO_ID = wo.WO_ID
    );


-- ============================================================================
-- PHASE 14: AUTOMATION — Task DAG (all on MFGPULSE_AUTOMATION_WH)
-- Full DAG DDL with procedures is in sql/14_automation.sql.
-- Below is a minimal deployment that creates the DAG structure.
-- For full procedure bodies, run sql/14_automation.sql or sql/ddl_objects.sql.
-- ============================================================================

-- DAG chain: Simulate → Fatigue → DT Refresh → WO Gen → PO Gen → PPO Convert

CREATE OR REPLACE TASK ANALYTICS.MFGPULSE_AUTOMATION_DAG
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    SCHEDULE = '720 MINUTE'
    SUSPEND_TASK_AFTER_NUM_FAILURES = 2
AS CALL MFGPULSE_DB.RAW_OT.SIMULATE_ALL_FEEDS_RANDOM();

CREATE OR REPLACE TASK ANALYTICS.DAG_REFRESH_FATIGUE
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.MFGPULSE_AUTOMATION_DAG
AS CALL MFGPULSE_DB.ML_MODELS.REFRESH_FATIGUE_SCORES();

CREATE OR REPLACE TASK ANALYTICS.DAG_REFRESH_DTS
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.DAG_REFRESH_FATIGUE
AS CALL MFGPULSE_DB.ANALYTICS.REFRESH_ALL_DTS();

CREATE OR REPLACE TASK ANALYTICS.DAG_GENERATE_WOS
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.DAG_REFRESH_DTS
AS CALL MFGPULSE_DB.ANALYTICS.AUTO_GENERATE_WORK_ORDERS();

CREATE OR REPLACE TASK ANALYTICS.DAG_GENERATE_POS
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.DAG_GENERATE_WOS
AS CALL MFGPULSE_DB.ANALYTICS.AUTO_GENERATE_PURCHASE_ORDERS();

CREATE OR REPLACE TASK ANALYTICS.DAG_CONVERT_PPOS
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.DAG_GENERATE_POS
AS CALL MFGPULSE_DB.ANALYTICS.AUTO_CONVERT_PLANNED_POS();

-- Note: Root task created SUSPENDED. To start the DAG:
-- 1. Resume children (bottom-up): DAG_CONVERT_PPOS, DAG_GENERATE_POS, DAG_GENERATE_WOS, DAG_REFRESH_DTS, DAG_REFRESH_FATIGUE
-- 2. Resume root: ALTER TASK ANALYTICS.MFGPULSE_AUTOMATION_DAG RESUME;


-- ============================================================================
-- PHASE 15: NOTIFICATION INTEGRATION
-- ============================================================================

CREATE NOTIFICATION INTEGRATION IF NOT EXISTS MFGPULSE_EMAIL
    TYPE = EMAIL
    ENABLED = TRUE;


-- ============================================================================
-- PHASE 16: FATIGUE SCORES (run after DTs and UDFs are created)
-- ============================================================================
-- NOTE: This INSERT requires ML_FEATURES DTs and COMPUTE_FATIGUE_SCORE UDF
-- to exist. Run only after Phases 6-12 are complete.

-- INSERT INTO ML_MODELS.FATIGUE_SCORES (ASSET_ID, TIMESTAMP, FATIGUE_SCORE, FATIGUE_LEVEL)
-- SELECT rs.asset_id, rs.timestamp,
--     ML_MODELS.COMPUTE_FATIGUE_SCORE(
--         rs.vib_crest_factor_6h, rs.vib_coeff_var_6h, rs.vib_peak_to_peak_6h,
--         rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
--         si.acoustic_vib_ratio, pc.stress_index,
--         COALESCE(si.vib_xy_correlation_daily, 0),
--         COALESCE(si.acoustic_vib_ratio, 0)
--     ) AS fatigue_score,
--     CASE
--         WHEN ML_MODELS.COMPUTE_FATIGUE_SCORE(
--             rs.vib_crest_factor_6h, rs.vib_coeff_var_6h, rs.vib_peak_to_peak_6h,
--             rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
--             si.acoustic_vib_ratio, pc.stress_index,
--             COALESCE(si.vib_xy_correlation_daily, 0),
--             COALESCE(si.acoustic_vib_ratio, 0)
--         ) > 0.8 THEN 'critical'
--         WHEN ML_MODELS.COMPUTE_FATIGUE_SCORE(
--             rs.vib_crest_factor_6h, rs.vib_coeff_var_6h, rs.vib_peak_to_peak_6h,
--             rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
--             si.acoustic_vib_ratio, pc.stress_index,
--             COALESCE(si.vib_xy_correlation_daily, 0),
--             COALESCE(si.acoustic_vib_ratio, 0)
--         ) > 0.5 THEN 'high'
--         WHEN ML_MODELS.COMPUTE_FATIGUE_SCORE(
--             rs.vib_crest_factor_6h, rs.vib_coeff_var_6h, rs.vib_peak_to_peak_6h,
--             rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
--             si.acoustic_vib_ratio, pc.stress_index,
--             COALESCE(si.vib_xy_correlation_daily, 0),
--             COALESCE(si.acoustic_vib_ratio, 0)
--         ) > 0.25 THEN 'accumul'
--         ELSE 'healthy'
--     END
-- FROM ML_FEATURES.ROLLING_STATS rs
-- LEFT JOIN ML_FEATURES.SENSOR_INTERACTIONS si ON rs.asset_id = si.asset_id AND rs.timestamp = si.timestamp
-- LEFT JOIN ML_FEATURES.PHYSICS_COMPOSITE pc ON rs.asset_id = pc.asset_id AND rs.timestamp = pc.timestamp
-- WHERE MOD(ROW_NUMBER() OVER (PARTITION BY rs.asset_id ORDER BY rs.timestamp), 25) = 0;


-- ============================================================================
-- PHASE 17: CORTEX AGENT (deploy from cortex_project/ directory)
-- ============================================================================
-- Deploy Semantic View and Agent using CoCo or Snowsight UI:
--   cortex agent-studio sv-deploy cortex_project/MAINTENANCE_SEMANTIC_VIEW.sv.yaml
--   cortex agent-studio agent-deploy cortex_project/MAINTENANCE_COPILOT_agent.yaml
-- Targets:
--   MFGPULSE_DB.AGENT.MAINTENANCE_SEMANTIC_VIEW (6 tables, 17 VQRs)
--   MFGPULSE_DB.AGENT.MAINTENANCE_COPILOT (5 tools)


-- ============================================================================
-- PHASE 18: VALIDATION
-- ============================================================================

-- Schema existence
SELECT 'SCHEMA' AS OBJ_TYPE, SCHEMA_NAME, 'PASS' AS STATUS
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME IN ('RAW_OT','RAW_IT','CURATED','ML_FEATURES','ML_MODELS','ANALYTICS','AGENT')
ORDER BY SCHEMA_NAME;

-- Row counts
SELECT TABLE_NAME, CNT,
    CASE
        WHEN TABLE_NAME = 'ASSET_MASTER' AND CNT = 10 THEN 'PASS'
        WHEN TABLE_NAME = 'SENSOR_READINGS' AND CNT > 170000 THEN 'PASS'
        WHEN TABLE_NAME = 'WORK_ORDERS' AND CNT >= 22 THEN 'PASS'
        WHEN TABLE_NAME = 'MAINTENANCE_LOGS' AND CNT >= 26 THEN 'PASS'
        WHEN TABLE_NAME = 'MODEL_REGISTRY' AND CNT = 12 THEN 'PASS'
        ELSE 'CHECK'
    END AS STATUS
FROM (
    SELECT 'ASSET_MASTER' AS TABLE_NAME, COUNT(*) AS CNT FROM RAW_OT.ASSET_MASTER
    UNION ALL SELECT 'SENSOR_READINGS', COUNT(*) FROM RAW_OT.SENSOR_READINGS
    UNION ALL SELECT 'WORK_ORDERS', COUNT(*) FROM RAW_IT.WORK_ORDERS
    UNION ALL SELECT 'MAINTENANCE_LOGS', COUNT(*) FROM RAW_IT.MAINTENANCE_LOGS
    UNION ALL SELECT 'MODEL_REGISTRY', COUNT(*) FROM ML_MODELS.MODEL_REGISTRY
) t ORDER BY TABLE_NAME;

-- ML pipeline
SELECT 'LIVE_PREDICTIONS' AS OBJ, COUNT(*) AS CNT, CASE WHEN COUNT(*)=10 THEN 'PASS' ELSE 'FAIL' END AS STATUS FROM ML_MODELS.LIVE_PREDICTIONS
UNION ALL SELECT 'FATIGUE_SCORES', COUNT(*), CASE WHEN COUNT(*)>0 THEN 'PASS' ELSE 'FAIL' END FROM ML_MODELS.FATIGUE_SCORES
UNION ALL SELECT 'ANOMALY_SCORES', COUNT(*), CASE WHEN COUNT(*)>0 THEN 'PASS' ELSE 'FAIL' END FROM ML_MODELS.ANOMALY_SCORES;

-- Final summary
SELECT
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME IN ('RAW_OT','RAW_IT','CURATED','ML_FEATURES','ML_MODELS','ANALYTICS','AGENT')) AS SCHEMAS,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','PUBLIC')) AS TABLES_AND_DTS,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='VIEW' AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','PUBLIC')) AS VIEWS,
    (SELECT COUNT(*) FROM RAW_OT.SENSOR_READINGS) AS SENSOR_READINGS,
    (SELECT COUNT(*) FROM ML_MODELS.LIVE_PREDICTIONS) AS PREDICTIONS,
    (SELECT COUNT(*) FROM ANALYTICS.ACTIVE_ALERTS) AS ALERTS,
    (SELECT COUNT(*) FROM ML_MODELS.MODEL_REGISTRY) AS ML_MODELS_REG,
    (SELECT COUNT(*) FROM RAW_IT.USERS WHERE ACTIVE=TRUE) AS ACTIVE_USERS;

-- Expected: 7 schemas, 32 base tables, 24 views, 13 DTs, 6 DAG tasks, 17 procedures,
-- 5 UDFs, 3 streams, 1 Cortex Search, 2 warehouses, 3 resource monitors


-- ============================================================================
-- TEARDOWN (uncomment only if you want to remove everything)
-- ============================================================================
-- DROP DATABASE IF EXISTS MFGPULSE_DB CASCADE;
-- DROP WAREHOUSE IF EXISTS COMPUTE_WH;
-- DROP WAREHOUSE IF EXISTS MFGPULSE_AUTOMATION_WH;
-- DROP RESOURCE MONITOR IF EXISTS MFGPULSE_CREDIT_GUARD;
-- DROP RESOURCE MONITOR IF EXISTS MFGPULSE_AUTOMATION_GUARD;
-- DROP NOTIFICATION INTEGRATION IF EXISTS MFGPULSE_EMAIL;
