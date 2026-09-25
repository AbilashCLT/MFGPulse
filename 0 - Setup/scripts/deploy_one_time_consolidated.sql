-- Fix HOURS_SINCE_FIRST_BREACH all-NULL error for thermal degradation assets by coalescing to 0
-- Co-authored with CoCo
-- ============================================================================
-- MFGPulse AI: CONSOLIDATED One-Time Deployment Script
-- ============================================================================
-- Fully self-contained. No external file references.
-- Run top-to-bottom in Snowsight with ACCOUNTADMIN role.
-- Creates: 1 DB, 7 schemas, 3 WHs, 23+ tables, 13 DTs, 30+ views,
--          5 UDFs, 21+ procs, 10 DAG tasks, 1 Cortex Search service,
--          1 Semantic View, 1 Cortex Agent, + all seed data (~175K+ rows).
-- Estimated: ~15-25 min, ~1-2 credits (XS warehouses).
--
-- MIGRATION PREREQUISITES:
--   1. ACCOUNTADMIN role required (resource monitors, notification integrations, ACCOUNT_USAGE)
--   2. Cortex AI functions enabled (COMPLETE, SEARCH_PREVIEW) — LLM models: llama3.1-70b, llama3.3-70b
--   3. Cortex Search service enabled
--   4. Cortex Agents enabled
--   5. Snowflake ML (Classification, Forecast, Anomaly Detection) — requires Enterprise edition+
--   6. Snowpark-optimized warehouse support (Enterprise edition+)
--   7. To change database name: global find-replace MFGPULSE_DB → YOUR_DB_NAME
--   8. Streamlit app (MFGPulse_AI_App/) must be deployed separately via Snowsight Workspaces
-- ============================================================================
/*
USE ROLE ACCOUNTADMIN;


-- ============================================================================
-- CHECKPOINT 0: DEPLOYMENT LOG
-- ============================================================================

CREATE DATABASE IF NOT EXISTS MFGPULSE_DB;
USE DATABASE MFGPULSE_DB;

CREATE OR REPLACE TABLE PUBLIC.DEPLOYMENT_LOG (
    CHECKPOINT_ID INT, CHECKPOINT_NAME VARCHAR(100),
    STARTED_AT TIMESTAMP_NTZ, COMPLETED_AT TIMESTAMP_NTZ, DURATION_SEC FLOAT,
    OBJECTS_CREATED INT, VALIDATION VARCHAR(20), DETAILS VARCHAR(2000));

INSERT INTO PUBLIC.DEPLOYMENT_LOG VALUES (0,'DEPLOYMENT_LOG_CREATED',CURRENT_TIMESTAMP(),CURRENT_TIMESTAMP(),0,1,'PASS','Log table created');


-- ============================================================================
-- CHECKPOINT 1: INFRASTRUCTURE
-- ============================================================================

CREATE SCHEMA IF NOT EXISTS RAW_OT;
CREATE SCHEMA IF NOT EXISTS RAW_IT;
CREATE SCHEMA IF NOT EXISTS CURATED;
CREATE SCHEMA IF NOT EXISTS ML_FEATURES;
CREATE SCHEMA IF NOT EXISTS ML_MODELS;
CREATE SCHEMA IF NOT EXISTS ANALYTICS;
CREATE SCHEMA IF NOT EXISTS AGENT;

CREATE WAREHOUSE IF NOT EXISTS COMPUTE_WH WAREHOUSE_SIZE='XSMALL' AUTO_SUSPEND=60 AUTO_RESUME=TRUE INITIALLY_SUSPENDED=TRUE;
CREATE RESOURCE MONITOR IF NOT EXISTS MFGPULSE_CREDIT_GUARD WITH CREDIT_QUOTA=250 FREQUENCY=MONTHLY START_TIMESTAMP=IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY ON 90 PERCENT DO NOTIFY ON 100 PERCENT DO SUSPEND;
ALTER WAREHOUSE COMPUTE_WH SET RESOURCE_MONITOR = MFGPULSE_CREDIT_GUARD;

CREATE WAREHOUSE IF NOT EXISTS MFGPULSE_AUTOMATION_WH WAREHOUSE_SIZE='XSMALL' AUTO_SUSPEND=60 AUTO_RESUME=TRUE INITIALLY_SUSPENDED=TRUE;
CREATE OR REPLACE RESOURCE MONITOR MFGPULSE_AUTOMATION_GUARD WITH CREDIT_QUOTA=50 FREQUENCY=MONTHLY START_TIMESTAMP=IMMEDIATELY
  TRIGGERS ON 75 PERCENT DO NOTIFY ON 90 PERCENT DO SUSPEND ON 100 PERCENT DO SUSPEND_IMMEDIATE;
ALTER WAREHOUSE MFGPULSE_AUTOMATION_WH SET RESOURCE_MONITOR = MFGPULSE_AUTOMATION_GUARD;


-- ============================================================================
-- CHECKPOINT 2: BASE TABLES
-- ============================================================================

CREATE OR REPLACE TABLE RAW_OT.ASSET_MASTER (
    ASSET_ID VARCHAR(20) NOT NULL PRIMARY KEY, ASSET_NAME VARCHAR(100) NOT NULL,
    ASSET_TYPE VARCHAR(50) NOT NULL, LINE_ID VARCHAR(20) NOT NULL,
    INSTALL_DATE DATE, MANUFACTURER VARCHAR(100), MODEL_NUMBER VARCHAR(50),
    RATED_RPM FLOAT, RATED_TEMP_MAX FLOAT);
CREATE OR REPLACE TABLE RAW_OT.SENSOR_METADATA (
    SENSOR_ID VARCHAR(30) NOT NULL PRIMARY KEY, ASSET_ID VARCHAR(20) NOT NULL,
    SENSOR_TYPE VARCHAR(50) NOT NULL, LOCATION VARCHAR(100), CALIBRATION_DATE DATE, SAMPLING_RATE_HZ FLOAT);
CREATE OR REPLACE TABLE RAW_OT.SENSOR_READINGS (
    READING_ID NUMBER AUTOINCREMENT, ASSET_ID VARCHAR(20) NOT NULL,
    TIMESTAMP TIMESTAMP_NTZ NOT NULL, VIBRATION_X FLOAT, VIBRATION_Y FLOAT, VIBRATION_Z FLOAT,
    TEMPERATURE FLOAT, RPM FLOAT, PRESSURE FLOAT, CURRENT_AMPS FLOAT, ACOUSTIC_DB FLOAT,
    INGESTION_TS TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP());
CREATE OR REPLACE TABLE RAW_OT.AMBIENT_CONDITIONS (
    READING_DATE DATE NOT NULL, AMBIENT_TEMP_C FLOAT, HUMIDITY_PCT FLOAT, BAROMETRIC_PRESSURE_HPA FLOAT);
CREATE OR REPLACE TABLE RAW_IT.WORK_ORDERS (
    WO_ID VARCHAR(50) NOT NULL PRIMARY KEY, ASSET_ID VARCHAR(20) NOT NULL, WO_TYPE VARCHAR(20) NOT NULL,
    CREATED_DATE TIMESTAMP_NTZ NOT NULL, COMPLETED_DATE TIMESTAMP_NTZ, PRIORITY VARCHAR(10), STATUS VARCHAR(20),
    ASSIGNED_TO VARCHAR(100), LABOR_HOURS FLOAT, PARTS_COST FLOAT, TOTAL_COST FLOAT,
    ROOT_CAUSE_CONFIRMED VARCHAR, PART_USED BOOLEAN DEFAULT TRUE);
CREATE OR REPLACE TABLE RAW_IT.MAINTENANCE_LOGS (
    LOG_ID VARCHAR(20) NOT NULL PRIMARY KEY, WO_ID VARCHAR(20), ASSET_ID VARCHAR(20) NOT NULL,
    TIMESTAMP TIMESTAMP_NTZ NOT NULL, TECHNICIAN VARCHAR(100), NOTES_TEXT VARCHAR(2000));
CREATE OR REPLACE TABLE RAW_IT.PRODUCTION_OUTPUT (
    RECORD_ID VARCHAR(20) NOT NULL PRIMARY KEY, ASSET_ID VARCHAR(20) NOT NULL, SHIFT_ID VARCHAR(20),
    TIMESTAMP TIMESTAMP_NTZ NOT NULL, UNITS_PRODUCED INT, GOOD_UNITS INT, IDEAL_CYCLE_TIME_SEC FLOAT);
CREATE OR REPLACE TABLE RAW_IT.SHIFT_SCHEDULE (
    SHIFT_ID VARCHAR(20) NOT NULL PRIMARY KEY, LINE_ID VARCHAR(20) NOT NULL,
    SHIFT_START TIMESTAMP_NTZ NOT NULL, SHIFT_END TIMESTAMP_NTZ NOT NULL,
    OPERATOR_NAME VARCHAR(100), PLANNED_PRODUCTION_TIME_MINS INT);
CREATE OR REPLACE TABLE RAW_IT.PARTS_INVENTORY (
    PART_ID VARCHAR(20) NOT NULL PRIMARY KEY, PART_NAME VARCHAR(200) NOT NULL,
    COMPATIBLE_ASSETS ARRAY, QUANTITY_ON_HAND INT, LEAD_TIME_DAYS INT, UNIT_COST FLOAT);
CREATE OR REPLACE TABLE RAW_IT.USERS (
    USER_ID VARCHAR(20) NOT NULL PRIMARY KEY, USERNAME VARCHAR(100) NOT NULL, EMAIL VARCHAR(200),
    PERSONA VARCHAR(50) NOT NULL, ROLE VARCHAR(50), LINE_ID VARCHAR(20),
    ACTIVE BOOLEAN DEFAULT TRUE, CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP());
CREATE OR REPLACE TABLE RAW_IT.SUPPLIERS (
    SUPPLIER_ID VARCHAR(20) NOT NULL PRIMARY KEY, SUPPLIER_NAME VARCHAR(200) NOT NULL,
    CONTACT_EMAIL VARCHAR(200), PHONE VARCHAR(50), ACTIVE BOOLEAN DEFAULT TRUE,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP());
CREATE OR REPLACE TABLE RAW_IT.PART_SUPPLIERS (
    PART_ID VARCHAR(20) NOT NULL, SUPPLIER_ID VARCHAR(20) NOT NULL, SUPPLIER_PART_NUMBER VARCHAR(50),
    STANDARD_LEAD_TIME_DAYS INT DEFAULT 7, EXPEDITE_LEAD_TIME_DAYS INT DEFAULT 3,
    MIN_ORDER_QTY INT DEFAULT 1, UNIT_COST FLOAT, PREFERRED_SUPPLIER BOOLEAN DEFAULT FALSE);
CREATE OR REPLACE TABLE RAW_IT.PART_RESERVATIONS (
    RESERVATION_ID VARCHAR(50) NOT NULL PRIMARY KEY, PART_ID VARCHAR(20) NOT NULL, ASSET_ID VARCHAR(20) NOT NULL,
    WO_ID VARCHAR(50), QUANTITY_RESERVED INT DEFAULT 1, REQUIRED_BY_DATE DATE,
    STATUS VARCHAR(20) DEFAULT 'active', CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP());
CREATE OR REPLACE TABLE RAW_IT.FAILURE_MODE_BOM (
    ASSET_TYPE VARCHAR(50) NOT NULL, FAILURE_MODE VARCHAR(50) NOT NULL,
    PART_ID VARCHAR(20) NOT NULL, QTY_PER_REPAIR INT NOT NULL DEFAULT 1,
    NOTES VARCHAR(200));
CREATE OR REPLACE TABLE RAW_IT.INVENTORY_TRANSACTIONS (
    TXN_ID VARCHAR(50) NOT NULL, PART_ID VARCHAR(20) NOT NULL,
    QTY_CHANGE INT NOT NULL, TXN_TYPE VARCHAR(20) NOT NULL,
    REFERENCE_ID VARCHAR(50), ASSET_ID VARCHAR(20),
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CREATED_BY VARCHAR(100) DEFAULT 'SYSTEM');
CREATE OR REPLACE TABLE RAW_IT.PURCHASE_ORDERS (
    PO_ID VARCHAR(50) NOT NULL PRIMARY KEY, SUPPLIER_ID VARCHAR(20),
    CREATED_DATE TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), REQUIRED_BY_DATE DATE, EXPECTED_ARRIVAL_DATE DATE,
    STATUS VARCHAR(30) DEFAULT 'draft', PRIORITY VARCHAR(20) DEFAULT 'NORMAL', TOTAL_COST FLOAT,
    CREATED_BY VARCHAR(100) DEFAULT 'SYSTEM', SOURCE VARCHAR(30) DEFAULT 'prediction',
    REJECTION_REASON VARCHAR, REJECTED_BY VARCHAR, REJECTED_AT TIMESTAMP_NTZ);
CREATE OR REPLACE TABLE RAW_IT.PURCHASE_ORDER_LINES (
    PO_LINE_ID VARCHAR(50) NOT NULL PRIMARY KEY, PO_ID VARCHAR(50) NOT NULL, PART_ID VARCHAR(20) NOT NULL,
    ASSET_ID VARCHAR(20), WO_ID VARCHAR(50), QUANTITY_ORDERED INT DEFAULT 1, UNIT_COST FLOAT, LINE_COST FLOAT,
    RUL_HOURS_AT_ORDER FLOAT, FAILURE_MODE_PRED VARCHAR(50), PROCUREMENT_RISK VARCHAR(30));
CREATE OR REPLACE TABLE RAW_IT.NOTIFICATION_SETTINGS (
    EVENT_TYPE VARCHAR(50) NOT NULL PRIMARY KEY, EVENT_LABEL VARCHAR(200),
    EMAIL_ENABLED BOOLEAN DEFAULT FALSE, IN_APP_ENABLED BOOLEAN DEFAULT TRUE,
    EMAIL_RECIPIENTS VARCHAR(1000) DEFAULT '', NOTIFY_PERSONAS VARCHAR(500), PRIORITY VARCHAR(20) DEFAULT 'NORMAL',
    UPDATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), UPDATED_BY VARCHAR(100) DEFAULT CURRENT_USER());
CREATE OR REPLACE TABLE RAW_IT.APP_NOTIFICATIONS (
    NOTIF_ID VARCHAR(200) NOT NULL PRIMARY KEY, EVENT_TYPE VARCHAR(50),
    PERSONA_TARGET VARCHAR(50), USERNAME_TARGET VARCHAR(100),
    TITLE VARCHAR(500), MESSAGE VARCHAR(2000), ENTITY_ID VARCHAR(100),
    PRIORITY VARCHAR(20) DEFAULT 'NORMAL', IS_READ BOOLEAN DEFAULT FALSE,
    DISMISSED BOOLEAN DEFAULT FALSE, CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP());
CREATE OR REPLACE TABLE RAW_IT.SIMULATION_CONFIG (
    CONFIG_ID INT AUTOINCREMENT PRIMARY KEY, ASSET_ID VARCHAR(20) NOT NULL,
    SCENARIO VARCHAR(30) NOT NULL, SEVERITY FLOAT DEFAULT 0.0, HOURS INT DEFAULT 12,
    STATUS VARCHAR(20) DEFAULT 'PENDING', ROWS_GENERATED INT DEFAULT 0,
    ESTIMATED_CREDITS FLOAT DEFAULT 0, CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CREATED_BY VARCHAR(100) DEFAULT CURRENT_USER(), COMPLETED_AT TIMESTAMP_NTZ);
CREATE OR REPLACE TABLE ML_MODELS.MODEL_REGISTRY (
    MODEL_NAME VARCHAR(100), MODEL_TYPE VARCHAR(100), TRAINING_DATA VARCHAR(200),
    PRECISION_SCORE FLOAT, RECALL_SCORE FLOAT, F1_SCORE FLOAT,
    TOP_FEATURES VARCHAR(500), TRAINED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP());
CREATE OR REPLACE TABLE ML_MODELS.FATIGUE_SCORES (
    ASSET_ID VARCHAR(20), TIMESTAMP TIMESTAMP_NTZ, FATIGUE_SCORE FLOAT, FATIGUE_LEVEL VARCHAR(20));
CREATE OR REPLACE TABLE ML_MODELS.ANOMALY_SCORES (
    SERIES VARIANT, TS TIMESTAMP_NTZ, Y FLOAT, FORECAST FLOAT, LOWER_BOUND FLOAT, UPPER_BOUND FLOAT,
    IS_ANOMALY BOOLEAN, PERCENTILE FLOAT, DISTANCE FLOAT);
CREATE OR REPLACE TABLE ANALYTICS.SHIFT_HANDOVER_HISTORY (
    GENERATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(), SUMMARY_TEXT TEXT, WOS_GENERATED INT,
    PLANT_OEE FLOAT, CRITICAL_ASSETS INT);
CREATE OR REPLACE TABLE ANALYTICS.KPI_SNAPSHOTS (
    SNAPSHOT_DATE DATE NOT NULL, PLANT_OEE FLOAT, CRITICAL_ASSETS NUMBER, WARNING_ASSETS NUMBER,
    HEALTHY_ASSETS NUMBER, TOTAL_COST_AVOIDED FLOAT, DOWNTIME_HOURS_PREVENTED FLOAT,
    MAINTENANCE_ROI_X FLOAT, TOTAL_ALERTS NUMBER, CRITICAL_ALERTS NUMBER,
    AVG_EARLY_DETECTION_DAYS FLOAT, TOTAL_MAINTENANCE_SPEND FLOAT,
    SNAPSHOT_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP());
CREATE OR REPLACE TABLE ANALYTICS.ALERT_HISTORY (
    ALERT_ID VARCHAR, ASSET_ID VARCHAR(20), ASSET_NAME VARCHAR(100), SEVERITY VARCHAR(10),
    ALERT_TYPE VARCHAR(20), MESSAGE VARCHAR, RUL_HOURS FLOAT, FAILURE_MODE_PRED VARCHAR(50),
    FATIGUE_SCORE FLOAT, CREATED_AT TIMESTAMP_NTZ,
    ARCHIVED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP());


-- ============================================================================
-- CHECKPOINT 3: STREAMS
-- ============================================================================

CREATE OR REPLACE STREAM RAW_OT.SENSOR_READINGS_STREAM ON TABLE RAW_OT.SENSOR_READINGS APPEND_ONLY = TRUE;
CREATE OR REPLACE STREAM RAW_IT.MAINTENANCE_LOGS_STREAM ON TABLE RAW_IT.MAINTENANCE_LOGS APPEND_ONLY = TRUE;
CREATE OR REPLACE STREAM RAW_IT.WORK_ORDERS_STREAM ON TABLE RAW_IT.WORK_ORDERS;


-- ============================================================================
-- CHECKPOINT 4: SEED DATA (idempotent: truncates before insert)
-- ============================================================================

-- 1. ASSET_MASTER (10 assets across 3 production lines)
TRUNCATE TABLE IF EXISTS RAW_OT.ASSET_MASTER;
INSERT INTO RAW_OT.ASSET_MASTER
    (ASSET_ID, ASSET_NAME, ASSET_TYPE, LINE_ID, INSTALL_DATE, MANUFACTURER, MODEL_NUMBER, RATED_RPM, RATED_TEMP_MAX)
VALUES
    ('ASSET_001', 'Compressor A1',  'compressor',       'LINE_01', '2021-03-15', 'Atlas Copco',        'GA-55-VSD',   3000, 105),
    ('ASSET_002', 'Compressor A2',  'compressor',       'LINE_01', '2022-06-10', 'Atlas Copco',        'GA-75-VSD',   3000, 110),
    ('ASSET_003', 'Pump P1',        'centrifugal_pump', 'LINE_01', '2020-11-22', 'Grundfos',           'CR-32-8',     1750, 90),
    ('ASSET_004', 'Pump P2',        'centrifugal_pump', 'LINE_02', '2021-08-05', 'Grundfos',           'CR-45-3',     1750, 95),
    ('ASSET_005', 'Motor M1',       'electric_motor',   'LINE_02', '2019-04-18', 'ABB',                'M3BP-315',    1500, 120),
    ('ASSET_006', 'Motor M2',       'electric_motor',   'LINE_02', '2020-01-30', 'ABB',                'M3BP-280',    1500, 115),
    ('ASSET_007', 'Fan F1',         'axial_fan',        'LINE_03', '2023-02-14', 'Howden',             'AXN-900',     1200, 80),
    ('ASSET_008', 'Gearbox G1',     'gearbox',          'LINE_03', '2021-09-25', 'Flender',            'SIG-300',      900, 100),
    ('ASSET_009', 'Conveyor C1',    'conveyor_drive',   'LINE_03', '2022-03-08', 'SEW-Eurodrive',      'MC-07B',       600, 85),
    ('ASSET_010', 'Turbine T1',     'steam_turbine',    'LINE_03', '2018-07-20', 'Siemens Energy',     'SST-060',     6000, 540);


-- 2. SENSOR_METADATA (23 sensors, 2-3 per asset)
TRUNCATE TABLE IF EXISTS RAW_OT.SENSOR_METADATA;
INSERT INTO RAW_OT.SENSOR_METADATA
    (SENSOR_ID, ASSET_ID, SENSOR_TYPE, LOCATION, CALIBRATION_DATE, SAMPLING_RATE_HZ)
VALUES
    ('SEN-001-VIB', 'ASSET_001', 'vibration_triaxial', 'Drive end bearing',       '2026-01-15', 1000),
    ('SEN-001-TMP', 'ASSET_001', 'temperature',        'Discharge manifold',      '2026-01-15', 1),
    ('SEN-001-PRS', 'ASSET_001', 'pressure',           'Discharge line',          '2026-01-15', 10),
    ('SEN-002-VIB', 'ASSET_002', 'vibration_triaxial', 'Drive end bearing',       '2026-02-10', 1000),
    ('SEN-002-TMP', 'ASSET_002', 'temperature',        'Discharge manifold',      '2026-02-10', 1),
    ('SEN-003-VIB', 'ASSET_003', 'vibration_triaxial', 'Impeller housing',        '2026-01-20', 1000),
    ('SEN-003-FLW', 'ASSET_003', 'flow_rate',          'Outlet pipe',             '2026-01-20', 10),
    ('SEN-004-VIB', 'ASSET_004', 'vibration_triaxial', 'Impeller housing',        '2025-12-05', 1000),
    ('SEN-004-TMP', 'ASSET_004', 'temperature',        'Seal chamber',            '2025-12-05', 1),
    ('SEN-005-VIB', 'ASSET_005', 'vibration_triaxial', 'Drive end bearing',       '2026-02-20', 1000),
    ('SEN-005-AMP', 'ASSET_005', 'current',            'Motor terminal box',      '2026-02-20', 100),
    ('SEN-006-VIB', 'ASSET_006', 'vibration_triaxial', 'Drive end bearing',       '2026-01-05', 1000),
    ('SEN-006-TMP', 'ASSET_006', 'temperature',        'Stator winding',          '2026-01-05', 1),
    ('SEN-007-VIB', 'ASSET_007', 'vibration_triaxial', 'Fan hub',                 '2026-03-01', 1000),
    ('SEN-007-ACO', 'ASSET_007', 'acoustic',           'Fan inlet',               '2026-03-01', 500),
    ('SEN-008-VIB', 'ASSET_008', 'vibration_triaxial', 'Input shaft bearing',     '2025-11-15', 1000),
    ('SEN-008-TMP', 'ASSET_008', 'temperature',        'Oil sump',                '2025-11-15', 1),
    ('SEN-008-ACO', 'ASSET_008', 'acoustic',           'Gear mesh zone',          '2025-11-15', 500),
    ('SEN-009-VIB', 'ASSET_009', 'vibration_triaxial', 'Drive pulley bearing',    '2026-02-01', 1000),
    ('SEN-009-AMP', 'ASSET_009', 'current',            'VFD output',              '2026-02-01', 100),
    ('SEN-010-VIB', 'ASSET_010', 'vibration_triaxial', 'Turbine front bearing',   '2025-10-20', 1000),
    ('SEN-010-TMP', 'ASSET_010', 'temperature',        'Exhaust casing',          '2025-10-20', 1),
    ('SEN-010-RPM', 'ASSET_010', 'tachometer',         'Shaft encoder',           '2025-10-20', 1000);


-- 3. USERS (9 users, 6 personas)
TRUNCATE TABLE IF EXISTS RAW_IT.USERS;
INSERT INTO RAW_IT.USERS
    (USER_ID, USERNAME, EMAIL, PERSONA, ROLE, LINE_ID, ACTIVE)
VALUES
    ('USR-001', 'Mike Torres',   'mike.torres@mfgpulse.io',   'TECHNICIAN',          'MAINTENANCE_TECH',  'LINE_01', TRUE),
    ('USR-002', 'Sarah Chen',    'sarah.chen@mfgpulse.io',    'TECHNICIAN',          'MAINTENANCE_TECH',  'LINE_02', TRUE),
    ('USR-003', 'James Wright',  'james.wright@mfgpulse.io',  'RELIABILITY_ENGINEER','RELIABILITY_ENG',   'LINE_01', TRUE),
    ('USR-004', 'Maria Garcia',  'maria.garcia@mfgpulse.io',  'SHIFT_SUPERVISOR',    'SHIFT_SUPER',       'LINE_02', TRUE),
    ('USR-005', 'David Kim',     'david.kim@mfgpulse.io',     'PLANT_MANAGER',       'PLANT_MGR',         NULL,      TRUE),
    ('USR-006', 'Lisa Patel',    'lisa.patel@mfgpulse.io',    'PROCUREMENT_ADMIN',   'PROCUREMENT',       NULL,      TRUE),
    ('USR-007', 'Alex Johnson',  'alex.johnson@mfgpulse.io',  'APP_ADMIN',           'ADMIN',             NULL,      TRUE),
    ('USR-008', 'Rachel Wu',     'rachel.wu@mfgpulse.io',     'TECHNICIAN',          'MAINTENANCE_TECH',  'LINE_03', TRUE),
    ('USR-009', 'Tom Baker',     'tom.baker@mfgpulse.io',     'RELIABILITY_ENGINEER','RELIABILITY_ENG',   'LINE_03', TRUE);


-- 4. PARTS_INVENTORY (15 parts with compatible asset arrays)
TRUNCATE TABLE IF EXISTS RAW_IT.PARTS_INVENTORY;
INSERT INTO RAW_IT.PARTS_INVENTORY
    (PART_ID, PART_NAME, COMPATIBLE_ASSETS, QUANTITY_ON_HAND, LEAD_TIME_DAYS, UNIT_COST)
SELECT 'PART-001','Bearing 6205-2RS',ARRAY_CONSTRUCT('ASSET_001','ASSET_002','ASSET_005','ASSET_006'),12,5,45.00
UNION ALL SELECT 'PART-002','Bearing 6308-ZZ',ARRAY_CONSTRUCT('ASSET_005','ASSET_006'),4,7,120.00
UNION ALL SELECT 'PART-003','Vibratory Seal Kit',ARRAY_CONSTRUCT('ASSET_001','ASSET_002'),8,3,15.00
UNION ALL SELECT 'PART-004','Oil Filter - Medium',ARRAY_CONSTRUCT('ASSET_001','ASSET_002','ASSET_008'),20,2,8.00
UNION ALL SELECT 'PART-005','V-Belt Kit',ARRAY_CONSTRUCT('ASSET_001','ASSET_002','ASSET_005','ASSET_006'),6,4,25.00
UNION ALL SELECT 'PART-006','Impeller - Centrifugal',ARRAY_CONSTRUCT('ASSET_003','ASSET_004'),2,14,850.00
UNION ALL SELECT 'PART-007','Mechanical Seal - Pump',ARRAY_CONSTRUCT('ASSET_003','ASSET_004'),3,10,320.00
UNION ALL SELECT 'PART-008','Roller Bearing NUP310',ARRAY_CONSTRUCT('ASSET_005','ASSET_006','ASSET_008'),5,6,95.00
UNION ALL SELECT 'PART-009','Heater Coil 3kW',ARRAY_CONSTRUCT('ASSET_006'),1,12,280.00
UNION ALL SELECT 'PART-010','Flexible Coupling',ARRAY_CONSTRUCT('ASSET_003','ASSET_004','ASSET_009'),4,5,180.00
UNION ALL SELECT 'PART-011','Bearing 6310-2RS',ARRAY_CONSTRUCT('ASSET_008','ASSET_009'),3,7,150.00
UNION ALL SELECT 'PART-012','Gear Set G1',ARRAY_CONSTRUCT('ASSET_008'),1,21,1200.00
UNION ALL SELECT 'PART-013','Conveyor Roller Set',ARRAY_CONSTRUCT('ASSET_009'),4,3,65.00
UNION ALL SELECT 'PART-014','Shaft Sleeve - Compressor',ARRAY_CONSTRUCT('ASSET_001','ASSET_002'),2,12,450.00
UNION ALL SELECT 'PART-015','Turbine Blade Set',ARRAY_CONSTRUCT('ASSET_010'),0,28,2200.00;


-- 5. MODEL_REGISTRY (12 models: 8 UDF/Proc + 4 native)
TRUNCATE TABLE IF EXISTS ML_MODELS.MODEL_REGISTRY;
INSERT INTO ML_MODELS.MODEL_REGISTRY
    (MODEL_NAME, MODEL_TYPE, TRAINING_DATA, PRECISION_SCORE, RECALL_SCORE, F1_SCORE, TOP_FEATURES)
VALUES
    ('M1_FAILURE_MODE_CLASSIFIER', 'UDF - Rule-Based Ensemble',
     'ML_FEATURES.ALL_DERIVED_FEATURES', 0.89, 0.86, 0.87,
     'vib_rms_6h, crest_factor_6h, vib_xy_correlation, temp_rpm_ratio, bearing_defect_indicator'),
    ('M2_RUL_ESTIMATOR', 'UDF - Physics-Informed Regression',
     'ML_FEATURES.ALL_DERIVED_FEATURES', 0.84, 0.81, 0.82,
     'vib_rms_24h, fatigue_score, composite_health_score, degradation_velocity_30d, stress_index'),
    ('M3_DEGRADATION_STAGER', 'UDF - Weighted Composite Scoring',
     'ML_FEATURES.ALL_DERIVED_FEATURES', 0.91, 0.88, 0.89,
     'composite_health_score, fatigue_score, vib_rms_6h, stress_index, iso_10816_velocity'),
    ('M4_FATIGUE_DETECTOR', 'UDF - Cumulative Damage Model',
     'ML_FEATURES.ALL_DERIVED_FEATURES', 0.87, 0.85, 0.86,
     'vib_rms_6h, temperature, stress_index, iso_10816_velocity, composite_health_score'),
    ('M5_ROOT_CAUSE_ANALYZER', 'Procedure - Cortex Search RAG + LLM',
     'ML_MODELS.MAINTENANCE_SEARCH', 0.82, 0.79, 0.80,
     'maintenance_history, sensor_anomalies, asset_type, failure_mode, work_order_context'),
    ('M6_DIGITAL_TWIN_SIMULATOR', 'UDF - Monte Carlo Simulation',
     'ML_FEATURES.ALL_DERIVED_FEATURES_INFERENCE', 0.85, 0.83, 0.84,
     'current_health, degradation_rate, stress_index, fatigue_score, rpm_deviation'),
    ('M7_MAINTENANCE_PRESCRIBER', 'Procedure - LLM Decision Engine',
     'ML_MODELS.LIVE_PREDICTIONS + RAW_IT.PARTS_INVENTORY', 0.80, 0.78, 0.79,
     'failure_mode, rul_hours, degradation_stage, fatigue_level, parts_availability'),
    ('N1_FAILURE_MODE_NATIVE', 'Snowflake Classification',
     'ML_FEATURES.TRAIN_FAILURE_MODE', 0.86, 0.83, 0.84,
     'vib_rms_6h, crest_factor_6h, temp_rpm_ratio, vib_xy_correlation, bearing_defect_indicator'),
    ('N2_DEGRADATION_STAGER_NATIVE', 'Snowflake Classification',
     'ML_FEATURES.TRAIN_TRAJECTORY_3CLASS', 0.84, 0.82, 0.83,
     'degradation_velocity_30d, trend_reversal_count, composite_health_score, fatigue_score, stress_index'),
    ('N3_RUL_FORECAST', 'Snowflake Forecast',
     'ML_FEATURES.TRAIN_RUL', 0.82, 0.80, 0.81,
     'composite_health_score, fatigue_score, degradation_velocity_30d, stress_index, vib_rms_24h'),
    ('M8_ANOMALY_SCORER', 'UDF - Statistical Anomaly Scoring',
     'ML_FEATURES.HEALTHY_DERIVED_FEATURES', 0.85, 0.82, 0.83,
     'vib_rms_6h, vib_crest_factor_24h, temp_rate_of_change, acoustic_vib_ratio, energy_balance_ratio'),
    ('N4_ANOMALY_DETECTOR', 'Snowflake Anomaly Detection',
     'ML_FEATURES.TRAIN_ANOMALY_SMALL', 0.88, 0.85, 0.86,
     'vib_rms_6h, vib_crest_factor_6h, stress_index, composite_health_score, current_rpm_ratio');


-- 6. WORK_ORDERS (22 orders: mix of emergency, corrective, preventive)
TRUNCATE TABLE IF EXISTS RAW_IT.WORK_ORDERS;
INSERT INTO RAW_IT.WORK_ORDERS
    (WO_ID, ASSET_ID, WO_TYPE, CREATED_DATE, COMPLETED_DATE, PRIORITY, STATUS, ASSIGNED_TO, LABOR_HOURS, PARTS_COST, TOTAL_COST, ROOT_CAUSE_CONFIRMED, PART_USED)
VALUES
    -- Emergency WOs (bearing failures, thermal events)
    ('WO-001', 'ASSET_001', 'emergency',  '2026-04-10 06:30:00', '2026-04-10 14:30:00', 'EMERGENCY', 'completed', 'Mike Torres',   8.0, 500, 1300, 'bearing_wear',           TRUE),
    ('WO-002', 'ASSET_002', 'emergency',  '2026-04-22 14:15:00', '2026-04-23 02:15:00', 'EMERGENCY', 'completed', 'Sarah Chen',    12.0, 750, 1950, 'thermal_degradation',    TRUE),
    ('WO-003', 'ASSET_005', 'emergency',  '2026-05-08 22:00:00', '2026-05-09 06:00:00', 'EMERGENCY', 'completed', 'Mike Torres',   8.0, 500, 1300, 'bearing_wear',           TRUE),
    ('WO-004', 'ASSET_004', 'emergency',  '2026-06-01 10:45:00', '2026-06-01 20:45:00', 'EMERGENCY', 'completed', 'James Wright',  10.0, 600, 1600, 'misalignment',           TRUE),
    -- Corrective WOs (detected early, scheduled fix)
    ('WO-005', 'ASSET_003', 'corrective', '2026-04-15 08:00:00', '2026-04-15 14:00:00', 'HIGH',      'completed', 'James Wright',  6.0, 450, 1050, 'imbalance',              TRUE),
    ('WO-006', 'ASSET_006', 'corrective', '2026-05-01 07:00:00', '2026-05-01 13:00:00', 'HIGH',      'completed', 'Sarah Chen',    6.0, 400, 1000, 'thermal_degradation',    TRUE),
    ('WO-007', 'ASSET_009', 'corrective', '2026-05-20 09:30:00', '2026-05-20 15:30:00', 'HIGH',      'completed', 'Maria Garcia',  6.0, 350, 950,  'misalignment',           TRUE),
    ('WO-008', 'ASSET_001', 'corrective', '2026-06-10 08:00:00', '2026-06-10 12:00:00', 'HIGH',      'completed', 'Mike Torres',   4.0, 300, 700,  'bearing_wear',           TRUE),
    ('WO-009', 'ASSET_008', 'corrective', '2026-06-15 07:00:00', '2026-06-15 15:00:00', 'HIGH',      'completed', 'Rachel Wu',     8.0, 600, 1400, 'imbalance',              TRUE),
    ('WO-010', 'ASSET_005', 'corrective', '2026-07-01 09:00:00', '2026-07-01 14:00:00', 'MEDIUM',    'completed', 'Mike Torres',   5.0, 400, 900,  'bearing_wear',           TRUE),
    ('WO-011', 'ASSET_007', 'preventive', '2026-04-01 06:00:00', '2026-04-01 10:00:00', 'LOW',       'completed', 'Rachel Wu',     4.0, 100, 500,  NULL,                     TRUE),
    ('WO-012', 'ASSET_010', 'preventive', '2026-04-15 06:00:00', '2026-04-15 14:00:00', 'LOW',       'completed', 'Tom Baker',     8.0, 200, 1000, NULL,                     TRUE),
    ('WO-013', 'ASSET_003', 'preventive', '2026-05-10 06:00:00', '2026-05-10 10:00:00', 'LOW',       'completed', 'James Wright',  4.0, 150, 550,  NULL,                     TRUE),
    ('WO-014', 'ASSET_002', 'preventive', '2026-05-25 06:00:00', '2026-05-25 10:00:00', 'LOW',       'completed', 'Sarah Chen',    4.0, 120, 520,  NULL,                     TRUE),
    ('WO-015', 'ASSET_006', 'preventive', '2026-06-05 06:00:00', '2026-06-05 12:00:00', 'LOW',       'completed', 'Sarah Chen',    6.0, 280, 880,  NULL,                     TRUE),
    ('WO-016', 'ASSET_004', 'preventive', '2026-06-20 06:00:00', '2026-06-20 10:00:00', 'MEDIUM',    'completed', 'Maria Garcia',  4.0, 180, 580,  NULL,                     TRUE),
    ('WO-017', 'ASSET_009', 'preventive', '2026-07-05 06:00:00', '2026-07-05 10:00:00', 'LOW',       'completed', 'Rachel Wu',     4.0, 100, 500,  NULL,                     TRUE),
    ('WO-018', 'ASSET_008', 'preventive', '2026-07-15 06:00:00', '2026-07-15 12:00:00', 'MEDIUM',    'completed', 'Tom Baker',     6.0, 250, 850,  NULL,                     FALSE),
    -- Open / in-progress WOs (active at demo time)
    ('WO-019', 'ASSET_001', 'corrective', '2026-08-10 08:00:00', NULL,                  'HIGH',      'in_progress','Mike Torres',  NULL, 500, 1100, NULL,                     TRUE),
    ('WO-020', 'ASSET_006', 'emergency',  '2026-08-18 14:00:00', NULL,                  'EMERGENCY', 'open',       'Sarah Chen',   NULL, 750, 1950, NULL,                     TRUE),
    ('WO-021', 'ASSET_004', 'corrective', '2026-08-20 09:00:00', NULL,                  'MEDIUM',    'open',       'Maria Garcia', NULL, 350, 950,  NULL,                     TRUE),
    ('WO-022', 'ASSET_009', 'preventive', '2026-08-25 06:00:00', NULL,                  'LOW',       'open',       'Rachel Wu',    NULL, 100, 500,  NULL,                     FALSE);


-- 7. MAINTENANCE_LOGS (26 logs linked to work orders)
TRUNCATE TABLE IF EXISTS RAW_IT.MAINTENANCE_LOGS;
INSERT INTO RAW_IT.MAINTENANCE_LOGS
    (LOG_ID, WO_ID, ASSET_ID, TIMESTAMP, TECHNICIAN, NOTES_TEXT)
VALUES
    ('LOG-001', 'WO-001', 'ASSET_001', '2026-04-10 07:00:00', 'Mike Torres',   'Inspected drive end bearing on Compressor A1. Excessive radial play detected. Vibration readings above 8 mm/s RMS on X-axis. Bearing 6205-2RS replaced. Root cause: bearing wear due to inadequate lubrication schedule. Recommended increasing grease interval from 90 to 60 days.'),
    ('LOG-002', 'WO-001', 'ASSET_001', '2026-04-10 12:00:00', 'Mike Torres',   'Post-repair vibration test: X-axis now 1.8 mm/s RMS, within ISO 10816 Zone A. Bearing replaced with SKF 6205-2RS-C3. Alignment verified with laser. Machine returned to service.'),
    ('LOG-003', 'WO-002', 'ASSET_002', '2026-04-22 15:00:00', 'Sarah Chen',    'Compressor A2 emergency shutdown triggered by high discharge temperature alarm at 108°C (rated max 110°C). Intercooler fins heavily fouled. Thermal compound degraded on aftercooler. Cleaned fins, replaced thermal paste, and installed new temperature sensor.'),
    ('LOG-004', 'WO-002', 'ASSET_002', '2026-04-23 01:00:00', 'Sarah Chen',    'Compressor A2 restart after thermal remediation. Discharge temp stable at 62°C under load. Monitored for 2 hours. Root cause confirmed: thermal degradation from fouled intercooler reducing heat transfer efficiency by ~35%.'),
    ('LOG-005', 'WO-003', 'ASSET_005', '2026-05-08 23:00:00', 'Mike Torres',   'Motor M1 tripped on vibration alarm. Drive end bearing hot to touch (~95°C). Bearing 6308-ZZ seized. Emergency replacement performed during night shift. Found metal shavings in old grease — bearing cage failure likely cause.'),
    ('LOG-006', 'WO-003', 'ASSET_005', '2026-05-09 04:00:00', 'Mike Torres',   'Motor M1 bearing replacement complete. New bearing greased with Mobil SHC 100. Vibration test: 2.1 mm/s X, 1.8 mm/s Y. Motor insulation resistance >500 MΩ. Returned to service.'),
    ('LOG-007', 'WO-004', 'ASSET_004', '2026-06-01 11:30:00', 'James Wright',  'Pump P2 high vibration alert on all three axes. Laser alignment check revealed 0.12mm offset and 0.08mm angular misalignment at coupling. Coupling flexible element cracked. Replaced coupling and re-aligned to within 0.02mm tolerance.'),
    ('LOG-008', 'WO-005', 'ASSET_003', '2026-04-15 09:00:00', 'James Wright',  'Pump P1 scheduled corrective: Y-axis vibration trending upward over past 2 weeks. Impeller inspection revealed slight mass imbalance from cavitation erosion on 2 vanes. Balanced in-situ using trial weights. Final reading: 1.6 mm/s RMS.'),
    ('LOG-009', 'WO-006', 'ASSET_006', '2026-05-01 08:00:00', 'Sarah Chen',    'Motor M2 corrective: stator winding temperature rising 2°C/week over baseline. Cleaned motor cooling fan, replaced clogged inlet filter, and re-applied thermal compound to terminal connections. Winding temp dropped from 92°C to 74°C.'),
    ('LOG-010', 'WO-007', 'ASSET_009', '2026-05-20 10:00:00', 'Maria Garcia',  'Conveyor C1 drive misalignment corrected. Belt tracking was off by 15mm causing uneven bearing load. Re-aligned drive pulley, adjusted belt tension to 4.5 kN. Current draw reduced from 18A to 12A.'),
    ('LOG-011', 'WO-008', 'ASSET_001', '2026-06-10 09:00:00', 'Mike Torres',   'Compressor A1 follow-up inspection after April bearing replacement. Vibration levels stable at 2.0 mm/s. Replaced V-belt showing early fraying. Oil filter changed as preventive measure.'),
    ('LOG-012', 'WO-009', 'ASSET_008', '2026-06-15 08:00:00', 'Rachel Wu',     'Gearbox G1 gear mesh vibration elevated at 1x and 2x gear mesh frequency. Oil analysis showed elevated iron content (45 ppm vs 15 ppm baseline). Drained oil, flushed, and refilled with ISO VG 320. Replaced oil filter. Scheduled follow-up in 30 days.'),
    ('LOG-013', 'WO-009', 'ASSET_008', '2026-06-15 14:00:00', 'Rachel Wu',     'Gearbox G1 post-service vibration: mesh frequency amplitude reduced by 40%. Oil temp stable at 68°C. Acoustic emissions returned to normal range (72 dB vs 81 dB pre-service).'),
    ('LOG-014', 'WO-010', 'ASSET_005', '2026-07-01 10:00:00', 'Mike Torres',   'Motor M1 scheduled corrective after May emergency repair. Bearing running well. Replaced V-belts and adjusted tension. Current balance across phases within 2%. Infrared scan shows even temperature distribution.'),
    ('LOG-015', 'WO-011', 'ASSET_007', '2026-04-01 07:00:00', 'Rachel Wu',     'Fan F1 quarterly preventive. Inspected blade pitch mechanism, lubricated bearings, checked inlet vanes. All readings nominal. No issues found.'),
    ('LOG-016', 'WO-012', 'ASSET_010', '2026-04-15 07:00:00', 'Tom Baker',     'Turbine T1 semi-annual preventive maintenance. Borescope inspection of first-stage blades — no cracking or erosion detected. Governor tested and calibrated. Bearing oil analysis clean. All readings nominal.'),
    ('LOG-017', 'WO-013', 'ASSET_003', '2026-05-10 07:00:00', 'James Wright',  'Pump P1 preventive: replaced mechanical seal as per 18-month schedule. Old seal showed minor wear on carbon face but no leakage. Impeller clearance checked — within spec at 0.3mm.'),
    ('LOG-018', 'WO-014', 'ASSET_002', '2026-05-25 07:00:00', 'Sarah Chen',    'Compressor A2 preventive: oil change, filter replacement, and belt inspection. Oil sample sent to lab. Safety valve tested — lifts at 8.5 bar (spec 8.0-9.0). All nominal.'),
    ('LOG-019', 'WO-015', 'ASSET_006', '2026-06-05 07:00:00', 'Sarah Chen',    'Motor M2 preventive: insulation resistance test 850 MΩ (good). Bearing grease replenished. Cooling fan blades cleaned. Alignment verified — within 0.03mm. Terminal connections re-torqued.'),
    ('LOG-020', 'WO-016', 'ASSET_004', '2026-06-20 07:00:00', 'Maria Garcia',  'Pump P2 preventive post-alignment repair. Coupling bolts re-torqued. Vibration baseline established: X=2.1, Y=1.9, Z=1.7 mm/s. Seal leak check — dry. Performance test: flow rate 95% of rated.'),
    ('LOG-021', 'WO-017', 'ASSET_009', '2026-07-05 07:00:00', 'Rachel Wu',     'Conveyor C1 quarterly PM. Belt condition good — no fraying or cracks. Drive roller bearings greased. Belt tension measured at 4.4 kN — within 4.0-5.0 kN spec. Speed verified at 1.2 m/s.'),
    ('LOG-022', 'WO-018', 'ASSET_008', '2026-07-15 07:00:00', 'Tom Baker',     'Gearbox G1 preventive follow-up after June oil change. Oil sample clean — iron at 18 ppm (down from 45). Gear mesh vibration stable. Input shaft bearing temperature 64°C. No action required, continue monitoring.'),
    ('LOG-023', 'WO-019', 'ASSET_001', '2026-08-10 09:00:00', 'Mike Torres',   'Compressor A1 bearing vibration trending upward again — X-axis at 4.2 mm/s. Ordered replacement bearing. Monitoring every 4 hours until part arrives. Machine running at reduced load (80%).'),
    ('LOG-024', 'WO-020', 'ASSET_006', '2026-08-18 15:00:00', 'Sarah Chen',    'Motor M2 emergency: stator winding temp spiked to 112°C. Immediately de-energized. Insulation resistance dropped to 50 MΩ (was 850 MΩ in June). Suspect inter-turn short developing. Heater coil ordered for rewind.'),
    ('LOG-025', 'WO-021', 'ASSET_004', '2026-08-20 10:00:00', 'Maria Garcia',  'Pump P2 vibration rising on Y-axis: 3.8 mm/s. Coupling showing signs of wear — flexible element starting to crack. Ordered replacement coupling. Pump can continue at current load for ~72 hours.'),
    ('LOG-026', 'WO-022', 'ASSET_009', '2026-08-25 07:00:00', 'Rachel Wu',     'Conveyor C1 preventive: belt tracking drifting again (8mm offset). Suspect drive pulley lagging surface worn. Ordered new lagging kit. Adjusted tracking as interim measure. Current draw nominal.');


-- 8. SUPPLIERS (5 suppliers)
TRUNCATE TABLE IF EXISTS RAW_IT.SUPPLIERS;
INSERT INTO RAW_IT.SUPPLIERS
    (SUPPLIER_ID, SUPPLIER_NAME, CONTACT_EMAIL, PHONE)
VALUES
    ('SUP-001', 'Industrial Parts Co',       'orders@indparts.com',      '+1-555-0101'),
    ('SUP-002', 'Atlas Copco Parts Direct',  'parts@atlascopco.com',     '+1-555-0102'),
    ('SUP-003', 'Bearing World Inc',         'sales@bearingworld.com',   '+1-555-0103'),
    ('SUP-004', 'ThermalTech Supply',        'orders@thermaltech.com',   '+1-555-0104'),
    ('SUP-005', 'PumpParts Global',          'sales@pumpparts.com',      '+1-555-0105');


-- 9. PART_SUPPLIERS (16 mappings)
TRUNCATE TABLE IF EXISTS RAW_IT.PART_SUPPLIERS;
INSERT INTO RAW_IT.PART_SUPPLIERS
    (PART_ID, SUPPLIER_ID, SUPPLIER_PART_NUMBER, STANDARD_LEAD_TIME_DAYS, EXPEDITE_LEAD_TIME_DAYS, MIN_ORDER_QTY, UNIT_COST, PREFERRED_SUPPLIER)
VALUES
    ('PART-001', 'SUP-003', 'BW-6205-2RS',     5,  2,  1, 45.00,   TRUE),
    ('PART-001', 'SUP-001', 'IP-BRG-6205',     7,  3,  2, 42.00,   FALSE),
    ('PART-002', 'SUP-003', 'BW-6308-ZZ',      7,  3,  1, 120.00,  TRUE),
    ('PART-003', 'SUP-001', 'IP-SEAL-V100',    3,  1,  5, 15.00,   TRUE),
    ('PART-004', 'SUP-002', 'AC-FLT-OIL-M',    2,  1, 10, 8.00,    TRUE),
    ('PART-005', 'SUP-001', 'IP-BLT-V100',     4,  2,  3, 25.00,   TRUE),
    ('PART-006', 'SUP-005', 'PP-IMP-CF150',   14,  7,  1, 850.00,  TRUE),
    ('PART-007', 'SUP-005', 'PP-SEAL-MECH',   10,  5,  1, 320.00,  TRUE),
    ('PART-008', 'SUP-001', 'IP-BRG-NUP310',   6,  3,  1, 95.00,   TRUE),
    ('PART-009', 'SUP-004', 'TT-HTR-COIL-3K', 12,  6,  1, 280.00,  TRUE),
    ('PART-010', 'SUP-001', 'IP-COUP-FLEX',     5,  2,  1, 180.00,  TRUE),
    ('PART-011', 'SUP-003', 'BW-6310-2RS',      7,  3,  1, 150.00,  TRUE),
    ('PART-012', 'SUP-001', 'IP-GEAR-SET-G1',  21, 10,  1, 1200.00, TRUE),
    ('PART-013', 'SUP-001', 'IP-ROLL-CONV',     3,  1,  4, 65.00,   TRUE),
    ('PART-014', 'SUP-002', 'AC-SHAFT-SLV',    12,  5,  1, 450.00,  TRUE),
    ('PART-015', 'SUP-004', 'TT-BLADE-STM',    28, 14,  1, 2200.00, TRUE),
    ('PART-016', 'SUP-003', 'BW-AXF-BRG-001',  5,  3,  1, 65.00,   TRUE),
    ('PART-017', 'SUP-001', 'IPC-AXN900-BLD',  10,  5,  1, 210.00,  TRUE);

-- FAILURE_MODE_BOM seed data (39 rows: repair parts by asset type + failure mode)
TRUNCATE TABLE IF EXISTS RAW_IT.FAILURE_MODE_BOM;
INSERT INTO RAW_IT.FAILURE_MODE_BOM (ASSET_TYPE, FAILURE_MODE, PART_ID, QTY_PER_REPAIR, NOTES)
SELECT * FROM VALUES
  ('compressor', 'bearing_wear', 'PART-001', 2, 'Bearing 6205-2RS x 2 — dual bearing replacement per WO history'),
  ('compressor', 'bearing_wear', 'PART-003', 1, 'Vibratory Seal Kit x 1 — replace seal during bearing swap'),
  ('compressor', 'bearing_wear', 'PART-005', 1, 'V-Belt Kit x 1 — inspect/replace belt during teardown'),
  ('compressor', 'imbalance', 'PART-014', 1, 'Shaft Sleeve x 1 — primary repair for imbalance'),
  ('compressor', 'imbalance', 'PART-003', 1, 'Vibratory Seal Kit x 1 — replace after realignment'),
  ('compressor', 'thermal_degradation', 'PART-014', 1, 'Shaft Sleeve x 1 — heat damage'),
  ('compressor', 'thermal_degradation', 'PART-001', 2, 'Bearing 6205-2RS x 2 — thermal stress on bearings'),
  ('compressor', 'thermal_degradation', 'PART-004', 1, 'Oil Filter x 1 — contaminated by heat'),
  ('centrifugal_pump', 'bearing_wear', 'PART-006', 1, 'Impeller x 1 — bearing wear causes impeller damage'),
  ('centrifugal_pump', 'bearing_wear', 'PART-007', 1, 'Mechanical Seal x 1 — replace seal during impeller swap'),
  ('centrifugal_pump', 'misalignment', 'PART-006', 1, 'Impeller x 1 — confirmed from WO-AUTO-ASSET_003'),
  ('centrifugal_pump', 'misalignment', 'PART-007', 1, 'Mechanical Seal x 1 — confirmed from WO-AUTO-ASSET_003'),
  ('centrifugal_pump', 'misalignment', 'PART-010', 1, 'Flexible Coupling x 1 — confirmed from WO-AUTO-ASSET_003'),
  ('centrifugal_pump', 'imbalance', 'PART-007', 1, 'Mechanical Seal x 1 — primary repair'),
  ('electric_motor', 'bearing_wear', 'PART-001', 2, 'Bearing 6205-2RS x 2 — dual bearing replacement'),
  ('electric_motor', 'bearing_wear', 'PART-008', 1, 'Roller Bearing NUP310 x 1 — main shaft bearing'),
  ('electric_motor', 'bearing_wear', 'PART-005', 1, 'V-Belt Kit x 1 — inspect/replace during teardown'),
  ('electric_motor', 'imbalance', 'PART-002', 1, 'Bearing 6308-ZZ x 1 — primary repair for imbalance'),
  ('electric_motor', 'imbalance', 'PART-008', 1, 'Roller Bearing NUP310 x 1 — check/replace during repair'),
  ('electric_motor', 'thermal_degradation', 'PART-009', 1, 'Heater Coil 3kW x 1 — thermal component replacement'),
  ('conveyor_drive', 'misalignment', 'PART-010', 1, 'Flexible Coupling x 1 — confirmed from WO-022'),
  ('conveyor_drive', 'misalignment', 'PART-013', 1, 'Conveyor Roller Set x 1 — replace worn rollers'),
  ('conveyor_drive', 'bearing_wear', 'PART-011', 1, 'Bearing 6310-2RS x 1 — main bearing'),
  ('conveyor_drive', 'bearing_wear', 'PART-013', 1, 'Conveyor Roller Set x 1 — replace if damaged'),
  ('gearbox', 'imbalance', 'PART-008', 1, 'Roller Bearing NUP310 x 1 — realignment repair'),
  ('gearbox', 'imbalance', 'PART-011', 1, 'Bearing 6310-2RS x 1 — secondary bearing check'),
  ('gearbox', 'imbalance', 'PART-004', 1, 'Oil Filter x 1 — contamination from wear debris'),
  ('gearbox', 'thermal_degradation', 'PART-012', 1, 'Gear Set G1 x 1 — heat-damaged gears'),
  ('gearbox', 'bearing_wear', 'PART-008', 1, 'Roller Bearing NUP310 x 1'),
  ('gearbox', 'bearing_wear', 'PART-011', 1, 'Bearing 6310-2RS x 1'),
  ('steam_turbine', 'bearing_wear', 'PART-015', 1, 'Turbine Blade Set x 1 — inspect/replace during overhaul'),
  ('steam_turbine', 'imbalance', 'PART-015', 1, 'Turbine Blade Set x 1 — imbalance causes blade damage'),
  ('steam_turbine', 'thermal_degradation', 'PART-015', 1, 'Turbine Blade Set x 1 — heat damage'),
  ('steam_turbine', 'misalignment', 'PART-015', 1, 'Turbine Blade Set x 1 — alignment repair'),
  ('axial_fan', 'bearing_wear', 'PART-016', 1, 'Axial Fan Bearing Kit x 1'),
  ('axial_fan', 'misalignment', 'PART-016', 1, 'Axial Fan Bearing Kit x 1 — realignment'),
  ('axial_fan', 'misalignment', 'PART-017', 1, 'Fan Blade Assembly x 1 — blade damage from misalignment'),
  ('axial_fan', 'imbalance', 'PART-017', 1, 'Fan Blade Assembly x 1 — blade damage'),
  ('axial_fan', 'imbalance', 'PART-016', 1, 'Axial Fan Bearing Kit x 1 — check during repair')
AS t(ASSET_TYPE, FAILURE_MODE, PART_ID, QTY_PER_REPAIR, NOTES);


-- 10. SHIFT_SCHEDULE (~1710 rows: 3 shifts x 3 lines x 190 days)
TRUNCATE TABLE IF EXISTS RAW_IT.SHIFT_SCHEDULE;
INSERT INTO RAW_IT.SHIFT_SCHEDULE
    (SHIFT_ID, LINE_ID, SHIFT_START, SHIFT_END, OPERATOR_NAME, PLANNED_PRODUCTION_TIME_MINS)
WITH date_range AS (
    SELECT DATEADD('day', seq4(), '2026-03-01'::DATE) AS shift_date
    FROM TABLE(GENERATOR(ROWCOUNT => 190))
),
lines AS (
    SELECT column1 AS LINE_ID FROM VALUES ('LINE_01'), ('LINE_02'), ('LINE_03')
),
shifts AS (
    SELECT column1 AS shift_num, column2 AS start_hour, column3 AS end_offset
    FROM VALUES (1, 6, 0), (2, 14, 0), (3, 22, 1)
),
operators AS (
    SELECT column1 AS LINE_ID, column2 AS shift_num, column3 AS OPERATOR_NAME
    FROM VALUES
        ('LINE_01', 1, 'Mike Torres'),    ('LINE_01', 2, 'James Wright'),  ('LINE_01', 3, 'Alex Johnson'),
        ('LINE_02', 1, 'Sarah Chen'),     ('LINE_02', 2, 'Maria Garcia'),  ('LINE_02', 3, 'David Kim'),
        ('LINE_03', 1, 'Rachel Wu'),      ('LINE_03', 2, 'Tom Baker'),     ('LINE_03', 3, 'Lisa Patel')
)
SELECT
    'SH-' || REPLACE(l.LINE_ID, 'LINE_', 'L') || '-' || TO_CHAR(d.shift_date, 'YYYYMMDD') || '-S' || s.shift_num AS SHIFT_ID,
    l.LINE_ID,
    DATEADD('hour', s.start_hour, d.shift_date::TIMESTAMP_NTZ) AS SHIFT_START,
    DATEADD('hour', s.start_hour + 8, DATEADD('day', s.end_offset, d.shift_date)::TIMESTAMP_NTZ) AS SHIFT_END,
    o.OPERATOR_NAME,
    480 AS PLANNED_PRODUCTION_TIME_MINS
FROM date_range d
CROSS JOIN lines l
CROSS JOIN shifts s
JOIN operators o ON o.LINE_ID = l.LINE_ID AND o.shift_num = s.shift_num;


-- 11. PRODUCTION_OUTPUT (~3330 rows)
TRUNCATE TABLE IF EXISTS RAW_IT.PRODUCTION_OUTPUT;
INSERT INTO RAW_IT.PRODUCTION_OUTPUT
    (RECORD_ID, ASSET_ID, SHIFT_ID, TIMESTAMP, UNITS_PRODUCED, GOOD_UNITS, IDEAL_CYCLE_TIME_SEC)
WITH date_range AS (
    SELECT DATEADD('day', seq4(), '2026-03-01'::DATE) AS prod_date
    FROM TABLE(GENERATOR(ROWCOUNT => 185))
),
producing_assets AS (
    SELECT column1 AS ASSET_ID, column2 AS LINE_ID
    FROM VALUES
        ('ASSET_001', 'LINE_01'), ('ASSET_002', 'LINE_01'), ('ASSET_003', 'LINE_01'),
        ('ASSET_004', 'LINE_02'), ('ASSET_005', 'LINE_02'), ('ASSET_006', 'LINE_02'),
        ('ASSET_009', 'LINE_03')
),
shifts AS (
    SELECT column1 AS shift_num, column2 AS start_hour FROM VALUES (1, 6), (2, 14), (3, 22)
)
SELECT
    'P-' || REPLACE(a.ASSET_ID, 'ASSET_', 'A') || '-' || TO_CHAR(d.prod_date, 'YYYYMMDD') || '-S' || s.shift_num AS RECORD_ID,
    a.ASSET_ID,
    'SH-' || REPLACE(a.LINE_ID, 'LINE_', 'L') || '-' || TO_CHAR(d.prod_date, 'YYYYMMDD') || '-S' || s.shift_num AS SHIFT_ID,
    DATEADD('hour', s.start_hour + 4, d.prod_date::TIMESTAMP_NTZ) AS TIMESTAMP,
    GREATEST(80, LEAST(200, ROUND(150 + UNIFORM(-30::FLOAT, 30::FLOAT, RANDOM()))))::INT AS UNITS_PRODUCED,
    GREATEST(70, LEAST(195, ROUND(145 + UNIFORM(-30::FLOAT, 25::FLOAT, RANDOM()))))::INT AS GOOD_UNITS,
    2.5 AS IDEAL_CYCLE_TIME_SEC
FROM date_range d
CROSS JOIN producing_assets a
CROSS JOIN shifts s
WHERE UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) > 0.15;


-- 12. AMBIENT_CONDITIONS (190 days of daily weather data)
TRUNCATE TABLE IF EXISTS RAW_OT.AMBIENT_CONDITIONS;
INSERT INTO RAW_OT.AMBIENT_CONDITIONS
    (READING_DATE, AMBIENT_TEMP_C, HUMIDITY_PCT, BAROMETRIC_PRESSURE_HPA)
SELECT
    DATEADD('day', seq4(), '2026-03-01'::DATE) AS READING_DATE,
    ROUND(18 + 12 * SIN((seq4() - 30) * 3.14159 / 180) + UNIFORM(-3::FLOAT, 3::FLOAT, RANDOM()), 1) AS AMBIENT_TEMP_C,
    ROUND(55 + 20 * COS((seq4() - 60) * 3.14159 / 180) + UNIFORM(-8::FLOAT, 8::FLOAT, RANDOM()), 1) AS HUMIDITY_PCT,
    ROUND(1013.25 + UNIFORM(-15::FLOAT, 15::FLOAT, RANDOM()), 1) AS BAROMETRIC_PRESSURE_HPA
FROM TABLE(GENERATOR(ROWCOUNT => 190));


-- NOTE: NOTIFICATION_SETTINGS and SIMULATION_CONFIG are seeded in
-- 19_notifications.sql and 20_configurable_simulation.sql respectively,
-- since those tables are created in those scripts.


-- SEED DATA COMPLETE
-- Expected counts:
--   ASSET_MASTER:       10
--   SENSOR_METADATA:    23
--   USERS:               9  (6 personas)
--   PARTS_INVENTORY:    15
--   MODEL_REGISTRY:     12  (8 UDF/Proc + 4 native)
--   WORK_ORDERS:        22
--   MAINTENANCE_LOGS:   26
--   SUPPLIERS:           5
--   PART_SUPPLIERS:     16
--   SHIFT_SCHEDULE:   ~1710  (190 days × 3 lines × 3 shifts)
--   PRODUCTION_OUTPUT: ~3330  (185 days × 7 assets × 3 shifts, ~85% fill)
--   AMBIENT_CONDITIONS:  190
--   NOTIFICATION_SETTINGS: 7


-- ============================================================================
-- CHECKPOINT 5: SENSOR DATA GENERATION
-- ============================================================================

-- Creates procedure then calls it to generate 172K+ sensor readings.
-- This is the longest step (~1-2 minutes).
-- Truncate first for idempotency.
TRUNCATE TABLE IF EXISTS RAW_OT.SENSOR_READINGS;
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

-- To run: CALL MFGPULSE_DB.RAW_OT.GENERATE_SENSOR_DATA();

USE WAREHOUSE COMPUTE_WH;

CALL MFGPULSE_DB.RAW_OT.GENERATE_SENSOR_DATA();


-- ============================================================================
-- CHECKPOINT 6: UDFs AND ML PROCEDURES
-- ============================================================================

-- 5 UDFs + 4 procedures from full_ddl_export.sql

-- M4: COMPUTE_FATIGUE_SCORE
CREATE OR REPLACE FUNCTION ML_MODELS.COMPUTE_FATIGUE_SCORE(VIB_CREST_FACTOR_6H FLOAT, VIB_COEFF_VAR_6H FLOAT, VIB_PEAK_TO_PEAK_6H FLOAT, VIB_RATE_OF_CHANGE_1H FLOAT, VIB_ACCELERATION_1H FLOAT, ENERGY_BALANCE_RATIO FLOAT, STRESS_INDEX FLOAT, VIB_XY_CORRELATION FLOAT, ACOUSTIC_VIB_RATIO FLOAT)
RETURNS FLOAT
LANGUAGE SQL
AS '
    -- Multi-signal fatigue score (0 = healthy, 1 = critical fatigue)
    -- Each component detects a different fatigue mechanism
    LEAST(1.0, GREATEST(0.0,
        -- Component 1: Impulsiveness (kurtosis proxy via crest factor)
        -- High crest factor = sharp impacts = bearing pitting
        LEAST(1.0, GREATEST(0, (vib_crest_factor_6h - 1.2) / 1.5)) * 0.25

        -- Component 2: Signal instability (coefficient of variation)
        -- High CoV = intermittent contact / looseness
        + LEAST(1.0, GREATEST(0, (vib_coeff_var_6h - 0.15) / 0.4)) * 0.15

        -- Component 3: Degradation acceleration (2nd derivative)
        -- Positive acceleration = failure approaching faster
        + LEAST(1.0, GREATEST(0, vib_acceleration_1h / 2.0)) * 0.20

        -- Component 4: Energy inefficiency
        -- Divergence from 1.0 = energy loss to friction/misalignment
        + LEAST(1.0, GREATEST(0, ABS(energy_balance_ratio - 1.0) / 0.5)) * 0.15

        -- Component 5: Multi-axis correlation shift
        -- Sudden correlation change = new failure mode developing
        + LEAST(1.0, GREATEST(0, ABS(vib_xy_correlation - 0.3) / 0.5)) * 0.10

        -- Component 6: Acoustic-vibration decoupling
        -- Rising acoustic with stable vibration = internal crack
        + LEAST(1.0, GREATEST(0, (acoustic_vib_ratio - 25.0) / 20.0)) * 0.15
    ))
';

-- M3: PREDICT_DEGRADATION_STAGE
CREATE OR REPLACE FUNCTION ML_MODELS.PREDICT_DEGRADATION_STAGE(VIB_RMS_24H FLOAT, VIB_CREST_FACTOR_6H FLOAT, STRESS_INDEX FLOAT, COMPOSITE_HEALTH_SCORE FLOAT, DEGRADATION_VELOCITY_30D FLOAT, HOURS_SINCE_FIRST_BREACH FLOAT, ABOVE_NORMAL_COUNT_24H FLOAT)
RETURNS OBJECT
LANGUAGE SQL
AS '
    SELECT OBJECT_CONSTRUCT(
        ''predicted_stage'', 
        CASE 
            WHEN (LEAST(1.0, GREATEST(0, (vib_rms_24h - 2.5)/10.0)) * 0.25 +
                  LEAST(1.0, GREATEST(0, (vib_crest_factor_6h - 1.2)/1.5)) * 0.15 +
                  LEAST(1.0, stress_index) * 0.15 +
                  LEAST(1.0, GREATEST(0, COALESCE(degradation_velocity_30d, 0)/0.5)) * 0.20 +
                  CASE WHEN hours_since_first_breach IS NULL THEN 0 ELSE LEAST(1.0, hours_since_first_breach/2000.0) END * 0.10 +
                  LEAST(1.0, COALESCE(above_normal_count_24h, 0)/80.0) * 0.15
            ) < 0.30 THEN ''Healthy''
            WHEN (LEAST(1.0, GREATEST(0, (vib_rms_24h - 2.5)/10.0)) * 0.25 +
                  LEAST(1.0, GREATEST(0, (vib_crest_factor_6h - 1.2)/1.5)) * 0.15 +
                  LEAST(1.0, stress_index) * 0.15 +
                  LEAST(1.0, GREATEST(0, COALESCE(degradation_velocity_30d, 0)/0.5)) * 0.20 +
                  CASE WHEN hours_since_first_breach IS NULL THEN 0 ELSE LEAST(1.0, hours_since_first_breach/2000.0) END * 0.10 +
                  LEAST(1.0, COALESCE(above_normal_count_24h, 0)/80.0) * 0.15
            ) < 0.65 THEN ''Warning''
            ELSE ''Critical''
        END,
        ''degradation_score'', 
        ROUND(LEAST(1.0, GREATEST(0, (vib_rms_24h - 2.5)/10.0)) * 0.25 +
              LEAST(1.0, GREATEST(0, (vib_crest_factor_6h - 1.2)/1.5)) * 0.15 +
              LEAST(1.0, stress_index) * 0.15 +
              LEAST(1.0, GREATEST(0, COALESCE(degradation_velocity_30d, 0)/0.5)) * 0.20 +
              CASE WHEN hours_since_first_breach IS NULL THEN 0 ELSE LEAST(1.0, hours_since_first_breach/2000.0) END * 0.10 +
              LEAST(1.0, COALESCE(above_normal_count_24h, 0)/80.0) * 0.15, 4),
        ''transition_probability'',
        ROUND(LEAST(1.0, GREATEST(0, COALESCE(degradation_velocity_30d, 0)/0.5)) * 0.5 +
              LEAST(1.0, COALESCE(above_normal_count_24h, 0)/80.0) * 0.5, 4)
    )
';

-- M1: PREDICT_FAILURE_MODE
CREATE OR REPLACE FUNCTION ML_MODELS.PREDICT_FAILURE_MODE(VIB_MAG_MEAN_6H FLOAT, VIB_MAG_STD_6H FLOAT, VIB_MAG_MAX_6H FLOAT, VIB_CREST_FACTOR_6H FLOAT, VIB_PEAK_TO_PEAK_6H FLOAT, VIB_RMS_6H FLOAT, VIB_COEFF_VAR_6H FLOAT, TEMP_MEAN_6H FLOAT, TEMP_STD_6H FLOAT, CURRENT_MEAN_6H FLOAT, CURRENT_STD_6H FLOAT, VIB_MAG_MEAN_24H FLOAT, VIB_MAG_STD_24H FLOAT, VIB_CREST_FACTOR_24H FLOAT, VIB_RMS_24H FLOAT, TEMP_MEAN_24H FLOAT, CURRENT_MEAN_24H FLOAT, ACOUSTIC_MEAN_24H FLOAT, VIB_RATE_OF_CHANGE_1H FLOAT, VIB_ACCELERATION_1H FLOAT, VIB_XY_CORRELATION FLOAT, VIB_TEMP_COUPLING FLOAT, CURRENT_RPM_RATIO FLOAT, VIB_AXIS_DOMINANCE FLOAT, ACOUSTIC_VIB_RATIO FLOAT, STRESS_INDEX FLOAT, ISO_SEVERITY FLOAT, COMPOSITE_HEALTH FLOAT)
RETURNS OBJECT
LANGUAGE SQL
AS '
    -- Physics-informed failure mode classification
    -- Encodes domain knowledge: which signal patterns map to which failure modes
    SELECT OBJECT_CONSTRUCT(
        ''predicted_failure_mode'',
        CASE
            -- Bearing wear: high crest factor + high acoustic + rising vibration
            WHEN vib_crest_factor_6h > 1.5 AND acoustic_vib_ratio > 20 AND vib_rms_24h > 5.0
                THEN ''bearing_wear''
            -- Thermal degradation: high temp + low vibration + efficiency loss
            WHEN temp_mean_24h > 70 AND vib_rms_24h < 4.0 AND stress_index > 0.5
                THEN ''thermal_degradation''
            -- Misalignment: multi-axis correlation + high current + moderate vibration
            WHEN ABS(vib_xy_correlation) > 0.6 AND current_rpm_ratio > 8.0 AND vib_axis_dominance < 0.7
                THEN ''misalignment''
            -- Imbalance: single-axis dominant + RPM-dependent vibration
            WHEN vib_axis_dominance > 0.75 AND vib_rms_24h > 4.0 AND current_rpm_ratio < 7.0
                THEN ''imbalance''
            -- Normal
            ELSE ''normal''
        END,
        ''confidence'', 
        CASE 
            WHEN composite_health < 30 THEN 0.95
            WHEN composite_health < 60 THEN 0.80
            WHEN composite_health < 80 THEN 0.65
            ELSE 0.90
        END,
        ''prob_bearing_wear'', ROUND(LEAST(1, GREATEST(0, (vib_crest_factor_6h - 1.0) / 2.0 * (acoustic_vib_ratio / 40.0))), 4),
        ''prob_thermal'', ROUND(LEAST(1, GREATEST(0, (temp_mean_24h - 50) / 50.0 * (1 - vib_rms_24h / 15.0))), 4),
        ''prob_misalignment'', ROUND(LEAST(1, GREATEST(0, ABS(vib_xy_correlation) * current_rpm_ratio / 15.0)), 4),
        ''prob_imbalance'', ROUND(LEAST(1, GREATEST(0, vib_axis_dominance * vib_rms_24h / 10.0)), 4),
        ''prob_normal'', ROUND(GREATEST(0, 1 - stress_index), 4)
    )
';

-- M2: PREDICT_RUL
CREATE OR REPLACE FUNCTION ML_MODELS.PREDICT_RUL(VIB_RMS_24H FLOAT, VIB_RATE_OF_CHANGE FLOAT, VIB_ACCELERATION FLOAT, DEGRADATION_VELOCITY FLOAT, HOURS_SINCE_BREACH FLOAT, STRESS_INDEX FLOAT, COMPOSITE_HEALTH FLOAT, FATIGUE_SCORE FLOAT)
RETURNS OBJECT
LANGUAGE SQL
AS '
    -- Physics-based RUL estimation with confidence intervals
    -- Uses degradation rate + remaining capacity to estimate hours to failure
    SELECT OBJECT_CONSTRUCT(
        ''predicted_rul_hours'', ROUND(GREATEST(0,
            CASE 
                WHEN COALESCE(degradation_velocity, 0) > 0.01 THEN
                    -- Rate-based: remaining capacity / degradation rate
                    (1.0 - COALESCE(fatigue_score, stress_index)) / (degradation_velocity / 24.0)
                WHEN stress_index > 0.7 THEN
                    -- High stress but low velocity: use stress-based estimate
                    (1.0 - stress_index) * 500.0
                ELSE
                    -- Low degradation: long RUL
                    2000.0
            END
        ), 1),
        ''rul_lower_ci'', ROUND(GREATEST(0,
            CASE 
                WHEN COALESCE(degradation_velocity, 0) > 0.01 THEN
                    (1.0 - COALESCE(fatigue_score, stress_index)) / (degradation_velocity * 1.5 / 24.0)
                ELSE 1500.0
            END
        ), 1),
        ''rul_upper_ci'', ROUND(GREATEST(0,
            CASE 
                WHEN COALESCE(degradation_velocity, 0) > 0.01 THEN
                    (1.0 - COALESCE(fatigue_score, stress_index)) / (degradation_velocity * 0.5 / 24.0)
                ELSE 3000.0
            END
        ), 1),
        ''confidence_level'', CASE
            WHEN COALESCE(degradation_velocity, 0) > 0.1 THEN ''HIGH''
            WHEN COALESCE(degradation_velocity, 0) > 0.01 THEN ''MEDIUM''
            ELSE ''LOW''
        END
    )
';

-- M6: SIMULATE_FAILURE_TWIN
CREATE OR REPLACE FUNCTION ML_MODELS.SIMULATE_FAILURE_TWIN(CURRENT_VIB_MAG FLOAT, DEGRADATION_VELOCITY FLOAT, CURRENT_FATIGUE_SCORE FLOAT, LOAD_REDUCTION_PCT FLOAT, MAINTENANCE_DELAY_DAYS FLOAT, RPM_ADJUSTMENT_PCT FLOAT)
RETURNS OBJECT
LANGUAGE SQL
AS '
    -- Monte Carlo simulation: 100 stochastic projections with noise
    WITH params AS (
        SELECT 
            GREATEST(0.001, COALESCE(degradation_velocity, 0.1)) 
                * (1.0 - load_reduction_pct / 100.0 * 0.6) 
                * (1.0 + rpm_adjustment_pct / 100.0 * 0.3) AS adj_rate,
            current_fatigue_score AS base_fatigue,
            maintenance_delay_days AS delay_days
    ),
    simulations AS (
        SELECT 
            seq4() AS sim_id,
            -- Stochastic degradation rate: base rate * random multiplier (0.5x to 2.0x)
            p.adj_rate * (0.5 + UNIFORM(0::FLOAT, 1.5::FLOAT, RANDOM())) AS sim_rate,
            -- Random shock events (5% chance per day of acceleration event)
            UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS shock_rnd
        FROM TABLE(GENERATOR(ROWCOUNT => 100))
        CROSS JOIN params p
    ),
    projections AS (
        SELECT 
            s.sim_id,
            -- Day 3 fatigue
            LEAST(1.0, p.base_fatigue + s.sim_rate * 3 + CASE WHEN s.shock_rnd < 0.15 THEN 0.1 ELSE 0 END) AS fatigue_day3,
            -- Day 7 fatigue
            LEAST(1.0, p.base_fatigue + s.sim_rate * 7 + CASE WHEN s.shock_rnd < 0.35 THEN 0.15 ELSE 0 END) AS fatigue_day7,
            -- Day 14 fatigue
            LEAST(1.0, p.base_fatigue + s.sim_rate * 14 + CASE WHEN s.shock_rnd < 0.50 THEN 0.2 ELSE 0 END) AS fatigue_day14,
            -- Estimated failure day (when fatigue reaches 1.0)
            CASE WHEN s.sim_rate > 0 
                THEN (1.0 - p.base_fatigue) / s.sim_rate 
                ELSE 999 
            END AS days_to_failure,
            -- Apply maintenance delay: if fixed before failure, fatigue resets
            CASE WHEN p.delay_days < (1.0 - p.base_fatigue) / NULLIF(s.sim_rate, 0)
                THEN 0  -- maintenance happens before failure
                ELSE 1  -- failure happens before maintenance
            END AS fails_before_maintenance
        FROM simulations s
        CROSS JOIN params p
    )
    SELECT OBJECT_CONSTRUCT(
        ''scenario'', OBJECT_CONSTRUCT(
            ''load_reduction_pct'', load_reduction_pct,
            ''maintenance_delay_days'', maintenance_delay_days,
            ''rpm_adjustment_pct'', rpm_adjustment_pct
        ),
        ''num_simulations'', 100,
        -- Failure probability = % of simulations that exceed threshold
        ''failure_prob_day_3'', ROUND((SELECT COUNT(*) FROM projections WHERE fatigue_day3 > 0.9) / 100.0, 3),
        ''failure_prob_day_7'', ROUND((SELECT COUNT(*) FROM projections WHERE fatigue_day7 > 0.9) / 100.0, 3),
        ''failure_prob_day_14'', ROUND((SELECT COUNT(*) FROM projections WHERE fatigue_day14 > 0.9) / 100.0, 3),
        -- RUL distribution (percentiles)
        ''rul_days_p10'', ROUND((SELECT PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY days_to_failure) FROM projections), 1),
        ''rul_days_p50'', ROUND((SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY days_to_failure) FROM projections), 1),
        ''rul_days_p90'', ROUND((SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY days_to_failure) FROM projections), 1),
        -- Risk of failure before maintenance arrives
        ''fails_before_maintenance_pct'', ROUND((SELECT SUM(fails_before_maintenance) FROM projections) / 100.0 * 100, 1),
        -- Recommended intervention
        ''recommended_intervention'', CASE
            WHEN current_fatigue_score > 0.8 THEN ''IMMEDIATE - within 24 hours''
            WHEN current_fatigue_score > 0.6 THEN ''URGENT - within 3 days''
            WHEN current_fatigue_score > 0.4 THEN ''PLANNED - within 7 days''
            ELSE ''MONITOR - next scheduled PM''
        END,
        -- Cost analysis
        ''cost_of_repair_now'', 520,
        ''cost_of_failure'', 12000,
        ''expected_cost'', ROUND(520 + 12000 * (SELECT COUNT(*) FROM projections WHERE fatigue_day14 > 0.9) / 100.0, 0)
    )
';

-- M8: ANOMALY_SCORER (statistical Z-score anomaly detection)
CREATE OR REPLACE FUNCTION ML_MODELS.ANOMALY_SCORER(
    VIB_CREST_FACTOR_6H FLOAT, VIB_CREST_FACTOR_24H FLOAT,
    TEMP_RATE_OF_CHANGE FLOAT, ACOUSTIC_VIB_RATIO FLOAT, ENERGY_BALANCE_RATIO FLOAT)
RETURNS FLOAT LANGUAGE SQL AS '
    LEAST(1.0, GREATEST(0.0,
        LEAST(3.0, ABS(VIB_CREST_FACTOR_6H - 1.1443) / NULLIF(0.0347, 0)) / 3.0 * 0.25 +
        LEAST(3.0, ABS(VIB_CREST_FACTOR_24H - 1.1729) / NULLIF(0.0318, 0)) / 3.0 * 0.20 +
        LEAST(3.0, ABS(COALESCE(TEMP_RATE_OF_CHANGE, 0)) / NULLIF(1.605, 0)) / 3.0 * 0.20 +
        LEAST(3.0, ABS(COALESCE(ACOUSTIC_VIB_RATIO, 25.2554) - 25.2554) / NULLIF(4.6552, 0)) / 3.0 * 0.15 +
        LEAST(3.0, ABS(COALESCE(ENERGY_BALANCE_RATIO, 14.7049) - 14.7049) / NULLIF(12.2242, 0)) / 3.0 * 0.20
    ))';

-- M7: PRESCRIBE_MAINTENANCE
CREATE OR REPLACE PROCEDURE ML_MODELS.PRESCRIBE_MAINTENANCE(P_ASSET_ID VARCHAR, P_FAILURE_MODE VARCHAR, P_RUL_HOURS FLOAT, P_STAGE VARCHAR, P_FATIGUE_SCORE FLOAT, P_ROOT_CAUSE VARCHAR, P_SIM_RESULT VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    parts_info VARCHAR DEFAULT ''None'';
    shift_info VARCHAR DEFAULT ''Next available'';
    avg_cost FLOAT DEFAULT 1000;
    fail_cost FLOAT DEFAULT 5000;
    prompt VARCHAR;
    llm_response VARCHAR;
BEGIN
    SELECT COALESCE(ARRAY_TO_STRING(ARRAY_AGG(
        part_name || '' (qty:'' || quantity_on_hand || '', $'' || unit_cost || '')''
    ), ''; ''), ''None'') INTO :parts_info
    FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY
    WHERE ARRAY_CONTAINS(:p_asset_id::VARIANT, compatible_assets);

    fail_cost := CASE WHEN :p_stage = ''Critical'' THEN 12000 ELSE 5000 END;

    prompt := CONCAT(
        ''Maintenance AI. Asset '', :p_asset_id, '' has '', :p_failure_mode, '', '', :p_rul_hours::VARCHAR, ''hrs RUL, '', :p_stage,
        ''. Fatigue:'', :p_fatigue_score::VARCHAR, ''. Root cause:'', COALESCE(:p_root_cause, ''Unknown''),
        ''. Parts:'', :parts_info, ''. Repair:$'', :avg_cost::VARCHAR, '' FailureCost:$'', :fail_cost::VARCHAR,
        ''. Reply JSON only no markdown: {""action"":""x"",""priority"":""EMERGENCY"",""parts_needed"":[""x""],""parts_available"":true,""optimal_window"":""x"",""estimated_repair_cost"":520,""estimated_failure_cost"":12000,""cost_savings"":""x"",""risk_if_delayed"":""x"",""work_order_summary"":""x""}''
    );

    SELECT SNOWFLAKE.CORTEX.COMPLETE(''llama3.1-70b'', :prompt) INTO :llm_response;
    
    RETURN :llm_response;
EXCEPTION
    WHEN OTHER THEN
        RETURN CONCAT(''ERROR: '', SQLERRM);
END;
';

-- M5: ANALYZE_ROOT_CAUSE (overload 1)
CREATE OR REPLACE PROCEDURE ML_MODELS.ANALYZE_ROOT_CAUSE(P_ASSET_ID VARCHAR, P_CURRENT_VIB_MAG FLOAT, P_CURRENT_TEMP FLOAT, P_CURRENT_RPM FLOAT, P_CURRENT_AMPS FLOAT, P_FATIGUE_SCORE FLOAT, P_PREDICTED_FAILURE_MODE VARCHAR, P_PREDICTED_RUL_HOURS FLOAT, P_DEGRADATION_STAGE NUMBER(38,0))
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run'
EXECUTE AS CALLER
AS '
import json, re

def run(session, p_asset_id, p_current_vib_mag, p_current_temp, p_current_rpm,
        p_current_amps, p_fatigue_score, p_predicted_failure_mode,
        p_predicted_rul_hours, p_degradation_stage):

    search_query = str(p_predicted_failure_mode) + "" "" + str(p_asset_id) + "" degradation failure""
    fleet_query = str(p_predicted_failure_mode) + "" vibration temperature failure""

    # Retrieve asset-specific maintenance history via Cortex Search
    try:
        search_params = json.dumps({
            ""query"": search_query,
            ""columns"": [""search_text"", ""asset_id"", ""wo_type""],
            ""filter"": {""@eq"": {""asset_id"": str(p_asset_id)}},
            ""limit"": 5
        })
        safe_params = search_params.replace(""''"", ""''''"")
        sql = f""SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(''MFGPULSE_DB.ML_MODELS.MAINTENANCE_SEARCH'', ''{safe_params}''))[''results''] AS results""
        rows = session.sql(sql).collect()
        results_arr = json.loads(str(rows[0][""RESULTS""]))
        asset_history = "" | "".join([r.get(""search_text"", """") for r in results_arr[:5]])
    except Exception as e:
        asset_history = ""No maintenance history found. Error: "" + str(e)

    # Retrieve fleet-wide similar failures
    try:
        fleet_params = json.dumps({
            ""query"": fleet_query,
            ""columns"": [""search_text"", ""asset_id"", ""wo_type""],
            ""limit"": 5
        })
        safe_fleet = fleet_params.replace(""''"", ""''''"")
        sql2 = f""SELECT PARSE_JSON(SNOWFLAKE.CORTEX.SEARCH_PREVIEW(''MFGPULSE_DB.ML_MODELS.MAINTENANCE_SEARCH'', ''{safe_fleet}''))[''results''] AS results""
        frows = session.sql(sql2).collect()
        fleet_arr = json.loads(str(frows[0][""RESULTS""]))
        fleet_history = "" | "".join([r.get(""search_text"", """") for r in fleet_arr[:5]])
    except Exception as e:
        fleet_history = ""No fleet history found. Error: "" + str(e)

    # Build the LLM prompt
    lines = [
        ""You are an expert reliability engineer performing root cause analysis."",
        """",
        ""CURRENT ASSET STATE:"",
        ""- Asset ID: "" + str(p_asset_id),
        ""- Vibration: "" + str(p_current_vib_mag) + "" mm/s"",
        ""- Temperature: "" + str(p_current_temp) + "" C"",
        ""- RPM: "" + str(p_current_rpm),
        ""- Current: "" + str(p_current_amps) + "" A"",
        ""- Fatigue Score: "" + str(p_fatigue_score) + "" (0=healthy, 1=critical)"",
        ""- Predicted Failure Mode: "" + str(p_predicted_failure_mode),
        ""- Predicted RUL: "" + str(p_predicted_rul_hours) + "" hours"",
        ""- Degradation Stage: "" + str(p_degradation_stage) + ""/4"",
        """",
        ""MAINTENANCE HISTORY FOR THIS ASSET:"",
        asset_history,
        """",
        ""SIMILAR FAILURES ACROSS FLEET:"",
        fleet_history,
        """",
        ''Respond ONLY with valid JSON in this exact format:'',
        ''{""root_cause"": ""specific mechanical root cause"",'',
        ''""confidence"": 0.9,'',
        ''""failure_mechanism"": ""bearing_wear or thermal_degradation or imbalance or misalignment or unknown"",'',
        ''""evidence"": [""evidence 1"", ""evidence 2"", ""evidence 3""],'',
        ''""contributing_factors"": [""factor 1"", ""factor 2""],'',
        ''""risk_level"": ""CRITICAL or HIGH or MEDIUM or LOW"",'',
        ''""recommended_immediate_action"": ""what to do now"",'',
        ''""similar_past_failure_reference"": ""reference to similar event""}'',
        """",
        ""No markdown, no text outside JSON.""
    ]
    prompt = chr(10).join(lines)

    safe_prompt = prompt.replace(""''"", ""''''"")
    llm_sql = f""SELECT SNOWFLAKE.CORTEX.COMPLETE(''llama3.3-70b'', ''{safe_prompt}'') AS response""
    llm_rows = session.sql(llm_sql).collect()
    raw = str(llm_rows[0][""RESPONSE""])

    start = raw.find(''{'')
    end = raw.rfind(''}'') + 1
    if start != -1 and end > start:
        try:
            return json.loads(raw[start:end])
        except:
            return {""root_cause"": raw, ""confidence"": 0.5, ""parse_error"": True}
    return {""root_cause"": raw, ""confidence"": 0.5, ""no_json"": True}
';

-- M5: ANALYZE_ROOT_CAUSE (overload 2)
CREATE OR REPLACE PROCEDURE ML_MODELS.ANALYZE_ROOT_CAUSE(P_ASSET_ID VARCHAR, P_VIB_MAG FLOAT, P_TEMP FLOAT, P_RPM FLOAT, P_AMPS FLOAT, P_FATIGUE FLOAT, P_FAILURE_MODE VARCHAR, P_RUL_HOURS FLOAT, P_STAGE VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    LET asset_ctx VARCHAR := '';
    LET fleet_ctx VARCHAR := '';
    LET search_json VARCHAR;
    LET fleet_json VARCHAR;

    search_json := '{"query": "' || :p_failure_mode || ' ' || :p_asset_id || ' failure degradation", "columns": ["search_text","asset_id","wo_type"], "filter": {"@eq": {"asset_id": "' || :p_asset_id || '"}}, "limit": 5}';

    SELECT ARRAY_TO_STRING(
        ARRAY_AGG(r.value:search_text::VARCHAR), '\n'
    ) INTO :asset_ctx
    FROM TABLE(FLATTEN(
        input => PARSE_JSON(
            SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                'MFGPULSE_DB.ML_MODELS.MAINTENANCE_SEARCH',
                :search_json
            )
        )['results']
    )) r;

    fleet_json := '{"query": "' || :p_failure_mode || ' failure root cause repair", "columns": ["search_text","asset_id","wo_type"], "limit": 5}';

    SELECT ARRAY_TO_STRING(
        ARRAY_AGG(r.value:search_text::VARCHAR), '\n'
    ) INTO :fleet_ctx
    FROM TABLE(FLATTEN(
        input => PARSE_JSON(
            SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                'MFGPULSE_DB.ML_MODELS.MAINTENANCE_SEARCH',
                :fleet_json
            )
        )['results']
    )) r;

    LET prompt VARCHAR := 
        'You are an expert reliability engineer. Analyze this asset condition and provide root cause diagnosis.\n\n' ||
        '## CURRENT STATE:\n' ||
        '- Asset: ' || :p_asset_id || '\n' ||
        '- Vibration: ' || :p_vib_mag::VARCHAR || ' mm/s\n' ||
        '- Temperature: ' || :p_temp::VARCHAR || ' C\n' ||
        '- RPM: ' || :p_rpm::VARCHAR || '\n' ||
        '- Current: ' || :p_amps::VARCHAR || ' A\n' ||
        '- Fatigue Score: ' || :p_fatigue::VARCHAR || '/1.0\n' ||
        '- Predicted Failure: ' || :p_failure_mode || '\n' ||
        '- Remaining Life: ' || :p_rul_hours::VARCHAR || ' hours\n' ||
        '- Stage: ' || :p_stage || '\n\n' ||
        '## MAINTENANCE HISTORY:\n' || COALESCE(:asset_ctx, 'None available') || '\n\n' ||
        '## SIMILAR FLEET FAILURES:\n' || COALESCE(:fleet_ctx, 'None available') || '\n\n' ||
        'RESPOND IN VALID JSON ONLY. No markdown, no explanation outside JSON:\n' ||
        '{"root_cause":"<specific mechanical root cause in 1-2 sentences>",' ||
        '"confidence":<0.0 to 1.0>,' ||
        '"failure_mechanism":"<bearing_wear|thermal_degradation|imbalance|misalignment|unknown>",' ||
        '"evidence":["<evidence 1>","<evidence 2>","<evidence 3>"],' ||
        '"risk_level":"<CRITICAL|HIGH|MEDIUM|LOW>",' ||
        '"recommended_action":"<specific action with part numbers if applicable>"}';

    LET llm_response VARCHAR;
    SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', :prompt) INTO :llm_response;

    LET result VARIANT;
    SELECT TRY_PARSE_JSON(REGEXP_SUBSTR(:llm_response, '\\{[\\s\\S]*\\}')) INTO :result;
    
    RETURN :result;
END;

-- PREDICT_ALL orchestrator
CREATE OR REPLACE PROCEDURE ML_MODELS.PREDICT_ALL(P_ASSET_ID VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    v_asset_name VARCHAR;
    v_vib_mag FLOAT; v_temp FLOAT; v_rpm FLOAT; v_amps FLOAT; v_acoustic FLOAT; v_health FLOAT;
    v_rms_24h FLOAT; v_crest_6h FLOAT; v_stress FLOAT; v_composite_health FLOAT;
    v_deg_velocity FLOAT; v_hours_breach FLOAT; v_above_normal FLOAT;
    v_vib_mean_6h FLOAT; v_vib_std_6h FLOAT; v_vib_max_6h FLOAT;
    v_pp_6h FLOAT; v_rms_6h FLOAT; v_cv_6h FLOAT;
    v_temp_mean_6h FLOAT; v_temp_std_6h FLOAT;
    v_current_mean_6h FLOAT; v_current_std_6h FLOAT;
    v_vib_std_24h FLOAT; v_crest_24h FLOAT;
    v_temp_24h FLOAT; v_current_24h FLOAT; v_acoustic_24h FLOAT;
    v_roc FLOAT; v_accel FLOAT;
    v_xy_corr FLOAT; v_vt_coupling FLOAT; v_crpm_ratio FLOAT; v_axis_dom FLOAT; v_av_ratio FLOAT;
    v_iso FLOAT;
    v_fatigue FLOAT;
    v_m1_result OBJECT; v_m2_result OBJECT; v_m3_result OBJECT; v_m6_result OBJECT;
    v_m5_raw VARCHAR; v_m7_raw VARCHAR;
    v_failure_mode VARCHAR; v_rul_hours FLOAT; v_stage VARCHAR;
BEGIN
    -- Get asset info
    SELECT asset_name INTO :v_asset_name FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER WHERE asset_id = :p_asset_id;

    -- Get current health
    SELECT current_vib_magnitude, current_temperature, current_rpm, current_amps, current_acoustic_db, health_score
    INTO :v_vib_mag, :v_temp, :v_rpm, :v_amps, :v_acoustic, :v_health
    FROM MFGPULSE_DB.CURATED.ASSET_HEALTH_CURRENT WHERE asset_id = :p_asset_id;

    -- Get rolling stats features
    SELECT vib_mag_mean_6h, vib_mag_std_6h, vib_mag_max_6h, vib_crest_factor_6h,
           vib_peak_to_peak_6h, vib_rms_6h, vib_coeff_var_6h,
           temp_mean_6h, temp_std_6h, current_mean_6h, current_std_6h,
           vib_mag_std_24h, vib_crest_factor_24h, vib_rms_24h,
           temp_mean_24h, current_mean_24h, acoustic_mean_24h,
           vib_rate_of_change_1h, vib_acceleration_1h
    INTO :v_vib_mean_6h, :v_vib_std_6h, :v_vib_max_6h, :v_crest_6h,
         :v_pp_6h, :v_rms_6h, :v_cv_6h,
         :v_temp_mean_6h, :v_temp_std_6h, :v_current_mean_6h, :v_current_std_6h,
         :v_vib_std_24h, :v_crest_24h, :v_rms_24h,
         :v_temp_24h, :v_current_24h, :v_acoustic_24h,
         :v_roc, :v_accel
    FROM MFGPULSE_DB.ML_FEATURES.ROLLING_STATS
    WHERE asset_id = :p_asset_id ORDER BY timestamp DESC LIMIT 1;

    -- Get sensor interaction features
    SELECT vib_xy_correlation_daily, vib_temp_coupling_daily, current_rpm_ratio, vib_axis_dominance, acoustic_vib_ratio
    INTO :v_xy_corr, :v_vt_coupling, :v_crpm_ratio, :v_axis_dom, :v_av_ratio
    FROM MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS
    WHERE asset_id = :p_asset_id ORDER BY timestamp DESC LIMIT 1;

    -- Get temporal + physics features
    SELECT tm.degradation_velocity_30d, tm.hours_since_first_breach, tm.above_normal_count_24h,
           pc.stress_index, pc.composite_health_score, pc.iso_10816_severity
    INTO :v_deg_velocity, :v_hours_breach, :v_above_normal, :v_stress, :v_composite_health, :v_iso
    FROM MFGPULSE_DB.ML_FEATURES.TEMPORAL_MEMORY tm
    JOIN MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE pc ON tm.asset_id = pc.asset_id AND tm.timestamp = pc.timestamp
    WHERE tm.asset_id = :p_asset_id ORDER BY tm.timestamp DESC LIMIT 1;

    -- Get fatigue score
    v_fatigue := 0;
    BEGIN
        SELECT fatigue_score INTO :v_fatigue
        FROM MFGPULSE_DB.ML_MODELS.FATIGUE_SCORES
        WHERE asset_id = :p_asset_id ORDER BY timestamp DESC LIMIT 1;
    EXCEPTION WHEN OTHER THEN v_fatigue := 0;
    END;

    -- ===== M1: Failure Mode =====
    SELECT MFGPULSE_DB.ML_MODELS.PREDICT_FAILURE_MODE(
        :v_vib_mean_6h, :v_vib_std_6h, :v_vib_max_6h, :v_crest_6h, :v_pp_6h, :v_rms_6h, :v_cv_6h,
        :v_temp_mean_6h, :v_temp_std_6h, :v_current_mean_6h, :v_current_std_6h,
        :v_rms_24h, :v_vib_std_24h, :v_crest_24h, :v_rms_24h,
        :v_temp_24h, :v_current_24h, :v_acoustic_24h,
        :v_roc, :v_accel,
        :v_xy_corr, :v_vt_coupling, :v_crpm_ratio, :v_axis_dom, :v_av_ratio,
        :v_stress, :v_iso, :v_composite_health
    ) INTO :v_m1_result;
    v_failure_mode := :v_m1_result[''predicted_failure_mode'']::VARCHAR;

    -- ===== M2: RUL =====
    SELECT MFGPULSE_DB.ML_MODELS.PREDICT_RUL(
        :v_rms_24h, :v_roc, :v_accel, :v_deg_velocity, :v_hours_breach, :v_stress, :v_composite_health, :v_fatigue
    ) INTO :v_m2_result;
    v_rul_hours := :v_m2_result[''predicted_rul_hours'']::FLOAT;

    -- ===== M3: Degradation Stage =====
    SELECT MFGPULSE_DB.ML_MODELS.PREDICT_DEGRADATION_STAGE(
        :v_rms_24h, :v_crest_6h, :v_stress, :v_composite_health, :v_deg_velocity, :v_hours_breach, :v_above_normal
    ) INTO :v_m3_result;
    v_stage := :v_m3_result[''predicted_stage'']::VARCHAR;

    -- ===== M4: Fatigue Score (already computed) =====

    -- ===== M5: Root Cause (LLM) =====
    CALL MFGPULSE_DB.ML_MODELS.ANALYZE_ROOT_CAUSE(
        :p_asset_id, :v_vib_mag, :v_temp, :v_rpm, :v_amps, :v_fatigue,
        :v_failure_mode, :v_rul_hours, :v_stage
    );
    SELECT * INTO :v_m5_raw FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- ===== M6: Simulation =====
    SELECT MFGPULSE_DB.ML_MODELS.SIMULATE_FAILURE_TWIN(
        :v_vib_mag, COALESCE(:v_deg_velocity, 0.1), COALESCE(:v_fatigue, 0.5), 0, 7, 0
    ) INTO :v_m6_result;

    -- ===== M7: Prescriptive AI (LLM) =====
    CALL MFGPULSE_DB.ML_MODELS.PRESCRIBE_MAINTENANCE(
        :p_asset_id, :v_failure_mode, :v_rul_hours, :v_stage, :v_fatigue,
        TRY_PARSE_JSON(:v_m5_raw):root_cause::VARCHAR,
        :v_m6_result::VARCHAR
    );
    SELECT * INTO :v_m7_raw FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));

    -- ===== ASSEMBLE RESULT =====
    RETURN OBJECT_CONSTRUCT(
        ''asset_id'', :p_asset_id,
        ''asset_name'', :v_asset_name,
        ''current_state'', OBJECT_CONSTRUCT(
            ''vibration_mm_s'', ROUND(:v_vib_mag, 2),
            ''temperature_c'', ROUND(:v_temp, 1),
            ''rpm'', ROUND(:v_rpm, 0),
            ''current_amps'', ROUND(:v_amps, 1),
            ''health_score'', ROUND(:v_health, 0),
            ''fatigue_score'', ROUND(:v_fatigue, 3)
        ),
        ''M1_failure_mode'', :v_m1_result,
        ''M2_remaining_useful_life'', :v_m2_result,
        ''M3_degradation_stage'', :v_m3_result,
        ''M4_fatigue_score'', ROUND(:v_fatigue, 3),
        ''M5_root_cause'', TRY_PARSE_JSON(:v_m5_raw),
        ''M6_simulation'', :v_m6_result,
        ''M7_prescription'', TRY_PARSE_JSON(:v_m7_raw)
    );
EXCEPTION
    WHEN OTHER THEN
        RETURN OBJECT_CONSTRUCT(''error'', SQLERRM, ''asset_id'', :p_asset_id);
END;
';

-- PREDICT_CORE: Fast M1-M4 diagnosis (no LLM calls, <2s)
CREATE OR REPLACE PROCEDURE ML_MODELS.PREDICT_CORE(P_ASSET_ID VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    v_asset_name VARCHAR;
    v_vib_mag FLOAT; v_temp FLOAT; v_rpm FLOAT; v_amps FLOAT; v_acoustic FLOAT; v_health FLOAT;
    v_rms_24h FLOAT; v_crest_6h FLOAT; v_stress FLOAT; v_composite_health FLOAT;
    v_deg_velocity FLOAT; v_hours_breach FLOAT; v_above_normal FLOAT;
    v_vib_mean_6h FLOAT; v_vib_std_6h FLOAT; v_vib_max_6h FLOAT;
    v_pp_6h FLOAT; v_rms_6h FLOAT; v_cv_6h FLOAT;
    v_temp_mean_6h FLOAT; v_temp_std_6h FLOAT;
    v_current_mean_6h FLOAT; v_current_std_6h FLOAT;
    v_vib_std_24h FLOAT; v_crest_24h FLOAT;
    v_temp_24h FLOAT; v_current_24h FLOAT; v_acoustic_24h FLOAT;
    v_roc FLOAT; v_accel FLOAT;
    v_xy_corr FLOAT; v_vt_coupling FLOAT; v_crpm_ratio FLOAT; v_axis_dom FLOAT; v_av_ratio FLOAT;
    v_iso FLOAT;
    v_fatigue FLOAT;
    v_m1_result OBJECT; v_m2_result OBJECT; v_m3_result OBJECT;
    v_failure_mode VARCHAR; v_rul_hours FLOAT; v_stage VARCHAR;
BEGIN
    SELECT asset_name INTO :v_asset_name FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER WHERE asset_id = :p_asset_id;
    SELECT current_vib_magnitude, current_temperature, current_rpm, current_amps, current_acoustic_db, health_score
    INTO :v_vib_mag, :v_temp, :v_rpm, :v_amps, :v_acoustic, :v_health
    FROM MFGPULSE_DB.CURATED.ASSET_HEALTH_CURRENT WHERE asset_id = :p_asset_id;
    SELECT vib_mag_mean_6h, vib_mag_std_6h, vib_mag_max_6h, vib_crest_factor_6h,
           vib_peak_to_peak_6h, vib_rms_6h, vib_coeff_var_6h,
           temp_mean_6h, temp_std_6h, current_mean_6h, current_std_6h,
           vib_mag_std_24h, vib_crest_factor_24h, vib_rms_24h,
           temp_mean_24h, current_mean_24h, acoustic_mean_24h,
           vib_rate_of_change_1h, vib_acceleration_1h
    INTO :v_vib_mean_6h, :v_vib_std_6h, :v_vib_max_6h, :v_crest_6h,
         :v_pp_6h, :v_rms_6h, :v_cv_6h,
         :v_temp_mean_6h, :v_temp_std_6h, :v_current_mean_6h, :v_current_std_6h,
         :v_vib_std_24h, :v_crest_24h, :v_rms_24h,
         :v_temp_24h, :v_current_24h, :v_acoustic_24h,
         :v_roc, :v_accel
    FROM MFGPULSE_DB.ML_FEATURES.ROLLING_STATS
    WHERE asset_id = :p_asset_id ORDER BY timestamp DESC LIMIT 1;
    SELECT vib_xy_correlation_daily, vib_temp_coupling_daily, current_rpm_ratio, vib_axis_dominance, acoustic_vib_ratio
    INTO :v_xy_corr, :v_vt_coupling, :v_crpm_ratio, :v_axis_dom, :v_av_ratio
    FROM MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS
    WHERE asset_id = :p_asset_id ORDER BY timestamp DESC LIMIT 1;
    SELECT tm.degradation_velocity_30d, tm.hours_since_first_breach, tm.above_normal_count_24h,
           pc.stress_index, pc.composite_health_score, pc.iso_10816_severity
    INTO :v_deg_velocity, :v_hours_breach, :v_above_normal, :v_stress, :v_composite_health, :v_iso
    FROM MFGPULSE_DB.ML_FEATURES.TEMPORAL_MEMORY tm
    JOIN MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE pc ON tm.asset_id = pc.asset_id AND tm.timestamp = pc.timestamp
    WHERE tm.asset_id = :p_asset_id ORDER BY tm.timestamp DESC LIMIT 1;
    v_fatigue := 0;
    BEGIN
        SELECT fatigue_score INTO :v_fatigue
        FROM MFGPULSE_DB.ML_MODELS.FATIGUE_SCORES
        WHERE asset_id = :p_asset_id ORDER BY timestamp DESC LIMIT 1;
    EXCEPTION WHEN OTHER THEN v_fatigue := 0;
    END;
    SELECT MFGPULSE_DB.ML_MODELS.PREDICT_FAILURE_MODE(
        :v_vib_mean_6h, :v_vib_std_6h, :v_vib_max_6h, :v_crest_6h, :v_pp_6h, :v_rms_6h, :v_cv_6h,
        :v_temp_mean_6h, :v_temp_std_6h, :v_current_mean_6h, :v_current_std_6h,
        :v_rms_24h, :v_vib_std_24h, :v_crest_24h, :v_rms_24h,
        :v_temp_24h, :v_current_24h, :v_acoustic_24h,
        :v_roc, :v_accel,
        :v_xy_corr, :v_vt_coupling, :v_crpm_ratio, :v_axis_dom, :v_av_ratio,
        :v_stress, :v_iso, :v_composite_health
    ) INTO :v_m1_result;
    v_failure_mode := :v_m1_result[''predicted_failure_mode'']::VARCHAR;
    SELECT MFGPULSE_DB.ML_MODELS.PREDICT_RUL(
        :v_rms_24h, :v_roc, :v_accel, :v_deg_velocity, :v_hours_breach, :v_stress, :v_composite_health, :v_fatigue
    ) INTO :v_m2_result;
    v_rul_hours := :v_m2_result[''predicted_rul_hours'']::FLOAT;
    SELECT MFGPULSE_DB.ML_MODELS.PREDICT_DEGRADATION_STAGE(
        :v_rms_24h, :v_crest_6h, :v_stress, :v_composite_health, :v_deg_velocity, :v_hours_breach, :v_above_normal
    ) INTO :v_m3_result;
    v_stage := :v_m3_result[''predicted_stage'']::VARCHAR;
    RETURN OBJECT_CONSTRUCT(
        ''asset_id'', :p_asset_id, ''asset_name'', :v_asset_name,
        ''current_state'', OBJECT_CONSTRUCT(
            ''vibration_mm_s'', ROUND(:v_vib_mag, 2), ''temperature_c'', ROUND(:v_temp, 1),
            ''rpm'', ROUND(:v_rpm, 0), ''current_amps'', ROUND(:v_amps, 1),
            ''health_score'', ROUND(:v_health, 0), ''fatigue_score'', ROUND(:v_fatigue, 3)
        ),
        ''M1_failure_mode'', :v_m1_result,
        ''M2_remaining_useful_life'', :v_m2_result,
        ''M3_degradation_stage'', :v_m3_result,
        ''M4_fatigue_score'', ROUND(:v_fatigue, 3)
    );
EXCEPTION
    WHEN OTHER THEN
        RETURN OBJECT_CONSTRUCT(''error'', SQLERRM, ''asset_id'', :p_asset_id);
END;
';

-- PREDICT_DEEP: LLM-powered M5-M7 analysis (root cause + simulation + prescription)
CREATE OR REPLACE PROCEDURE ML_MODELS.PREDICT_DEEP(
    P_ASSET_ID VARCHAR, P_FAILURE_MODE VARCHAR, P_RUL_HOURS FLOAT,
    P_STAGE VARCHAR, P_FATIGUE_SCORE FLOAT
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    v_vib_mag FLOAT; v_temp FLOAT; v_rpm FLOAT; v_amps FLOAT;
    v_deg_velocity FLOAT;
    v_m5_raw VARCHAR; v_m6_result OBJECT; v_m7_raw VARCHAR;
BEGIN
    SELECT current_vib_magnitude, current_temperature, current_rpm, current_amps
    INTO :v_vib_mag, :v_temp, :v_rpm, :v_amps
    FROM MFGPULSE_DB.CURATED.ASSET_HEALTH_CURRENT WHERE asset_id = :p_asset_id;
    v_deg_velocity := 0.1;
    BEGIN
        SELECT degradation_velocity_30d INTO :v_deg_velocity
        FROM MFGPULSE_DB.ML_FEATURES.TEMPORAL_MEMORY
        WHERE asset_id = :p_asset_id ORDER BY timestamp DESC LIMIT 1;
    EXCEPTION WHEN OTHER THEN v_deg_velocity := 0.1;
    END;
    CALL MFGPULSE_DB.ML_MODELS.ANALYZE_ROOT_CAUSE(
        :p_asset_id, :v_vib_mag, :v_temp, :v_rpm, :v_amps, :p_fatigue_score,
        :p_failure_mode, :p_rul_hours, :p_stage
    );
    SELECT * INTO :v_m5_raw FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    SELECT MFGPULSE_DB.ML_MODELS.SIMULATE_FAILURE_TWIN(
        :v_vib_mag, COALESCE(:v_deg_velocity, 0.1), COALESCE(:p_fatigue_score, 0.5), 0, 7, 0
    ) INTO :v_m6_result;
    CALL MFGPULSE_DB.ML_MODELS.PRESCRIBE_MAINTENANCE(
        :p_asset_id, :p_failure_mode, :p_rul_hours, :p_stage, :p_fatigue_score,
        TRY_PARSE_JSON(:v_m5_raw):root_cause::VARCHAR,
        :v_m6_result::VARCHAR
    );
    SELECT * INTO :v_m7_raw FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    RETURN OBJECT_CONSTRUCT(
        ''asset_id'', :p_asset_id,
        ''M5_root_cause'', TRY_PARSE_JSON(:v_m5_raw),
        ''M6_simulation'', :v_m6_result,
        ''M7_prescription'', TRY_PARSE_JSON(:v_m7_raw)
    );
EXCEPTION
    WHEN OTHER THEN
        RETURN OBJECT_CONSTRUCT(''error'', SQLERRM, ''asset_id'', :p_asset_id);
END;
';
-- CHECKPOINT 7: DYNAMIC TABLES (Curated + ML Features)
-- ============================================================================

-- 10 Dynamic Tables in dependency order.
-- Layer 1: Curated (reads from base tables)
drop table if exists CURATED.SENSOR_WITH_CONTEXT;
-- SENSOR_WITH_CONTEXT
create or replace dynamic table CURATED.SENSOR_WITH_CONTEXT(
	READING_ID,
	ASSET_ID,
	ASSET_NAME,
	ASSET_TYPE,
	LINE_ID,
	TIMESTAMP,
	VIBRATION_X,
	VIBRATION_Y,
	VIBRATION_Z,
	VIBRATION_MAGNITUDE,
	TEMPERATURE,
	RPM,
	PRESSURE,
	CURRENT_AMPS,
	ACOUSTIC_DB,
	RATED_RPM,
	RATED_TEMP_MAX,
	TEMP_RATIO_TO_MAX,
	RPM_RATIO_TO_RATED,
	LAST_MAINTENANCE_DATE,
	HOURS_SINCE_LAST_MAINTENANCE
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
 as
SELECT 
    sr.reading_id,
    sr.asset_id,
    am.asset_name,
    am.asset_type,
    am.line_id,
    sr.timestamp,
    sr.vibration_x,
    sr.vibration_y,
    sr.vibration_z,
    SQRT(POWER(sr.vibration_x,2) + POWER(sr.vibration_y,2) + POWER(sr.vibration_z,2)) AS vibration_magnitude,
    sr.temperature,
    sr.rpm,
    sr.pressure,
    sr.current_amps,
    sr.acoustic_db,
    am.rated_rpm,
    am.rated_temp_max,
    sr.temperature / NULLIF(am.rated_temp_max, 0) AS temp_ratio_to_max,
    sr.rpm / NULLIF(am.rated_rpm, 0) AS rpm_ratio_to_rated,
    lm.last_maintenance_date,
    DATEDIFF('hour', lm.last_maintenance_date, sr.timestamp) AS hours_since_last_maintenance
FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS sr
JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON sr.asset_id = am.asset_id
LEFT JOIN (
    SELECT asset_id, MAX(completed_date) AS last_maintenance_date
    FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS
    WHERE status = 'completed'
    GROUP BY asset_id
) lm ON sr.asset_id = lm.asset_id;

drop table if exists CURATED.ASSET_HEALTH_CURRENT;
-- ASSET_HEALTH_CURRENT
create or replace dynamic table CURATED.ASSET_HEALTH_CURRENT(
	ASSET_ID,
	ASSET_NAME,
	ASSET_TYPE,
	LINE_ID,
	LAST_READING_TIME,
	CURRENT_VIB_X,
	CURRENT_VIB_Y,
	CURRENT_VIB_Z,
	CURRENT_VIB_MAGNITUDE,
	CURRENT_TEMPERATURE,
	CURRENT_RPM,
	CURRENT_PRESSURE,
	CURRENT_AMPS,
	CURRENT_ACOUSTIC_DB,
	AVG_VIB_MAG_24H,
	AVG_TEMP_24H,
	AVG_RPM_24H,
	AVG_CURRENT_24H,
	STD_VIB_X_24H,
	STD_TEMP_24H,
	MAX_VIB_MAG_24H,
	HEALTH_SCORE
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
 as
WITH latest_readings AS (
    SELECT *,
        ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn
    FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS
),
recent_stats AS (
    SELECT 
        asset_id,
        AVG(vibration_x) AS avg_vib_x_24h,
        AVG(vibration_y) AS avg_vib_y_24h,
        AVG(vibration_z) AS avg_vib_z_24h,
        AVG(SQRT(POWER(vibration_x,2)+POWER(vibration_y,2)+POWER(vibration_z,2))) AS avg_vib_mag_24h,
        AVG(temperature) AS avg_temp_24h,
        AVG(rpm) AS avg_rpm_24h,
        AVG(current_amps) AS avg_current_24h,
        STDDEV(vibration_x) AS std_vib_x_24h,
        STDDEV(temperature) AS std_temp_24h,
        MAX(SQRT(POWER(vibration_x,2)+POWER(vibration_y,2)+POWER(vibration_z,2))) AS max_vib_mag_24h
    FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS
    WHERE timestamp >= DATEADD('hour', -24, (SELECT MAX(timestamp) FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS))
    GROUP BY asset_id
)
SELECT 
    lr.asset_id,
    am.asset_name,
    am.asset_type,
    am.line_id,
    lr.timestamp AS last_reading_time,
    lr.vibration_x AS current_vib_x,
    lr.vibration_y AS current_vib_y,
    lr.vibration_z AS current_vib_z,
    SQRT(POWER(lr.vibration_x,2)+POWER(lr.vibration_y,2)+POWER(lr.vibration_z,2)) AS current_vib_magnitude,
    lr.temperature AS current_temperature,
    lr.rpm AS current_rpm,
    lr.pressure AS current_pressure,
    lr.current_amps AS current_amps,
    lr.acoustic_db AS current_acoustic_db,
    rs.avg_vib_mag_24h,
    rs.avg_temp_24h,
    rs.avg_rpm_24h,
    rs.avg_current_24h,
    rs.std_vib_x_24h,
    rs.std_temp_24h,
    rs.max_vib_mag_24h,
    -- Simple health score (0-100, lower = worse)
    GREATEST(0, LEAST(100,
        100 
        - CASE WHEN SQRT(POWER(lr.vibration_x,2)+POWER(lr.vibration_y,2)+POWER(lr.vibration_z,2)) > 7 THEN 40
               WHEN SQRT(POWER(lr.vibration_x,2)+POWER(lr.vibration_y,2)+POWER(lr.vibration_z,2)) > 4 THEN 20
               WHEN SQRT(POWER(lr.vibration_x,2)+POWER(lr.vibration_y,2)+POWER(lr.vibration_z,2)) > 2.5 THEN 10
               ELSE 0 END
        - CASE WHEN lr.temperature / NULLIF(am.rated_temp_max,0) > 0.9 THEN 30
               WHEN lr.temperature / NULLIF(am.rated_temp_max,0) > 0.75 THEN 15
               ELSE 0 END
        - CASE WHEN rs.std_vib_x_24h > 3 THEN 20
               WHEN rs.std_vib_x_24h > 1.5 THEN 10
               ELSE 0 END
    )) AS health_score
FROM latest_readings lr
JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON lr.asset_id = am.asset_id
LEFT JOIN recent_stats rs ON lr.asset_id = rs.asset_id
WHERE lr.rn = 1;

-- FAILURE_HISTORY
drop table if exists CURATED.FAILURE_HISTORY;
create or replace dynamic table CURATED.FAILURE_HISTORY(
	WO_ID,
	ASSET_ID,
	FAILURE_DATE,
	WO_TYPE,
	PRIORITY,
	TOTAL_COST,
	PRE_FAIL_AVG_VIB_X,
	PRE_FAIL_AVG_VIB_Y,
	PRE_FAIL_AVG_VIB_Z,
	PRE_FAIL_AVG_VIB_MAG,
	PRE_FAIL_MAX_VIB_MAG,
	PRE_FAIL_AVG_TEMP,
	PRE_FAIL_MAX_TEMP,
	PRE_FAIL_AVG_CURRENT,
	PRE_FAIL_MAX_CURRENT,
	PRE_FAIL_AVG_ACOUSTIC,
	PRE_FAIL_STD_VIB_X,
	PRE_FAIL_STD_TEMP,
	READINGS_IN_WINDOW,
	ASSET_NAME,
	ASSET_TYPE,
	LINE_ID,
	FAILURE_NOTES
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
 as
WITH failure_events AS (
    SELECT 
        wo_id,
        asset_id,
        created_date AS failure_date,
        wo_type,
        priority,
        total_cost
    FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS
    WHERE wo_type IN ('emergency', 'corrective')
),
pre_failure_stats AS (
    SELECT 
        fe.wo_id,
        fe.asset_id,
        fe.failure_date,
        fe.wo_type,
        fe.priority,
        fe.total_cost,
        -- Stats from 7 days before failure
        AVG(sr.vibration_x) AS pre_fail_avg_vib_x,
        AVG(sr.vibration_y) AS pre_fail_avg_vib_y,
        AVG(sr.vibration_z) AS pre_fail_avg_vib_z,
        AVG(SQRT(POWER(sr.vibration_x,2)+POWER(sr.vibration_y,2)+POWER(sr.vibration_z,2))) AS pre_fail_avg_vib_mag,
        MAX(SQRT(POWER(sr.vibration_x,2)+POWER(sr.vibration_y,2)+POWER(sr.vibration_z,2))) AS pre_fail_max_vib_mag,
        AVG(sr.temperature) AS pre_fail_avg_temp,
        MAX(sr.temperature) AS pre_fail_max_temp,
        AVG(sr.current_amps) AS pre_fail_avg_current,
        MAX(sr.current_amps) AS pre_fail_max_current,
        AVG(sr.acoustic_db) AS pre_fail_avg_acoustic,
        STDDEV(sr.vibration_x) AS pre_fail_std_vib_x,
        STDDEV(sr.temperature) AS pre_fail_std_temp,
        COUNT(sr.reading_id) AS readings_in_window
    FROM failure_events fe
    JOIN MFGPULSE_DB.RAW_OT.SENSOR_READINGS sr 
        ON fe.asset_id = sr.asset_id 
        AND sr.timestamp BETWEEN DATEADD('day', -7, fe.failure_date) AND fe.failure_date
    GROUP BY fe.wo_id, fe.asset_id, fe.failure_date, fe.wo_type, fe.priority, fe.total_cost
)
SELECT 
    pfs.*,
    am.asset_name,
    am.asset_type,
    am.line_id,
    ml.notes_text AS failure_notes
FROM pre_failure_stats pfs
JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON pfs.asset_id = am.asset_id
LEFT JOIN MFGPULSE_DB.RAW_IT.MAINTENANCE_LOGS ml ON pfs.wo_id = ml.wo_id
    AND ml.log_id = (
        SELECT MIN(log_id) FROM MFGPULSE_DB.RAW_IT.MAINTENANCE_LOGS 
        WHERE wo_id = pfs.wo_id
    );


-- Layer 2: ML Features (reads from Curated DTs)

-- ROLLING_STATS
drop table if exists ML_FEATURES.ROLLING_STATS;
create or replace dynamic table ML_FEATURES.ROLLING_STATS(
	ASSET_ID,
	TIMESTAMP,
	CURRENT_VIB_MAG,
	CURRENT_TEMP,
	CURRENT_AMPS_VAL,
	CURRENT_RPM,
	CURRENT_ACOUSTIC,
	VIB_MAG_MEAN_6H,
	VIB_MAG_STD_6H,
	VIB_MAG_MIN_6H,
	VIB_MAG_MAX_6H,
	VIB_CREST_FACTOR_6H,
	VIB_PEAK_TO_PEAK_6H,
	VIB_RMS_6H,
	VIB_COEFF_VAR_6H,
	TEMP_MEAN_6H,
	TEMP_STD_6H,
	TEMP_MAX_6H,
	CURRENT_MEAN_6H,
	CURRENT_STD_6H,
	CURRENT_MAX_6H,
	VIB_MAG_MEAN_24H,
	VIB_MAG_STD_24H,
	VIB_MAG_MIN_24H,
	VIB_MAG_MAX_24H,
	VIB_CREST_FACTOR_24H,
	VIB_PEAK_TO_PEAK_24H,
	VIB_RMS_24H,
	VIB_COEFF_VAR_24H,
	TEMP_MEAN_24H,
	TEMP_STD_24H,
	TEMP_MAX_24H,
	CURRENT_MEAN_24H,
	CURRENT_STD_24H,
	CURRENT_MAX_24H,
	ACOUSTIC_MEAN_24H,
	ACOUSTIC_STD_24H,
	VIB_RATE_OF_CHANGE_1H,
	VIB_ACCELERATION_1H,
	TEMP_RATE_OF_CHANGE_1H,
	CURRENT_RATE_OF_CHANGE_1H
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
 as
WITH base AS (
    SELECT 
        asset_id,
        timestamp,
        SQRT(POWER(vibration_x,2)+POWER(vibration_y,2)+POWER(vibration_z,2)) AS vib_mag,
        vibration_x, vibration_y, vibration_z,
        temperature,
        rpm,
        current_amps,
        acoustic_db,
        ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp) AS rn
    FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS
)
SELECT 
    asset_id,
    timestamp,
    vib_mag AS current_vib_mag,
    temperature AS current_temp,
    current_amps AS current_amps_val,
    rpm AS current_rpm,
    acoustic_db AS current_acoustic,
    
    -- 6HR WINDOW (24 rows at 15-min intervals): VIBRATION
    AVG(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) AS vib_mag_mean_6h,
    STDDEV(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) AS vib_mag_std_6h,
    MIN(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) AS vib_mag_min_6h,
    MAX(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) AS vib_mag_max_6h,
    -- Crest Factor = Peak / RMS
    MAX(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) /
        NULLIF(SQRT(AVG(POWER(vib_mag,2)) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW)),0) AS vib_crest_factor_6h,
    -- Peak-to-Peak
    MAX(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) -
        MIN(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) AS vib_peak_to_peak_6h,
    -- RMS Energy
    SQRT(AVG(POWER(vib_mag,2)) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW)) AS vib_rms_6h,
    -- Coefficient of Variation
    STDDEV(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) /
        NULLIF(AVG(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW),0) AS vib_coeff_var_6h,
    
    -- 6HR: TEMPERATURE
    AVG(temperature) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) AS temp_mean_6h,
    STDDEV(temperature) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) AS temp_std_6h,
    MAX(temperature) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) AS temp_max_6h,
    
    -- 6HR: CURRENT
    AVG(current_amps) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) AS current_mean_6h,
    STDDEV(current_amps) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) AS current_std_6h,
    MAX(current_amps) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 24 PRECEDING AND CURRENT ROW) AS current_max_6h,

    -- 24HR WINDOW (96 rows): VIBRATION
    AVG(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS vib_mag_mean_24h,
    STDDEV(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS vib_mag_std_24h,
    MIN(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS vib_mag_min_24h,
    MAX(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS vib_mag_max_24h,
    MAX(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) /
        NULLIF(SQRT(AVG(POWER(vib_mag,2)) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW)),0) AS vib_crest_factor_24h,
    MAX(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) -
        MIN(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS vib_peak_to_peak_24h,
    SQRT(AVG(POWER(vib_mag,2)) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW)) AS vib_rms_24h,
    STDDEV(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) /
        NULLIF(AVG(vib_mag) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW),0) AS vib_coeff_var_24h,

    -- 24HR: TEMPERATURE
    AVG(temperature) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS temp_mean_24h,
    STDDEV(temperature) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS temp_std_24h,
    MAX(temperature) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS temp_max_24h,

    -- 24HR: CURRENT
    AVG(current_amps) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS current_mean_24h,
    STDDEV(current_amps) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS current_std_24h,
    MAX(current_amps) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS current_max_24h,

    -- 24HR: ACOUSTIC
    AVG(acoustic_db) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS acoustic_mean_24h,
    STDDEV(acoustic_db) OVER (PARTITION BY asset_id ORDER BY rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS acoustic_std_24h,

    -- DYNAMICS: Rate of change (1hr = 4 readings apart)
    (vib_mag - LAG(vib_mag, 4) OVER (PARTITION BY asset_id ORDER BY rn)) AS vib_rate_of_change_1h,
    -- Acceleration of change (2nd derivative)
    (vib_mag - 2*LAG(vib_mag, 4) OVER (PARTITION BY asset_id ORDER BY rn) + LAG(vib_mag, 8) OVER (PARTITION BY asset_id ORDER BY rn)) AS vib_acceleration_1h,
    -- Temperature rate of change
    (temperature - LAG(temperature, 4) OVER (PARTITION BY asset_id ORDER BY rn)) AS temp_rate_of_change_1h,
    -- Current rate of change  
    (current_amps - LAG(current_amps, 4) OVER (PARTITION BY asset_id ORDER BY rn)) AS current_rate_of_change_1h

FROM base;

-- SENSOR_INTERACTIONS
drop table if exists ML_FEATURES.SENSOR_INTERACTIONS;
create or replace dynamic table ML_FEATURES.SENSOR_INTERACTIONS(
	ASSET_ID,
	TIMESTAMP,
	VIB_XY_CORRELATION_DAILY,
	VIB_TEMP_COUPLING_DAILY,
	CURRENT_RPM_RATIO,
	TEMP_LOAD_RATIO,
	VIB_AXIS_DOMINANCE,
	ACOUSTIC_VIB_RATIO,
	CURRENT_VIB_COUPLING_DAILY
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
 as
WITH daily_corr AS (
    SELECT 
        asset_id,
        DATE_TRUNC('day', timestamp) AS reading_date,
        -- Correlations computed daily (96 readings per day)
        CORR(vibration_x, vibration_y) AS vib_xy_correlation,
        CORR(SQRT(POWER(vibration_x,2)+POWER(vibration_y,2)+POWER(vibration_z,2)), temperature) AS vib_temp_coupling,
        CORR(current_amps, SQRT(POWER(vibration_x,2)+POWER(vibration_y,2)+POWER(vibration_z,2))) AS current_vib_coupling
    FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS
    GROUP BY asset_id, DATE_TRUNC('day', timestamp)
),
readings AS (
    SELECT 
        asset_id,
        timestamp,
        DATE_TRUNC('day', timestamp) AS reading_date,
        vibration_x, vibration_y, vibration_z,
        SQRT(POWER(vibration_x,2)+POWER(vibration_y,2)+POWER(vibration_z,2)) AS vib_mag,
        temperature,
        rpm,
        current_amps,
        acoustic_db
    FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS
)
SELECT 
    r.asset_id,
    r.timestamp,
    
    -- 1. Vib_X to Vib_Y correlation (daily) — high = misalignment, low = bearing
    dc.vib_xy_correlation AS vib_xy_correlation_daily,
    
    -- 2. Vibration to Temperature coupling — friction source detector
    dc.vib_temp_coupling AS vib_temp_coupling_daily,
    
    -- 3. Current to RPM ratio — load-normalized power (rising = mechanical resistance)
    r.current_amps / NULLIF(r.rpm, 0) * 1000 AS current_rpm_ratio,
    
    -- 4. Temperature to Load ratio — heat per unit work (rising = efficiency loss)
    r.temperature / NULLIF(r.current_amps * r.rpm, 0) * 10000 AS temp_load_ratio,
    
    -- 5. Vibration axis dominance — X-dominant = imbalance, multi-axis = misalignment
    GREATEST(ABS(r.vibration_x), ABS(r.vibration_y), ABS(r.vibration_z)) / NULLIF(r.vib_mag, 0) AS vib_axis_dominance,
    
    -- 6. Acoustic to Vibration ratio — rising with stable vib = internal crack
    r.acoustic_db / NULLIF(r.vib_mag, 0) AS acoustic_vib_ratio,
    
    -- 7. Current-Vibration coupling (daily) — mechanical load transfer
    dc.current_vib_coupling AS current_vib_coupling_daily

FROM readings r
JOIN daily_corr dc ON r.asset_id = dc.asset_id AND r.reading_date = dc.reading_date;

-- PHYSICS_COMPOSITE (INCREMENTAL)
drop table if exists ML_FEATURES.PHYSICS_COMPOSITE;
create or replace dynamic table ML_FEATURES.PHYSICS_COMPOSITE(
	ASSET_ID,
	TIMESTAMP,
	MECHANICAL_POWER_PROXY,
	THERMAL_EFFICIENCY,
	ISO_10816_SEVERITY,
	BEARING_DEFECT_INDICATOR,
	ENERGY_BALANCE_RATIO,
	STRESS_INDEX,
	OPERATING_REGIME,
	COMPOSITE_HEALTH_SCORE
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
 as
WITH base AS (
    SELECT 
        sr.asset_id,
        sr.timestamp,
        sr.vibration_x, sr.vibration_y, sr.vibration_z,
        SQRT(POWER(sr.vibration_x,2)+POWER(sr.vibration_y,2)+POWER(sr.vibration_z,2)) AS vib_mag,
        sr.temperature,
        sr.rpm,
        sr.current_amps,
        sr.acoustic_db,
        sr.pressure,
        am.rated_rpm,
        am.rated_temp_max,
        ROW_NUMBER() OVER (PARTITION BY sr.asset_id ORDER BY sr.timestamp) AS rn
    FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS sr
    JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON sr.asset_id = am.asset_id
)
SELECT 
    asset_id,
    timestamp,
    
    -- 1. Mechanical Power Proxy = torque * speed ≈ current * rpm
    current_amps * rpm AS mechanical_power_proxy,
    
    -- 2. Thermal Efficiency = useful work / heat generated
    (current_amps * rpm) / NULLIF(temperature, 0) AS thermal_efficiency,
    
    -- 3. Vibration Severity per ISO 10816 (RMS velocity in mm/s)
    --    Good: <2.8, Satisfactory: 2.8-7.1, Unsatisfactory: 7.1-18, Unacceptable: >18
    CASE 
        WHEN vib_mag < 2.8 THEN 1   -- Good
        WHEN vib_mag < 7.1 THEN 2   -- Satisfactory  
        WHEN vib_mag < 18.0 THEN 3  -- Unsatisfactory
        ELSE 4                       -- Unacceptable
    END AS iso_10816_severity,
    
    -- 4. Bearing Defect Frequency Indicator
    --    Approximated: high kurtosis in vib + increasing acoustic = bearing defect
    (vib_mag * acoustic_db) / NULLIF(rpm, 0) AS bearing_defect_indicator,
    
    -- 5. Energy Balance Ratio = output energy proxy / input energy proxy
    --    Divergence from 1.0 indicates energy loss (friction, misalignment)
    (pressure * rpm) / NULLIF(current_amps * 100, 0) AS energy_balance_ratio,
    
    -- 6. Stress Index = multi-factor stress on asset
    (temperature / NULLIF(rated_temp_max, 0)) * 0.3 +
    (vib_mag / 7.1) * 0.4 +  -- normalized to ISO boundary
    (current_amps / 15.0) * 0.3 AS stress_index,
    
    -- 7. Operating Regime (categorical: low/normal/high/overload)
    CASE 
        WHEN rpm < rated_rpm * 0.7 THEN 0   -- Low load
        WHEN rpm < rated_rpm * 0.95 THEN 1  -- Normal
        WHEN rpm < rated_rpm * 1.05 THEN 2  -- High load
        ELSE 3                               -- Overload
    END AS operating_regime,
    
    -- 8. Composite Health Score (weighted multi-signal)
    GREATEST(0, LEAST(100,
        100.0
        - GREATEST(0, (vib_mag - 2.5)) * 8.0       -- vibration penalty
        - GREATEST(0, (temperature / NULLIF(rated_temp_max,0) - 0.7)) * 80.0  -- temp penalty
        - GREATEST(0, (current_amps - 13.0)) * 5.0  -- current penalty
        - GREATEST(0, (acoustic_db - 75.0)) * 2.0   -- acoustic penalty
    )) AS composite_health_score

FROM base;

drop table if exists ML_FEATURES.TEMPORAL_MEMORY;
-- TEMPORAL_MEMORY
create or replace dynamic table ML_FEATURES.TEMPORAL_MEMORY(
	ASSET_ID,
	TIMESTAMP,
	HOURS_SINCE_FIRST_BREACH,
	DEGRADATION_VELOCITY_30D,
	TREND_REVERSAL_COUNT_7D,
	ABOVE_NORMAL_COUNT_24H,
	VIB_TREND_72H,
	DEGRADATION_ACCELERATION
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
 as
WITH base AS (
    SELECT 
        asset_id,
        timestamp,
        SQRT(POWER(vibration_x,2)+POWER(vibration_y,2)+POWER(vibration_z,2)) AS vib_mag,
        ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp) AS rn
    FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS
),
-- First time each asset crossed threshold of 3.5 mm/s
first_breach AS (
    SELECT asset_id, MIN(timestamp) AS first_breach_ts
    FROM base
    WHERE vib_mag > 3.5
    GROUP BY asset_id
),
-- 30-day-ago value for degradation velocity
lagged AS (
    SELECT 
        asset_id,
        timestamp,
        vib_mag,
        rn,
        LAG(vib_mag, 2880) OVER (PARTITION BY asset_id ORDER BY rn) AS vib_30d_ago,  -- 30 days * 96/day
        -- Detect trend reversals: did vib decrease then increase?
        CASE 
            WHEN vib_mag > LAG(vib_mag, 1) OVER (PARTITION BY asset_id ORDER BY rn)
             AND LAG(vib_mag, 1) OVER (PARTITION BY asset_id ORDER BY rn) < LAG(vib_mag, 2) OVER (PARTITION BY asset_id ORDER BY rn)
            THEN 1 ELSE 0
        END AS is_reversal,
        -- Above normal flag (mean + 2*std approximation — using 3.0 as threshold)
        CASE WHEN vib_mag > 3.0 THEN 1 ELSE 0 END AS above_normal
    FROM base
),
-- Count reversals in 7-day window and longest above-normal streak
features AS (
    SELECT 
        l.asset_id,
        l.timestamp,
        l.vib_mag,
        
        -- 1. Hours since first threshold breach (0 if never breached, so ML models don't see all-NULL series)
        COALESCE(DATEDIFF('hour', fb.first_breach_ts, l.timestamp), 0) AS hours_since_first_breach,
        
        -- 2. Degradation velocity (mm/s per day over 30 days)
        (l.vib_mag - l.vib_30d_ago) / 30.0 AS degradation_velocity_30d,
        
        -- 3. Trend reversal count (7 days = 672 readings)
        SUM(l.is_reversal) OVER (PARTITION BY l.asset_id ORDER BY l.rn ROWS BETWEEN 672 PRECEDING AND CURRENT ROW) AS trend_reversal_count_7d,
        
        -- 4. Longest continuous above-normal streak (running)
        SUM(l.above_normal) OVER (PARTITION BY l.asset_id ORDER BY l.rn ROWS BETWEEN 96 PRECEDING AND CURRENT ROW) AS above_normal_count_24h,
        
        -- 5. Time in high-load regime (% of last 24h where rpm > 95% rated)
        -- Will be computed via join with asset master below
        l.rn,
        
        -- 6. Vibration trend direction (slope approximation: current vs 72h ago)
        (l.vib_mag - LAG(l.vib_mag, 288) OVER (PARTITION BY l.asset_id ORDER BY l.rn)) AS vib_trend_72h
        
    FROM lagged l
    LEFT JOIN first_breach fb ON l.asset_id = fb.asset_id
)
SELECT 
    f.asset_id,
    f.timestamp,
    -- 1. Hours since first threshold breach (NULL if never breached = healthy)
    f.hours_since_first_breach,
    -- 2. Degradation velocity (mm/s per day) — 2.0 mm/s/day = fast degradation
    f.degradation_velocity_30d,
    -- 3. Trend reversals in 7 days — monotonic = true degradation, oscillating = intermittent
    f.trend_reversal_count_7d,
    -- 4. Above-normal readings in last 24h (out of 96) — sustained = structural change
    f.above_normal_count_24h,
    -- 5. 72-hour vibration trend (positive = worsening)
    f.vib_trend_72h,
    -- 6. Degradation acceleration (is velocity increasing?)
    f.degradation_velocity_30d - LAG(f.degradation_velocity_30d, 96) OVER (PARTITION BY f.asset_id ORDER BY f.rn) AS degradation_acceleration
FROM features f;


-- CROSS_DOMAIN
drop table if exists ML_FEATURES.CROSS_DOMAIN;
create or replace dynamic table ML_FEATURES.CROSS_DOMAIN(
	ASSET_ID,
	TIMESTAMP,
	DAYS_SINCE_LAST_MAINTENANCE,
	CUMULATIVE_OPERATING_HOURS,
	HISTORICAL_FAILURE_COUNT,
	MAINTENANCE_EFFECTIVENESS,
	TEMP_DEVIATION_FROM_SPEC,
	RPM_DEVIATION_FROM_SPEC,
	WORKLOAD_INTENSITY_7D,
	CUMULATIVE_MAINTENANCE_COST,
	WO_FREQUENCY_PER_1000H
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
 as
WITH last_maintenance AS (
    SELECT 
        asset_id,
        MAX(CASE WHEN status = 'completed' THEN completed_date END) AS last_maint_date,
        COUNT(*) AS total_wo_count,
        COUNT(CASE WHEN wo_type = 'emergency' THEN 1 END) AS emergency_count,
        COUNT(CASE WHEN wo_type = 'corrective' THEN 1 END) AS corrective_count,
        SUM(total_cost) AS total_historical_cost
    FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS
    GROUP BY asset_id
),
-- Get vibration before/after last completed repair for maintenance effectiveness
maint_effectiveness AS (
    SELECT 
        wo.asset_id,
        wo.wo_id,
        wo.completed_date,
        AVG(CASE WHEN sr.timestamp BETWEEN DATEADD('day', -3, wo.created_date) AND wo.created_date 
            THEN SQRT(POWER(sr.vibration_x,2)+POWER(sr.vibration_y,2)+POWER(sr.vibration_z,2)) END) AS vib_before,
        AVG(CASE WHEN sr.timestamp BETWEEN wo.completed_date AND DATEADD('day', 3, wo.completed_date) 
            THEN SQRT(POWER(sr.vibration_x,2)+POWER(sr.vibration_y,2)+POWER(sr.vibration_z,2)) END) AS vib_after
    FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS wo
    JOIN MFGPULSE_DB.RAW_OT.SENSOR_READINGS sr ON wo.asset_id = sr.asset_id
    WHERE wo.status = 'completed' AND wo.completed_date IS NOT NULL
    GROUP BY wo.asset_id, wo.wo_id, wo.completed_date
    QUALIFY ROW_NUMBER() OVER (PARTITION BY wo.asset_id ORDER BY wo.completed_date DESC) = 1
),
production_intensity AS (
    SELECT 
        asset_id,
        AVG(units_produced) AS avg_production_7d
    FROM MFGPULSE_DB.RAW_IT.PRODUCTION_OUTPUT
    WHERE timestamp >= DATEADD('day', -7, (SELECT MAX(timestamp) FROM MFGPULSE_DB.RAW_IT.PRODUCTION_OUTPUT))
    GROUP BY asset_id
),
readings AS (
    SELECT 
        asset_id, timestamp,
        SQRT(POWER(vibration_x,2)+POWER(vibration_y,2)+POWER(vibration_z,2)) AS vib_mag,
        temperature, rpm, current_amps
    FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS
)
SELECT 
    r.asset_id,
    r.timestamp,
    
    -- 1. Days since last maintenance
    DATEDIFF('day', lm.last_maint_date, r.timestamp) AS days_since_last_maintenance,
    
    -- 2. Cumulative operating hours (since install)
    DATEDIFF('hour', am.install_date, r.timestamp) AS cumulative_operating_hours,
    
    -- 3. Historical failure count (chronic vs one-off)
    lm.emergency_count + lm.corrective_count AS historical_failure_count,
    
    -- 4. Maintenance effectiveness (vib_after / vib_before last repair)
    me.vib_after / NULLIF(me.vib_before, 0) AS maintenance_effectiveness,
    
    -- 5. Operating deviation from spec: temperature
    r.temperature / NULLIF(am.rated_temp_max, 0) AS temp_deviation_from_spec,
    
    -- 6. Operating deviation from spec: RPM
    r.rpm / NULLIF(am.rated_rpm, 0) AS rpm_deviation_from_spec,
    
    -- 7. Workload intensity (7-day avg production)
    pi.avg_production_7d / 192.0 AS workload_intensity_7d,  -- normalized to max capacity
    
    -- 8. Total historical maintenance cost (indicates chronic problem asset)
    lm.total_historical_cost AS cumulative_maintenance_cost,
    
    -- 9. Work order frequency (WOs per 1000 operating hours)
    lm.total_wo_count / NULLIF(DATEDIFF('hour', am.install_date, r.timestamp) / 1000.0, 0) AS wo_frequency_per_1000h

FROM readings r
JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON r.asset_id = am.asset_id
LEFT JOIN last_maintenance lm ON r.asset_id = lm.asset_id
LEFT JOIN maint_effectiveness me ON r.asset_id = me.asset_id
LEFT JOIN production_intensity pi ON r.asset_id = pi.asset_id;

-- FLEET_COMPARISON
drop table if exists ML_FEATURES.FLEET_COMPARISON;
create or replace dynamic table ML_FEATURES.FLEET_COMPARISON(
	ASSET_ID,
	READING_DATE,
	VIB_ZSCORE_VS_FLEET,
	TEMP_ZSCORE_VS_FLEET,
	VIB_PERCENTILE_IN_FLEET,
	VIB_RATIO_TO_FLEET_MEAN,
	IS_WORST_IN_FLEET
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
 as
WITH daily_asset_stats AS (
    SELECT 
        sr.asset_id,
        am.asset_type,
        DATE_TRUNC('day', sr.timestamp) AS reading_date,
        AVG(SQRT(POWER(sr.vibration_x,2)+POWER(sr.vibration_y,2)+POWER(sr.vibration_z,2))) AS daily_avg_vib,
        AVG(sr.temperature) AS daily_avg_temp,
        AVG(sr.current_amps) AS daily_avg_current,
        MAX(SQRT(POWER(sr.vibration_x,2)+POWER(sr.vibration_y,2)+POWER(sr.vibration_z,2))) AS daily_max_vib
    FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS sr
    JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON sr.asset_id = am.asset_id
    GROUP BY sr.asset_id, am.asset_type, DATE_TRUNC('day', sr.timestamp)
),
fleet_stats AS (
    SELECT 
        asset_type,
        reading_date,
        AVG(daily_avg_vib) AS fleet_avg_vib,
        STDDEV(daily_avg_vib) AS fleet_std_vib,
        AVG(daily_avg_temp) AS fleet_avg_temp,
        STDDEV(daily_avg_temp) AS fleet_std_temp,
        AVG(daily_avg_current) AS fleet_avg_current
    FROM daily_asset_stats
    GROUP BY asset_type, reading_date
)
SELECT 
    das.asset_id,
    das.reading_date,
    
    -- 1. Vibration Z-score vs fleet peers (same asset type)
    (das.daily_avg_vib - fs.fleet_avg_vib) / NULLIF(fs.fleet_std_vib, 0) AS vib_zscore_vs_fleet,
    
    -- 2. Temperature Z-score vs fleet peers
    (das.daily_avg_temp - fs.fleet_avg_temp) / NULLIF(fs.fleet_std_temp, 0) AS temp_zscore_vs_fleet,
    
    -- 3. Percentile rank within fleet (0-1, higher = worse)
    PERCENT_RANK() OVER (PARTITION BY das.asset_type, das.reading_date ORDER BY das.daily_avg_vib) AS vib_percentile_in_fleet,
    
    -- 4. Deviation from fleet mean (ratio)
    das.daily_avg_vib / NULLIF(fs.fleet_avg_vib, 0) AS vib_ratio_to_fleet_mean,
    
    -- 5. Is this the worst performer in its type today?
    CASE WHEN das.daily_max_vib = MAX(das.daily_max_vib) OVER (PARTITION BY das.asset_type, das.reading_date)
        THEN 1 ELSE 0 END AS is_worst_in_fleet

FROM daily_asset_stats das
JOIN fleet_stats fs ON das.asset_type = fs.asset_type AND das.reading_date = fs.reading_date;

-- LABELED_DATA
drop table if exists ML_FEATURES.LABELED_DATA;
create or replace dynamic table ML_FEATURES.LABELED_DATA(
	ASSET_ID,
	TIMESTAMP,
	FAILURE_MODE,
	HOURS_TO_FAILURE,
	IS_FAILURE_EVENT,
	DEGRADATION_STAGE,
	FAILURE_SEVERITY,
	IS_DEGRADING
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
 as
WITH failure_events AS (
    -- Get the emergency/corrective failure dates per asset
    SELECT 
        asset_id,
        MIN(CASE WHEN wo_type = 'emergency' THEN created_date END) AS first_emergency_date,
        MIN(CASE WHEN wo_type IN ('emergency','corrective') THEN created_date END) AS first_failure_date
    FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS
    WHERE wo_type IN ('emergency', 'corrective')
    GROUP BY asset_id
),
asset_failure_modes AS (
    SELECT asset_id,
        CASE asset_id
            WHEN 'ASSET_001' THEN 'bearing_wear'
            WHEN 'ASSET_002' THEN 'thermal_degradation'
            WHEN 'ASSET_003' THEN 'imbalance'
            WHEN 'ASSET_004' THEN 'misalignment'
            WHEN 'ASSET_005' THEN 'bearing_wear'
            WHEN 'ASSET_006' THEN 'thermal_degradation'
            WHEN 'ASSET_007' THEN 'normal'
            WHEN 'ASSET_008' THEN 'imbalance'
            WHEN 'ASSET_009' THEN 'misalignment'
            WHEN 'ASSET_010' THEN 'normal'
        END AS failure_mode
    FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER
),
readings AS (
    SELECT 
        sr.asset_id,
        sr.timestamp,
        SQRT(POWER(sr.vibration_x,2)+POWER(sr.vibration_y,2)+POWER(sr.vibration_z,2)) AS vib_mag,
        sr.temperature,
        am.rated_temp_max
    FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS sr
    JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON sr.asset_id = am.asset_id
)
SELECT 
    r.asset_id,
    r.timestamp,
    
    -- Failure mode label
    afm.failure_mode,
    
    -- Hours to failure (RUL) — NULL for healthy assets
    CASE 
        WHEN fe.first_failure_date IS NOT NULL AND r.timestamp < fe.first_failure_date
        THEN DATEDIFF('hour', r.timestamp, fe.first_failure_date)
        ELSE NULL
    END AS hours_to_failure,
    
    -- Is this the failure event moment?
    CASE 
        WHEN fe.first_emergency_date IS NOT NULL 
         AND ABS(DATEDIFF('minute', r.timestamp, fe.first_emergency_date)) < 15
        THEN TRUE ELSE FALSE
    END AS is_failure_event,
    
    -- Degradation stage (0-4)
    CASE 
        WHEN afm.failure_mode = 'normal' THEN 0
        WHEN fe.first_failure_date IS NULL THEN 0
        WHEN r.timestamp >= fe.first_failure_date THEN 4  -- Failed
        WHEN DATEDIFF('hour', r.timestamp, fe.first_failure_date) < 24 THEN 4    -- Imminent
        WHEN DATEDIFF('hour', r.timestamp, fe.first_failure_date) < 72 THEN 3    -- Critical
        WHEN DATEDIFF('hour', r.timestamp, fe.first_failure_date) < 336 THEN 2   -- Warning (14 days)
        WHEN DATEDIFF('hour', r.timestamp, fe.first_failure_date) < 720 THEN 1   -- Early (30 days)
        ELSE 0  -- Healthy
    END AS degradation_stage,
    
    -- Failure severity (what happens when it fails)
    CASE 
        WHEN afm.failure_mode = 'normal' THEN 'none'
        WHEN fe.first_emergency_date IS NOT NULL THEN 'emergency'
        WHEN fe.first_failure_date IS NOT NULL THEN 'corrective'
        ELSE 'none'
    END AS failure_severity,
    
    -- Binary: is asset currently in degrading state?
    CASE 
        WHEN afm.failure_mode != 'normal' 
         AND fe.first_failure_date IS NOT NULL 
         AND r.timestamp < fe.first_failure_date
         AND DATEDIFF('hour', r.timestamp, fe.first_failure_date) < 720
        THEN 1 ELSE 0
    END AS is_degrading

FROM readings r
JOIN asset_failure_modes afm ON r.asset_id = afm.asset_id
LEFT JOIN failure_events fe ON r.asset_id = fe.asset_id;


-- ============================================================================
-- CHECKPOINT 8: ML FEATURE VIEWS + LIVE_PREDICTIONS DT
-- ============================================================================

-- 11 ML_FEATURES views + LIVE_PREDICTIONS dynamic table

-- ALL_DERIVED_FEATURES
create or replace view ML_FEATURES.ALL_DERIVED_FEATURES(
	ASSET_ID,
	TIMESTAMP,
	VIB_CREST_FACTOR_6H,
	VIB_COEFF_VAR_6H,
	VIB_PEAK_TO_PEAK_6H,
	VIB_MAG_STD_6H,
	VIB_CREST_FACTOR_24H,
	VIB_COEFF_VAR_24H,
	VIB_PEAK_TO_PEAK_24H,
	VIB_MAG_STD_24H,
	VIB_RATE_OF_CHANGE_1H,
	VIB_ACCELERATION_1H,
	TEMP_RATE_OF_CHANGE_1H,
	VIB_XY_CORRELATION_DAILY,
	CURRENT_RPM_RATIO,
	ACOUSTIC_VIB_RATIO,
	ENERGY_BALANCE_RATIO,
	STRESS_INDEX
) as
SELECT 
    rs.asset_id,
    rs.timestamp,
    rs.vib_crest_factor_6h,
    rs.vib_coeff_var_6h,
    rs.vib_peak_to_peak_6h,
    rs.vib_mag_std_6h,
    rs.vib_crest_factor_24h,
    rs.vib_coeff_var_24h,
    rs.vib_peak_to_peak_24h,
    rs.vib_mag_std_24h,
    rs.vib_rate_of_change_1h,
    rs.vib_acceleration_1h,
    rs.temp_rate_of_change_1h,
    si.vib_xy_correlation_daily,
    si.current_rpm_ratio,
    si.acoustic_vib_ratio,
    pc.energy_balance_ratio,
    pc.stress_index
FROM MFGPULSE_DB.ML_FEATURES.ROLLING_STATS rs
JOIN MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS si 
    ON rs.asset_id = si.asset_id AND rs.timestamp = si.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE pc 
    ON rs.asset_id = pc.asset_id AND rs.timestamp = pc.timestamp;

-- ALL_DERIVED_FEATURES_INFERENCE
create or replace view ML_FEATURES.ALL_DERIVED_FEATURES_INFERENCE(
	ASSET_ID,
	TIMESTAMP,
	VIB_CREST_FACTOR_6H,
	VIB_COEFF_VAR_6H,
	VIB_PEAK_TO_PEAK_6H,
	VIB_MAG_STD_6H,
	VIB_CREST_FACTOR_24H,
	VIB_COEFF_VAR_24H,
	VIB_PEAK_TO_PEAK_24H,
	VIB_MAG_STD_24H,
	VIB_RATE_OF_CHANGE_1H,
	VIB_ACCELERATION_1H,
	TEMP_RATE_OF_CHANGE_1H,
	VIB_XY_CORRELATION_DAILY,
	CURRENT_RPM_RATIO,
	ACOUSTIC_VIB_RATIO,
	ENERGY_BALANCE_RATIO,
	STRESS_INDEX
) as
SELECT * FROM MFGPULSE_DB.ML_FEATURES.ALL_DERIVED_FEATURES
WHERE TIMESTAMP >= '2024-05-01';

-- FEATURE_CATALOG
create or replace view ML_FEATURES.FEATURE_CATALOG(
	FEATURE_NAME,
	LAYER,
	FORMULA_DESCRIPTION,
	PHYSICS_RATIONALE,
	USED_BY_MODELS
) as
SELECT column1 AS feature_name, column2 AS layer, column3 AS formula_description, column4 AS physics_rationale, column5 AS used_by_models
FROM VALUES
('vib_mag_mean_6h','Rolling Stats','AVG(vib_magnitude) over 6hr window','Baseline vibration level','M1,M3'),
('vib_mag_std_6h','Rolling Stats','STDDEV(vib_magnitude) over 6hr','Signal instability indicator','M1'),
('vib_mag_max_6h','Rolling Stats','MAX(vib_magnitude) over 6hr','Peak detection for impulsive events','M1'),
('vib_crest_factor_6h','Rolling Stats','Peak/RMS over 6hr','Bearing damage creates sharp peaks in normal RMS signal','M1,M3,M4'),
('vib_peak_to_peak_6h','Rolling Stats','MAX-MIN over 6hr','Vibration amplitude range','M1'),
('vib_rms_6h','Rolling Stats','RMS energy over 6hr','ISO 10816 vibration severity standard','M1,M2'),
('vib_coeff_var_6h','Rolling Stats','StdDev/Mean over 6hr','Signal stability - high CoV = intermittent contact','M1,M4'),
('vib_rate_of_change_1h','Rolling Stats','Current - 1hr_ago','1st derivative: degradation speed','M1,M2,M3'),
('vib_acceleration_1h','Rolling Stats','2nd derivative of vibration','When degradation is accelerating','M2,M4'),
('vib_xy_correlation_daily','Sensor Interactions','CORR(vib_x, vib_y) daily','High=misalignment, Low=bearing defect','M1,M3'),
('vib_temp_coupling_daily','Sensor Interactions','CORR(vib_mag, temperature)','Both rising=friction source','M1'),
('current_rpm_ratio','Sensor Interactions','current_amps/rpm*1000','Load-normalized power draw','M1,M3'),
('vib_axis_dominance','Sensor Interactions','MAX(axis)/magnitude','X-dominant=imbalance, Multi-axis=misalignment','M1,M3'),
('acoustic_vib_ratio','Sensor Interactions','acoustic_db/vib_mag','Rising with stable vib = internal crack','M1,M4'),
('hours_since_first_breach','Temporal Memory','Time since vib>3.5mm/s','P-F interval position','M2,M3'),
('degradation_velocity_30d','Temporal Memory','(current-30d_ago)/30','Speed of deterioration','M2,M3,M6'),
('trend_reversal_count_7d','Temporal Memory','Direction changes in 7d','Monotonic=true degradation, Oscillating=intermittent','M3'),
('above_normal_count_24h','Temporal Memory','Readings > mean+2σ in 24h','Sustained deviation = structural change','M3'),
('days_since_last_maintenance','Cross Domain','DATEDIFF from last WO','Time since human intervention','M2'),
('cumulative_operating_hours','Cross Domain','Hours since install_date','Equipment odometer','M2'),
('maintenance_effectiveness','Cross Domain','vib_after/vib_before repair','<1=effective, >1=wrong root cause','M2'),
('stress_index','Physics','Weighted multi-signal stress','Combined operating stress level','M1,M2,M3,M4'),
('composite_health_score','Physics','100 - penalty(vib,temp,current,acoustic)','Overall health 0-100','M1,M3'),
('iso_10816_severity','Physics','ISO standard vibration zones','Industry standard severity classification','M1,M3'),
('energy_balance_ratio','Physics','(pressure*rpm)/(current*100)','Energy efficiency - divergence=friction loss','M4'),
('fatigue_score','Hidden Fatigue','6-component physics-based UDF','Hidden degradation before threshold alerts','M4,M5,M6,M7'),
('vib_zscore_vs_fleet','Fleet Comparison','(asset-fleet_avg)/fleet_std','Performance vs peer assets of same type','Dashboard'),
('is_worst_in_fleet','Fleet Comparison','MAX(vib) = fleet max?','Worst performer identification','Dashboard');

-- HEALTHY_DERIVED_FEATURES
create or replace view ML_FEATURES.HEALTHY_DERIVED_FEATURES(
	ASSET_ID,
	TIMESTAMP,
	VIB_CREST_FACTOR_6H,
	VIB_COEFF_VAR_6H,
	VIB_PEAK_TO_PEAK_6H,
	VIB_MAG_STD_6H,
	VIB_CREST_FACTOR_24H,
	VIB_COEFF_VAR_24H,
	VIB_PEAK_TO_PEAK_24H,
	VIB_MAG_STD_24H,
	VIB_RATE_OF_CHANGE_1H,
	VIB_ACCELERATION_1H,
	TEMP_RATE_OF_CHANGE_1H,
	VIB_XY_CORRELATION_DAILY,
	CURRENT_RPM_RATIO,
	ACOUSTIC_VIB_RATIO,
	ENERGY_BALANCE_RATIO,
	STRESS_INDEX
) as
SELECT 
    rs.asset_id,
    rs.timestamp,
    -- DERIVED features only (not raw signals)
    rs.vib_crest_factor_6h,
    rs.vib_coeff_var_6h,
    rs.vib_peak_to_peak_6h,
    rs.vib_mag_std_6h,
    rs.vib_crest_factor_24h,
    rs.vib_coeff_var_24h,
    rs.vib_peak_to_peak_24h,
    rs.vib_mag_std_24h,
    rs.vib_rate_of_change_1h,
    rs.vib_acceleration_1h,
    rs.temp_rate_of_change_1h,
    si.vib_xy_correlation_daily,
    si.current_rpm_ratio,
    si.acoustic_vib_ratio,
    pc.energy_balance_ratio,
    pc.stress_index
FROM MFGPULSE_DB.ML_FEATURES.ROLLING_STATS rs
JOIN MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS si 
    ON rs.asset_id = si.asset_id AND rs.timestamp = si.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE pc 
    ON rs.asset_id = pc.asset_id AND rs.timestamp = pc.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.LABELED_DATA ld
    ON rs.asset_id = ld.asset_id AND rs.timestamp = ld.timestamp
WHERE ld.failure_mode = 'normal' 
   OR (ld.degradation_stage = 0 AND ld.hours_to_failure > 720);

-- HEALTHY_DERIVED_FEATURES_TRAIN
create or replace view ML_FEATURES.HEALTHY_DERIVED_FEATURES_TRAIN(
	ASSET_ID,
	TIMESTAMP,
	VIB_CREST_FACTOR_6H,
	VIB_COEFF_VAR_6H,
	VIB_PEAK_TO_PEAK_6H,
	VIB_MAG_STD_6H,
	VIB_CREST_FACTOR_24H,
	VIB_COEFF_VAR_24H,
	VIB_PEAK_TO_PEAK_24H,
	VIB_MAG_STD_24H,
	VIB_RATE_OF_CHANGE_1H,
	VIB_ACCELERATION_1H,
	TEMP_RATE_OF_CHANGE_1H,
	VIB_XY_CORRELATION_DAILY,
	CURRENT_RPM_RATIO,
	ACOUSTIC_VIB_RATIO,
	ENERGY_BALANCE_RATIO,
	STRESS_INDEX
) as
SELECT * FROM MFGPULSE_DB.ML_FEATURES.HEALTHY_DERIVED_FEATURES
WHERE TIMESTAMP < '2024-05-01';

-- TRAIN_ANOMALY
create or replace view ML_FEATURES.TRAIN_ANOMALY(
	ASSET_ID,
	TIMESTAMP,
	VIB_MAG_MEAN_6H,
	VIB_MAG_STD_6H,
	VIB_CREST_FACTOR_6H,
	VIB_RMS_6H,
	VIB_COEFF_VAR_6H,
	TEMP_MEAN_6H,
	TEMP_STD_6H,
	CURRENT_MEAN_6H,
	CURRENT_STD_6H,
	VIB_MAG_MEAN_24H,
	VIB_MAG_STD_24H,
	VIB_CREST_FACTOR_24H,
	VIB_XY_CORRELATION_DAILY,
	CURRENT_RPM_RATIO,
	VIB_AXIS_DOMINANCE,
	ACOUSTIC_VIB_RATIO,
	STRESS_INDEX,
	ENERGY_BALANCE_RATIO,
	THERMAL_EFFICIENCY
) as
-- ONLY healthy asset data for anomaly detection (train on normal, detect deviations)
SELECT 
    ld.asset_id, ld.timestamp,
    rs.vib_mag_mean_6h, rs.vib_mag_std_6h, rs.vib_crest_factor_6h, rs.vib_rms_6h, rs.vib_coeff_var_6h,
    rs.temp_mean_6h, rs.temp_std_6h, rs.current_mean_6h, rs.current_std_6h,
    rs.vib_mag_mean_24h, rs.vib_mag_std_24h, rs.vib_crest_factor_24h,
    si.vib_xy_correlation_daily, si.current_rpm_ratio, si.vib_axis_dominance, si.acoustic_vib_ratio,
    pc.stress_index, pc.energy_balance_ratio, pc.thermal_efficiency
FROM MFGPULSE_DB.ML_FEATURES.LABELED_DATA ld
JOIN MFGPULSE_DB.ML_FEATURES.ROLLING_STATS rs ON ld.asset_id = rs.asset_id AND ld.timestamp = rs.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS si ON ld.asset_id = si.asset_id AND ld.timestamp = si.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE pc ON ld.asset_id = pc.asset_id AND ld.timestamp = pc.timestamp
WHERE ld.failure_mode = 'normal' 
   OR (ld.degradation_stage = 0 AND ld.hours_to_failure > 720);

-- TRAIN_ANOMALY_SMALL
create or replace view ML_FEATURES.TRAIN_ANOMALY_SMALL(
	ASSET_ID,
	TIMESTAMP,
	VIB_MAG_MEAN_6H,
	VIB_MAG_STD_6H,
	VIB_CREST_FACTOR_6H,
	VIB_RMS_6H,
	VIB_COEFF_VAR_6H,
	TEMP_MEAN_6H,
	TEMP_STD_6H,
	CURRENT_MEAN_6H,
	CURRENT_STD_6H,
	VIB_MAG_MEAN_24H,
	VIB_MAG_STD_24H,
	VIB_CREST_FACTOR_24H,
	VIB_XY_CORRELATION_DAILY,
	CURRENT_RPM_RATIO,
	VIB_AXIS_DOMINANCE,
	ACOUSTIC_VIB_RATIO,
	STRESS_INDEX,
	ENERGY_BALANCE_RATIO,
	THERMAL_EFFICIENCY
) as
SELECT * FROM MFGPULSE_DB.ML_FEATURES.TRAIN_ANOMALY
WHERE ASSET_ID IN ('ASSET_007', 'ASSET_010')
AND TIMESTAMP >= '2024-03-01';

-- TRAIN_FAILURE_MODE
create or replace view ML_FEATURES.TRAIN_FAILURE_MODE(
	ASSET_ID,
	TIMESTAMP,
	FAILURE_MODE,
	DEGRADATION_STAGE,
	VIB_MAG_MEAN_6H,
	VIB_MAG_STD_6H,
	VIB_MAG_MAX_6H,
	VIB_CREST_FACTOR_6H,
	VIB_PEAK_TO_PEAK_6H,
	VIB_RMS_6H,
	VIB_COEFF_VAR_6H,
	TEMP_MEAN_6H,
	TEMP_STD_6H,
	CURRENT_MEAN_6H,
	CURRENT_STD_6H,
	VIB_MAG_MEAN_24H,
	VIB_MAG_STD_24H,
	VIB_CREST_FACTOR_24H,
	VIB_RMS_24H,
	TEMP_MEAN_24H,
	CURRENT_MEAN_24H,
	ACOUSTIC_MEAN_24H,
	VIB_RATE_OF_CHANGE_1H,
	VIB_ACCELERATION_1H,
	VIB_XY_CORRELATION_DAILY,
	VIB_TEMP_COUPLING_DAILY,
	CURRENT_RPM_RATIO,
	VIB_AXIS_DOMINANCE,
	ACOUSTIC_VIB_RATIO,
	STRESS_INDEX,
	ISO_10816_SEVERITY,
	COMPOSITE_HEALTH_SCORE
) as
-- Balanced dataset for multi-class failure mode prediction
SELECT 
    ld.asset_id, ld.timestamp, ld.failure_mode, ld.degradation_stage,
    rs.vib_mag_mean_6h, rs.vib_mag_std_6h, rs.vib_mag_max_6h, rs.vib_crest_factor_6h,
    rs.vib_peak_to_peak_6h, rs.vib_rms_6h, rs.vib_coeff_var_6h,
    rs.temp_mean_6h, rs.temp_std_6h, rs.current_mean_6h, rs.current_std_6h,
    rs.vib_mag_mean_24h, rs.vib_mag_std_24h, rs.vib_crest_factor_24h, rs.vib_rms_24h,
    rs.temp_mean_24h, rs.current_mean_24h, rs.acoustic_mean_24h,
    rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
    si.vib_xy_correlation_daily, si.vib_temp_coupling_daily,
    si.current_rpm_ratio, si.vib_axis_dominance, si.acoustic_vib_ratio,
    pc.stress_index, pc.iso_10816_severity, pc.composite_health_score
FROM MFGPULSE_DB.ML_FEATURES.LABELED_DATA ld
JOIN MFGPULSE_DB.ML_FEATURES.ROLLING_STATS rs 
    ON ld.asset_id = rs.asset_id AND ld.timestamp = rs.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS si 
    ON ld.asset_id = si.asset_id AND ld.timestamp = si.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE pc 
    ON ld.asset_id = pc.asset_id AND ld.timestamp = pc.timestamp
WHERE ld.failure_mode != 'normal' 
   OR (ld.failure_mode = 'normal' AND UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.50);

-- TRAIN_RUL
create or replace view ML_FEATURES.TRAIN_RUL(
	ASSET_ID,
	TIMESTAMP,
	HOURS_TO_FAILURE,
	FAILURE_MODE,
	DEGRADATION_STAGE,
	VIB_MAG_MEAN_6H,
	VIB_MAG_STD_6H,
	VIB_MAG_MAX_6H,
	VIB_CREST_FACTOR_6H,
	VIB_RMS_6H,
	VIB_COEFF_VAR_6H,
	TEMP_MEAN_6H,
	CURRENT_MEAN_6H,
	VIB_MAG_MEAN_24H,
	VIB_MAG_STD_24H,
	VIB_CREST_FACTOR_24H,
	VIB_RMS_24H,
	VIB_RATE_OF_CHANGE_1H,
	VIB_ACCELERATION_1H,
	TEMP_RATE_OF_CHANGE_1H,
	VIB_XY_CORRELATION_DAILY,
	VIB_TEMP_COUPLING_DAILY,
	CURRENT_RPM_RATIO,
	VIB_AXIS_DOMINANCE,
	HOURS_SINCE_FIRST_BREACH,
	DEGRADATION_VELOCITY_30D,
	TREND_REVERSAL_COUNT_7D,
	ABOVE_NORMAL_COUNT_24H,
	VIB_TREND_72H,
	DEGRADATION_ACCELERATION,
	DAYS_SINCE_LAST_MAINTENANCE,
	CUMULATIVE_OPERATING_HOURS,
	MAINTENANCE_EFFECTIVENESS,
	STRESS_INDEX,
	COMPOSITE_HEALTH_SCORE,
	THERMAL_EFFICIENCY
) as
-- Only degrading assets with known failure dates (hours_to_failure is not null)
SELECT 
    ld.asset_id, ld.timestamp, ld.hours_to_failure, ld.failure_mode, ld.degradation_stage,
    rs.vib_mag_mean_6h, rs.vib_mag_std_6h, rs.vib_mag_max_6h, rs.vib_crest_factor_6h,
    rs.vib_rms_6h, rs.vib_coeff_var_6h,
    rs.temp_mean_6h, rs.current_mean_6h,
    rs.vib_mag_mean_24h, rs.vib_mag_std_24h, rs.vib_crest_factor_24h, rs.vib_rms_24h,
    rs.vib_rate_of_change_1h, rs.vib_acceleration_1h, rs.temp_rate_of_change_1h,
    si.vib_xy_correlation_daily, si.vib_temp_coupling_daily, si.current_rpm_ratio, si.vib_axis_dominance,
    tm.hours_since_first_breach, tm.degradation_velocity_30d, tm.trend_reversal_count_7d,
    tm.above_normal_count_24h, tm.vib_trend_72h, tm.degradation_acceleration,
    cd.days_since_last_maintenance, cd.cumulative_operating_hours, cd.maintenance_effectiveness,
    pc.stress_index, pc.composite_health_score, pc.thermal_efficiency
FROM MFGPULSE_DB.ML_FEATURES.LABELED_DATA ld
JOIN MFGPULSE_DB.ML_FEATURES.ROLLING_STATS rs ON ld.asset_id = rs.asset_id AND ld.timestamp = rs.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS si ON ld.asset_id = si.asset_id AND ld.timestamp = si.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.TEMPORAL_MEMORY tm ON ld.asset_id = tm.asset_id AND ld.timestamp = tm.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.CROSS_DOMAIN cd ON ld.asset_id = cd.asset_id AND ld.timestamp = cd.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE pc ON ld.asset_id = pc.asset_id AND ld.timestamp = pc.timestamp
WHERE ld.hours_to_failure IS NOT NULL AND ld.is_degrading = 1;

-- TRAIN_TRAJECTORY
create or replace view ML_FEATURES.TRAIN_TRAJECTORY(
	ASSET_ID,
	TIMESTAMP,
	DEGRADATION_STAGE,
	FAILURE_MODE,
	VIB_MAG_MEAN_6H,
	VIB_MAG_STD_6H,
	VIB_MAG_MAX_6H,
	VIB_CREST_FACTOR_6H,
	VIB_RMS_6H,
	VIB_PEAK_TO_PEAK_6H,
	TEMP_MEAN_6H,
	CURRENT_MEAN_6H,
	VIB_MAG_MEAN_24H,
	VIB_RMS_24H,
	VIB_COEFF_VAR_24H,
	VIB_RATE_OF_CHANGE_1H,
	VIB_ACCELERATION_1H,
	VIB_XY_CORRELATION_DAILY,
	CURRENT_RPM_RATIO,
	VIB_AXIS_DOMINANCE,
	HOURS_SINCE_FIRST_BREACH,
	DEGRADATION_VELOCITY_30D,
	ABOVE_NORMAL_COUNT_24H,
	VIB_TREND_72H,
	DAYS_SINCE_LAST_MAINTENANCE,
	CUMULATIVE_OPERATING_HOURS,
	STRESS_INDEX,
	COMPOSITE_HEALTH_SCORE,
	ISO_10816_SEVERITY
) as
-- All stages, with oversampling for rare critical stages (stage 3 & 4)
SELECT 
    ld.asset_id, ld.timestamp, ld.degradation_stage, ld.failure_mode,
    rs.vib_mag_mean_6h, rs.vib_mag_std_6h, rs.vib_mag_max_6h, rs.vib_crest_factor_6h,
    rs.vib_rms_6h, rs.vib_peak_to_peak_6h,
    rs.temp_mean_6h, rs.current_mean_6h,
    rs.vib_mag_mean_24h, rs.vib_rms_24h, rs.vib_coeff_var_24h,
    rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
    si.vib_xy_correlation_daily, si.current_rpm_ratio, si.vib_axis_dominance,
    tm.hours_since_first_breach, tm.degradation_velocity_30d, tm.above_normal_count_24h, tm.vib_trend_72h,
    cd.days_since_last_maintenance, cd.cumulative_operating_hours,
    pc.stress_index, pc.composite_health_score, pc.iso_10816_severity
FROM MFGPULSE_DB.ML_FEATURES.LABELED_DATA ld
JOIN MFGPULSE_DB.ML_FEATURES.ROLLING_STATS rs ON ld.asset_id = rs.asset_id AND ld.timestamp = rs.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS si ON ld.asset_id = si.asset_id AND ld.timestamp = si.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.TEMPORAL_MEMORY tm ON ld.asset_id = tm.asset_id AND ld.timestamp = tm.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.CROSS_DOMAIN cd ON ld.asset_id = cd.asset_id AND ld.timestamp = cd.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE pc ON ld.asset_id = pc.asset_id AND ld.timestamp = pc.timestamp
WHERE ld.failure_mode != 'normal';

-- TRAIN_TRAJECTORY_3CLASS
create or replace view ML_FEATURES.TRAIN_TRAJECTORY_3CLASS(
	ASSET_ID,
	TIMESTAMP,
	FAILURE_MODE,
	ORIGINAL_STAGE,
	STAGE_3CLASS,
	VIB_MAG_MEAN_6H,
	VIB_MAG_STD_6H,
	VIB_MAG_MAX_6H,
	VIB_CREST_FACTOR_6H,
	VIB_RMS_6H,
	VIB_PEAK_TO_PEAK_6H,
	TEMP_MEAN_6H,
	CURRENT_MEAN_6H,
	VIB_MAG_MEAN_24H,
	VIB_RMS_24H,
	VIB_COEFF_VAR_24H,
	VIB_RATE_OF_CHANGE_1H,
	VIB_ACCELERATION_1H,
	VIB_XY_CORRELATION_DAILY,
	CURRENT_RPM_RATIO,
	VIB_AXIS_DOMINANCE,
	HOURS_SINCE_FIRST_BREACH,
	DEGRADATION_VELOCITY_30D,
	ABOVE_NORMAL_COUNT_24H,
	VIB_TREND_72H,
	DAYS_SINCE_LAST_MAINTENANCE,
	CUMULATIVE_OPERATING_HOURS,
	STRESS_INDEX,
	COMPOSITE_HEALTH_SCORE,
	ISO_10816_SEVERITY
) as
SELECT 
    ld.asset_id, ld.timestamp, ld.failure_mode,
    ld.degradation_stage AS original_stage,
    CASE 
        WHEN ld.degradation_stage IN (0, 1) THEN 'Healthy'
        WHEN ld.degradation_stage = 2 THEN 'Warning'
        WHEN ld.degradation_stage IN (3, 4) THEN 'Critical'
    END AS stage_3class,
    rs.vib_mag_mean_6h, rs.vib_mag_std_6h, rs.vib_mag_max_6h, rs.vib_crest_factor_6h,
    rs.vib_rms_6h, rs.vib_peak_to_peak_6h,
    rs.temp_mean_6h, rs.current_mean_6h,
    rs.vib_mag_mean_24h, rs.vib_rms_24h, rs.vib_coeff_var_24h,
    rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
    si.vib_xy_correlation_daily, si.current_rpm_ratio, si.vib_axis_dominance,
    tm.hours_since_first_breach, tm.degradation_velocity_30d, tm.above_normal_count_24h, tm.vib_trend_72h,
    cd.days_since_last_maintenance, cd.cumulative_operating_hours,
    pc.stress_index, pc.composite_health_score, pc.iso_10816_severity
FROM MFGPULSE_DB.ML_FEATURES.LABELED_DATA ld
JOIN MFGPULSE_DB.ML_FEATURES.ROLLING_STATS rs ON ld.asset_id = rs.asset_id AND ld.timestamp = rs.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS si ON ld.asset_id = si.asset_id AND ld.timestamp = si.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.TEMPORAL_MEMORY tm ON ld.asset_id = tm.asset_id AND ld.timestamp = tm.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.CROSS_DOMAIN cd ON ld.asset_id = cd.asset_id AND ld.timestamp = cd.timestamp
JOIN MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE pc ON ld.asset_id = pc.asset_id AND ld.timestamp = pc.timestamp
WHERE ld.failure_mode != 'normal';


-- LIVE_PREDICTIONS DT (reads ML_FEATURES + UDFs)
drop table if exists ML_MODELS.LIVE_PREDICTIONS;
create or replace dynamic table ML_MODELS.LIVE_PREDICTIONS(
	ASSET_ID,
	ASSET_NAME,
	ASSET_TYPE,
	LINE_ID,
	PREDICTION_TIME,
	FAILURE_MODE_PRED,
	FAILURE_MODE_CONFIDENCE,
	RUL_HOURS,
	RUL_LOWER_CI,
	RUL_UPPER_CI,
	STAGE_PRED,
	DEGRADATION_SCORE,
	TRANSITION_PROBABILITY,
	FATIGUE_SCORE,
	FATIGUE_LEVEL,
	COMPOSITE_HEALTH_SCORE,
	STRESS_INDEX
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
 as
WITH latest_rs AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn
    FROM MFGPULSE_DB.ML_FEATURES.ROLLING_STATS
),
latest_si AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn
    FROM MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS
),
latest_tm AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn
    FROM MFGPULSE_DB.ML_FEATURES.TEMPORAL_MEMORY
),
latest_pc AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn
    FROM MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE
),
latest_fs AS (
    SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn
    FROM MFGPULSE_DB.ML_MODELS.FATIGUE_SCORES
),
base AS (
    SELECT 
        am.asset_id, am.asset_name, am.asset_type, am.line_id,
        rs.timestamp AS prediction_time,
        rs.vib_rms_24h, rs.vib_crest_factor_6h, rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
        rs.vib_mag_mean_24h, rs.vib_mag_std_24h, rs.acoustic_mean_24h,
        rs.temp_mean_24h, rs.current_mean_24h,
        COALESCE(si.vib_xy_correlation_daily, 0) AS xy_corr,
        COALESCE(si.current_rpm_ratio, 0) AS crpm_ratio,
        COALESCE(si.vib_axis_dominance, 0.5) AS axis_dom,
        COALESCE(si.acoustic_vib_ratio, 0) AS av_ratio,
        pc.stress_index, pc.composite_health_score, pc.iso_10816_severity,
        tm.degradation_velocity_30d, tm.hours_since_first_breach, tm.above_normal_count_24h,
        COALESCE(fs.fatigue_score, 0) AS fatigue_score,
        COALESCE(fs.fatigue_level, 'HEALTHY') AS fatigue_level
    FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER am
    LEFT JOIN latest_rs rs ON am.asset_id = rs.asset_id AND rs.rn = 1
    LEFT JOIN latest_si si ON am.asset_id = si.asset_id AND si.rn = 1
    LEFT JOIN latest_tm tm ON am.asset_id = tm.asset_id AND tm.rn = 1
    LEFT JOIN latest_pc pc ON am.asset_id = pc.asset_id AND pc.rn = 1
    LEFT JOIN latest_fs fs ON am.asset_id = fs.asset_id AND fs.rn = 1
),
scored AS (
    SELECT *,
        -- Pre-compute degradation score and transition probability for use in RUL formula
        ROUND(LEAST(1.0, GREATEST(0, (vib_rms_24h - 2.5)/10.0)) * 0.25 +
              LEAST(1.0, GREATEST(0, (vib_crest_factor_6h - 1.2)/1.5)) * 0.15 +
              LEAST(1.0, stress_index) * 0.15 +
              LEAST(1.0, GREATEST(0, COALESCE(degradation_velocity_30d, 0)/0.5)) * 0.20 +
              CASE WHEN hours_since_first_breach IS NULL THEN 0 ELSE LEAST(1.0, hours_since_first_breach/2000.0) END * 0.10 +
              LEAST(1.0, COALESCE(above_normal_count_24h, 0)/80.0) * 0.15, 4) AS degradation_score,
        ROUND(LEAST(1.0, GREATEST(0, COALESCE(degradation_velocity_30d, 0)/0.5)) * 0.5 +
              LEAST(1.0, COALESCE(above_normal_count_24h, 0)/80.0) * 0.5, 4) AS transition_probability
    FROM base
)
SELECT 
    asset_id, asset_name, asset_type, line_id, prediction_time,
    
    -- M1: Failure Mode (inlined)
    CASE
        WHEN vib_crest_factor_6h > 1.5 AND av_ratio > 20 AND vib_rms_24h > 5.0 THEN 'bearing_wear'
        WHEN temp_mean_24h > 70 AND vib_rms_24h < 4.0 AND stress_index > 0.5 THEN 'thermal_degradation'
        WHEN ABS(xy_corr) > 0.6 AND crpm_ratio > 8.0 AND axis_dom < 0.7 THEN 'misalignment'
        WHEN axis_dom > 0.75 AND vib_rms_24h > 4.0 AND crpm_ratio < 7.0 THEN 'imbalance'
        ELSE 'normal'
    END AS failure_mode_pred,
    CASE WHEN composite_health_score < 30 THEN 0.95
         WHEN composite_health_score < 60 THEN 0.80
         WHEN composite_health_score < 80 THEN 0.65
         ELSE 0.90 END AS failure_mode_confidence,

    -- M2: RUL (recalibrated — composite fallback when velocity is unavailable)
    ROUND(GREATEST(0, LEAST(2000,
        CASE 
            WHEN COALESCE(degradation_velocity_30d, 0) > 0.01 THEN
                (1.0 - fatigue_score) / (degradation_velocity_30d / 24.0)
            ELSE
                2000.0 * POWER(1.0 - LEAST(1.0, 
                    degradation_score * 0.40 + 
                    fatigue_score * 0.35 + 
                    stress_index * 0.15 + 
                    transition_probability * 0.10
                ), 3.0)
        END
    )), 1) AS rul_hours,
    ROUND(GREATEST(0, LEAST(2000,
        CASE 
            WHEN COALESCE(degradation_velocity_30d, 0) > 0.01 THEN
                (1.0 - fatigue_score) / (degradation_velocity_30d * 1.5 / 24.0)
            ELSE
                2000.0 * POWER(1.0 - LEAST(1.0, 
                    degradation_score * 0.40 + 
                    fatigue_score * 0.35 + 
                    stress_index * 0.15 + 
                    transition_probability * 0.10
                ) * 1.15, 3.0)
        END
    )), 1) AS rul_lower_ci,
    ROUND(GREATEST(0, LEAST(2000,
        CASE 
            WHEN COALESCE(degradation_velocity_30d, 0) > 0.01 THEN
                (1.0 - fatigue_score) / (degradation_velocity_30d * 0.5 / 24.0)
            ELSE
                2000.0 * POWER(1.0 - LEAST(1.0, 
                    degradation_score * 0.40 + 
                    fatigue_score * 0.35 + 
                    stress_index * 0.15 + 
                    transition_probability * 0.10
                ) * 0.85, 3.0)
        END
    )), 1) AS rul_upper_ci,

    -- M3: Stage (uses pre-computed degradation_score from scored CTE)
    CASE 
        WHEN degradation_score < 0.30 THEN 'Healthy'
        WHEN degradation_score < 0.65 THEN 'Warning'
        ELSE 'Critical'
    END AS stage_pred,
    degradation_score,
    transition_probability,

    -- M4: Fatigue
    fatigue_score,
    fatigue_level,
    
    -- Health
    composite_health_score,
    stress_index
FROM scored;


-- ============================================================================
-- CHECKPOINT 8a: WAIT FOR DYNAMIC TABLES TO REFRESH
-- ============================================================================
-- Dynamic tables use initialize=ON_CREATE but refresh is asynchronous.
-- We must wait until at least ML_FEATURES.ROLLING_STATS has rows before training.

USE WAREHOUSE COMPUTE_WH;

-- Force a manual refresh cascade (Layer 1 → 2 → 3) then poll for data
ALTER DYNAMIC TABLE CURATED.SENSOR_WITH_CONTEXT REFRESH;
ALTER DYNAMIC TABLE CURATED.ASSET_HEALTH_CURRENT REFRESH;
ALTER DYNAMIC TABLE CURATED.FAILURE_HISTORY REFRESH;

-- Wait for Layer 1 to complete before kicking off Layer 2
CALL SYSTEM$WAIT(30, 'SECONDS');

ALTER DYNAMIC TABLE ML_FEATURES.ROLLING_STATS REFRESH;
ALTER DYNAMIC TABLE ML_FEATURES.SENSOR_INTERACTIONS REFRESH;
ALTER DYNAMIC TABLE ML_FEATURES.PHYSICS_COMPOSITE REFRESH;
ALTER DYNAMIC TABLE ML_FEATURES.TEMPORAL_MEMORY REFRESH;

CALL SYSTEM$WAIT(60, 'SECONDS');

ALTER DYNAMIC TABLE ML_FEATURES.CROSS_DOMAIN REFRESH;
ALTER DYNAMIC TABLE ML_FEATURES.FLEET_COMPARISON REFRESH;
ALTER DYNAMIC TABLE ML_FEATURES.LABELED_DATA REFRESH;

CALL SYSTEM$WAIT(60, 'SECONDS');

-- Poll until ROLLING_STATS has data (up to 5 minutes)
DECLARE
    dt_count INT := 0;
    poll_iter INT := 0;
BEGIN
    LOOP
        SELECT COUNT(*) INTO :dt_count FROM ML_FEATURES.ROLLING_STATS;
        IF (:dt_count > 100 OR :poll_iter >= 20) THEN
            BREAK;
        END IF;
        CALL SYSTEM$WAIT(15, 'SECONDS');
        poll_iter := :poll_iter + 1;
    END LOOP;
    IF (:dt_count < 100) THEN
        INSERT INTO PUBLIC.DEPLOYMENT_LOG VALUES (
            85, 'DT_REFRESH_WARNING', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 0, 0, 'WARN',
            'ROLLING_STATS has only ' || :dt_count || ' rows after 5 min. ML training may fail.');
    ELSE
        INSERT INTO PUBLIC.DEPLOYMENT_LOG VALUES (
            85, 'DT_REFRESH_OK', CURRENT_TIMESTAMP(), CURRENT_TIMESTAMP(), 0, :dt_count, 'PASS',
            'ROLLING_STATS ready with ' || :dt_count || ' rows.');
    END IF;
END;


-- ============================================================================
-- CHECKPOINT 8b: NATIVE ML MODEL TRAINING (optional, ~5-10 min, ~0.5-2 credits)
-- Requires DTs from CP7-CP8 to have completed initial refresh.
-- Requires a Snowpark-optimized warehouse for large training datasets.
-- ============================================================================

-- Switch to a Snowpark-optimized warehouse for ML training
CREATE WAREHOUSE IF NOT EXISTS MFGPULSE_ML_TRAINING_WH
    WAREHOUSE_TYPE = 'SNOWPARK-OPTIMIZED'
    WAREHOUSE_SIZE = 'MEDIUM'
    AUTO_SUSPEND = 60
    AUTO_RESUME = TRUE
    INITIALLY_SUSPENDED = TRUE;
CREATE OR REPLACE RESOURCE MONITOR MFGPULSE_ML_TRAINING_GUARD WITH CREDIT_QUOTA=30 FREQUENCY=MONTHLY START_TIMESTAMP=IMMEDIATELY
    TRIGGERS ON 50 PERCENT DO NOTIFY ON 80 PERCENT DO SUSPEND ON 100 PERCENT DO SUSPEND_IMMEDIATE;
ALTER WAREHOUSE MFGPULSE_ML_TRAINING_WH SET RESOURCE_MONITOR = 'MFGPULSE_ML_TRAINING_GUARD';
USE WAREHOUSE MFGPULSE_ML_TRAINING_WH;

-- N1: Native Failure Mode Classifier (5% sample validated — see docs/ML_SAMPLING_VALIDATION_REPORT.md)
CREATE OR REPLACE SNOWFLAKE.ML.CLASSIFICATION MFGPULSE_DB.ML_MODELS.NATIVE_FAILURE_MODE_CLASSIFIER (
    INPUT_DATA => SYSTEM$QUERY_REFERENCE(
        'SELECT * FROM MFGPULSE_DB.ML_FEATURES.TRAIN_FAILURE_MODE SAMPLE (5)'
    ),
    TARGET_COLNAME => 'FAILURE_MODE'
);

-- N2: Native Degradation Stager (0.5% sample validated — see docs/ML_SAMPLING_VALIDATION_REPORT.md)
CREATE OR REPLACE SNOWFLAKE.ML.CLASSIFICATION MFGPULSE_DB.ML_MODELS.NATIVE_DEGRADATION_STAGER (
    INPUT_DATA => SYSTEM$QUERY_REFERENCE(
        'SELECT * FROM MFGPULSE_DB.ML_FEATURES.TRAIN_TRAJECTORY_3CLASS SAMPLE (0.5)'
    ),
    TARGET_COLNAME => 'STAGE_3CLASS'
);

-- N3: Materialize training view to avoid recomputing 5-way join on each training run
-- This is a point-in-time snapshot — refresh before retraining if underlying feature tables change.
CREATE OR REPLACE TABLE MFGPULSE_DB.ML_FEATURES.TRAIN_RUL_MAT AS
SELECT
    ASSET_ID, TIMESTAMP, HOURS_TO_FAILURE, FAILURE_MODE, DEGRADATION_STAGE,
    VIB_MAG_MEAN_6H, VIB_MAG_STD_6H, VIB_CREST_FACTOR_6H, VIB_COEFF_VAR_6H,
    VIB_MAG_STD_24H, VIB_CREST_FACTOR_24H,
    TEMP_MEAN_6H, CURRENT_MEAN_6H,
    VIB_RATE_OF_CHANGE_1H, VIB_ACCELERATION_1H, TEMP_RATE_OF_CHANGE_1H,
    VIB_XY_CORRELATION_DAILY, VIB_TEMP_COUPLING_DAILY, CURRENT_RPM_RATIO, VIB_AXIS_DOMINANCE,
    HOURS_SINCE_FIRST_BREACH, DEGRADATION_VELOCITY_30D, TREND_REVERSAL_COUNT_7D,
    ABOVE_NORMAL_COUNT_24H, VIB_TREND_72H, DEGRADATION_ACCELERATION,
    DAYS_SINCE_LAST_MAINTENANCE, CUMULATIVE_OPERATING_HOURS, MAINTENANCE_EFFECTIVENESS,
    COMPOSITE_HEALTH_SCORE, THERMAL_EFFICIENCY
FROM MFGPULSE_DB.ML_FEATURES.TRAIN_RUL;

-- N3: Native RUL Forecaster (uses TABLE() syntax, not SYSTEM$REFERENCE)
CREATE OR REPLACE SNOWFLAKE.ML.FORECAST MFGPULSE_DB.ML_MODELS.NATIVE_RUL_FORECASTER (
    INPUT_DATA => TABLE(MFGPULSE_DB.ML_FEATURES.TRAIN_RUL_MAT),
    SERIES_COLNAME => 'ASSET_ID',
    TIMESTAMP_COLNAME => 'TIMESTAMP',
    TARGET_COLNAME => 'HOURS_TO_FAILURE'
);

-- Switch back to the automation warehouse
USE WAREHOUSE MFGPULSE_AUTOMATION_WH;


-- ---- Drift Detection + Closed-Loop ML Objects ----

-- DRIFT_COMPARISON table
CREATE TABLE IF NOT EXISTS ML_MODELS.DRIFT_COMPARISON (
    COMPARISON_DATE DATE NOT NULL,
    ASSET_ID VARCHAR(20) NOT NULL,
    ASSET_NAME VARCHAR(100),
    RULE_FAILURE_MODE VARCHAR(50),
    NATIVE_FAILURE_MODE VARCHAR(50),
    RULE_STAGE VARCHAR(50),
    NATIVE_STAGE VARCHAR(50),
    FAILURE_MODE_AGREES BOOLEAN,
    STAGE_AGREES BOOLEAN,
    RULE_DEGRADATION_SCORE FLOAT,
    NATIVE_DEGRADATION_SCORE FLOAT,
    COMPARED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP()
);

-- DRIFT_METRICS view
drop table if exists ML_MODELS.DRIFT_METRICS;
CREATE OR REPLACE VIEW ML_MODELS.DRIFT_METRICS AS
SELECT 
    COMPARISON_DATE,
    COUNT(*) AS total_assets,
    SUM(CASE WHEN FAILURE_MODE_AGREES THEN 1 ELSE 0 END) AS fm_agreements,
    ROUND(SUM(CASE WHEN FAILURE_MODE_AGREES THEN 1 ELSE 0 END)::FLOAT / COUNT(*) * 100, 1) AS fm_agreement_pct,
    SUM(CASE WHEN STAGE_AGREES THEN 1 ELSE 0 END) AS stage_agreements,
    ROUND(SUM(CASE WHEN STAGE_AGREES THEN 1 ELSE 0 END)::FLOAT / COUNT(*) * 100, 1) AS stage_agreement_pct,
    LISTAGG(CASE WHEN NOT FAILURE_MODE_AGREES THEN ASSET_NAME || ' (rule:' || RULE_FAILURE_MODE || ' vs native:' || NATIVE_FAILURE_MODE || ')' END, '; ') AS fm_disagreements,
    LISTAGG(CASE WHEN NOT STAGE_AGREES THEN ASSET_NAME || ' (rule:' || RULE_STAGE || ' vs native:' || NATIVE_STAGE || ')' END, '; ') AS stage_disagreements
FROM ML_MODELS.DRIFT_COMPARISON
GROUP BY COMPARISON_DATE
ORDER BY COMPARISON_DATE DESC;

-- FEEDBACK_LOG table
CREATE TABLE IF NOT EXISTS ML_MODELS.FEEDBACK_LOG (
    FEEDBACK_ID NUMBER AUTOINCREMENT,
    WO_ID VARCHAR(30),
    ASSET_ID VARCHAR(20),
    PREDICTED_FAILURE_MODE VARCHAR(50),
    PREDICTED_STAGE VARCHAR(20),
    CONFIRMED_ROOT_CAUSE VARCHAR(50),
    WAS_CORRECT BOOLEAN,
    STAGE_WAS_CORRECT BOOLEAN,
    CONFIRMED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CONFIRMED_BY VARCHAR(100)
);

-- MODEL_ACCURACY_LIVE view
drop table if exists ML_MODELS.MODEL_ACCURACY_LIVE;
CREATE OR REPLACE VIEW ML_MODELS.MODEL_ACCURACY_LIVE AS
SELECT 
    COUNT(*) AS total_feedback,
    SUM(CASE WHEN WAS_CORRECT THEN 1 ELSE 0 END) AS correct_predictions,
    ROUND(SUM(CASE WHEN WAS_CORRECT THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) * 100, 1) AS failure_mode_accuracy_pct,
    SUM(CASE WHEN STAGE_WAS_CORRECT THEN 1 ELSE 0 END) AS correct_stages,
    ROUND(SUM(CASE WHEN STAGE_WAS_CORRECT THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) * 100, 1) AS stage_accuracy_pct,
    SUM(CASE WHEN CONFIRMED_ROOT_CAUSE = 'false_alarm' THEN 1 ELSE 0 END) AS false_alarms,
    ROUND(SUM(CASE WHEN CONFIRMED_ROOT_CAUSE = 'false_alarm' THEN 1 ELSE 0 END)::FLOAT / NULLIF(COUNT(*), 0) * 100, 1) AS false_alarm_rate_pct,
    MIN(CONFIRMED_AT) AS first_feedback,
    MAX(CONFIRMED_AT) AS last_feedback
FROM ML_MODELS.FEEDBACK_LOG
WHERE CONFIRMED_AT >= DATEADD('day', -30, CURRENT_TIMESTAMP());

-- COMPUTE_NATIVE_PREDICTIONS procedure (compares rule-based vs native ML)
-- Features: dedup (DELETE before INSERT), exception-safe (!PREDICT failure → UNAVAILABLE),
-- guaranteed non-NULL booleans via COALESCE on equality checks.
CREATE OR REPLACE PROCEDURE ML_MODELS.COMPUTE_NATIVE_PREDICTIONS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    LET fm_ok BOOLEAN := FALSE;
    LET stage_ok BOOLEAN := FALSE;

    -- Dedup: remove existing rows for today before inserting
    DELETE FROM MFGPULSE_DB.ML_MODELS.DRIFT_COMPARISON
    WHERE COMPARISON_DATE = CURRENT_DATE();

    -- Step 1: Build latest features for failure mode classifier
    CREATE OR REPLACE TEMPORARY TABLE MFGPULSE_DB.ML_MODELS._INFERENCE_FM AS
    SELECT 
        rs.asset_id,
        rs.vib_mag_mean_6h, rs.vib_mag_std_6h, rs.vib_mag_max_6h, rs.vib_crest_factor_6h,
        rs.vib_peak_to_peak_6h, rs.vib_rms_6h, rs.vib_coeff_var_6h,
        rs.temp_mean_6h, rs.temp_std_6h, rs.current_mean_6h, rs.current_std_6h,
        rs.vib_mag_mean_24h, rs.vib_mag_std_24h, rs.vib_crest_factor_24h, rs.vib_rms_24h,
        rs.temp_mean_24h, rs.current_mean_24h, rs.acoustic_mean_24h,
        rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
        COALESCE(si.vib_xy_correlation_daily, 0) AS vib_xy_correlation_daily,
        COALESCE(si.vib_temp_coupling_daily, 0) AS vib_temp_coupling_daily,
        COALESCE(si.current_rpm_ratio, 0) AS current_rpm_ratio,
        COALESCE(si.vib_axis_dominance, 0.5) AS vib_axis_dominance,
        COALESCE(si.acoustic_vib_ratio, 0) AS acoustic_vib_ratio,
        pc.stress_index, pc.iso_10816_severity, pc.composite_health_score
    FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn 
          FROM MFGPULSE_DB.ML_FEATURES.ROLLING_STATS QUALIFY rn = 1) rs
    LEFT JOIN (SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn 
               FROM MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS QUALIFY rn = 1) si ON rs.asset_id = si.asset_id
    LEFT JOIN (SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn 
               FROM MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE QUALIFY rn = 1) pc ON rs.asset_id = pc.asset_id;

    -- Step 2: Build latest features for degradation stager
    CREATE OR REPLACE TEMPORARY TABLE MFGPULSE_DB.ML_MODELS._INFERENCE_STAGE AS
    SELECT 
        rs.asset_id,
        rs.vib_mag_mean_6h, rs.vib_mag_std_6h, rs.vib_mag_max_6h, rs.vib_crest_factor_6h,
        rs.vib_rms_6h, rs.vib_peak_to_peak_6h, rs.temp_mean_6h, rs.current_mean_6h,
        rs.vib_mag_mean_24h, rs.vib_rms_24h, rs.vib_coeff_var_24h,
        rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
        COALESCE(si.vib_xy_correlation_daily, 0) AS vib_xy_correlation_daily,
        COALESCE(si.current_rpm_ratio, 0) AS current_rpm_ratio,
        COALESCE(si.vib_axis_dominance, 0.5) AS vib_axis_dominance,
        COALESCE(tm.hours_since_first_breach, 0) AS hours_since_first_breach,
        COALESCE(tm.degradation_velocity_30d, 0) AS degradation_velocity_30d,
        COALESCE(tm.above_normal_count_24h, 0) AS above_normal_count_24h,
        COALESCE(tm.vib_trend_72h, 0) AS vib_trend_72h,
        COALESCE(cd.days_since_last_maintenance, 0) AS days_since_last_maintenance,
        COALESCE(cd.cumulative_operating_hours, 0) AS cumulative_operating_hours,
        pc.stress_index, pc.composite_health_score, pc.iso_10816_severity
    FROM (SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn 
          FROM MFGPULSE_DB.ML_FEATURES.ROLLING_STATS QUALIFY rn = 1) rs
    LEFT JOIN (SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn 
               FROM MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS QUALIFY rn = 1) si ON rs.asset_id = si.asset_id
    LEFT JOIN (SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn 
               FROM MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE QUALIFY rn = 1) pc ON rs.asset_id = pc.asset_id
    LEFT JOIN (SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn 
               FROM MFGPULSE_DB.ML_FEATURES.TEMPORAL_MEMORY QUALIFY rn = 1) tm ON rs.asset_id = tm.asset_id
    LEFT JOIN (SELECT *, ROW_NUMBER() OVER (PARTITION BY asset_id ORDER BY timestamp DESC) AS rn 
               FROM MFGPULSE_DB.ML_FEATURES.CROSS_DOMAIN QUALIFY rn = 1) cd ON rs.asset_id = cd.asset_id;

    -- Step 3: Run native failure mode classifier (exception-safe)
    BEGIN
        CREATE OR REPLACE TEMPORARY TABLE MFGPULSE_DB.ML_MODELS._NATIVE_FM_RESULTS AS
        SELECT inf.asset_id,
               MFGPULSE_DB.ML_MODELS.NATIVE_FAILURE_MODE_CLASSIFIER!PREDICT(
                   INPUT_DATA => OBJECT_CONSTRUCT(*)
               ):"class"::VARCHAR AS native_failure_mode
        FROM MFGPULSE_DB.ML_MODELS._INFERENCE_FM inf;
        fm_ok := TRUE;
    EXCEPTION
        WHEN OTHER THEN
            CREATE OR REPLACE TEMPORARY TABLE MFGPULSE_DB.ML_MODELS._NATIVE_FM_RESULTS (
                asset_id VARCHAR(20), native_failure_mode VARCHAR(50));
    END;

    -- Step 4: Run native degradation stager (exception-safe)
    BEGIN
        CREATE OR REPLACE TEMPORARY TABLE MFGPULSE_DB.ML_MODELS._NATIVE_STAGE_RESULTS AS
        SELECT inf.asset_id,
               MFGPULSE_DB.ML_MODELS.NATIVE_DEGRADATION_STAGER!PREDICT(
                   INPUT_DATA => OBJECT_CONSTRUCT(*)
               ):"class"::VARCHAR AS native_stage
        FROM MFGPULSE_DB.ML_MODELS._INFERENCE_STAGE inf;
        stage_ok := TRUE;
    EXCEPTION
        WHEN OTHER THEN
            CREATE OR REPLACE TEMPORARY TABLE MFGPULSE_DB.ML_MODELS._NATIVE_STAGE_RESULTS (
                asset_id VARCHAR(20), native_stage VARCHAR(50));
    END;

    -- Step 5: Join and insert with guaranteed non-NULL booleans
    INSERT INTO MFGPULSE_DB.ML_MODELS.DRIFT_COMPARISON
        (COMPARISON_DATE, ASSET_ID, ASSET_NAME, RULE_FAILURE_MODE, NATIVE_FAILURE_MODE,
         RULE_STAGE, NATIVE_STAGE, FAILURE_MODE_AGREES, STAGE_AGREES,
         RULE_DEGRADATION_SCORE, NATIVE_DEGRADATION_SCORE, COMPARED_AT)
    SELECT
        CURRENT_DATE(), lp.asset_id, lp.asset_name,
        lp.failure_mode_pred,
        COALESCE(nfm.native_failure_mode, 'UNAVAILABLE'),
        lp.stage_pred,
        COALESCE(nst.native_stage, 'UNAVAILABLE'),
        COALESCE(lp.failure_mode_pred = nfm.native_failure_mode, FALSE),
        COALESCE(lp.stage_pred = nst.native_stage, FALSE),
        lp.degradation_score, NULL, CURRENT_TIMESTAMP()
    FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS lp
    LEFT JOIN MFGPULSE_DB.ML_MODELS._NATIVE_FM_RESULTS nfm ON lp.asset_id = nfm.asset_id
    LEFT JOIN MFGPULSE_DB.ML_MODELS._NATIVE_STAGE_RESULTS nst ON lp.asset_id = nst.asset_id;

    -- Step 6: Clean up
    DROP TABLE IF EXISTS MFGPULSE_DB.ML_MODELS._INFERENCE_FM;
    DROP TABLE IF EXISTS MFGPULSE_DB.ML_MODELS._INFERENCE_STAGE;
    DROP TABLE IF EXISTS MFGPULSE_DB.ML_MODELS._NATIVE_FM_RESULTS;
    DROP TABLE IF EXISTS MFGPULSE_DB.ML_MODELS._NATIVE_STAGE_RESULTS;

    LET msg VARCHAR := 'Drift comparison updated for ' || CURRENT_DATE()::VARCHAR;
    IF (:fm_ok) THEN
        msg := :msg || '. FM classifier: OK';
    ELSE
        msg := :msg || '. FM classifier: FAILED (all UNAVAILABLE)';
    END IF;
    IF (:stage_ok) THEN
        msg := :msg || '. Stage classifier: OK';
    ELSE
        msg := :msg || '. Stage classifier: FAILED (all UNAVAILABLE)';
    END IF;
    RETURN :msg;
END;

-- RETRAIN_IF_NEEDED procedure (auto-retrain when agreement < 80%)
CREATE OR REPLACE PROCEDURE ML_MODELS.RETRAIN_IF_NEEDED()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    LET fm_agreement FLOAT := 100.0;
    LET stage_agreement FLOAT := 100.0;
    LET retrained VARCHAR := '';

    SELECT fm_agreement_pct, stage_agreement_pct
    INTO :fm_agreement, :stage_agreement
    FROM MFGPULSE_DB.ML_MODELS.DRIFT_METRICS
    ORDER BY comparison_date DESC LIMIT 1;

    IF (:fm_agreement < 80.0) THEN
        CREATE OR REPLACE SNOWFLAKE.ML.CLASSIFICATION
            MFGPULSE_DB.ML_MODELS.NATIVE_FAILURE_MODE_CLASSIFIER(
                INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'MFGPULSE_DB.ML_FEATURES.TRAIN_FAILURE_MODE'),
                TARGET_COLNAME => 'FAILURE_MODE'
            );
        retrained := 'NATIVE_FAILURE_MODE_CLASSIFIER (fm_agreement=' || :fm_agreement || '%)';
    END IF;

    IF (:stage_agreement < 80.0) THEN
        CREATE OR REPLACE SNOWFLAKE.ML.CLASSIFICATION
            MFGPULSE_DB.ML_MODELS.NATIVE_DEGRADATION_STAGER(
                INPUT_DATA => SYSTEM$REFERENCE('VIEW', 'MFGPULSE_DB.ML_FEATURES.TRAIN_TRAJECTORY_3CLASS'),
                TARGET_COLNAME => 'STAGE_3CLASS'
            );
        IF (LENGTH(:retrained) > 0) THEN
            retrained := :retrained || ', ';
        END IF;
        retrained := :retrained || 'NATIVE_DEGRADATION_STAGER (stage_agreement=' || :stage_agreement || '%)';
    END IF;

    IF (LENGTH(:retrained) = 0) THEN
        RETURN 'No retraining needed. FM agreement: ' || :fm_agreement || '%, Stage agreement: ' || :stage_agreement || '%';
    END IF;

    UPDATE MFGPULSE_DB.ML_MODELS.MODEL_REGISTRY
    SET TRAINED_AT = CURRENT_TIMESTAMP()
    WHERE MODEL_NAME IN ('N1_FAILURE_MODE_NATIVE', 'N2_DEGRADATION_STAGER_NATIVE')
      AND :retrained ILIKE '%' || MODEL_NAME || '%';

    RETURN 'Retrained: ' || :retrained;
END;

-- LOG_FEEDBACK procedure
CREATE OR REPLACE PROCEDURE ML_MODELS.LOG_FEEDBACK(
    p_wo_id VARCHAR, p_asset_id VARCHAR, p_root_cause VARCHAR, p_confirmed_by VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    LET pred_mode VARCHAR := 'unknown';
    LET pred_stage VARCHAR := 'unknown';

    SELECT failure_mode_pred, stage_pred INTO :pred_mode, :pred_stage
    FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS WHERE asset_id = :p_asset_id LIMIT 1;

    INSERT INTO MFGPULSE_DB.ML_MODELS.FEEDBACK_LOG
        (WO_ID, ASSET_ID, PREDICTED_FAILURE_MODE, PREDICTED_STAGE, CONFIRMED_ROOT_CAUSE,
         WAS_CORRECT, STAGE_WAS_CORRECT, CONFIRMED_BY)
    VALUES (:p_wo_id, :p_asset_id, :pred_mode, :pred_stage, :p_root_cause,
            :pred_mode = :p_root_cause,
            CASE WHEN :p_root_cause = 'false_alarm' THEN :pred_stage = 'Healthy' ELSE TRUE END,
            :p_confirmed_by);

    RETURN 'Feedback logged for ' || :p_wo_id;
END;

-- NOTE: DAG_CHECK_DRIFT task moved to Checkpoint 11 (after DAG_REFRESH_DTS parent is created)

-- LIVE_PREDICTIONS_WITH_ANOMALY (augments LIVE_PREDICTIONS with M8 anomaly score)
CREATE OR REPLACE VIEW ML_MODELS.LIVE_PREDICTIONS_WITH_ANOMALY AS
SELECT
    lp.ASSET_ID, lp.ASSET_NAME, lp.ASSET_TYPE, lp.LINE_ID, lp.PREDICTION_TIME,
    lp.FAILURE_MODE_PRED, lp.FAILURE_MODE_CONFIDENCE, lp.RUL_HOURS,
    lp.RUL_LOWER_CI, lp.RUL_UPPER_CI, lp.STAGE_PRED, lp.DEGRADATION_SCORE,
    lp.TRANSITION_PROBABILITY, lp.FATIGUE_SCORE, lp.FATIGUE_LEVEL,
    lp.COMPOSITE_HEALTH_SCORE, lp.STRESS_INDEX,
    MFGPULSE_DB.ML_MODELS.ANOMALY_SCORER(
        rs.VIB_CREST_FACTOR_6H, rs.VIB_CREST_FACTOR_24H,
        rs.TEMP_RATE_OF_CHANGE_1H, si.ACOUSTIC_VIB_RATIO, pc.ENERGY_BALANCE_RATIO
    ) AS ANOMALY_SCORE
FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS lp
LEFT JOIN (SELECT ASSET_ID, VIB_CREST_FACTOR_6H, VIB_CREST_FACTOR_24H, TEMP_RATE_OF_CHANGE_1H
    FROM MFGPULSE_DB.ML_FEATURES.ROLLING_STATS
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ASSET_ID ORDER BY TIMESTAMP DESC) = 1) rs ON lp.ASSET_ID = rs.ASSET_ID
LEFT JOIN (SELECT ASSET_ID, ACOUSTIC_VIB_RATIO
    FROM MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ASSET_ID ORDER BY TIMESTAMP DESC) = 1) si ON lp.ASSET_ID = si.ASSET_ID
LEFT JOIN (SELECT ASSET_ID, ENERGY_BALANCE_RATIO
    FROM MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ASSET_ID ORDER BY TIMESTAMP DESC) = 1) pc ON lp.ASSET_ID = pc.ASSET_ID;


-- ============================================================================
-- CHECKPOINT 9: ANALYTICS LAYER + PROCUREMENT VIEWS
-- ============================================================================

-- 2 Analytics DTs
-- ACTIVE_ALERTS
drop table if exists ANALYTICS.ACTIVE_ALERTS;
create or replace dynamic table ANALYTICS.ACTIVE_ALERTS(
	ALERT_ID,
	ASSET_ID,
	ASSET_NAME,
	ASSET_TYPE,
	LINE_ID,
	CREATED_AT,
	SEVERITY,
	ALERT_TYPE,
	MESSAGE,
	FAILURE_MODE_PRED,
	FAILURE_MODE_CONFIDENCE,
	RUL_HOURS,
	RUL_LOWER_CI,
	RUL_UPPER_CI,
	STAGE_PRED,
	DEGRADATION_SCORE,
	TRANSITION_PROBABILITY,
	FATIGUE_SCORE,
	COMPOSITE_HEALTH_SCORE,
	WO_COUNT_90D,
	IS_CHRONIC,
	ESCALATION_AT,
	ACKNOWLEDGED,
	RESOLVED
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
 as
WITH alert_history AS (
    -- Count recent work orders per asset (chronic issue indicator)
    SELECT asset_id, COUNT(*) AS wo_count_90d
    FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS
    WHERE created_date >= DATEADD('day', -90, CURRENT_TIMESTAMP())
    GROUP BY asset_id
),
predictions AS (
    SELECT lp.*, COALESCE(ah.wo_count_90d, 0) AS wo_count_90d
    FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS lp
    LEFT JOIN alert_history ah ON lp.asset_id = ah.asset_id
)
SELECT 
    asset_id || '-' || TO_CHAR(prediction_time, 'YYYYMMDD') || '-' || 
        CASE 
            WHEN stage_pred = 'Critical' AND (rul_hours < 24 OR fatigue_score > 0.85) THEN 'CRIT'
            WHEN stage_pred = 'Critical' OR rul_hours < 72 OR fatigue_score > 0.7 THEN 'WARN'
            WHEN stage_pred = 'Warning' OR fatigue_score > 0.4 THEN 'WATCH'
            ELSE 'INFO'
        END AS alert_id,
    asset_id,
    asset_name,
    asset_type,
    line_id,
    prediction_time AS created_at,
    
    -- Severity (multi-signal logic)
    CASE 
        WHEN stage_pred = 'Critical' AND (rul_hours < 24 OR fatigue_score > 0.85) THEN 'CRITICAL'
        WHEN stage_pred = 'Critical' OR rul_hours < 72 OR fatigue_score > 0.7 THEN 'WARNING'
        WHEN stage_pred = 'Warning' OR fatigue_score > 0.4 THEN 'WATCH'
        WHEN fatigue_score > 0.2 AND stage_pred = 'Healthy' THEN 'INFO'
        ELSE NULL  -- no alert
    END AS severity,
    
    -- Alert type
    CASE 
        WHEN failure_mode_pred != 'normal' THEN 'FAILURE_PREDICTION'
        WHEN fatigue_score > 0.4 AND stage_pred = 'Healthy' THEN 'HIDDEN_FATIGUE'
        WHEN rul_hours < 72 THEN 'LOW_RUL'
        ELSE 'DEGRADATION'
    END AS alert_type,
    
    -- Context-rich message
    CONCAT(
        asset_name, ': ',
        CASE failure_mode_pred 
            WHEN 'normal' THEN 'Degradation detected'
            ELSE INITCAP(REPLACE(failure_mode_pred, '_', ' ')) || ' detected'
        END,
        '. RUL: ', ROUND(rul_hours, 0)::VARCHAR, 'hrs',
        '. Fatigue: ', ROUND(fatigue_score, 2)::VARCHAR,
        '. Stage: ', stage_pred,
        CASE WHEN wo_count_90d > 2 THEN '. CHRONIC: ' || wo_count_90d::VARCHAR || ' work orders in 90 days' ELSE '' END,
        '.'
    ) AS message,
    
    -- Model outputs for drill-down
    failure_mode_pred,
    failure_mode_confidence,
    rul_hours,
    rul_lower_ci,
    rul_upper_ci,
    stage_pred,
    degradation_score,
    transition_probability,
    fatigue_score,
    composite_health_score,
    
    -- Chronic issue flag
    wo_count_90d,
    CASE WHEN wo_count_90d > 2 THEN TRUE ELSE FALSE END AS is_chronic,
    
    -- Escalation timestamp (when this alert would auto-escalate)
    CASE 
        WHEN stage_pred = 'Critical' AND (rul_hours < 24 OR fatigue_score > 0.85) THEN NULL  -- already max
        WHEN stage_pred = 'Critical' OR rul_hours < 72 THEN DATEADD('hour', 12, prediction_time)  -- escalate in 12hrs
        WHEN stage_pred = 'Warning' OR fatigue_score > 0.4 THEN DATEADD('hour', 24, prediction_time)  -- escalate in 24hrs
        ELSE NULL
    END AS escalation_at,
    
    FALSE AS acknowledged,
    FALSE AS resolved

FROM predictions
WHERE stage_pred != 'Healthy' OR fatigue_score > 0.2;

-- OEE_METRICS
drop table if exists ANALYTICS.OEE_METRICS;
create or replace dynamic table ANALYTICS.OEE_METRICS(
	ASSET_ID,
	ASSET_NAME,
	LINE_ID,
	SHIFT_ID,
	SHIFT_DATE,
	SHIFT_TIME,
	AVAILABILITY_PCT,
	PERFORMANCE_PCT,
	QUALITY_PCT,
	OEE_PCT,
	AVAILABILITY_LOSS_PCT,
	PERFORMANCE_LOSS_PCT,
	QUALITY_LOSS_PCT,
	LOSS_ATTRIBUTED_TO,
	STAGE_PRED,
	FAILURE_MODE_PRED,
	RUL_HOURS,
	UNITS_PRODUCED,
	GOOD_UNITS
) target_lag = '1 hour' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
 as
WITH shift_production AS (
    SELECT 
        po.asset_id,
        am.asset_name,
        am.line_id,
        po.shift_id,
        po.timestamp AS shift_time,
        DATE_TRUNC('day', po.timestamp) AS shift_date,
        po.units_produced,
        po.good_units,
        -- Max production per shift (based on historical max for this asset)
        MAX(po.units_produced) OVER (PARTITION BY po.asset_id) AS max_units_per_shift,
        COALESCE(lp.stage_pred, 'Healthy') AS stage_pred,
        COALESCE(lp.failure_mode_pred, 'normal') AS failure_mode_pred,
        COALESCE(lp.rul_hours, 2000) AS rul_hours
    FROM MFGPULSE_DB.RAW_IT.PRODUCTION_OUTPUT po
    JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON po.asset_id = am.asset_id
    LEFT JOIN MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS lp ON po.asset_id = lp.asset_id
)
SELECT 
    asset_id,
    asset_name,
    line_id,
    shift_id,
    shift_date,
    shift_time,
    
    -- Availability: degradation reduces run time
    ROUND(GREATEST(30, 100 - 5 - 
        CASE WHEN stage_pred = 'Critical' THEN 15
             WHEN stage_pred = 'Warning' THEN 5
             ELSE 0 END
    ), 1) AS availability_pct,
    
    -- Performance: actual vs max capacity for this asset
    ROUND(LEAST(100, units_produced * 100.0 / NULLIF(max_units_per_shift, 0)), 1) AS performance_pct,
    
    -- Quality: good units / total units
    ROUND(LEAST(100, good_units * 100.0 / NULLIF(units_produced, 0)), 1) AS quality_pct,
    
    -- OEE = A × P × Q
    ROUND(GREATEST(30, 100 - 5 - CASE WHEN stage_pred = 'Critical' THEN 15 WHEN stage_pred = 'Warning' THEN 5 ELSE 0 END)
        * LEAST(100, units_produced * 100.0 / NULLIF(max_units_per_shift, 0))
        * LEAST(100, good_units * 100.0 / NULLIF(units_produced, 0))
        / 10000, 1) AS oee_pct,
    
    -- Loss breakdown
    ROUND(5 + CASE WHEN stage_pred = 'Critical' THEN 15 WHEN stage_pred = 'Warning' THEN 5 ELSE 0 END, 1) AS availability_loss_pct,
    ROUND(100 - LEAST(100, units_produced * 100.0 / NULLIF(max_units_per_shift, 0)), 1) AS performance_loss_pct,
    ROUND(100 - LEAST(100, good_units * 100.0 / NULLIF(units_produced, 0)), 1) AS quality_loss_pct,
    
    -- Loss attribution
    CASE 
        WHEN stage_pred = 'Critical' THEN 
            asset_name || ': ' || REPLACE(failure_mode_pred, '_', ' ') || ' reducing availability by 15%'
        WHEN stage_pred = 'Warning' THEN
            asset_name || ': degradation impacting performance by 5%'
        ELSE NULL
    END AS loss_attributed_to,
    
    stage_pred, failure_mode_pred, rul_hours, units_produced, good_units
    
FROM shift_production;


-- 6 Analytics Views
-- ALERT_SUMMARY
create or replace view ANALYTICS.ALERT_SUMMARY(
	CRITICAL_COUNT,
	WARNING_COUNT,
	WATCH_COUNT,
	INFO_COUNT,
	TOTAL_ALERTS
) as
SELECT 
    COUNT(CASE WHEN SEVERITY = 'CRITICAL' THEN 1 END) AS critical_count,
    COUNT(CASE WHEN SEVERITY = 'WARNING' THEN 1 END) AS warning_count,
    COUNT(CASE WHEN SEVERITY = 'WATCH' THEN 1 END) AS watch_count,
    COUNT(CASE WHEN SEVERITY = 'INFO' THEN 1 END) AS info_count,
    COUNT(*) AS total_alerts
FROM MFGPULSE_DB.ANALYTICS.ACTIVE_ALERTS;

-- COST_IMPACT
create or replace view ANALYTICS.COST_IMPACT(
	ASSETS_WITH_EARLY_DETECTION,
	AVG_EARLY_DETECTION_DAYS,
	MAX_EARLY_DETECTION_DAYS,
	TOTAL_COST_AVOIDED,
	DOWNTIME_HOURS_PREVENTED,
	AVG_COST_PER_EMERGENCY_FAILURE,
	AVG_COST_PER_PLANNED_REPAIR,
	COST_MULTIPLIER_IF_UNDETECTED,
	MAINTENANCE_ROI_X,
	CURRENT_PLANT_OEE,
	TARGET_OEE,
	OEE_IMPROVEMENT_POTENTIAL,
	TOTAL_ASSETS_MONITORED,
	ACTIVE_CRITICAL_WARNINGS
) as
WITH early_detections AS (
    -- Assets where fatigue detection caught issues before threshold alerting
    SELECT 
        fs.asset_id,
        am.asset_name,
        MIN(fs.timestamp) AS fatigue_first_warning,
        MIN(CASE WHEN sr.vibration_mag > 7.1 THEN sr.timestamp END) AS threshold_first_alert,
        MIN(wo.created_date) AS first_failure_date,
        AVG(CASE WHEN wo.wo_type = 'emergency' THEN wo.total_cost END) AS avg_emergency_cost,
        AVG(CASE WHEN wo.wo_type = 'corrective' THEN wo.total_cost END) AS avg_corrective_cost
    FROM MFGPULSE_DB.ML_MODELS.FATIGUE_SCORES fs
    JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON fs.asset_id = am.asset_id
    LEFT JOIN (
        SELECT asset_id, timestamp, 
            SQRT(POWER(vibration_x,2)+POWER(vibration_y,2)+POWER(vibration_z,2)) AS vibration_mag
        FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS
    ) sr ON fs.asset_id = sr.asset_id
    LEFT JOIN MFGPULSE_DB.RAW_IT.WORK_ORDERS wo ON fs.asset_id = wo.asset_id 
        AND wo.wo_type IN ('emergency', 'corrective')
    WHERE fs.fatigue_score > 0.4
    GROUP BY fs.asset_id, am.asset_name
),
detection_metrics AS (
    SELECT 
        asset_id,
        asset_name,
        fatigue_first_warning,
        threshold_first_alert,
        first_failure_date,
        GREATEST(0, DATEDIFF('day', fatigue_first_warning, threshold_first_alert)) AS days_early_vs_threshold,
        GREATEST(0, DATEDIFF('day', fatigue_first_warning, first_failure_date)) AS days_before_failure,
        COALESCE(avg_emergency_cost, 12000) AS emergency_cost,
        COALESCE(avg_corrective_cost, 2000) AS planned_repair_cost,
        COALESCE(avg_emergency_cost, 12000) - COALESCE(avg_corrective_cost, 2000) AS cost_avoided_per_event
    FROM early_detections
    WHERE threshold_first_alert IS NOT NULL
      AND fatigue_first_warning < COALESCE(first_failure_date, CURRENT_TIMESTAMP())
),
plant_oee AS (
    SELECT 
        ROUND(AVG(oee_pct), 1) AS current_plant_oee,
        ROUND(AVG(CASE WHEN stage_pred = 'Healthy' THEN oee_pct END), 1) AS healthy_asset_oee
    FROM MFGPULSE_DB.ANALYTICS.OEE_METRICS
),
summary AS (
    SELECT 
        COUNT(DISTINCT asset_id) AS assets_with_early_detection,
        ROUND(AVG(days_early_vs_threshold), 0) AS avg_days_early,
        ROUND(MAX(days_early_vs_threshold), 0) AS max_days_early,
        ROUND(SUM(cost_avoided_per_event), 0) AS total_cost_avoided,
        ROUND(AVG(emergency_cost), 0) AS avg_emergency_cost,
        ROUND(AVG(planned_repair_cost), 0) AS avg_planned_cost,
        ROUND(SUM(days_before_failure) * 8, 0) AS downtime_hours_prevented
    FROM detection_metrics
)
SELECT 
    -- Headline metrics
    s.assets_with_early_detection,
    s.avg_days_early AS avg_early_detection_days,
    s.max_days_early AS max_early_detection_days,
    s.total_cost_avoided,
    s.downtime_hours_prevented,
    
    -- Cost comparison
    s.avg_emergency_cost AS avg_cost_per_emergency_failure,
    s.avg_planned_cost AS avg_cost_per_planned_repair,
    ROUND(s.avg_emergency_cost / NULLIF(s.avg_planned_cost, 0), 1) AS cost_multiplier_if_undetected,
    
    -- ROI
    ROUND(s.total_cost_avoided / NULLIF(s.avg_planned_cost * s.assets_with_early_detection, 0), 1) AS maintenance_roi_x,
    
    -- OEE Impact
    po.current_plant_oee,
    COALESCE(po.healthy_asset_oee, 85.0) AS target_oee,
    ROUND(COALESCE(po.healthy_asset_oee, 85.0) - po.current_plant_oee, 1) AS oee_improvement_potential,
    
    -- Total assets monitored
    (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER) AS total_assets_monitored,
    
    -- Active alerts
    (SELECT COUNT(*) FROM MFGPULSE_DB.ANALYTICS.ACTIVE_ALERTS WHERE severity IN ('CRITICAL','WARNING')) AS active_critical_warnings

FROM summary s
CROSS JOIN plant_oee po;

-- COST_IMPACT_BY_ASSET
create or replace view ANALYTICS.COST_IMPACT_BY_ASSET(
	ASSET_ID,
	ASSET_NAME,
	EMERGENCY_COUNT,
	CORRECTIVE_COUNT,
	EMERGENCY_COST,
	CORRECTIVE_COST,
	PREVENTIVE_COST,
	TOTAL_COST,
	STAGE_PRED,
	RUL_HOURS,
	FATIGUE_SCORE,
	POTENTIAL_SAVINGS_IF_DETECTED_EARLY
) as
WITH asset_costs AS (
    SELECT 
        wo.asset_id,
        am.asset_name,
        COUNT(CASE WHEN wo.wo_type = 'emergency' THEN 1 END) AS emergency_count,
        COUNT(CASE WHEN wo.wo_type = 'corrective' THEN 1 END) AS corrective_count,
        COALESCE(SUM(CASE WHEN wo.wo_type = 'emergency' THEN wo.total_cost END), 0) AS emergency_cost,
        COALESCE(SUM(CASE WHEN wo.wo_type = 'corrective' THEN wo.total_cost END), 0) AS corrective_cost,
        COALESCE(SUM(CASE WHEN wo.wo_type = 'preventive' THEN wo.total_cost END), 0) AS preventive_cost,
        COALESCE(SUM(wo.total_cost), 0) AS total_cost
    FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS wo
    JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON wo.asset_id = am.asset_id
    WHERE wo.total_cost IS NOT NULL
    GROUP BY wo.asset_id, am.asset_name
)
SELECT 
    ac.*,
    lp.stage_pred,
    lp.rul_hours,
    lp.fatigue_score,
    CASE WHEN lp.stage_pred = 'Critical' AND ac.emergency_count > 0
        THEN ROUND(ac.emergency_cost - ac.corrective_cost, 0) 
        ELSE 0 
    END AS potential_savings_if_detected_early
FROM asset_costs ac
LEFT JOIN MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS lp ON ac.asset_id = lp.asset_id
ORDER BY total_cost DESC;

-- EXECUTIVE_SUMMARY
create or replace view ANALYTICS.EXECUTIVE_SUMMARY(
	TOTAL_ASSETS,
	CRITICAL_ASSETS,
	WARNING_ASSETS,
	HEALTHY_ASSETS,
	PLANT_OEE,
	OEE_TARGET,
	TOTAL_COST_AVOIDED,
	DOWNTIME_HOURS_PREVENTED,
	MAINTENANCE_ROI_X,
	AVG_EARLY_DETECTION_DAYS,
	MAX_EARLY_DETECTION_DAYS,
	AVG_COST_PER_EMERGENCY_FAILURE,
	AVG_COST_PER_PLANNED_REPAIR,
	COST_MULTIPLIER_IF_UNDETECTED,
	OEE_IMPROVEMENT_POTENTIAL,
	TOTAL_EMERGENCY_WOS,
	TOTAL_CORRECTIVE_WOS,
	TOTAL_PREVENTIVE_WOS,
	TOTAL_MAINTENANCE_SPEND
) as
SELECT
    -- Asset Health
    (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER) AS TOTAL_ASSETS,
    (SELECT COUNT(*) FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS WHERE STAGE_PRED = 'Critical') AS CRITICAL_ASSETS,
    (SELECT COUNT(*) FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS WHERE STAGE_PRED = 'Warning') AS WARNING_ASSETS,
    (SELECT COUNT(*) FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS WHERE STAGE_PRED = 'Healthy') AS HEALTHY_ASSETS,
    -- OEE
    (SELECT ROUND(AVG(OEE_PCT), 1) FROM MFGPULSE_DB.ANALYTICS.OEE_METRICS) AS PLANT_OEE,
    85.0 AS OEE_TARGET,
    -- Financial
    ci.TOTAL_COST_AVOIDED,
    ci.DOWNTIME_HOURS_PREVENTED,
    ci.MAINTENANCE_ROI_X,
    ci.AVG_EARLY_DETECTION_DAYS,
    ci.MAX_EARLY_DETECTION_DAYS,
    ci.AVG_COST_PER_EMERGENCY_FAILURE,
    ci.AVG_COST_PER_PLANNED_REPAIR,
    ci.COST_MULTIPLIER_IF_UNDETECTED,
    ci.OEE_IMPROVEMENT_POTENTIAL,
    -- Work Orders
    (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS WHERE WO_TYPE = 'emergency') AS TOTAL_EMERGENCY_WOS,
    (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS WHERE WO_TYPE = 'corrective') AS TOTAL_CORRECTIVE_WOS,
    (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS WHERE WO_TYPE = 'preventive') AS TOTAL_PREVENTIVE_WOS,
    (SELECT ROUND(SUM(TOTAL_COST), 0) FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS WHERE TOTAL_COST IS NOT NULL) AS TOTAL_MAINTENANCE_SPEND
FROM MFGPULSE_DB.ANALYTICS.COST_IMPACT ci;

-- ASSET_COST_PROFILES: Per-asset emergency failure and planned repair base costs,
-- grounded in historical WO spend. Used by PREDICTIONS_WITH_COST instead of the
-- plant-wide averages in COST_IMPACT.
CREATE TABLE IF NOT EXISTS ANALYTICS.ASSET_COST_PROFILES (
    ASSET_ID VARCHAR(20) NOT NULL,
    EMERGENCY_FAILURE_COST FLOAT NOT NULL,
    PLANNED_REPAIR_COST FLOAT NOT NULL,
    COST_BASIS_NOTES VARCHAR(500)
);
TRUNCATE TABLE IF EXISTS ANALYTICS.ASSET_COST_PROFILES;
INSERT INTO ANALYTICS.ASSET_COST_PROFILES
SELECT * FROM VALUES
  ('ASSET_001', 12000, 1800, 'Compressor: avg emergency $1300-1950, max parts $450. Scaled for full unplanned downtime + cascading line impact.'),
  ('ASSET_002', 11500, 1700, 'Compressor: emergency WO $1950. Slightly lower spec than A1.'),
  ('ASSET_003',  7500, 1400, 'Centrifugal pump: emergency $1600, corrective avg $1063, high-cost impeller/seal parts.'),
  ('ASSET_004',  7800, 1450, 'Centrifugal pump: similar to P1, slightly higher corrective avg.'),
  ('ASSET_005',  6000, 1100, 'Electric motor: avg emergency $1218, corrective $950. 4 emergency WOs on record.'),
  ('ASSET_006',  5800, 1050, 'Electric motor: emergency $1950 peak but lower avg part cost than M1.'),
  ('ASSET_007',  4200,  800, 'Axial fan: no emergency history, preventive avg $700. Scaled ~2x preventive for unplanned.'),
  ('ASSET_008',  9500, 1800, 'Gearbox: emergency $1300, corrective $1400, high-value gear set ($1200). Precision alignment.'),
  ('ASSET_009',  5000,  950, 'Conveyor: no emergency history, corrective avg $1025. Moderate complexity.'),
  ('ASSET_010', 25000, 4500, 'Steam turbine: no emergency history but $2200 blade set, 6000 RPM, 540C. Highest criticality.')
  AS t(ASSET_ID, EMERGENCY_FAILURE_COST, PLANNED_REPAIR_COST, COST_BASIS_NOTES);

-- PREDICTIONS_WITH_COST
-- Uses per-asset cost profiles (ASSET_COST_PROFILES) instead of plant-wide averages.
-- Degradation score influences cost estimates in ALL RUL brackets, not just <48h.
create or replace view ANALYTICS.PREDICTIONS_WITH_COST(
  ASSET_ID,
  ASSET_NAME,
  ASSET_TYPE,
  LINE_ID,
  PREDICTION_TIME,
  FAILURE_MODE_PRED,
  FAILURE_MODE_CONFIDENCE,
  RUL_HOURS,
  RUL_LOWER_CI,
  RUL_UPPER_CI,
  STAGE_PRED,
  DEGRADATION_SCORE,
  TRANSITION_PROBABILITY,
  FATIGUE_SCORE,
  FATIGUE_LEVEL,
  COMPOSITE_HEALTH_SCORE,
  STRESS_INDEX,
  ESTIMATED_FAILURE_COST,
  PLANNED_REPAIR_COST,
  COST_OF_INACTION,
  SHIFTS_REMAINING,
  ACTION_WINDOW,
  RECOMMENDED_PART,
  PARTS_IN_STOCK,
  PART_LEAD_TIME,
  PARTS_STATUS,
  OPEN_WO_ID,
  WO_ASSIGNED_TO,
  WO_PRIORITY
) as
SELECT 
    p.ASSET_ID, p.ASSET_NAME, p.ASSET_TYPE, p.LINE_ID, p.PREDICTION_TIME,
    p.FAILURE_MODE_PRED, p.FAILURE_MODE_CONFIDENCE, p.RUL_HOURS, p.RUL_LOWER_CI, p.RUL_UPPER_CI,
    p.STAGE_PRED, p.DEGRADATION_SCORE, p.TRANSITION_PROBABILITY,
    p.FATIGUE_SCORE, p.FATIGUE_LEVEL, p.COMPOSITE_HEALTH_SCORE, p.STRESS_INDEX,
    CASE 
        WHEN p.RUL_HOURS < 48  THEN ROUND(acp.EMERGENCY_FAILURE_COST * (1 + p.DEGRADATION_SCORE), 0)
        WHEN p.RUL_HOURS < 120 THEN ROUND(acp.EMERGENCY_FAILURE_COST * 0.7 * (1 + p.DEGRADATION_SCORE * 0.5), 0)
        ELSE ROUND(acp.EMERGENCY_FAILURE_COST * 0.4 * (1 + p.DEGRADATION_SCORE * 0.3), 0)
    END AS ESTIMATED_FAILURE_COST,
    CASE 
        WHEN p.RUL_HOURS < 48  THEN ROUND(acp.PLANNED_REPAIR_COST * 1.3, 0)
        WHEN p.RUL_HOURS < 120 THEN ROUND(acp.PLANNED_REPAIR_COST * (1 + p.DEGRADATION_SCORE * 0.2), 0)
        ELSE ROUND(acp.PLANNED_REPAIR_COST * 0.8 * (1 + p.DEGRADATION_SCORE * 0.1), 0)
    END AS PLANNED_REPAIR_COST,
    CASE 
        WHEN p.RUL_HOURS < 48  THEN ROUND(acp.EMERGENCY_FAILURE_COST * (1 + p.DEGRADATION_SCORE) - acp.PLANNED_REPAIR_COST * 1.3, 0)
        WHEN p.RUL_HOURS < 120 THEN ROUND(acp.EMERGENCY_FAILURE_COST * 0.7 * (1 + p.DEGRADATION_SCORE * 0.5) - acp.PLANNED_REPAIR_COST * (1 + p.DEGRADATION_SCORE * 0.2), 0)
        ELSE ROUND(acp.EMERGENCY_FAILURE_COST * 0.4 * (1 + p.DEGRADATION_SCORE * 0.3) - acp.PLANNED_REPAIR_COST * 0.8 * (1 + p.DEGRADATION_SCORE * 0.1), 0)
    END AS COST_OF_INACTION,
    ROUND(p.RUL_HOURS / 8, 1) AS SHIFTS_REMAINING,
    CASE WHEN p.RUL_HOURS < 48 THEN 'IMMEDIATE' WHEN p.RUL_HOURS < 168 THEN 'THIS WEEK' WHEN p.RUL_HOURS < 720 THEN 'NEXT WEEK' ELSE 'SCHEDULED' END AS ACTION_WINDOW,
    pi.PART_NAME AS RECOMMENDED_PART,
    pi.QUANTITY_ON_HAND AS PARTS_IN_STOCK,
    pi.LEAD_TIME_DAYS AS PART_LEAD_TIME,
    CASE WHEN pi.QUANTITY_ON_HAND > 0 THEN 'IN STOCK' WHEN pi.QUANTITY_ON_HAND = 0 THEN 'ORDER NEEDED' ELSE 'CHECK INVENTORY' END AS PARTS_STATUS,
    wo.WO_ID AS OPEN_WO_ID,
    wo.ASSIGNED_TO AS WO_ASSIGNED_TO,
    wo.PRIORITY AS WO_PRIORITY
FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS p
JOIN MFGPULSE_DB.ANALYTICS.ASSET_COST_PROFILES acp ON acp.ASSET_ID = p.ASSET_ID
LEFT JOIN MFGPULSE_DB.RAW_IT.PARTS_INVENTORY pi
    ON ARRAY_CONTAINS(p.ASSET_ID::VARIANT, pi.COMPATIBLE_ASSETS)
LEFT JOIN MFGPULSE_DB.RAW_IT.WORK_ORDERS wo
    ON wo.ASSET_ID = p.ASSET_ID AND wo.STATUS = 'open'
QUALIFY ROW_NUMBER() OVER (PARTITION BY p.ASSET_ID ORDER BY pi.UNIT_COST DESC NULLS LAST) = 1;

-- SHIFT_HANDOVER_VIEW
create or replace view ANALYTICS.SHIFT_HANDOVER_VIEW(
	CRITICAL_ACTION_COUNT,
	WARNING_COUNT,
	PLANT_OEE,
	PLANT_AVAIL,
	PLANT_PERF,
	PLANT_QUAL,
	URGENT_ALERTS,
	TOTAL_ALERTS,
	TOTAL_COST_AVOIDED,
	DOWNTIME_HOURS_PREVENTED,
	MAINTENANCE_ROI_X,
	GENERATED_AT
) as
WITH critical_actions AS (
    SELECT ASSET_NAME, FAILURE_MODE_PRED, RUL_HOURS, STAGE_PRED, FATIGUE_SCORE, DEGRADATION_SCORE
    FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS
    WHERE STAGE_PRED = 'Critical' AND RUL_HOURS < 72
    ORDER BY RUL_HOURS ASC
),
warnings AS (
    SELECT ASSET_NAME, STAGE_PRED, RUL_HOURS, FATIGUE_SCORE
    FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS
    WHERE STAGE_PRED = 'Critical' AND RUL_HOURS >= 72
    ORDER BY RUL_HOURS ASC
),
plant_oee AS (
    SELECT ROUND(AVG(OEE_PCT), 1) AS PLANT_OEE,
        ROUND(AVG(AVAILABILITY_PCT), 1) AS PLANT_AVAIL,
        ROUND(AVG(PERFORMANCE_PCT), 1) AS PLANT_PERF,
        ROUND(AVG(QUALITY_PCT), 1) AS PLANT_QUAL
    FROM MFGPULSE_DB.ANALYTICS.OEE_METRICS
),
alert_counts AS (
    SELECT COUNT(CASE WHEN SEVERITY IN ('CRITICAL','WARNING') THEN 1 END) AS URGENT_ALERTS,
        COUNT(*) AS TOTAL_ALERTS
    FROM MFGPULSE_DB.ANALYTICS.ACTIVE_ALERTS
),
costs AS (
    SELECT TOTAL_COST_AVOIDED, DOWNTIME_HOURS_PREVENTED, MAINTENANCE_ROI_X
    FROM MFGPULSE_DB.ANALYTICS.COST_IMPACT
)
SELECT 
    (SELECT COUNT(*) FROM critical_actions) AS CRITICAL_ACTION_COUNT,
    (SELECT COUNT(*) FROM warnings) AS WARNING_COUNT,
    po.PLANT_OEE, po.PLANT_AVAIL, po.PLANT_PERF, po.PLANT_QUAL,
    ac.URGENT_ALERTS, ac.TOTAL_ALERTS,
    co.TOTAL_COST_AVOIDED, co.DOWNTIME_HOURS_PREVENTED, co.MAINTENANCE_ROI_X,
    CURRENT_TIMESTAMP() AS GENERATED_AT
FROM plant_oee po
CROSS JOIN alert_counts ac
CROSS JOIN costs co;


-- Analytics Procedures
-- AUTO_GENERATE_WORK_ORDERS
CREATE OR REPLACE PROCEDURE ANALYTICS.AUTO_GENERATE_WORK_ORDERS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS '
BEGIN
    INSERT INTO MFGPULSE_DB.RAW_IT.WORK_ORDERS (WO_ID, ASSET_ID, WO_TYPE, CREATED_DATE, PRIORITY, STATUS, ASSIGNED_TO, LABOR_HOURS, PARTS_COST, TOTAL_COST)
    WITH candidates AS (
        SELECT p.ASSET_ID, p.RUL_HOURS, p.DEGRADATION_SCORE, p.FAILURE_MODE_PRED,
            ROW_NUMBER() OVER (ORDER BY p.RUL_HOURS ASC) AS rn
        FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS p
        WHERE (p.RUL_HOURS < 200 OR p.DEGRADATION_SCORE > 0.6 OR p.FAILURE_MODE_PRED != ''normal'')
            AND NOT EXISTS (SELECT 1 FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS wo WHERE wo.ASSET_ID = p.ASSET_ID AND wo.STATUS IN (''open'',''in_progress''))
    )
    SELECT ''WO-AUTO-'' || c.ASSET_ID || ''-'' || TO_CHAR(CURRENT_TIMESTAMP(), ''YYYYMMDD''),
        c.ASSET_ID,
        CASE WHEN c.RUL_HOURS < 48 THEN ''emergency'' WHEN c.RUL_HOURS < 120 THEN ''corrective'' ELSE ''preventive'' END,
        CURRENT_TIMESTAMP(),
        CASE WHEN c.RUL_HOURS < 48 THEN ''EMERGENCY'' WHEN c.RUL_HOURS < 120 THEN ''HIGH'' WHEN c.DEGRADATION_SCORE > 0.7 THEN ''MEDIUM'' ELSE ''LOW'' END,
        ''open'',
        CASE MOD(c.rn, 4) WHEN 0 THEN ''Mike Torres'' WHEN 1 THEN ''Sarah Chen'' WHEN 2 THEN ''James Wright'' ELSE ''Maria Garcia'' END,
        CASE WHEN c.RUL_HOURS < 48 THEN 8 WHEN c.RUL_HOURS < 120 THEN 6 ELSE 4 END,
        500,
        CASE WHEN c.RUL_HOURS < 48 THEN 1300 WHEN c.RUL_HOURS < 120 THEN 1100 ELSE 900 END
    FROM candidates c;
    BEGIN
        CALL MFGPULSE_DB.RAW_IT.LOG_APP_NOTIFICATION(
            ''WO_CREATED'', ''Auto-generated work orders'',
            ''Work orders auto-generated for at-risk assets at '' || CURRENT_TIMESTAMP()::VARCHAR,
            ''AUTO_GEN_WO'');
    EXCEPTION WHEN OTHER THEN NULL;
    END;
    RETURN ''Work orders generated at '' || CURRENT_TIMESTAMP()::VARCHAR;
END;
';

-- GENERATE_SHIFT_HANDOVER_SUMMARY
CREATE OR REPLACE PROCEDURE ANALYTICS.GENERATE_SHIFT_HANDOVER_SUMMARY()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS '
BEGIN
    LET data_context VARCHAR := (
        SELECT OBJECT_CONSTRUCT(
            ''plant_oee'', (SELECT PLANT_OEE FROM MFGPULSE_DB.ANALYTICS.EXECUTIVE_SUMMARY),
            ''oee_target'', 85,
            ''critical_assets'', (
                SELECT ARRAY_AGG(OBJECT_CONSTRUCT(
                    ''name'', ASSET_NAME, ''failure_mode'', FAILURE_MODE_PRED, 
                    ''rul_hours'', RUL_HOURS, ''stage'', STAGE_PRED,
                    ''degradation'', ROUND(DEGRADATION_SCORE, 2),
                    ''action_window'', ACTION_WINDOW,
                    ''failure_cost'', ESTIMATED_FAILURE_COST,
                    ''repair_cost'', PLANNED_REPAIR_COST,
                    ''assigned_to'', WO_ASSIGNED_TO,
                    ''wo_id'', OPEN_WO_ID,
                    ''parts_status'', PARTS_STATUS
                ))
                FROM MFGPULSE_DB.ANALYTICS.PREDICTIONS_WITH_COST
                WHERE RUL_HOURS < 200
            ),
            ''healthy_assets'', (
                SELECT ARRAY_AGG(ASSET_NAME) 
                FROM MFGPULSE_DB.ANALYTICS.PREDICTIONS_WITH_COST 
                WHERE STAGE_PRED = ''Healthy''
            ),
            ''alert_summary'', (SELECT OBJECT_CONSTRUCT(''critical'', CRITICAL_COUNT, ''warning'', WARNING_COUNT, ''info'', INFO_COUNT) FROM MFGPULSE_DB.ANALYTICS.ALERT_SUMMARY),
            ''auto_work_orders'', (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS WHERE WO_ID LIKE ''WO-AUTO%'' AND STATUS = ''open''),
            ''cost_avoided'', (SELECT TOTAL_COST_AVOIDED FROM MFGPULSE_DB.ANALYTICS.COST_IMPACT),
            ''maintenance_roi'', (SELECT MAINTENANCE_ROI_X FROM MFGPULSE_DB.ANALYTICS.COST_IMPACT)
        )::VARCHAR
    );

    LET ai_summary VARCHAR := (
        SELECT SNOWFLAKE.CORTEX.COMPLETE(
            ''llama3.1-70b'',
            ''You are a shift handover intelligence system for a manufacturing plant. Generate a concise, actionable shift handover briefing from this data. Use this exact format:

SHIFT HANDOVER BRIEFING
Generated: [current time]

CRITICAL ACTIONS (do these first):
[List assets with RUL < 72hrs. For each: asset name, failure mode, RUL, assigned technician, work order ID]

WARNINGS (monitor closely):
[List assets with RUL 72-200hrs. For each: asset name, risk, action window]

PLANT STATUS:
OEE: [current]% vs [target]% target | Gap: [diff]%
Alerts: [critical] critical, [warning] warnings
Active Work Orders: [count]

HEALTHY ASSETS:
[List healthy assets - all clear]

COST INTELLIGENCE:
Total cost avoided by early detection: $[amount]
Maintenance ROI: [X]x return
Cost of inaction on critical assets: $[sum of failure costs for critical]

INCOMING SHIFT PRIORITIES:
1. [Most urgent action]
2. [Second priority]
3. [Third priority]

Keep it factual, use exact numbers from the data. No fluff. Every line should be actionable.

DATA: '' || :data_context
        )
    );

    RETURN :ai_summary;
END;
';

-- GENERATE_WORK_ORDER (with auto-reserve from BOM)
CREATE OR REPLACE PROCEDURE ANALYTICS.GENERATE_WORK_ORDER(P_ASSET_ID VARCHAR, P_PRIORITY VARCHAR, P_ACTION VARCHAR, P_PARTS_NEEDED VARCHAR, P_ESTIMATED_COST FLOAT)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    v_wo_id VARCHAR;
    v_technician VARCHAR DEFAULT ''Unassigned'';
    v_parts_available BOOLEAN DEFAULT FALSE;
    v_line_id VARCHAR;
    v_asset_type VARCHAR;
    v_failure_mode VARCHAR;
    v_reserved_count INT DEFAULT 0;
    c_part_id VARCHAR;
    c_qty INT;
    bom_cursor CURSOR FOR
        SELECT bom.PART_ID, bom.QTY_PER_REPAIR
        FROM MFGPULSE_DB.RAW_IT.FAILURE_MODE_BOM bom
        JOIN MFGPULSE_DB.RAW_IT.PARTS_INVENTORY pi
            ON bom.PART_ID = pi.PART_ID AND ARRAY_CONTAINS(:p_asset_id::VARIANT, pi.COMPATIBLE_ASSETS)
        WHERE bom.ASSET_TYPE = :v_asset_type AND bom.FAILURE_MODE = :v_failure_mode;
BEGIN
    v_wo_id := ''WO-AUTO-'' || :p_asset_id || ''-'' || TO_CHAR(CURRENT_DATE(), ''YYYYMMDD'');
    SELECT line_id INTO :v_line_id FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER WHERE asset_id = :p_asset_id;
    SELECT asset_type INTO :v_asset_type FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER WHERE asset_id = :p_asset_id;
    BEGIN
        SELECT operator_name INTO :v_technician
        FROM MFGPULSE_DB.RAW_IT.SHIFT_SCHEDULE
        WHERE line_id = :v_line_id AND shift_start > CURRENT_TIMESTAMP()
        ORDER BY shift_start LIMIT 1;
    EXCEPTION WHEN OTHER THEN v_technician := ''Next available technician'';
    END;
    BEGIN
        SELECT COUNT(*) > 0 INTO :v_parts_available
        FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY
        WHERE ARRAY_CONTAINS(:p_asset_id::VARIANT, compatible_assets)
            AND quantity_on_hand > 0;
    EXCEPTION WHEN OTHER THEN v_parts_available := FALSE;
    END;
    BEGIN
        SELECT lp.FAILURE_MODE_PRED INTO :v_failure_mode
        FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS lp WHERE lp.ASSET_ID = :p_asset_id;
    EXCEPTION WHEN OTHER THEN v_failure_mode := ''normal'';
    END;
    INSERT INTO MFGPULSE_DB.RAW_IT.WORK_ORDERS 
    (wo_id, asset_id, wo_type, created_date, priority, status, assigned_to, parts_cost)
    VALUES (
        :v_wo_id, :p_asset_id, 
        CASE WHEN :p_priority = ''EMERGENCY'' THEN ''emergency'' ELSE ''corrective'' END,
        CURRENT_TIMESTAMP(), :p_priority, ''open'', :v_technician, :p_estimated_cost
    );
    IF (:v_failure_mode != ''normal'' AND :v_parts_available) THEN
        OPEN bom_cursor;
        FOR rec IN bom_cursor DO
            c_part_id := rec.PART_ID;
            c_qty := rec.QTY_PER_REPAIR;
            BEGIN
                CALL MFGPULSE_DB.ANALYTICS.RESERVE_PART_FOR_WORK_ORDER(
                    :p_asset_id, :v_wo_id, :c_part_id, :c_qty,
                    DATEADD(''day'', 7, CURRENT_DATE())
                );
                v_reserved_count := :v_reserved_count + 1;
            EXCEPTION WHEN OTHER THEN NULL;
            END;
        END FOR;
        CLOSE bom_cursor;
    END IF;
    RETURN OBJECT_CONSTRUCT(
        ''wo_id'', :v_wo_id,
        ''asset_id'', :p_asset_id,
        ''priority'', :p_priority,
        ''status'', ''open'',
        ''action'', :p_action,
        ''assigned_to'', :v_technician,
        ''parts_needed'', :p_parts_needed,
        ''parts_available'', :v_parts_available,
        ''parts_reserved'', :v_reserved_count,
        ''failure_mode'', :v_failure_mode,
        ''estimated_cost'', :p_estimated_cost,
        ''created_at'', CURRENT_TIMESTAMP()::VARCHAR,
        ''message'', ''Work order '' || :v_wo_id || '' created for '' || :p_asset_id || ''. Assigned to: '' || :v_technician || ''. Reserved '' || :v_reserved_count || '' part(s).''
    );
END;
';

-- PROCESS_INVENTORY_TRANSACTION
CREATE OR REPLACE PROCEDURE ANALYTICS.PROCESS_INVENTORY_TRANSACTION(
    P_PART_ID VARCHAR, P_QTY_CHANGE INT, P_TXN_TYPE VARCHAR, P_REFERENCE_ID VARCHAR, P_ASSET_ID VARCHAR, P_CREATED_BY VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    v_txn_id VARCHAR;
    v_current_qoh INT;
    v_new_qoh INT;
BEGIN
    v_txn_id := ''TXN-'' || TO_CHAR(CURRENT_TIMESTAMP(), ''YYYYMMDD-HH24MISS'') || ''-'' || :p_part_id;
    SELECT QUANTITY_ON_HAND INTO :v_current_qoh FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY WHERE PART_ID = :p_part_id;
    v_new_qoh := GREATEST(0, :v_current_qoh + :p_qty_change);
    INSERT INTO MFGPULSE_DB.RAW_IT.INVENTORY_TRANSACTIONS (TXN_ID, PART_ID, QTY_CHANGE, TXN_TYPE, REFERENCE_ID, ASSET_ID, CREATED_BY)
    VALUES (:v_txn_id, :p_part_id, :p_qty_change, :p_txn_type, :p_reference_id, :p_asset_id, :p_created_by);
    UPDATE MFGPULSE_DB.RAW_IT.PARTS_INVENTORY SET QUANTITY_ON_HAND = :v_new_qoh WHERE PART_ID = :p_part_id;
    RETURN OBJECT_CONSTRUCT(''status'', ''OK'', ''txn_id'', :v_txn_id, ''part_id'', :p_part_id,
        ''previous_qoh'', :v_current_qoh, ''change'', :p_qty_change, ''new_qoh'', :v_new_qoh);
END;
';

-- COMPLETE_WORK_ORDER (consumes inventory via BOM + consumes reservations)
CREATE OR REPLACE PROCEDURE ANALYTICS.COMPLETE_WORK_ORDER(P_WO_ID VARCHAR, P_PART_USED BOOLEAN)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    v_asset_id VARCHAR;
    v_asset_type VARCHAR;
    v_failure_mode VARCHAR;
    v_parts_consumed INT DEFAULT 0;
    v_reservations_consumed INT DEFAULT 0;
    c_part_id VARCHAR;
    c_qty INT;
    bom_cursor CURSOR FOR
        SELECT bom.PART_ID, bom.QTY_PER_REPAIR
        FROM MFGPULSE_DB.RAW_IT.FAILURE_MODE_BOM bom
        JOIN MFGPULSE_DB.RAW_IT.PARTS_INVENTORY pi
            ON bom.PART_ID = pi.PART_ID AND ARRAY_CONTAINS(:v_asset_id::VARIANT, pi.COMPATIBLE_ASSETS)
        WHERE bom.ASSET_TYPE = :v_asset_type AND bom.FAILURE_MODE = :v_failure_mode;
BEGIN
    SELECT wo.ASSET_ID INTO :v_asset_id FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS wo WHERE wo.WO_ID = :p_wo_id;
    SELECT am.ASSET_TYPE INTO :v_asset_type FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER am WHERE am.ASSET_ID = :v_asset_id;
    BEGIN
        SELECT lp.FAILURE_MODE_PRED INTO :v_failure_mode
        FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS lp WHERE lp.ASSET_ID = :v_asset_id;
    EXCEPTION WHEN OTHER THEN v_failure_mode := ''normal'';
    END;
    UPDATE MFGPULSE_DB.RAW_IT.WORK_ORDERS
    SET STATUS = ''completed'', COMPLETED_DATE = CURRENT_TIMESTAMP(), PART_USED = :p_part_used,
        ROOT_CAUSE_CONFIRMED = :v_failure_mode
    WHERE WO_ID = :p_wo_id;
    IF (:p_part_used AND :v_failure_mode != ''normal'') THEN
        OPEN bom_cursor;
        FOR rec IN bom_cursor DO
            c_part_id := rec.PART_ID;
            c_qty := rec.QTY_PER_REPAIR;
            CALL MFGPULSE_DB.ANALYTICS.PROCESS_INVENTORY_TRANSACTION(
                :c_part_id, -1 * :c_qty, ''consumption'', :p_wo_id, :v_asset_id, ''WO_COMPLETION'');
            v_parts_consumed := :v_parts_consumed + :c_qty;
        END FOR;
        CLOSE bom_cursor;
    END IF;
    UPDATE MFGPULSE_DB.RAW_IT.PART_RESERVATIONS
    SET STATUS = ''consumed''
    WHERE WO_ID = :p_wo_id AND STATUS = ''active'';
    SELECT CHANGES INTO :v_reservations_consumed;
    RETURN OBJECT_CONSTRUCT(''status'', ''COMPLETED'', ''wo_id'', :p_wo_id, ''asset_id'', :v_asset_id,
        ''failure_mode'', :v_failure_mode, ''parts_consumed'', :v_parts_consumed,
        ''reservations_consumed'', :v_reservations_consumed);
END;
';


-- Procurement Procedures
-- Stub LOG_APP_NOTIFICATION so procedures below can reference it.
-- Full implementation is in checkpoint 11 (notifications section) and overwrites this stub.
CREATE OR REPLACE PROCEDURE RAW_IT.LOG_APP_NOTIFICATION(
    P_EVENT_TYPE VARCHAR, P_TITLE VARCHAR, P_MESSAGE VARCHAR, P_ENTITY_ID VARCHAR)
RETURNS VARIANT LANGUAGE SQL EXECUTE AS CALLER AS 'BEGIN RETURN OBJECT_CONSTRUCT(''status'', ''STUB''); END';

-- GENERATE_PURCHASE_ORDER
CREATE OR REPLACE PROCEDURE ANALYTICS.GENERATE_PURCHASE_ORDER(
    P_ASSET_ID VARCHAR, P_PART_ID VARCHAR, P_QUANTITY NUMBER, P_REQUIRED_BY_DATE DATE,
    P_WO_ID VARCHAR, P_PRIORITY VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE
    v_po_id VARCHAR; v_supplier_id VARCHAR DEFAULT NULL; v_supplier_name VARCHAR DEFAULT 'Unknown';
    v_lead_time NUMBER DEFAULT 7; v_unit_cost FLOAT DEFAULT 0; v_expected_arrival DATE;
    v_existing_po VARCHAR DEFAULT NULL; v_rul_hours FLOAT DEFAULT NULL;
    v_failure_mode VARCHAR DEFAULT NULL; v_risk VARCHAR DEFAULT 'UNKNOWN';
BEGIN
    BEGIN
        SELECT po.PO_ID INTO :v_existing_po
        FROM MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES pol
        JOIN MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS po ON pol.PO_ID = po.PO_ID
        WHERE pol.PART_ID = :p_part_id AND pol.ASSET_ID = :p_asset_id
          AND po.STATUS NOT IN ('cancelled', 'received') LIMIT 1;
    EXCEPTION WHEN OTHER THEN v_existing_po := NULL;
    END;
    IF (:v_existing_po IS NOT NULL) THEN
        RETURN OBJECT_CONSTRUCT('status', 'DUPLICATE', 'existing_po_id', :v_existing_po,
            'message', 'Open PO already exists for this part and asset');
    END IF;
    BEGIN
        SELECT ps.SUPPLIER_ID, s.SUPPLIER_NAME, ps.STANDARD_LEAD_TIME_DAYS, ps.UNIT_COST
        INTO :v_supplier_id, :v_supplier_name, :v_lead_time, :v_unit_cost
        FROM MFGPULSE_DB.RAW_IT.PART_SUPPLIERS ps
        JOIN MFGPULSE_DB.RAW_IT.SUPPLIERS s ON ps.SUPPLIER_ID = s.SUPPLIER_ID
        WHERE ps.PART_ID = :p_part_id AND ps.PREFERRED_SUPPLIER = TRUE AND s.ACTIVE = TRUE LIMIT 1;
    EXCEPTION WHEN OTHER THEN NULL;
    END;
    IF (:v_supplier_id IS NULL) THEN
        BEGIN
            SELECT ps.SUPPLIER_ID, s.SUPPLIER_NAME, ps.STANDARD_LEAD_TIME_DAYS, ps.UNIT_COST
            INTO :v_supplier_id, :v_supplier_name, :v_lead_time, :v_unit_cost
            FROM MFGPULSE_DB.RAW_IT.PART_SUPPLIERS ps
            JOIN MFGPULSE_DB.RAW_IT.SUPPLIERS s ON ps.SUPPLIER_ID = s.SUPPLIER_ID
            WHERE ps.PART_ID = :p_part_id AND s.ACTIVE = TRUE ORDER BY ps.UNIT_COST ASC LIMIT 1;
        EXCEPTION WHEN OTHER THEN NULL;
        END;
    END IF;
    IF (:v_supplier_id IS NULL) THEN
        RETURN OBJECT_CONSTRUCT('status', 'ERROR', 'message', 'No active supplier found for part ' || :p_part_id);
    END IF;
    v_expected_arrival := DATEADD('day', :v_lead_time, CURRENT_DATE());
    BEGIN
        SELECT RUL_HOURS, FAILURE_MODE_PRED INTO :v_rul_hours, :v_failure_mode
        FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS WHERE ASSET_ID = :p_asset_id;
    EXCEPTION WHEN OTHER THEN NULL;
    END;
    v_risk := CASE
        WHEN :v_expected_arrival > DATEADD('hour', COALESCE(:v_rul_hours, 2000)::INTEGER, CURRENT_TIMESTAMP())::DATE THEN 'CRITICAL_SHORTAGE'
        WHEN :v_expected_arrival > :p_required_by_date THEN 'EXPEDITE'
        ELSE 'ORDER_NOW' END;
    v_po_id := 'PO-' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD-HH24MISS') || '-' || :p_asset_id;
    INSERT INTO MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS
        (PO_ID, SUPPLIER_ID, REQUIRED_BY_DATE, EXPECTED_ARRIVAL_DATE, STATUS, PRIORITY, TOTAL_COST, CREATED_BY, SOURCE)
    VALUES (:v_po_id, :v_supplier_id, :p_required_by_date, :v_expected_arrival, 'pending_approval',
        COALESCE(:p_priority, 'NORMAL'), :v_unit_cost * :p_quantity, CURRENT_USER(), 'prediction');
    INSERT INTO MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES
        (PO_LINE_ID, PO_ID, PART_ID, ASSET_ID, WO_ID, QUANTITY_ORDERED, UNIT_COST, LINE_COST,
         RUL_HOURS_AT_ORDER, FAILURE_MODE_PRED, PROCUREMENT_RISK)
    VALUES (:v_po_id || '-L1', :v_po_id, :p_part_id, :p_asset_id, :p_wo_id, :p_quantity,
        :v_unit_cost, :v_unit_cost * :p_quantity, :v_rul_hours, :v_failure_mode, :v_risk);
    BEGIN
        CALL MFGPULSE_DB.RAW_IT.LOG_APP_NOTIFICATION(
            'PO_CREATED', 'Purchase order created: ' || :v_po_id,
            'PO ' || :v_po_id || ' created for ' || :p_part_id || ' (asset: ' || :p_asset_id || '). Supplier: ' || :v_supplier_name || '. Cost: $' || (:v_unit_cost * :p_quantity)::VARCHAR,
            :v_po_id);
    EXCEPTION WHEN OTHER THEN NULL;
    END;
    RETURN OBJECT_CONSTRUCT('status', 'CREATED', 'po_id', :v_po_id, 'supplier', :v_supplier_name,
        'expected_arrival', :v_expected_arrival::VARCHAR, 'procurement_risk', :v_risk,
        'total_cost', :v_unit_cost * :p_quantity);
END;
$$;

-- AUTO_GENERATE_PURCHASE_ORDERS
CREATE OR REPLACE PROCEDURE ANALYTICS.AUTO_GENERATE_PURCHASE_ORDERS()
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE
    v_created NUMBER DEFAULT 0; v_skipped NUMBER DEFAULT 0; v_result VARIANT;
    c_asset_id VARCHAR; c_part_id VARCHAR; c_required_by DATE; c_wo_id VARCHAR; c_risk VARCHAR;
    c_req_qty NUMBER;
    rec_cursor CURSOR FOR
        SELECT ASSET_ID, PART_ID, REQUIRED_QUANTITY, REQUIRED_BY_DATE, WO_ID, PROCUREMENT_RISK
        FROM MFGPULSE_DB.ANALYTICS.PROCUREMENT_RECOMMENDATIONS
        WHERE RECOMMENDED_PROCUREMENT_ACTION IN (
            'CREATE_PO', 'EXPEDITE_PO',
            'ESCALATE_CRITICAL_SHORTAGE', 'ESCALATE_NO_WO',
            'RESERVE_AND_REORDER'
        )
          AND OPEN_PO_ID IS NULL
          AND (RUL_HOURS < 336 OR STAGE_PRED IN ('Warning', 'Critical') OR FAILURE_MODE_PRED != 'normal');
BEGIN
    OPEN rec_cursor;
    FOR rec IN rec_cursor DO
        c_asset_id := rec.ASSET_ID;
        c_part_id := rec.PART_ID;
        c_req_qty := rec.REQUIRED_QUANTITY;
        c_required_by := rec.REQUIRED_BY_DATE;
        c_wo_id := rec.WO_ID;
        c_risk := rec.PROCUREMENT_RISK;
        LET priority VARCHAR := CASE
            WHEN :c_risk = 'CRITICAL_SHORTAGE' THEN 'EMERGENCY'
            WHEN :c_risk = 'EXPEDITE' THEN 'EXPEDITE'
            ELSE 'HIGH' END;
        CALL MFGPULSE_DB.ANALYTICS.GENERATE_PURCHASE_ORDER(
            :c_asset_id, :c_part_id, :c_req_qty, :c_required_by, :c_wo_id, :priority);
        SELECT * INTO :v_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        IF (v_result:status::VARCHAR = 'CREATED') THEN v_created := :v_created + 1;
        ELSE v_skipped := :v_skipped + 1; END IF;
    END FOR;
    CLOSE rec_cursor;
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETE', 'pos_created', :v_created, 'pos_skipped', :v_skipped);
END;
$$;

-- RESERVE_PART_FOR_WORK_ORDER
CREATE OR REPLACE PROCEDURE ANALYTICS.RESERVE_PART_FOR_WORK_ORDER(
    P_ASSET_ID VARCHAR, P_WO_ID VARCHAR, P_PART_ID VARCHAR, P_QUANTITY NUMBER, P_REQUIRED_BY_DATE DATE
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE v_atp NUMBER; v_res_id VARCHAR;
BEGIN
    SELECT AVAILABLE_TO_PROMISE INTO :v_atp FROM MFGPULSE_DB.ANALYTICS.PARTS_AVAILABLE_TO_PROMISE WHERE PART_ID = :p_part_id;
    IF (:v_atp < :p_quantity) THEN
        RETURN OBJECT_CONSTRUCT('status', 'REJECTED', 'reason', 'Insufficient ATP: ' || :v_atp || ' available', 'available_to_promise', :v_atp);
    END IF;
    v_res_id := 'RES-' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD-HH24MISS') || '-' || :p_asset_id;
    INSERT INTO MFGPULSE_DB.RAW_IT.PART_RESERVATIONS
        (RESERVATION_ID, PART_ID, ASSET_ID, WO_ID, QUANTITY_RESERVED, REQUIRED_BY_DATE, STATUS)
    VALUES (:v_res_id, :p_part_id, :p_asset_id, :p_wo_id, :p_quantity, :p_required_by_date, 'active');
    RETURN OBJECT_CONSTRUCT('status', 'RESERVED', 'reservation_id', :v_res_id, 'quantity', :p_quantity, 'remaining_atp', :v_atp - :p_quantity);
END;
$$;

-- AUTO_CONVERT_PLANNED_POS (3-way logic: over-ordered → cancel+resize, under-ordered → supplement, exact → skip)
CREATE OR REPLACE PROCEDURE ANALYTICS.AUTO_CONVERT_PLANNED_POS()
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE
    v_converted NUMBER DEFAULT 0; v_skipped NUMBER DEFAULT 0;
    v_cancelled NUMBER DEFAULT 0; v_supplemented NUMBER DEFAULT 0;
    c_ppo_id VARCHAR; c_part_id VARCHAR; c_supplier_id VARCHAR;
    c_total_qty NUMBER; c_required_by DATE; c_asset_list VARCHAR; c_priority VARCHAR;
    existing_po_id VARCHAR; existing_po_qty NUMBER;
    v_supplier_id VARCHAR; v_supplier_name VARCHAR;
    v_lead_time NUMBER; v_unit_cost FLOAT; v_po_id VARCHAR; v_expected_arrival DATE;
    v_gap_qty NUMBER;
    ppo_cursor CURSOR FOR
        SELECT PPO_ID, PART_ID, SUPPLIER_ID, TOTAL_QTY_NEEDED, EARLIEST_REQUIRED_BY, ASSET_LIST, PRIORITY_CLASSIFICATION
        FROM MFGPULSE_DB.ANALYTICS.PLANNED_PURCHASE_ORDERS
        WHERE AUTO_CONVERT_DUE = TRUE AND PPO_STATUS IN ('AUTO_CONVERTING', 'EXPEDITE_IMMEDIATELY');
BEGIN
    OPEN ppo_cursor;
    FOR rec IN ppo_cursor DO
        c_ppo_id := rec.PPO_ID;
        c_part_id := rec.PART_ID;
        c_supplier_id := rec.SUPPLIER_ID;
        c_total_qty := rec.TOTAL_QTY_NEEDED;
        c_required_by := rec.EARLIEST_REQUIRED_BY;
        c_asset_list := rec.ASSET_LIST;
        c_priority := rec.PRIORITY_CLASSIFICATION;

        existing_po_id := NULL;
        existing_po_qty := 0;
        BEGIN
            SELECT po.PO_ID, SUM(pol.QUANTITY_ORDERED)
            INTO :existing_po_id, :existing_po_qty
            FROM MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES pol
            JOIN MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS po ON pol.PO_ID = po.PO_ID
            WHERE pol.PART_ID = :c_part_id AND po.STATUS NOT IN ('cancelled', 'received')
              AND po.SOURCE = 'auto_planned'
            GROUP BY po.PO_ID
            LIMIT 1;
        EXCEPTION WHEN OTHER THEN
            existing_po_id := NULL;
            existing_po_qty := 0;
        END;

        v_supplier_id := :c_supplier_id;
        v_supplier_name := 'Unknown';
        v_lead_time := 7;
        v_unit_cost := 0;
        BEGIN
            SELECT ps.SUPPLIER_ID, s.SUPPLIER_NAME, ps.STANDARD_LEAD_TIME_DAYS, ps.UNIT_COST
            INTO :v_supplier_id, :v_supplier_name, :v_lead_time, :v_unit_cost
            FROM MFGPULSE_DB.RAW_IT.PART_SUPPLIERS ps
            JOIN MFGPULSE_DB.RAW_IT.SUPPLIERS s ON ps.SUPPLIER_ID = s.SUPPLIER_ID
            WHERE ps.PART_ID = :c_part_id AND s.ACTIVE = TRUE
            ORDER BY ps.UNIT_COST ASC LIMIT 1;
        EXCEPTION WHEN OTHER THEN NULL;
        END;

        IF (:existing_po_id IS NULL) THEN
            -- NO EXISTING PO: Create new
            v_po_id := 'PO-AUTO-' || TO_CHAR(CURRENT_DATE(), 'YYYYMMDD') || '-' || :c_part_id;
            v_expected_arrival := DATEADD('day', :v_lead_time, CURRENT_DATE());
            INSERT INTO MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS
                (PO_ID, SUPPLIER_ID, REQUIRED_BY_DATE, EXPECTED_ARRIVAL_DATE, STATUS, PRIORITY, TOTAL_COST, CREATED_BY, SOURCE)
            VALUES (:v_po_id, :v_supplier_id, :c_required_by, :v_expected_arrival,
                'pending_approval', :c_priority, :v_unit_cost * :c_total_qty,
                'SYSTEM_AUTO_CONVERT', 'auto_planned');
            INSERT INTO MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES
                (PO_LINE_ID, PO_ID, PART_ID, ASSET_ID, WO_ID, QUANTITY_ORDERED, UNIT_COST, LINE_COST, PROCUREMENT_RISK)
            SELECT :v_po_id || '-L' || ROW_NUMBER() OVER (ORDER BY pr.ASSET_ID),
                :v_po_id, pr.PART_ID, pr.ASSET_ID, pr.WO_ID, pr.REQUIRED_QUANTITY,
                :v_unit_cost, :v_unit_cost * pr.REQUIRED_QUANTITY, pr.PROCUREMENT_RISK
            FROM MFGPULSE_DB.ANALYTICS.PROCUREMENT_RECOMMENDATIONS pr
            WHERE pr.PART_ID = :c_part_id
              AND pr.RECOMMENDED_PROCUREMENT_ACTION IN (
                  'CREATE_PO', 'EXPEDITE_PO',
                  'ESCALATE_CRITICAL_SHORTAGE', 'ESCALATE_NO_WO',
                  'RESERVE_AND_REORDER'
              )
              AND pr.OPEN_PO_ID IS NULL;
            BEGIN
                CALL MFGPULSE_DB.RAW_IT.LOG_APP_NOTIFICATION(
                    'PO_CREATED', 'Auto-converted PPO to PO: ' || :v_po_id,
                    'Planned PO ' || :c_ppo_id || ' auto-converted. Part: ' || :c_part_id || ', Qty: ' || :c_total_qty || ', Assets: ' || :c_asset_list,
                    :v_po_id);
            EXCEPTION WHEN OTHER THEN NULL;
            END;
            v_converted := :v_converted + 1;

        ELSEIF (:existing_po_qty > :c_total_qty) THEN
            -- OVER_ORDERED: Cancel existing + create right-sized replacement
            UPDATE MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS
            SET STATUS = 'cancelled',
                REJECTION_REASON = 'Over-ordered: PO had ' || :existing_po_qty || ' but safety stock recalculation needs only ' || :c_total_qty || '. Cancelled by auto-convert.',
                REJECTED_BY = 'SYSTEM_AUTO_CONVERT',
                REJECTED_AT = CURRENT_TIMESTAMP()
            WHERE PO_ID = :existing_po_id;
            v_po_id := 'PO-AUTO-' || TO_CHAR(CURRENT_DATE(), 'YYYYMMDD') || '-' || :c_part_id || '-RSZ';
            v_expected_arrival := DATEADD('day', :v_lead_time, CURRENT_DATE());
            INSERT INTO MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS
                (PO_ID, SUPPLIER_ID, REQUIRED_BY_DATE, EXPECTED_ARRIVAL_DATE, STATUS, PRIORITY, TOTAL_COST, CREATED_BY, SOURCE)
            VALUES (:v_po_id, :v_supplier_id, :c_required_by, :v_expected_arrival,
                'pending_approval', :c_priority, :v_unit_cost * :c_total_qty,
                'SYSTEM_AUTO_CONVERT', 'auto_planned');
            INSERT INTO MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES
                (PO_LINE_ID, PO_ID, PART_ID, ASSET_ID, WO_ID, QUANTITY_ORDERED, UNIT_COST, LINE_COST, PROCUREMENT_RISK)
            SELECT :v_po_id || '-L' || ROW_NUMBER() OVER (ORDER BY pr.ASSET_ID),
                :v_po_id, pr.PART_ID, pr.ASSET_ID, pr.WO_ID, pr.REQUIRED_QUANTITY,
                :v_unit_cost, :v_unit_cost * pr.REQUIRED_QUANTITY, pr.PROCUREMENT_RISK
            FROM MFGPULSE_DB.ANALYTICS.PROCUREMENT_RECOMMENDATIONS pr
            WHERE pr.PART_ID = :c_part_id
              AND pr.RECOMMENDED_PROCUREMENT_ACTION IN (
                  'CREATE_PO', 'EXPEDITE_PO',
                  'ESCALATE_CRITICAL_SHORTAGE', 'ESCALATE_NO_WO',
                  'RESERVE_AND_REORDER'
              )
              AND pr.OPEN_PO_ID IS NULL;
            BEGIN
                CALL MFGPULSE_DB.RAW_IT.LOG_APP_NOTIFICATION(
                    'PO_CANCELLED', 'Cancelled over-ordered PO ' || :existing_po_id || ', replaced with ' || :v_po_id,
                    'Old PO had ' || :existing_po_qty || ' units, safety stock now needs ' || :c_total_qty || '. Part: ' || :c_part_id || ', Assets: ' || :c_asset_list,
                    :v_po_id);
            EXCEPTION WHEN OTHER THEN NULL;
            END;
            v_cancelled := :v_cancelled + 1;

        ELSEIF (:existing_po_qty < :c_total_qty) THEN
            -- UNDER_ORDERED: Create supplemental PO for the gap
            v_gap_qty := :c_total_qty - :existing_po_qty;
            v_po_id := 'PO-AUTO-' || TO_CHAR(CURRENT_DATE(), 'YYYYMMDD') || '-' || :c_part_id || '-SUP';
            v_expected_arrival := DATEADD('day', :v_lead_time, CURRENT_DATE());
            INSERT INTO MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS
                (PO_ID, SUPPLIER_ID, REQUIRED_BY_DATE, EXPECTED_ARRIVAL_DATE, STATUS, PRIORITY, TOTAL_COST, CREATED_BY, SOURCE)
            VALUES (:v_po_id, :v_supplier_id, :c_required_by, :v_expected_arrival,
                'pending_approval', :c_priority, :v_unit_cost * :v_gap_qty,
                'SYSTEM_AUTO_CONVERT', 'auto_planned');
            INSERT INTO MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES
                (PO_LINE_ID, PO_ID, PART_ID, ASSET_ID, WO_ID, QUANTITY_ORDERED, UNIT_COST, LINE_COST, PROCUREMENT_RISK)
            SELECT :v_po_id || '-L' || ROW_NUMBER() OVER (ORDER BY pr.ASSET_ID),
                :v_po_id, pr.PART_ID, pr.ASSET_ID, pr.WO_ID, pr.REQUIRED_QUANTITY,
                :v_unit_cost, :v_unit_cost * pr.REQUIRED_QUANTITY, pr.PROCUREMENT_RISK
            FROM MFGPULSE_DB.ANALYTICS.PROCUREMENT_RECOMMENDATIONS pr
            WHERE pr.PART_ID = :c_part_id
              AND pr.RECOMMENDED_PROCUREMENT_ACTION IN (
                  'CREATE_PO', 'EXPEDITE_PO',
                  'ESCALATE_CRITICAL_SHORTAGE', 'ESCALATE_NO_WO',
                  'RESERVE_AND_REORDER'
              )
              AND pr.OPEN_PO_ID IS NULL;
            BEGIN
                CALL MFGPULSE_DB.RAW_IT.LOG_APP_NOTIFICATION(
                    'PO_CREATED', 'Supplemental PO ' || :v_po_id || ' for gap qty ' || :v_gap_qty,
                    'Existing PO ' || :existing_po_id || ' covers ' || :existing_po_qty || ' of ' || :c_total_qty || ' needed. Gap: ' || :v_gap_qty || '. Part: ' || :c_part_id || ', Assets: ' || :c_asset_list,
                    :v_po_id);
            EXCEPTION WHEN OTHER THEN NULL;
            END;
            v_supplemented := :v_supplemented + 1;

        ELSE
            -- EXACT_MATCH: Skip
            v_skipped := :v_skipped + 1;
        END IF;
    END FOR;
    CLOSE ppo_cursor;
    RETURN OBJECT_CONSTRUCT(
        'status', 'COMPLETE',
        'converted', :v_converted,
        'cancelled_and_resized', :v_cancelled,
        'supplemented', :v_supplemented,
        'skipped_exact_match', :v_skipped,
        'run_at', CURRENT_TIMESTAMP()::VARCHAR
    );
END;
$$;


-- 3 Procurement Views (PARTS_AVAILABLE_TO_PROMISE, PROCUREMENT_RECOMMENDATIONS, PARTS_LIFECYCLE_INSIGHTS)
--          PARTS_LIFECYCLE_INSIGHTS
--   PURCHASE_ORDERS, PURCHASE_ORDER_LINES, WORK_ORDERS, LIVE_PREDICTIONS



-- 1. PARTS_AVAILABLE_TO_PROMISE — ATP calculation per part
CREATE OR REPLACE VIEW ANALYTICS.PARTS_AVAILABLE_TO_PROMISE AS
SELECT
    pi.PART_ID,
    pi.PART_NAME,
    pi.QUANTITY_ON_HAND,
    COALESCE(r.RESERVED_QUANTITY, 0) AS RESERVED_QUANTITY,
    GREATEST(0, pi.QUANTITY_ON_HAND - COALESCE(r.RESERVED_QUANTITY, 0)) AS AVAILABLE_TO_PROMISE,
    pi.LEAD_TIME_DAYS,
    pi.UNIT_COST,
    COALESCE(ps.SUPPLIER_NAME, 'No Supplier') AS SUPPLIER_NAME,
    COALESCE(po_incoming.INCOMING_QTY, 0) AS INCOMING_PO_QTY
FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY pi
LEFT JOIN (
    SELECT PART_ID, SUM(QUANTITY_RESERVED) AS RESERVED_QUANTITY
    FROM MFGPULSE_DB.RAW_IT.PART_RESERVATIONS
    WHERE STATUS = 'active'
    GROUP BY PART_ID
) r ON pi.PART_ID = r.PART_ID
LEFT JOIN (
    SELECT ps2.PART_ID, s.SUPPLIER_NAME
    FROM MFGPULSE_DB.RAW_IT.PART_SUPPLIERS ps2
    JOIN MFGPULSE_DB.RAW_IT.SUPPLIERS s ON ps2.SUPPLIER_ID = s.SUPPLIER_ID
    WHERE ps2.PREFERRED_SUPPLIER = TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ps2.PART_ID ORDER BY ps2.UNIT_COST) = 1
) ps ON pi.PART_ID = ps.PART_ID
LEFT JOIN (
    SELECT pol.PART_ID, SUM(pol.QUANTITY_ORDERED) AS INCOMING_QTY
    FROM MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES pol
    JOIN MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS po ON pol.PO_ID = po.PO_ID
    WHERE po.STATUS IN ('approved','ordered','shipped')
    GROUP BY pol.PART_ID
) po_incoming ON pi.PART_ID = po_incoming.PART_ID;


-- ============================================================================
-- SAFETY_STOCK_POLICY — Auto-computed per-part safety stock thresholds
--    Inputs: LIVE_PREDICTIONS (at-risk assets), PARTS_INVENTORY (lead time),
--            PURCHASE_ORDER_LINES (historical PO frequency)
--    Updates automatically as predictions change.
-- ============================================================================
CREATE OR REPLACE DYNAMIC TABLE ANALYTICS.SAFETY_STOCK_POLICY
    TARGET_LAG = '2 days'
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
AS
WITH at_risk_demand AS (
    SELECT pi.PART_ID, COUNT(DISTINCT lp.ASSET_ID) AS at_risk_assets
    FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY pi
    JOIN MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS lp
      ON ARRAY_CONTAINS(lp.ASSET_ID::VARIANT, pi.COMPATIBLE_ASSETS)
    WHERE lp.FAILURE_MODE_PRED != 'normal' OR lp.STAGE_PRED IN ('Warning','Critical')
    GROUP BY pi.PART_ID
),
po_history AS (
    SELECT pol.PART_ID, COUNT(*) AS total_pos, ROUND(AVG(pol.QUANTITY_ORDERED), 1) AS avg_po_qty
    FROM MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES pol
    GROUP BY pol.PART_ID
)
SELECT
    pi.PART_ID,
    pi.PART_NAME,
    pi.QUANTITY_ON_HAND,
    pi.LEAD_TIME_DAYS,
    ARRAY_SIZE(pi.COMPATIBLE_ASSETS) AS TOTAL_COMPATIBLE_ASSETS,
    COALESCE(ard.at_risk_assets, 0) AS AT_RISK_ASSETS,
    COALESCE(ph.total_pos, 0) AS HISTORICAL_PO_COUNT,
    GREATEST(1, COALESCE(ard.at_risk_assets, 0) + 1) AS MIN_STOCK,
    GREATEST(2, COALESCE(ard.at_risk_assets, 0) + 1
        + CEIL(pi.LEAD_TIME_DAYS / 7.0 * GREATEST(COALESCE(ard.at_risk_assets, 0), 1))
    ) AS REORDER_POINT,
    GREATEST(1, COALESCE(ard.at_risk_assets, 0) + 1) AS REORDER_QTY
FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY pi
LEFT JOIN at_risk_demand ard ON pi.PART_ID = ard.PART_ID
LEFT JOIN po_history ph ON pi.PART_ID = ph.PART_ID;


-- ============================================================================
-- 2. PROCUREMENT_RECOMMENDATIONS — Industry-standard 3-signal evaluation
--    Signal 1: Urgency (RUL-based)
--    Signal 2: Supply (ATP, reservations, competing demand)
--    Signal 3: Fulfillment (lead time vs RUL gap)
--    Signal 4: Safety stock policy (auto-computed thresholds from SAFETY_STOCK_POLICY DT)
-- ============================================================================
CREATE OR REPLACE VIEW ANALYTICS.PROCUREMENT_RECOMMENDATIONS AS
WITH asset_predictions AS (
    SELECT lp.ASSET_ID, lp.ASSET_NAME, lp.FAILURE_MODE_PRED, lp.RUL_HOURS,
        lp.STAGE_PRED, lp.DEGRADATION_SCORE, lp.FATIGUE_SCORE,
        am.ASSET_TYPE
    FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS lp
    JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON lp.ASSET_ID = am.ASSET_ID
    WHERE lp.FAILURE_MODE_PRED != 'normal' OR lp.STAGE_PRED IN ('Warning','Critical')
),
compatible_parts AS (
    SELECT DISTINCT
        ap.ASSET_ID, ap.ASSET_NAME, ap.ASSET_TYPE, ap.FAILURE_MODE_PRED, ap.RUL_HOURS,
        ap.STAGE_PRED, ap.DEGRADATION_SCORE, ap.FATIGUE_SCORE,
        pi.PART_ID, pi.PART_NAME, pi.UNIT_COST, pi.LEAD_TIME_DAYS,
        COALESCE(bom.QTY_PER_REPAIR, 1) AS BOM_QTY
    FROM asset_predictions ap
    JOIN MFGPULSE_DB.RAW_IT.PARTS_INVENTORY pi
      ON ARRAY_CONTAINS(ap.ASSET_ID::VARIANT, pi.COMPATIBLE_ASSETS)
    LEFT JOIN MFGPULSE_DB.RAW_IT.FAILURE_MODE_BOM bom
      ON ap.ASSET_TYPE = bom.ASSET_TYPE AND ap.FAILURE_MODE_PRED = bom.FAILURE_MODE AND pi.PART_ID = bom.PART_ID
),
competing_assets AS (
    SELECT pi2.PART_ID, COUNT(DISTINCT lp2.ASSET_ID) AS COMPETING_ASSETS
    FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY pi2
    JOIN MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS lp2
      ON ARRAY_CONTAINS(lp2.ASSET_ID::VARIANT, pi2.COMPATIBLE_ASSETS)
    WHERE lp2.FAILURE_MODE_PRED != 'normal' OR lp2.STAGE_PRED IN ('Warning','Critical')
    GROUP BY pi2.PART_ID
),
active_reservations AS (
    SELECT PART_ID, ASSET_ID, WO_ID, SUM(QUANTITY_RESERVED) AS RESERVED_QTY
    FROM MFGPULSE_DB.RAW_IT.PART_RESERVATIONS
    WHERE STATUS = 'active'
    GROUP BY PART_ID, ASSET_ID, WO_ID
),
earliest_arrivals AS (
    SELECT pol.PART_ID, MIN(po.EXPECTED_ARRIVAL_DATE) AS EARLIEST_PO_ARRIVAL
    FROM MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES pol
    JOIN MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS po ON pol.PO_ID = po.PO_ID
    WHERE po.STATUS NOT IN ('cancelled','received')
    GROUP BY pol.PART_ID
),
with_supply AS (
    SELECT cp.*,
        atp.AVAILABLE_TO_PROMISE,
        atp.INCOMING_PO_QTY,
        COALESCE(atp.SUPPLIER_NAME, 'Unknown') AS SUPPLIER_NAME,
        COALESCE(ps.SUPPLIER_ID, 'SUP-001') AS SUPPLIER_ID,
        GREATEST(0, COALESCE(atp.AVAILABLE_TO_PROMISE, 0)
            - GREATEST(0, COALESCE(ca.COMPETING_ASSETS, 1) - 1)) AS EFFECTIVE_ATP,
        COALESCE(atp.AVAILABLE_TO_PROMISE, 0) + COALESCE(atp.INCOMING_PO_QTY, 0)
            - GREATEST(cp.BOM_QTY, COALESCE(ssp.MIN_STOCK, cp.BOM_QTY)) AS NET_POSITION,
        DATEADD('hour', GREATEST(cp.RUL_HOURS - 24, 0), CURRENT_TIMESTAMP())::DATE AS REQUIRED_BY_DATE,
        CASE WHEN cp.LEAD_TIME_DAYS * 24 <= cp.RUL_HOURS THEN TRUE ELSE FALSE END AS LEAD_TIME_FEASIBLE,
        epo.OPEN_PO_ID,
        wo.WO_ID,
        COALESCE(ca.COMPETING_ASSETS, 1) AS COMPETING_ASSETS,
        ea.EARLIEST_PO_ARRIVAL,
        CASE WHEN ar.RESERVED_QTY > 0 THEN TRUE ELSE FALSE END AS HAS_ACTIVE_RESERVATION,
        COALESCE(ar.RESERVED_QTY, 0) AS RESERVED_QTY,
        ssp.MIN_STOCK AS SSP_MIN_STOCK,
        ssp.REORDER_POINT AS SSP_REORDER_POINT,
        ssp.REORDER_QTY AS SSP_REORDER_QTY
    FROM compatible_parts cp
    LEFT JOIN MFGPULSE_DB.ANALYTICS.PARTS_AVAILABLE_TO_PROMISE atp ON cp.PART_ID = atp.PART_ID
    LEFT JOIN (
        SELECT ps2.PART_ID, ps2.SUPPLIER_ID
        FROM MFGPULSE_DB.RAW_IT.PART_SUPPLIERS ps2 WHERE ps2.PREFERRED_SUPPLIER = TRUE
        QUALIFY ROW_NUMBER() OVER (PARTITION BY ps2.PART_ID ORDER BY ps2.UNIT_COST) = 1
    ) ps ON cp.PART_ID = ps.PART_ID
    LEFT JOIN (
        SELECT pol.PART_ID, pol.ASSET_ID, po.PO_ID AS OPEN_PO_ID
        FROM MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES pol
        JOIN MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS po ON pol.PO_ID = po.PO_ID
        WHERE po.STATUS NOT IN ('cancelled','received')
        QUALIFY ROW_NUMBER() OVER (PARTITION BY pol.PART_ID, pol.ASSET_ID ORDER BY po.CREATED_DATE DESC) = 1
    ) epo ON cp.PART_ID = epo.PART_ID AND cp.ASSET_ID = epo.ASSET_ID
    LEFT JOIN (
        SELECT ASSET_ID, WO_ID FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS
        WHERE STATUS IN ('open','in_progress')
        QUALIFY ROW_NUMBER() OVER (PARTITION BY ASSET_ID ORDER BY CREATED_DATE DESC) = 1
    ) wo ON cp.ASSET_ID = wo.ASSET_ID
    LEFT JOIN competing_assets ca ON cp.PART_ID = ca.PART_ID
    LEFT JOIN earliest_arrivals ea ON cp.PART_ID = ea.PART_ID
    LEFT JOIN active_reservations ar ON cp.PART_ID = ar.PART_ID AND cp.ASSET_ID = ar.ASSET_ID
    LEFT JOIN MFGPULSE_DB.ANALYTICS.SAFETY_STOCK_POLICY ssp ON cp.PART_ID = ssp.PART_ID
)
SELECT
    ws.ASSET_ID, ws.ASSET_NAME, ws.PART_ID, ws.PART_NAME,
    ws.SUPPLIER_ID, ws.SUPPLIER_NAME,
    ws.RUL_HOURS, ws.STAGE_PRED, ws.FAILURE_MODE_PRED,
    ws.DEGRADATION_SCORE, ws.FATIGUE_SCORE,
    CASE
        WHEN ws.HAS_ACTIVE_RESERVATION                                         THEN 'RESERVED'
        WHEN ws.AVAILABLE_TO_PROMISE <= 0 AND ws.INCOMING_PO_QTY <= 0          THEN 'CRITICAL_SHORTAGE'
        WHEN ws.SSP_MIN_STOCK IS NOT NULL
             AND ws.AVAILABLE_TO_PROMISE <= ws.SSP_MIN_STOCK                    THEN 'CRITICAL_SHORTAGE'
        WHEN ws.RUL_HOURS < 72  AND ws.EFFECTIVE_ATP < ws.BOM_QTY
             AND NOT ws.LEAD_TIME_FEASIBLE                                      THEN 'EXPEDITE'
        WHEN ws.RUL_HOURS < 72  AND ws.EFFECTIVE_ATP < ws.BOM_QTY             THEN 'EXPEDITE'
        WHEN ws.RUL_HOURS < 72  AND ws.EFFECTIVE_ATP >= ws.BOM_QTY            THEN 'REPLENISH_NOW'
        WHEN NOT ws.LEAD_TIME_FEASIBLE AND ws.RUL_HOURS < 336
             AND ws.STAGE_PRED IN ('Warning','Critical')                        THEN 'EXPEDITE'
        WHEN ws.SSP_REORDER_POINT IS NOT NULL
             AND ws.AVAILABLE_TO_PROMISE <= ws.SSP_REORDER_POINT                THEN 'ORDER_NOW'
        WHEN ws.NET_POSITION < 0                                                THEN 'ORDER_NOW'
        WHEN ws.RUL_HOURS < 336 AND ws.EFFECTIVE_ATP < ws.BOM_QTY
             AND NOT ws.LEAD_TIME_FEASIBLE                                      THEN 'EXPEDITE'
        WHEN ws.RUL_HOURS < 336 AND ws.EFFECTIVE_ATP < ws.BOM_QTY             THEN 'ORDER_NOW'
        WHEN ws.RUL_HOURS < 336 AND ws.EFFECTIVE_ATP >= ws.BOM_QTY            THEN 'REPLENISH_NOW'
        ELSE 'NO_RISK'
    END AS PROCUREMENT_RISK,
    CASE
        WHEN ws.HAS_ACTIVE_RESERVATION                                         THEN 'MONITOR_RESERVATION'
        WHEN ws.OPEN_PO_ID IS NOT NULL
             AND ws.LEAD_TIME_FEASIBLE
             AND (ws.SSP_MIN_STOCK IS NULL
                  OR ws.AVAILABLE_TO_PROMISE + COALESCE(ws.INCOMING_PO_QTY, 0) > ws.SSP_MIN_STOCK)
             THEN 'MONITOR_EXISTING_PO'
        WHEN ws.AVAILABLE_TO_PROMISE <= 0 AND ws.INCOMING_PO_QTY <= 0          THEN 'ESCALATE_CRITICAL_SHORTAGE'
        WHEN ws.SSP_MIN_STOCK IS NOT NULL
             AND ws.AVAILABLE_TO_PROMISE <= ws.SSP_MIN_STOCK                    THEN 'ESCALATE_CRITICAL_SHORTAGE'
        WHEN ws.WO_ID IS NULL AND ws.RUL_HOURS < 72
             AND ws.STAGE_PRED IN ('Warning','Critical')                        THEN 'ESCALATE_NO_WO'
        WHEN ws.RUL_HOURS < 72  AND ws.EFFECTIVE_ATP >= ws.BOM_QTY            THEN 'RESERVE_AND_REORDER'
        WHEN ws.RUL_HOURS < 72  AND NOT ws.LEAD_TIME_FEASIBLE                 THEN 'ESCALATE_CRITICAL_SHORTAGE'
        WHEN ws.RUL_HOURS < 72                                                  THEN 'EXPEDITE_PO'
        WHEN ws.SSP_REORDER_POINT IS NOT NULL
             AND ws.AVAILABLE_TO_PROMISE <= ws.SSP_REORDER_POINT
             AND ws.OPEN_PO_ID IS NULL                                          THEN 'CREATE_PO'
        WHEN ws.OPEN_PO_ID IS NOT NULL AND NOT ws.LEAD_TIME_FEASIBLE           THEN 'EXPEDITE_PO'
        WHEN ws.EFFECTIVE_ATP >= ws.BOM_QTY AND ws.RUL_HOURS < 336            THEN 'RESERVE_AND_REORDER'
        WHEN ws.NET_POSITION < 0                                                THEN 'CREATE_PO'
        WHEN ws.RUL_HOURS < 336 AND NOT ws.LEAD_TIME_FEASIBLE                 THEN 'EXPEDITE_PO'
        WHEN ws.RUL_HOURS < 336                                                 THEN 'CREATE_PO'
        ELSE 'NO_ACTION'
    END AS RECOMMENDED_PROCUREMENT_ACTION,
    ws.OPEN_PO_ID, ws.WO_ID,
    ws.AVAILABLE_TO_PROMISE, ws.EFFECTIVE_ATP, ws.INCOMING_PO_QTY, ws.NET_POSITION,
    CASE
        WHEN ws.SSP_REORDER_QTY IS NOT NULL
             AND ws.AVAILABLE_TO_PROMISE <= ws.SSP_REORDER_POINT
             THEN GREATEST(ws.BOM_QTY, ws.SSP_REORDER_QTY)
        ELSE ws.BOM_QTY
    END AS REQUIRED_QUANTITY,
    ws.REQUIRED_BY_DATE,
    ws.LEAD_TIME_DAYS, ws.UNIT_COST,
    ws.COMPETING_ASSETS,
    ws.HAS_ACTIVE_RESERVATION, ws.RESERVED_QTY,
    ws.LEAD_TIME_FEASIBLE,
    CASE
        WHEN ws.NET_POSITION >= 2 THEN 'SURPLUS'
        WHEN ws.NET_POSITION >= 0 THEN 'TIGHT'
        ELSE 'DEFICIT'
    END AS BUFFER_STATUS,
    ws.LEAD_TIME_DAYS - CEIL(ws.RUL_HOURS / 24.0) AS LEAD_TIME_GAP_DAYS,
    ws.EARLIEST_PO_ARRIVAL
FROM with_supply ws;


-- 3. PARTS_LIFECYCLE_INSIGHTS — part health, usage trends, procurement history
CREATE OR REPLACE VIEW ANALYTICS.PARTS_LIFECYCLE_INSIGHTS AS
SELECT
    pi.PART_ID, pi.PART_NAME, pi.QUANTITY_ON_HAND, pi.UNIT_COST, pi.LEAD_TIME_DAYS,
    COALESCE(wo_usage.TIMES_USED, 0) AS TIMES_USED_IN_WOS,
    COALESCE(wo_usage.TOTAL_WO_COST, 0) AS TOTAL_WO_COST_INVOLVING_PART,
    COALESCE(po_history.TOTAL_ORDERED, 0) AS TOTAL_ORDERED_HISTORICALLY,
    COALESCE(po_history.LAST_ORDERED_DATE, NULL) AS LAST_ORDERED_DATE,
    COALESCE(res.ACTIVE_RESERVATIONS, 0) AS ACTIVE_RESERVATIONS,
    COALESCE(atp.AVAILABLE_TO_PROMISE, pi.QUANTITY_ON_HAND) AS AVAILABLE_TO_PROMISE,
    CASE
        WHEN pi.QUANTITY_ON_HAND = 0 THEN 'OUT_OF_STOCK'
        WHEN COALESCE(atp.AVAILABLE_TO_PROMISE, pi.QUANTITY_ON_HAND) <= 1 THEN 'LOW_STOCK'
        WHEN pi.LEAD_TIME_DAYS > 14 THEN 'LONG_LEAD_TIME'
        ELSE 'HEALTHY'
    END AS STOCK_STATUS,
    ARRAY_SIZE(pi.COMPATIBLE_ASSETS) AS COMPATIBLE_ASSET_COUNT,
    ps.SUPPLIER_NAME AS PREFERRED_SUPPLIER,
    COALESCE(at_risk.AT_RISK_ASSET_COUNT, 0) AS AT_RISK_ASSET_COUNT,
    COALESCE(at_risk.AT_RISK_ASSETS, '') AS AT_RISK_ASSETS,
    COALESCE(atp.INCOMING_PO_QTY, 0) AS INCOMING_QTY,
    COALESCE(atp.AVAILABLE_TO_PROMISE, pi.QUANTITY_ON_HAND)
        + COALESCE(atp.INCOMING_PO_QTY, 0)
        - COALESCE(at_risk.AT_RISK_ASSET_COUNT, 0) AS NET_POSITION,
    CASE
        WHEN COALESCE(atp.AVAILABLE_TO_PROMISE, pi.QUANTITY_ON_HAND)
             + COALESCE(atp.INCOMING_PO_QTY, 0)
             - COALESCE(at_risk.AT_RISK_ASSET_COUNT, 0) >= 2 THEN 'SURPLUS'
        WHEN COALESCE(atp.AVAILABLE_TO_PROMISE, pi.QUANTITY_ON_HAND)
             + COALESCE(atp.INCOMING_PO_QTY, 0)
             - COALESCE(at_risk.AT_RISK_ASSET_COUNT, 0) >= 0 THEN 'TIGHT'
        ELSE 'DEFICIT'
    END AS BUFFER_STATUS,
    CASE
        WHEN COALESCE(at_risk.AT_RISK_ASSET_COUNT, 0) = 0 THEN NULL
        ELSE ROUND(COALESCE(at_risk.MIN_RUL_HOURS, 0) / 24.0, 1)
    END AS EST_DAYS_UNTIL_STOCKOUT,
    ROUND(COALESCE(at_risk.MIN_RUL_HOURS, 0) / 24.0, 1) AS MIN_RUL_DAYS,
    po_arrival.EARLIEST_ARRIVAL
FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY pi
LEFT JOIN (
    SELECT pol.PART_ID, COUNT(DISTINCT wo.WO_ID) AS TIMES_USED, SUM(wo.TOTAL_COST) AS TOTAL_WO_COST
    FROM MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES pol
    JOIN MFGPULSE_DB.RAW_IT.WORK_ORDERS wo ON pol.WO_ID = wo.WO_ID
    GROUP BY pol.PART_ID
) wo_usage ON pi.PART_ID = wo_usage.PART_ID
LEFT JOIN (
    SELECT pol.PART_ID, SUM(pol.QUANTITY_ORDERED) AS TOTAL_ORDERED, MAX(po.CREATED_DATE) AS LAST_ORDERED_DATE
    FROM MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES pol
    JOIN MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS po ON pol.PO_ID = po.PO_ID
    GROUP BY pol.PART_ID
) po_history ON pi.PART_ID = po_history.PART_ID
LEFT JOIN (
    SELECT PART_ID, COUNT(*) AS ACTIVE_RESERVATIONS
    FROM MFGPULSE_DB.RAW_IT.PART_RESERVATIONS WHERE STATUS = 'active'
    GROUP BY PART_ID
) res ON pi.PART_ID = res.PART_ID
LEFT JOIN MFGPULSE_DB.ANALYTICS.PARTS_AVAILABLE_TO_PROMISE atp ON pi.PART_ID = atp.PART_ID
LEFT JOIN (
    SELECT ps2.PART_ID, s.SUPPLIER_NAME
    FROM MFGPULSE_DB.RAW_IT.PART_SUPPLIERS ps2
    JOIN MFGPULSE_DB.RAW_IT.SUPPLIERS s ON ps2.SUPPLIER_ID = s.SUPPLIER_ID
    WHERE ps2.PREFERRED_SUPPLIER = TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ps2.PART_ID ORDER BY ps2.UNIT_COST) = 1
) ps ON pi.PART_ID = ps.PART_ID
LEFT JOIN (
    SELECT pi2.PART_ID,
        COUNT(DISTINCT lp.ASSET_ID) AS AT_RISK_ASSET_COUNT,
        LISTAGG(DISTINCT lp.ASSET_NAME, ', ') WITHIN GROUP (ORDER BY lp.ASSET_NAME) AS AT_RISK_ASSETS,
        MIN(lp.RUL_HOURS) AS MIN_RUL_HOURS
    FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY pi2
    JOIN MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS lp
      ON ARRAY_CONTAINS(lp.ASSET_ID::VARIANT, pi2.COMPATIBLE_ASSETS)
    WHERE lp.FAILURE_MODE_PRED != 'normal' OR lp.STAGE_PRED IN ('Warning','Critical')
    GROUP BY pi2.PART_ID
) at_risk ON pi.PART_ID = at_risk.PART_ID
LEFT JOIN (
    SELECT pol.PART_ID, MIN(po.EXPECTED_ARRIVAL_DATE) AS EARLIEST_ARRIVAL
    FROM MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES pol
    JOIN MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS po ON pol.PO_ID = po.PO_ID
    WHERE po.STATUS NOT IN ('cancelled','received')
    GROUP BY pol.PART_ID
) po_arrival ON pi.PART_ID = po_arrival.PART_ID;


-- ============================================================================
-- 4. PROCUREMENT_PERFORMANCE — Cross-entity metrics (Tier 2)
--    Links: WO → PO → Parts → Predictions
-- ============================================================================
CREATE OR REPLACE VIEW ANALYTICS.PROCUREMENT_PERFORMANCE AS
WITH wo_po_link AS (
    SELECT
        wo.WO_ID, wo.ASSET_ID, wo.WO_TYPE, wo.CREATED_DATE AS WO_CREATED,
        wo.COMPLETED_DATE AS WO_COMPLETED, wo.STATUS AS WO_STATUS,
        wo.ROOT_CAUSE_CONFIRMED, wo.PART_USED,
        wo.TOTAL_COST AS WO_COST,
        pol.PO_ID, pol.PART_ID, pol.FAILURE_MODE_PRED AS PRED_AT_ORDER,
        po.CREATED_DATE AS PO_CREATED, po.STATUS AS PO_STATUS,
        po.EXPECTED_ARRIVAL_DATE,
        am.ASSET_NAME, am.ASSET_TYPE
    FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS wo
    JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON wo.ASSET_ID = am.ASSET_ID
    LEFT JOIN MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES pol ON wo.WO_ID = pol.WO_ID
    LEFT JOIN MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS po ON pol.PO_ID = po.PO_ID
),
-- WO-to-PO response time
wo_po_lag AS (
    SELECT
        WO_ID, ASSET_ID, ASSET_NAME,
        WO_CREATED, PO_CREATED,
        DATEDIFF('hour', WO_CREATED, PO_CREATED) AS WO_TO_PO_LAG_HOURS
    FROM wo_po_link
    WHERE PO_CREATED IS NOT NULL
),
-- WO blocked time (open but not started due to parts)
wo_blocked AS (
    SELECT
        wo.WO_ID, wo.ASSET_ID,
        wo.CREATED_DATE AS WO_CREATED,
        MIN(n.CREATED_AT) AS FIRST_START,
        DATEDIFF('hour', wo.CREATED_DATE, MIN(n.CREATED_AT)) AS WO_BLOCKED_HOURS
    FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS wo
    LEFT JOIN MFGPULSE_DB.RAW_IT.APP_NOTIFICATIONS n
        ON n.ENTITY_ID = wo.WO_ID AND n.EVENT_TYPE = 'WO_STARTED'
    WHERE wo.STATUS IN ('in_progress', 'completed')
    GROUP BY wo.WO_ID, wo.ASSET_ID, wo.CREATED_DATE
),
-- Repeat failures: same asset + failure mode within 60 days
repeat_failures AS (
    SELECT
        w1.WO_ID,
        w1.ASSET_ID,
        w1.ROOT_CAUSE_CONFIRMED AS FAILURE_MODE,
        COUNT(w2.WO_ID) AS REPEAT_COUNT
    FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS w1
    JOIN MFGPULSE_DB.RAW_IT.WORK_ORDERS w2
        ON w1.ASSET_ID = w2.ASSET_ID
        AND w1.ROOT_CAUSE_CONFIRMED = w2.ROOT_CAUSE_CONFIRMED
        AND w2.CREATED_DATE > w1.COMPLETED_DATE
        AND w2.CREATED_DATE <= DATEADD('day', 60, w1.COMPLETED_DATE)
        AND w1.WO_ID != w2.WO_ID
    WHERE w1.STATUS = 'completed' AND w1.ROOT_CAUSE_CONFIRMED IS NOT NULL
    GROUP BY w1.WO_ID, w1.ASSET_ID, w1.ROOT_CAUSE_CONFIRMED
),
-- Cost avoidance: emergency vs preventive/corrective cost differential
cost_avoidance AS (
    SELECT
        wo.WO_ID, wo.ASSET_ID, wo.WO_TYPE,
        wo.TOTAL_COST,
        CASE
            WHEN wo.WO_TYPE IN ('preventive', 'corrective') THEN
                (SELECT AVG(w2.TOTAL_COST) FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS w2
                 WHERE w2.WO_TYPE = 'emergency' AND w2.ASSET_ID = wo.ASSET_ID AND w2.TOTAL_COST IS NOT NULL)
                - wo.TOTAL_COST
            ELSE 0
        END AS COST_AVOIDED
    FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS wo
    WHERE wo.STATUS = 'completed' AND wo.TOTAL_COST IS NOT NULL
)
SELECT
    wpl.WO_ID, wpl.ASSET_ID, wpl.ASSET_NAME, wpl.ASSET_TYPE,
    wpl.WO_TYPE, wpl.WO_STATUS, wpl.WO_CREATED, wpl.WO_COMPLETED,
    wpl.ROOT_CAUSE_CONFIRMED, wpl.PART_USED, wpl.WO_COST,
    wpl.PO_ID, wpl.PART_ID, wpl.PO_STATUS,
    COALESCE(wpl2.WO_TO_PO_LAG_HOURS, NULL) AS WO_TO_PO_LAG_HOURS,
    COALESCE(wb.WO_BLOCKED_HOURS, 0) AS WO_BLOCKED_HOURS,
    COALESCE(rf.REPEAT_COUNT, 0) AS REPEAT_FAILURE_COUNT,
    rf.FAILURE_MODE AS REPEAT_FAILURE_MODE,
    COALESCE(ca.COST_AVOIDED, 0) AS COST_AVOIDED,
    CASE WHEN wpl.WO_TYPE IN ('preventive','corrective') AND wpl.ROOT_CAUSE_CONFIRMED IS NOT NULL
         THEN TRUE ELSE FALSE END AS PREDICTION_LED_TO_WO,
    CASE WHEN wpl.PART_USED = TRUE AND wpl.WO_TYPE IN ('preventive','corrective')
         THEN 'CONSUMED_AS_PREDICTED'
         WHEN wpl.PART_USED = FALSE AND wpl.WO_TYPE IN ('preventive','corrective')
         THEN 'NOT_CONSUMED'
         ELSE 'N/A'
    END AS PART_CONSUMPTION_OUTCOME
FROM wo_po_link wpl
LEFT JOIN wo_po_lag wpl2 ON wpl.WO_ID = wpl2.WO_ID
LEFT JOIN wo_blocked wb ON wpl.WO_ID = wb.WO_ID
LEFT JOIN repeat_failures rf ON wpl.WO_ID = rf.WO_ID
LEFT JOIN cost_avoidance ca ON wpl.WO_ID = ca.WO_ID
QUALIFY ROW_NUMBER() OVER (PARTITION BY wpl.WO_ID ORDER BY wpl.PO_CREATED DESC NULLS LAST) = 1;


-- ============================================================================
-- 5. SUPPLIER_SCORECARD — Supplier performance metrics (Tier 3)
-- ============================================================================
CREATE OR REPLACE VIEW ANALYTICS.SUPPLIER_SCORECARD AS
WITH po_delivery AS (
    SELECT
        po.PO_ID, po.SUPPLIER_ID, po.STATUS,
        po.CREATED_DATE, po.EXPECTED_ARRIVAL_DATE,
        po.PRIORITY,
        pol.PART_ID, pol.UNIT_COST AS LINE_UNIT_COST,
        ps.UNIT_COST AS CATALOG_UNIT_COST,
        ps.STANDARD_LEAD_TIME_DAYS,
        ps.EXPEDITE_LEAD_TIME_DAYS,
        CASE WHEN po.STATUS = 'received' THEN TRUE ELSE FALSE END AS IS_DELIVERED,
        CASE WHEN po.PRIORITY IN ('EMERGENCY','HIGH') THEN TRUE ELSE FALSE END AS IS_EXPEDITED
    FROM MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS po
    JOIN MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES pol ON po.PO_ID = pol.PO_ID
    LEFT JOIN MFGPULSE_DB.RAW_IT.PART_SUPPLIERS ps
        ON pol.PART_ID = ps.PART_ID AND po.SUPPLIER_ID = ps.SUPPLIER_ID
    WHERE po.STATUS NOT IN ('draft','cancelled')
)
SELECT
    s.SUPPLIER_ID,
    s.SUPPLIER_NAME,
    s.CONTACT_EMAIL,
    COUNT(DISTINCT pd.PO_ID) AS TOTAL_POS,
    COUNT(DISTINCT CASE WHEN pd.IS_DELIVERED THEN pd.PO_ID END) AS DELIVERED_POS,
    COUNT(DISTINCT CASE WHEN pd.IS_EXPEDITED THEN pd.PO_ID END) AS EXPEDITED_POS,
    -- On-time delivery rate (received POs where delivery <= expected)
    ROUND(DIV0NULL(
        COUNT(DISTINCT CASE WHEN pd.IS_DELIVERED THEN pd.PO_ID END),
        NULLIF(COUNT(DISTINCT pd.PO_ID), 0)
    ) * 100, 1) AS DELIVERY_RATE_PCT,
    -- Average lead time (days from PO creation to expected arrival)
    ROUND(AVG(DATEDIFF('day', pd.CREATED_DATE, pd.EXPECTED_ARRIVAL_DATE)), 1) AS AVG_LEAD_TIME_DAYS,
    -- Cost variance: actual line cost vs catalog cost
    ROUND(AVG(CASE WHEN pd.CATALOG_UNIT_COST > 0
        THEN (pd.LINE_UNIT_COST - pd.CATALOG_UNIT_COST) / pd.CATALOG_UNIT_COST * 100
        ELSE 0 END), 1) AS AVG_COST_VARIANCE_PCT,
    -- Total spend
    SUM(pd.LINE_UNIT_COST) AS TOTAL_SPEND,
    -- Unique parts supplied
    COUNT(DISTINCT pd.PART_ID) AS UNIQUE_PARTS_SUPPLIED,
    -- Rejection rate
    ROUND(DIV0NULL(
        COUNT(DISTINCT CASE WHEN po_rej.PO_ID IS NOT NULL THEN po_rej.PO_ID END),
        NULLIF(COUNT(DISTINCT pd.PO_ID), 0)
    ) * 100, 1) AS REJECTION_RATE_PCT,
    -- Overall score (simple weighted: delivery 40%, cost 30%, reliability 30%)
    ROUND(
        (DIV0NULL(COUNT(DISTINCT CASE WHEN pd.IS_DELIVERED THEN pd.PO_ID END),
            NULLIF(COUNT(DISTINCT pd.PO_ID), 0)) * 40) +
        (GREATEST(0, 30 - ABS(AVG(CASE WHEN pd.CATALOG_UNIT_COST > 0
            THEN (pd.LINE_UNIT_COST - pd.CATALOG_UNIT_COST) / pd.CATALOG_UNIT_COST * 100
            ELSE 0 END)))) +
        ((1 - DIV0NULL(COUNT(DISTINCT CASE WHEN po_rej.PO_ID IS NOT NULL THEN po_rej.PO_ID END),
            NULLIF(COUNT(DISTINCT pd.PO_ID), 0))) * 30)
    , 1) AS SUPPLIER_SCORE
FROM MFGPULSE_DB.RAW_IT.SUPPLIERS s
LEFT JOIN po_delivery pd ON s.SUPPLIER_ID = pd.SUPPLIER_ID
LEFT JOIN (
    SELECT PO_ID FROM MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS WHERE REJECTION_REASON IS NOT NULL
) po_rej ON pd.PO_ID = po_rej.PO_ID
WHERE s.ACTIVE = TRUE
GROUP BY s.SUPPLIER_ID, s.SUPPLIER_NAME, s.CONTACT_EMAIL;


-- PLANNED_PURCHASE_ORDERS view (safety-stock-aware aggregate qty)
CREATE OR REPLACE VIEW ANALYTICS.PLANNED_PURCHASE_ORDERS AS
WITH demand_by_part AS (
    SELECT
        pr.PART_ID, pr.PART_NAME, pr.SUPPLIER_ID, pr.SUPPLIER_NAME,
        pr.LEAD_TIME_DAYS, pr.UNIT_COST,
        COUNT(DISTINCT pr.ASSET_ID) AS ASSET_COUNT,
        LISTAGG(DISTINCT pr.ASSET_NAME, ', ') AS ASSET_LIST,
        SUM(pr.REQUIRED_QUANTITY) AS BOM_TOTAL,
        MIN(pr.RUL_HOURS) AS MIN_RUL_HOURS,
        MIN(pr.REQUIRED_BY_DATE) AS EARLIEST_REQUIRED_BY,
        MAX(CASE WHEN pr.STAGE_PRED = 'Critical' THEN 1 ELSE 0 END) AS HAS_CRITICAL_ASSET,
        MAX(CASE WHEN pr.PROCUREMENT_RISK = 'CRITICAL_SHORTAGE' THEN 1 ELSE 0 END) AS HAS_CRITICAL_SHORTAGE,
        MAX(CASE WHEN pr.PROCUREMENT_RISK = 'EXPEDITE' THEN 1 ELSE 0 END) AS HAS_EXPEDITE_RISK,
        pr.AVAILABLE_TO_PROMISE, pr.INCOMING_PO_QTY, pr.NET_POSITION
    FROM MFGPULSE_DB.ANALYTICS.PROCUREMENT_RECOMMENDATIONS pr
    WHERE pr.RECOMMENDED_PROCUREMENT_ACTION IN (
        'CREATE_PO', 'EXPEDITE_PO', 'ESCALATE',
        'RESERVE_AND_ORDER', 'RESERVE_AND_REORDER',
        'ESCALATE_CRITICAL_SHORTAGE', 'ESCALATE_NO_WO'
    )
      AND pr.OPEN_PO_ID IS NULL
    GROUP BY pr.PART_ID, pr.PART_NAME, pr.SUPPLIER_ID, pr.SUPPLIER_NAME,
             pr.LEAD_TIME_DAYS, pr.UNIT_COST, pr.AVAILABLE_TO_PROMISE,
             pr.INCOMING_PO_QTY, pr.NET_POSITION
),
with_ssp AS (
    SELECT d.*,
        GREATEST(d.BOM_TOTAL, COALESCE(ssp.REORDER_QTY, d.BOM_TOTAL)) AS TOTAL_QTY_NEEDED,
        'PPO-' || d.PART_ID || '-' || TO_CHAR(CURRENT_DATE(), 'YYYYMMDD') AS PPO_ID,
        CURRENT_DATE() AS STANDARD_ORDER_DATE,
        DATEADD('day', d.LEAD_TIME_DAYS, CURRENT_DATE()) AS STANDARD_ARRIVAL_DATE,
        DATEADD('day', GREATEST(CEIL(d.LEAD_TIME_DAYS / 2.0), 1), CURRENT_DATE()) AS EXPEDITE_ARRIVAL_DATE,
        DATEADD('day', -1 * d.LEAD_TIME_DAYS, d.EARLIEST_REQUIRED_BY) AS ORDER_BY_DEADLINE,
        DATEADD('day', -1 * GREATEST(CEIL(d.LEAD_TIME_DAYS / 2.0), 1), d.EARLIEST_REQUIRED_BY) AS EXPEDITE_DEADLINE,
        GREATEST(d.BOM_TOTAL, COALESCE(ssp.REORDER_QTY, d.BOM_TOTAL)) * d.UNIT_COST AS ESTIMATED_TOTAL_COST,
        ROUND(
            LEAST(1.0, GREATEST(0, (336.0 - COALESCE(d.MIN_RUL_HOURS, 336)) / 336.0)) * 0.40
            + LEAST(1.0, GREATEST(0, (0.0 - COALESCE(d.NET_POSITION, 0)) / GREATEST(d.BOM_TOTAL, 1))) * 0.30
            + LEAST(1.0, (d.ASSET_COUNT - 1.0) / 4.0) * 0.20
            + d.HAS_CRITICAL_ASSET * 0.10
        , 3) AS PRIORITY_SCORE
    FROM demand_by_part d
    LEFT JOIN MFGPULSE_DB.ANALYTICS.SAFETY_STOCK_POLICY ssp ON d.PART_ID = ssp.PART_ID
)
SELECT t.PPO_ID, t.PART_ID, t.PART_NAME, t.SUPPLIER_ID, t.SUPPLIER_NAME,
    t.ASSET_COUNT, t.ASSET_LIST, t.TOTAL_QTY_NEEDED, t.ESTIMATED_TOTAL_COST, t.UNIT_COST,
    t.LEAD_TIME_DAYS, t.MIN_RUL_HOURS, ROUND(t.MIN_RUL_HOURS / 24.0, 1) AS MIN_RUL_DAYS,
    t.EARLIEST_REQUIRED_BY, t.AVAILABLE_TO_PROMISE, t.INCOMING_PO_QTY, t.NET_POSITION,
    t.STANDARD_ORDER_DATE, t.STANDARD_ARRIVAL_DATE, t.EXPEDITE_ARRIVAL_DATE,
    t.ORDER_BY_DEADLINE, t.EXPEDITE_DEADLINE,
    CASE WHEN CURRENT_DATE() >= t.ORDER_BY_DEADLINE THEN TRUE ELSE FALSE END AS AUTO_CONVERT_DUE,
    DATEDIFF('day', CURRENT_DATE(), t.ORDER_BY_DEADLINE) AS DAYS_UNTIL_AUTO_CONVERT,
    CASE WHEN t.PRIORITY_SCORE >= 0.7 THEN 'EMERGENCY' WHEN t.PRIORITY_SCORE >= 0.4 THEN 'HIGH'
         WHEN t.PRIORITY_SCORE >= 0.2 THEN 'NORMAL' ELSE 'LOW' END AS PRIORITY_CLASSIFICATION,
    t.PRIORITY_SCORE,
    CASE WHEN t.HAS_CRITICAL_SHORTAGE = 1 THEN 'EXPEDITE_IMMEDIATELY'
         WHEN CURRENT_DATE() >= t.ORDER_BY_DEADLINE THEN 'AUTO_CONVERTING'
         WHEN DATEDIFF('day', CURRENT_DATE(), t.ORDER_BY_DEADLINE) <= 2 THEN 'ORDER_SOON'
         WHEN t.HAS_EXPEDITE_RISK = 1 THEN 'REVIEW_AND_EXPEDITE'
         ELSE 'PLANNED' END AS PPO_STATUS,
    t.HAS_CRITICAL_ASSET, t.HAS_CRITICAL_SHORTAGE, t.HAS_EXPEDITE_RISK
FROM with_ssp t;


-- DATA_FRESHNESS_SLA view
CREATE OR REPLACE VIEW ANALYTICS.DATA_FRESHNESS_SLA AS
SELECT 
    'SENSOR_READINGS' AS source_table,
    MAX(TIMESTAMP) AS last_data_timestamp,
    CURRENT_TIMESTAMP()::TIMESTAMP_NTZ AS checked_at,
    DATEDIFF('minute', MAX(TIMESTAMP), CURRENT_TIMESTAMP()) AS staleness_minutes,
    120 AS sla_threshold_minutes,
    CASE 
        WHEN DATEDIFF('minute', MAX(TIMESTAMP), CURRENT_TIMESTAMP()) < 10 THEN 'LIVE'
        WHEN DATEDIFF('minute', MAX(TIMESTAMP), CURRENT_TIMESTAMP()) < 60 THEN 'RECENT'
        WHEN DATEDIFF('minute', MAX(TIMESTAMP), CURRENT_TIMESTAMP()) < 120 THEN 'APPROACHING_SLA'
        ELSE 'SLA_BREACH'
    END AS freshness_status
FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS
UNION ALL
SELECT 'MAINTENANCE_LOGS', MAX(TIMESTAMP), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
    DATEDIFF('minute', MAX(TIMESTAMP), CURRENT_TIMESTAMP()), 1440,
    CASE WHEN DATEDIFF('minute', MAX(TIMESTAMP), CURRENT_TIMESTAMP()) < 1440 THEN 'LIVE' ELSE 'SLA_BREACH' END
FROM MFGPULSE_DB.RAW_IT.MAINTENANCE_LOGS
UNION ALL
SELECT 'WORK_ORDERS', MAX(CREATED_DATE), CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
    DATEDIFF('minute', MAX(CREATED_DATE), CURRENT_TIMESTAMP()), 1440,
    CASE WHEN DATEDIFF('minute', MAX(CREATED_DATE), CURRENT_TIMESTAMP()) < 1440 THEN 'LIVE' ELSE 'SLA_BREACH' END
FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS;

-- OEE_PERIOD_COMPARISON view (week-over-week)
CREATE OR REPLACE VIEW ANALYTICS.OEE_PERIOD_COMPARISON AS
WITH current_period AS (
    SELECT LINE_ID,
        ROUND(AVG(AVAILABILITY_PCT), 1) AS avail, ROUND(AVG(PERFORMANCE_PCT), 1) AS perf,
        ROUND(AVG(QUALITY_PCT), 1) AS qual, ROUND(AVG(OEE_PCT), 1) AS oee
    FROM MFGPULSE_DB.ANALYTICS.OEE_METRICS
    WHERE SHIFT_DATE >= DATEADD('day', -7, CURRENT_DATE()) GROUP BY LINE_ID
),
previous_period AS (
    SELECT LINE_ID,
        ROUND(AVG(AVAILABILITY_PCT), 1) AS avail, ROUND(AVG(PERFORMANCE_PCT), 1) AS perf,
        ROUND(AVG(QUALITY_PCT), 1) AS qual, ROUND(AVG(OEE_PCT), 1) AS oee
    FROM MFGPULSE_DB.ANALYTICS.OEE_METRICS
    WHERE SHIFT_DATE >= DATEADD('day', -14, CURRENT_DATE())
      AND SHIFT_DATE < DATEADD('day', -7, CURRENT_DATE()) GROUP BY LINE_ID
)
SELECT c.LINE_ID,
    c.oee AS current_oee, p.oee AS previous_oee,
    ROUND(c.oee - COALESCE(p.oee, c.oee), 1) AS oee_delta,
    c.avail AS current_avail, ROUND(c.avail - COALESCE(p.avail, c.avail), 1) AS avail_delta,
    c.perf AS current_perf, ROUND(c.perf - COALESCE(p.perf, c.perf), 1) AS perf_delta,
    c.qual AS current_qual, ROUND(c.qual - COALESCE(p.qual, c.qual), 1) AS qual_delta
FROM current_period c LEFT JOIN previous_period p ON c.LINE_ID = p.LINE_ID;

-- PROACTIVE_REORDER view
CREATE OR REPLACE VIEW ANALYTICS.PROACTIVE_REORDER AS
SELECT 
    pi.PART_ID, pi.PART_NAME, pi.QUANTITY_ON_HAND, pi.LEAD_TIME_DAYS, pi.UNIT_COST,
    COALESCE(ps.SUPPLIER_NAME, 'No Supplier') AS SUPPLIER_NAME,
    ARRAY_SIZE(pi.COMPATIBLE_ASSETS) AS COMPATIBLE_ASSET_COUNT,
    CASE WHEN pi.QUANTITY_ON_HAND = 0 THEN 'CRITICAL_STOCKOUT'
         WHEN pi.QUANTITY_ON_HAND <= 1 THEN 'LOW_STOCK_REORDER'
         ELSE 'MONITOR' END AS REORDER_STATUS,
    CASE WHEN pi.QUANTITY_ON_HAND = 0 THEN 'EMERGENCY_REORDER'
         WHEN pi.QUANTITY_ON_HAND <= 1 AND pi.LEAD_TIME_DAYS > 14 THEN 'EXPEDITE_REORDER'
         WHEN pi.QUANTITY_ON_HAND <= 1 THEN 'STANDARD_REORDER'
         ELSE 'NO_ACTION' END AS RECOMMENDED_ACTION
FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY pi
LEFT JOIN (
    SELECT ps2.PART_ID, s.SUPPLIER_NAME
    FROM MFGPULSE_DB.RAW_IT.PART_SUPPLIERS ps2
    JOIN MFGPULSE_DB.RAW_IT.SUPPLIERS s ON ps2.SUPPLIER_ID = s.SUPPLIER_ID
    WHERE ps2.PREFERRED_SUPPLIER = TRUE
    QUALIFY ROW_NUMBER() OVER (PARTITION BY ps2.PART_ID ORDER BY ps2.UNIT_COST) = 1
) ps ON pi.PART_ID = ps.PART_ID
WHERE pi.QUANTITY_ON_HAND <= 1;


-- ============================================================================
-- CHECKPOINT 10: FATIGUE SCORES + CORTEX SEARCH
-- ============================================================================

-- Wait 3-5 minutes for DTs to complete initial refresh before running this section.
-- You can check: SELECT NAME, SCHEDULING_STATE FROM TABLE(INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(NAME_PREFIX=>'MFGPULSE_DB')) ORDER BY DATA_TIMESTAMP DESC LIMIT 13;

-- Compute and store cumulative fatigue scores for all assets


-- Populate FATIGUE_SCORES using the COMPUTE_FATIGUE_SCORE UDF (defined in 10_udfs)
TRUNCATE TABLE IF EXISTS ML_MODELS.FATIGUE_SCORES;
INSERT INTO ML_MODELS.FATIGUE_SCORES (ASSET_ID, TIMESTAMP, FATIGUE_SCORE, FATIGUE_LEVEL)
SELECT
    rs.asset_id, rs.timestamp,
    ML_MODELS.COMPUTE_FATIGUE_SCORE(
        rs.vib_crest_factor_6h, rs.vib_coeff_var_6h, rs.vib_peak_to_peak_6h,
        rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
        si.acoustic_vib_ratio, pc.stress_index,
        COALESCE(si.vib_xy_correlation_daily, 0),
        COALESCE(si.acoustic_vib_ratio, 0)
    ) AS fatigue_score,
    CASE
        WHEN ML_MODELS.COMPUTE_FATIGUE_SCORE(
            rs.vib_crest_factor_6h, rs.vib_coeff_var_6h, rs.vib_peak_to_peak_6h,
            rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
            si.acoustic_vib_ratio, pc.stress_index,
            COALESCE(si.vib_xy_correlation_daily, 0),
            COALESCE(si.acoustic_vib_ratio, 0)
        ) > 0.8 THEN 'critical'
        WHEN ML_MODELS.COMPUTE_FATIGUE_SCORE(
            rs.vib_crest_factor_6h, rs.vib_coeff_var_6h, rs.vib_peak_to_peak_6h,
            rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
            si.acoustic_vib_ratio, pc.stress_index,
            COALESCE(si.vib_xy_correlation_daily, 0),
            COALESCE(si.acoustic_vib_ratio, 0)
        ) > 0.5 THEN 'high'
        WHEN ML_MODELS.COMPUTE_FATIGUE_SCORE(
            rs.vib_crest_factor_6h, rs.vib_coeff_var_6h, rs.vib_peak_to_peak_6h,
            rs.vib_rate_of_change_1h, rs.vib_acceleration_1h,
            si.acoustic_vib_ratio, pc.stress_index,
            COALESCE(si.vib_xy_correlation_daily, 0),
            COALESCE(si.acoustic_vib_ratio, 0)
        ) > 0.25 THEN 'accumul'
        ELSE 'healthy'
    END
FROM ML_FEATURES.ROLLING_STATS rs
LEFT JOIN ML_FEATURES.SENSOR_INTERACTIONS si ON rs.asset_id = si.asset_id AND rs.timestamp = si.timestamp
LEFT JOIN ML_FEATURES.PHYSICS_COMPOSITE pc ON rs.asset_id = pc.asset_id AND rs.timestamp = pc.timestamp
QUALIFY MOD(ROW_NUMBER() OVER (PARTITION BY rs.asset_id ORDER BY rs.timestamp), 25) = 0;
-- Samples every 25th reading per asset to reduce volume (~6.7K rows)


-- RAG over maintenance logs for root cause investigation


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
-- CHECKPOINT 11: NOTIFICATIONS + SIMULATION + AUTOMATION
-- ============================================================================

-- Notification system
-- Email + in-app notification infrastructure with admin-configurable settings


-- 1. NOTIFICATION_SETTINGS — admin-configurable per event type
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

-- Seed: 7 event types with sensible defaults
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

-- 2. APP_NOTIFICATIONS — in-app notification store
CREATE TABLE IF NOT EXISTS RAW_IT.APP_NOTIFICATIONS (
    NOTIF_ID VARCHAR(50) NOT NULL PRIMARY KEY,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    EVENT_TYPE VARCHAR(30) NOT NULL,
    PERSONA_TARGET VARCHAR(50),
    USERNAME_TARGET VARCHAR(100),
    TITLE VARCHAR(200),
    MESSAGE VARCHAR(1000),
    ENTITY_ID VARCHAR(50),
    PRIORITY VARCHAR(10) DEFAULT 'NORMAL',
    IS_READ BOOLEAN DEFAULT FALSE,
    DISMISSED BOOLEAN DEFAULT FALSE
);

-- 3. EMAIL NOTIFICATION INTEGRATION
CREATE NOTIFICATION INTEGRATION IF NOT EXISTS MFGPULSE_EMAIL
    TYPE = EMAIL
    ENABLED = TRUE;

-- 4. SEND_MFGPULSE_EMAIL — wrapper for SYSTEM$SEND_SNOWFLAKE_NOTIFICATION
CREATE OR REPLACE PROCEDURE RAW_IT.SEND_MFGPULSE_EMAIL(
    P_SUBJECT VARCHAR, P_BODY_HTML VARCHAR, P_RECIPIENTS VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    IF (:p_recipients IS NULL OR LENGTH(TRIM(:p_recipients)) = 0) THEN
        RETURN ''SKIPPED: No recipients'';
    END IF;
    BEGIN
        CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(
            SNOWFLAKE.NOTIFICATION.TEXT_HTML(:p_body_html),
            SNOWFLAKE.NOTIFICATION.EMAIL_INTEGRATION_CONFIG(
                ''MFGPULSE_EMAIL'',
                :p_subject,
                SPLIT(:p_recipients, '','')
            )
        );
        RETURN ''SENT'';
    EXCEPTION
        WHEN OTHER THEN RETURN ''EMAIL_ERROR: '' || SQLERRM;
    END;
END;
';

-- 5. LOG_APP_NOTIFICATION — central notification dispatcher
CREATE OR REPLACE PROCEDURE RAW_IT.LOG_APP_NOTIFICATION(
    P_EVENT_TYPE VARCHAR, P_TITLE VARCHAR, P_MESSAGE VARCHAR, P_ENTITY_ID VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    v_email_enabled BOOLEAN DEFAULT FALSE;
    v_in_app_enabled BOOLEAN DEFAULT TRUE;
    v_recipients VARCHAR DEFAULT '''';
    v_personas VARCHAR DEFAULT '''';
    v_priority VARCHAR DEFAULT ''NORMAL'';
    v_notif_count NUMBER DEFAULT 0;
    v_email_result VARCHAR DEFAULT ''SKIPPED'';
BEGIN
    -- Read settings for this event type
    BEGIN
        SELECT EMAIL_ENABLED, IN_APP_ENABLED, EMAIL_RECIPIENTS, NOTIFY_PERSONAS, PRIORITY
        INTO :v_email_enabled, :v_in_app_enabled, :v_recipients, :v_personas, :v_priority
        FROM MFGPULSE_DB.RAW_IT.NOTIFICATION_SETTINGS
        WHERE EVENT_TYPE = :p_event_type;
    EXCEPTION
        WHEN OTHER THEN
            v_in_app_enabled := TRUE;
            v_personas := ''PLANT_MANAGER,APP_ADMIN'';
    END;

    -- In-app notifications: one per target persona
    IF (:v_in_app_enabled) THEN
        INSERT INTO MFGPULSE_DB.RAW_IT.APP_NOTIFICATIONS
            (NOTIF_ID, EVENT_TYPE, PERSONA_TARGET, TITLE, MESSAGE, ENTITY_ID, PRIORITY)
        SELECT
            :p_event_type || ''-'' || value || ''-'' || TO_CHAR(CURRENT_TIMESTAMP(), ''YYYYMMDD_HH24MISS''),
            :p_event_type,
            TRIM(value),
            :p_title,
            :p_message,
            :p_entity_id,
            :v_priority
        FROM TABLE(SPLIT_TO_TABLE(:v_personas, '',''));

        SELECT COUNT(*) INTO :v_notif_count
        FROM MFGPULSE_DB.RAW_IT.APP_NOTIFICATIONS
        WHERE ENTITY_ID = :p_entity_id AND EVENT_TYPE = :p_event_type;
    END IF;

    -- Email notification
    IF (:v_email_enabled AND LENGTH(TRIM(:v_recipients)) > 0) THEN
        LET email_subject VARCHAR := ''MFGPulse '' || :v_priority || '': '' || :p_title;
        LET email_body VARCHAR := ''<div style="font-family:sans-serif;"><h3>'' || :p_title || ''</h3><p>'' || :p_message || ''</p><p style="color:#666;font-size:12px;">Entity: '' || COALESCE(:p_entity_id, ''N/A'') || '' | '' || CURRENT_TIMESTAMP()::VARCHAR || ''</p></div>'';
        CALL MFGPULSE_DB.RAW_IT.SEND_MFGPULSE_EMAIL(:email_subject, :email_body, :v_recipients);
        SELECT * INTO :v_email_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    END IF;

    RETURN OBJECT_CONSTRUCT(
        ''status'', ''OK'',
        ''event_type'', :p_event_type,
        ''in_app_sent'', :v_notif_count,
        ''email_result'', :v_email_result
    );
END;
';


-- Configurable simulation
-- Parameterized sensor feed + production simulation with admin control


-- 1. Simulation config / history table
CREATE TABLE IF NOT EXISTS RAW_IT.SIMULATION_CONFIG (
    CONFIG_ID INT AUTOINCREMENT PRIMARY KEY,
    ASSET_ID VARCHAR(20) NOT NULL,
    SCENARIO VARCHAR(30) NOT NULL,
    SEVERITY FLOAT DEFAULT 0.0,
    HOURS INT DEFAULT 12,
    STATUS VARCHAR(20) DEFAULT 'PENDING',
    ROWS_GENERATED INT DEFAULT 0,
    ESTIMATED_CREDITS FLOAT DEFAULT 0,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    CREATED_BY VARCHAR(100) DEFAULT CURRENT_USER(),
    COMPLETED_AT TIMESTAMP_NTZ
);

-- 2. Configurable sensor feed procedure
CREATE OR REPLACE PROCEDURE RAW_OT.SIMULATE_SENSOR_FEED_CONFIGURABLE(
    P_ASSET_ID VARCHAR,
    P_SCENARIO VARCHAR,
    P_SEVERITY FLOAT,
    P_HOURS INT
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
$$
DECLARE
    v_rows INT := 0;
    v_readings_per_asset INT;
    v_scenario VARCHAR;
BEGIN
    v_readings_per_asset := :P_HOURS * 4;
    v_scenario := UPPER(:P_SCENARIO);

    -- Generate sensor readings
    INSERT INTO MFGPULSE_DB.RAW_OT.SENSOR_READINGS
        (asset_id, timestamp, vibration_x, vibration_y, vibration_z, temperature, rpm, pressure, current_amps, acoustic_db)
    WITH time_slots AS (
        SELECT DATEADD('minute', seq4() * 15, DATEADD('hour', -:P_HOURS, CURRENT_TIMESTAMP())::TIMESTAMP_NTZ) AS ts
        FROM TABLE(GENERATOR(ROWCOUNT => :v_readings_per_asset))
    ),
    target_assets AS (
        SELECT asset_id, rated_rpm, rated_temp_max
        FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER
        WHERE (:P_ASSET_ID = 'ALL' OR asset_id = :P_ASSET_ID)
    ),
    combined AS (
        SELECT a.asset_id, t.ts, a.rated_rpm, a.rated_temp_max,
            :v_scenario AS scenario,
            :P_SEVERITY AS severity,
            ROW_NUMBER() OVER (PARTITION BY a.asset_id ORDER BY t.ts) / :v_readings_per_asset::FLOAT AS timeline_pct,
            UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS n1,
            UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS n2,
            UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS n3,
            UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS n4
        FROM time_slots t CROSS JOIN target_assets a
    )
    SELECT
        asset_id, ts,
        -- vibration_x
        CASE
            WHEN scenario = 'CLEAN' THEN 1.5 + n1*0.3
            WHEN scenario = 'BEARING_WEAR' THEN 2.0 + n1*0.5 + severity*8.0*(1+severity) + CASE WHEN severity > 0.8 THEN ABS(n2)*15.0 ELSE 0 END
            WHEN scenario = 'MISALIGNMENT' THEN 2.5 + n1*0.4 + severity*5.0 + severity*SIN(timeline_pct*200)*3.0
            WHEN scenario = 'IMBALANCE' THEN 1.8 + n1*0.3 + severity*2.0
            WHEN scenario = 'THERMAL_DEGRADATION' THEN 1.6 + n1*0.3 + severity*0.5
            ELSE 1.5 + n1*0.3
        END,
        -- vibration_y
        CASE
            WHEN scenario = 'CLEAN' THEN 1.3 + n2*0.3
            WHEN scenario = 'BEARING_WEAR' THEN 1.8 + n2*0.4 + severity*6.0*(1+severity*0.5)
            WHEN scenario = 'MISALIGNMENT' THEN 2.2 + n2*0.5 + severity*6.5 + severity*COS(timeline_pct*200)*2.5
            WHEN scenario = 'IMBALANCE' THEN 1.5 + n2*0.3 + severity*7.0*(1+severity)
            WHEN scenario = 'THERMAL_DEGRADATION' THEN 1.4 + n2*0.3 + severity*0.4
            ELSE 1.3 + n2*0.3
        END,
        -- vibration_z
        CASE
            WHEN scenario = 'CLEAN' THEN 1.1 + n3*0.25
            WHEN scenario = 'BEARING_WEAR' THEN 1.5 + n3*0.3 + severity*4.0
            WHEN scenario = 'MISALIGNMENT' THEN 2.0 + n3*0.5 + severity*5.5
            WHEN scenario = 'IMBALANCE' THEN 1.2 + n3*0.25 + severity*1.5
            WHEN scenario = 'THERMAL_DEGRADATION' THEN 1.2 + n3*0.25 + severity*0.3
            ELSE 1.1 + n3*0.25
        END,
        -- temperature
        CASE
            WHEN scenario = 'CLEAN' THEN rated_temp_max*0.50 + n1*2.0
            WHEN scenario = 'THERMAL_DEGRADATION' THEN rated_temp_max*0.55 + n1*2.0 + severity*rated_temp_max*0.40*(1+severity*0.3) + SIN(timeline_pct*48)*3.0
            WHEN scenario = 'BEARING_WEAR' THEN rated_temp_max*0.50 + n1*1.5 + severity*rated_temp_max*0.15
            WHEN scenario = 'MISALIGNMENT' THEN rated_temp_max*0.52 + n1*1.5 + severity*rated_temp_max*0.08
            ELSE rated_temp_max*0.50 + n1*2.0
        END,
        -- rpm
        CASE
            WHEN scenario = 'IMBALANCE' THEN rated_rpm*(1.0 + n1*0.005 - severity*0.08)
            ELSE rated_rpm*(1.0 + n1*0.003)
        END,
        -- pressure
        CASE
            WHEN scenario = 'BEARING_WEAR' THEN 6.5 + n2*0.2 + severity*1.5
            ELSE 6.0 + n2*0.2
        END,
        -- current_amps
        CASE
            WHEN scenario = 'CLEAN' THEN 10.5 + n3*0.4
            WHEN scenario = 'MISALIGNMENT' THEN 12.0 + n3*0.5 + severity*8.0*(1+severity)
            WHEN scenario = 'BEARING_WEAR' THEN 11.5 + n3*0.4 + severity*3.0
            ELSE 10.5 + n3*0.4
        END,
        -- acoustic_db
        CASE
            WHEN scenario = 'CLEAN' THEN 65 + n1*2.0
            WHEN scenario = 'BEARING_WEAR' THEN 72 + n1*2.0 + severity*18.0 + CASE WHEN severity > 0.7 THEN ABS(n2)*8.0 ELSE 0 END
            WHEN scenario = 'MISALIGNMENT' THEN 70 + n1*1.5 + severity*12.0
            WHEN scenario = 'IMBALANCE' THEN 68 + n1*1.5 + severity*6.0
            ELSE 65 + n1*2.0
        END
    FROM combined;

    -- Count inserted sensor rows
    v_rows := (SELECT :v_readings_per_asset * (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER WHERE (:P_ASSET_ID = 'ALL' OR asset_id = :P_ASSET_ID)));

    -- Generate matching production output records
    INSERT INTO MFGPULSE_DB.RAW_IT.PRODUCTION_OUTPUT
        (record_id, asset_id, shift_id, timestamp, units_produced, good_units, ideal_cycle_time_sec)
    SELECT
        'S' || RIGHT(asset_id, 3) || '-' || TO_CHAR(CURRENT_TIMESTAMP(), 'MMDDHH24MISS'),
        asset_id,
        'SHIFT_SIM',
        CURRENT_TIMESTAMP()::TIMESTAMP_NTZ,
        CASE
            WHEN :v_scenario = 'CLEAN' THEN 100
            WHEN :P_SEVERITY > 0.7 THEN GREATEST(20, 100 - FLOOR(:P_SEVERITY * 80))
            ELSE GREATEST(50, 100 - FLOOR(:P_SEVERITY * 50))
        END,
        CASE
            WHEN :v_scenario = 'CLEAN' THEN 98
            WHEN :P_SEVERITY > 0.7 THEN GREATEST(10, 98 - FLOOR(:P_SEVERITY * 88))
            ELSE GREATEST(40, 98 - FLOOR(:P_SEVERITY * 58))
        END,
        30.0
    FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER
    WHERE (:P_ASSET_ID = 'ALL' OR asset_id = :P_ASSET_ID);

    RETURN 'Generated ' || :v_rows || ' sensor readings + production records for ' || :P_ASSET_ID || ' [' || :v_scenario || ' severity=' || :P_SEVERITY || ']';
END;
$$;


-- SIMULATE_ALL_FEEDS_RANDOM (required by DAG root task)
CREATE OR REPLACE PROCEDURE RAW_OT.SIMULATE_ALL_FEEDS_RANDOM()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE
    v_result VARCHAR;
    v_total_rows NUMBER DEFAULT 0;
    c_asset_id VARCHAR; c_line_id VARCHAR; c_current_deg FLOAT;
    c_has_recent_wo BOOLEAN; c_scenario VARCHAR; c_severity FLOAT;
    asset_cursor CURSOR FOR
        SELECT
            am.ASSET_ID, am.LINE_ID,
            COALESCE(lp.DEGRADATION_SCORE, 0.1) AS CURRENT_DEG,
            CASE WHEN EXISTS (
                SELECT 1 FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS wo
                WHERE wo.ASSET_ID = am.ASSET_ID AND wo.STATUS = 'completed'
                  AND wo.COMPLETED_DATE >= DATEADD('hour', -13, CURRENT_TIMESTAMP())
            ) THEN TRUE ELSE FALSE END AS HAS_RECENT_WO
        FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER am
        LEFT JOIN MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS lp ON am.ASSET_ID = lp.ASSET_ID;
BEGIN
    OPEN asset_cursor;
    FOR rec IN asset_cursor DO
        c_asset_id := rec.ASSET_ID;
        c_line_id := rec.LINE_ID;
        c_current_deg := rec.CURRENT_DEG;
        c_has_recent_wo := rec.HAS_RECENT_WO;
        IF (:c_has_recent_wo) THEN
            c_severity := ROUND(GREATEST(0.10, :c_current_deg * 0.30) + UNIFORM(0.0::FLOAT, 0.05::FLOAT, RANDOM()), 2);
            c_scenario := 'CLEAN';
        ELSE
            LET delta FLOAT := ROUND(UNIFORM(0.01::FLOAT, 0.06::FLOAT, RANDOM()), 3);
            c_severity := LEAST(0.95, :c_current_deg + :delta);
            LET flicker FLOAT := UNIFORM(0::FLOAT, 1::FLOAT, RANDOM());
            IF (:c_severity > 0.30 AND :flicker < 0.10) THEN
                c_severity := GREATEST(0.15, :c_severity - UNIFORM(0.10::FLOAT, 0.20::FLOAT, RANDOM()));
            END IF;
            IF (:c_severity < 0.30) THEN
                LET r FLOAT := UNIFORM(0::FLOAT, 1::FLOAT, RANDOM());
                c_scenario := CASE WHEN :r < 0.80 THEN 'CLEAN' WHEN :r < 0.90 THEN 'BEARING_WEAR' ELSE 'IMBALANCE' END;
            ELSEIF (:c_severity < 0.60) THEN
                LET r FLOAT := UNIFORM(0::FLOAT, 1::FLOAT, RANDOM());
                c_scenario := CASE WHEN :r < 0.20 THEN 'CLEAN' WHEN :r < 0.50 THEN 'BEARING_WEAR' WHEN :r < 0.75 THEN 'THERMAL_DEGRADATION' ELSE 'IMBALANCE' END;
            ELSE
                LET r FLOAT := UNIFORM(0::FLOAT, 1::FLOAT, RANDOM());
                c_scenario := CASE WHEN :r < 0.30 THEN 'BEARING_WEAR' WHEN :r < 0.55 THEN 'THERMAL_DEGRADATION' WHEN :r < 0.80 THEN 'MISALIGNMENT' ELSE 'IMBALANCE' END;
            END IF;
        END IF;
        CALL MFGPULSE_DB.RAW_OT.SIMULATE_SENSOR_FEED_CONFIGURABLE(:c_asset_id, :c_scenario, :c_severity, 12);
        v_total_rows := :v_total_rows + 1;
    END FOR;
    CLOSE asset_cursor;
    BEGIN
        INSERT INTO MFGPULSE_DB.RAW_IT.SIMULATION_CONFIG
            (ASSET_ID, SCENARIO, SEVERITY, HOURS, STATUS, ROWS_GENERATED, ESTIMATED_CREDITS, CREATED_AT, CREATED_BY, COMPLETED_AT)
        VALUES ('ALL_RANDOM', 'PERSISTENT_DEGRADATION', 0, 12, 'COMPLETED', :v_total_rows * 49, 0.15, CURRENT_TIMESTAMP(), 'SIMULATE_ALL_FEEDS_RANDOM', CURRENT_TIMESTAMP());
    EXCEPTION WHEN OTHER THEN NULL;
    END;
    v_result := 'Completed: ' || :v_total_rows || ' assets simulated with persistent degradation + WO recovery';
    RETURN :v_result;
END;
$$;


-- Automation DAG (6 tasks, all SUSPENDED)
-- All automation runs as a single DAG: MFGPULSE_AUTOMATION_DAG (root, 720 min)
-- Uses dedicated MFGPULSE_AUTOMATION_WH (XS, 60s auto-suspend)
-- Monitored by MFGPULSE_AUTOMATION_GUARD (50 credits/month)


-- BULK_OPERATION_LOG: Audit trail for bulk WO/PO operations from Streamlit console
CREATE TABLE IF NOT EXISTS ANALYTICS.BULK_OPERATION_LOG (
    LOG_ID           NUMBER AUTOINCREMENT START 1 INCREMENT 1,
    OPERATION_TYPE   VARCHAR(50)   NOT NULL,
    ENTITY_TYPE      VARCHAR(10)   NOT NULL,
    ENTITY_IDS       ARRAY         NOT NULL,
    TOTAL_SELECTED   NUMBER        NOT NULL,
    TOTAL_SUCCEEDED  NUMBER        NOT NULL,
    TOTAL_BLOCKED    NUMBER        NOT NULL,
    BLOCKED_REASON   VARCHAR(500),
    PERFORMED_BY     VARCHAR(100)  NOT NULL,
    PERSONA          VARCHAR(50)   NOT NULL,
    DETAILS          VARIANT,
    CREATED_AT       TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    PRIMARY KEY (LOG_ID)
);

CREATE OR REPLACE PROCEDURE ANALYTICS.LOG_BULK_OPERATION(
    P_OPERATION_TYPE VARCHAR, P_ENTITY_TYPE VARCHAR, P_ENTITY_IDS ARRAY,
    P_TOTAL_SELECTED NUMBER, P_TOTAL_SUCCEEDED NUMBER, P_TOTAL_BLOCKED NUMBER,
    P_BLOCKED_REASON VARCHAR, P_PERFORMED_BY VARCHAR, P_PERSONA VARCHAR, P_DETAILS VARIANT
)
RETURNS VARIANT
LANGUAGE SQL
AS
BEGIN
    INSERT INTO MFGPULSE_DB.ANALYTICS.BULK_OPERATION_LOG
        (OPERATION_TYPE, ENTITY_TYPE, ENTITY_IDS, TOTAL_SELECTED,
         TOTAL_SUCCEEDED, TOTAL_BLOCKED, BLOCKED_REASON,
         PERFORMED_BY, PERSONA, DETAILS)
    VALUES
        (:P_OPERATION_TYPE, :P_ENTITY_TYPE, :P_ENTITY_IDS, :P_TOTAL_SELECTED,
         :P_TOTAL_SUCCEEDED, :P_TOTAL_BLOCKED, :P_BLOCKED_REASON,
         :P_PERFORMED_BY, :P_PERSONA, :P_DETAILS);
    RETURN OBJECT_CONSTRUCT(
        'status', 'logged', 'operation', :P_OPERATION_TYPE,
        'entity_type', :P_ENTITY_TYPE, 'succeeded', :P_TOTAL_SUCCEEDED,
        'blocked', :P_TOTAL_BLOCKED);
END;


-- INFRASTRUCTURE: Dedicated automation warehouse + resource monitor

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

-- PROCEDURES (called by DAG tasks)

-- 1. SIMULATE_ALL_FEEDS_RANDOM — sensor + production data with persistent degradation
--    (Full DDL in sql/ddl_objects.sql and docs/full_ddl_export.sql)

-- 2. REFRESH_FATIGUE_SCORES — batch-update fatigue for all assets
CREATE OR REPLACE PROCEDURE ML_MODELS.REFRESH_FATIGUE_SCORES()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE
    v_count NUMBER DEFAULT 0;
BEGIN
    INSERT INTO MFGPULSE_DB.ML_MODELS.FATIGUE_SCORES (ASSET_ID, TIMESTAMP, FATIGUE_SCORE, FATIGUE_LEVEL)
    SELECT
        rs.ASSET_ID, rs.TIMESTAMP,
        MFGPULSE_DB.ML_MODELS.COMPUTE_FATIGUE_SCORE(
            rs.VIB_CREST_FACTOR_6H, rs.VIB_COEFF_VAR_6H, rs.VIB_PEAK_TO_PEAK_6H,
            rs.VIB_RATE_OF_CHANGE_1H, rs.VIB_ACCELERATION_1H,
            COALESCE(pc.ENERGY_BALANCE_RATIO, 1.0), COALESCE(pc.STRESS_INDEX, 0.0),
            COALESCE(si.VIB_XY_CORRELATION_DAILY, 0.3), COALESCE(si.ACOUSTIC_VIB_RATIO, 25.0)
        ) AS FATIGUE_SCORE,
        CASE
            WHEN MFGPULSE_DB.ML_MODELS.COMPUTE_FATIGUE_SCORE(
                rs.VIB_CREST_FACTOR_6H, rs.VIB_COEFF_VAR_6H, rs.VIB_PEAK_TO_PEAK_6H,
                rs.VIB_RATE_OF_CHANGE_1H, rs.VIB_ACCELERATION_1H,
                COALESCE(pc.ENERGY_BALANCE_RATIO, 1.0), COALESCE(pc.STRESS_INDEX, 0.0),
                COALESCE(si.VIB_XY_CORRELATION_DAILY, 0.3), COALESCE(si.ACOUSTIC_VIB_RATIO, 25.0)
            ) > 0.7 THEN 'CRITICAL'
            WHEN MFGPULSE_DB.ML_MODELS.COMPUTE_FATIGUE_SCORE(
                rs.VIB_CREST_FACTOR_6H, rs.VIB_COEFF_VAR_6H, rs.VIB_PEAK_TO_PEAK_6H,
                rs.VIB_RATE_OF_CHANGE_1H, rs.VIB_ACCELERATION_1H,
                COALESCE(pc.ENERGY_BALANCE_RATIO, 1.0), COALESCE(pc.STRESS_INDEX, 0.0),
                COALESCE(si.VIB_XY_CORRELATION_DAILY, 0.3), COALESCE(si.ACOUSTIC_VIB_RATIO, 25.0)
            ) > 0.4 THEN 'HIGH'
            WHEN MFGPULSE_DB.ML_MODELS.COMPUTE_FATIGUE_SCORE(
                rs.VIB_CREST_FACTOR_6H, rs.VIB_COEFF_VAR_6H, rs.VIB_PEAK_TO_PEAK_6H,
                rs.VIB_RATE_OF_CHANGE_1H, rs.VIB_ACCELERATION_1H,
                COALESCE(pc.ENERGY_BALANCE_RATIO, 1.0), COALESCE(pc.STRESS_INDEX, 0.0),
                COALESCE(si.VIB_XY_CORRELATION_DAILY, 0.3), COALESCE(si.ACOUSTIC_VIB_RATIO, 25.0)
            ) > 0.2 THEN 'ACCUMULATING'
            ELSE 'HEALTHY'
        END AS FATIGUE_LEVEL
    FROM MFGPULSE_DB.ML_FEATURES.ROLLING_STATS rs
    LEFT JOIN MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE pc
        ON rs.ASSET_ID = pc.ASSET_ID AND rs.TIMESTAMP = pc.TIMESTAMP
    LEFT JOIN MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS si
        ON rs.ASSET_ID = si.ASSET_ID AND rs.TIMESTAMP = si.TIMESTAMP
    WHERE rs.TIMESTAMP > (SELECT COALESCE(MAX(TIMESTAMP), '2000-01-01') FROM MFGPULSE_DB.ML_MODELS.FATIGUE_SCORES)
    QUALIFY ROW_NUMBER() OVER (PARTITION BY rs.ASSET_ID ORDER BY rs.TIMESTAMP DESC) <= 48;
    SELECT COUNT(*) INTO :v_count FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    RETURN 'Fatigue scores refreshed: ' || :v_count || ' rows at ' || CURRENT_TIMESTAMP()::VARCHAR;
END;
$$;

-- 3. REFRESH_ALL_DTS — force immediate DT refresh in dependency order
CREATE OR REPLACE PROCEDURE ANALYTICS.REFRESH_ALL_DTS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
BEGIN
    -- Layer 0: Raw → Curated
    ALTER DYNAMIC TABLE MFGPULSE_DB.CURATED.SENSOR_WITH_CONTEXT REFRESH;
    ALTER DYNAMIC TABLE MFGPULSE_DB.CURATED.ASSET_HEALTH_CURRENT REFRESH;
    ALTER DYNAMIC TABLE MFGPULSE_DB.CURATED.FAILURE_HISTORY REFRESH;
    -- Layer 1: Raw → Features
    ALTER DYNAMIC TABLE MFGPULSE_DB.ML_FEATURES.ROLLING_STATS REFRESH;
    ALTER DYNAMIC TABLE MFGPULSE_DB.ML_FEATURES.PHYSICS_COMPOSITE REFRESH;
    ALTER DYNAMIC TABLE MFGPULSE_DB.ML_FEATURES.SENSOR_INTERACTIONS REFRESH;
    ALTER DYNAMIC TABLE MFGPULSE_DB.ML_FEATURES.LABELED_DATA REFRESH;
    -- Layer 2: Features → Advanced features
    ALTER DYNAMIC TABLE MFGPULSE_DB.ML_FEATURES.TEMPORAL_MEMORY REFRESH;
    ALTER DYNAMIC TABLE MFGPULSE_DB.ML_FEATURES.FLEET_COMPARISON REFRESH;
    ALTER DYNAMIC TABLE MFGPULSE_DB.ML_FEATURES.CROSS_DOMAIN REFRESH;
    -- Layer 3: Features + Fatigue → Predictions
    ALTER DYNAMIC TABLE MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS REFRESH;
    -- Layer 4: Predictions → Business
    ALTER DYNAMIC TABLE MFGPULSE_DB.ANALYTICS.ACTIVE_ALERTS REFRESH;
    ALTER DYNAMIC TABLE MFGPULSE_DB.ANALYTICS.OEE_METRICS REFRESH;
    RETURN 'All 13 DTs refreshed at ' || CURRENT_TIMESTAMP()::VARCHAR;
END;
$$;

-- NOTE: AUTO_GENERATE_WORK_ORDERS, AUTO_GENERATE_PURCHASE_ORDERS, and AUTO_CONVERT_PLANNED_POS
-- are defined earlier in this script (checkpoint 9 procurement section).

-- 4. CHECK_DATA_FRESHNESS — checks sensor/WO/log staleness, fires notification on SLA breach
CREATE OR REPLACE PROCEDURE ANALYTICS.CHECK_DATA_FRESHNESS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    LET stale_count NUMBER := 0;
    SELECT COUNT(*) INTO :stale_count
    FROM MFGPULSE_DB.ANALYTICS.DATA_FRESHNESS_SLA
    WHERE FRESHNESS_STATUS = 'SLA_BREACH';
    IF (:stale_count > 0) THEN
        BEGIN
            CALL MFGPULSE_DB.RAW_IT.LOG_APP_NOTIFICATION(
                'DATA_STALE',
                'Data freshness SLA breach detected',
                :stale_count || ' data source(s) have breached their freshness SLA. Check DATA_FRESHNESS_SLA view.',
                'FRESHNESS_CHECK');
        EXCEPTION WHEN OTHER THEN NULL;
        END;
    END IF;
    RETURN 'Freshness check complete. SLA breaches: ' || :stale_count;
END;

-- 5. SNAPSHOT_KPIS — daily KPI snapshot for trending
CREATE OR REPLACE PROCEDURE ANALYTICS.SNAPSHOT_KPIS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    MERGE INTO MFGPULSE_DB.ANALYTICS.KPI_SNAPSHOTS t
    USING (
        SELECT
            CURRENT_DATE() AS snapshot_date,
            es.PLANT_OEE, es.CRITICAL_ASSETS, es.WARNING_ASSETS, es.HEALTHY_ASSETS,
            es.TOTAL_COST_AVOIDED, es.DOWNTIME_HOURS_PREVENTED, es.MAINTENANCE_ROI_X,
            als.TOTAL_ALERTS, als.CRITICAL_COUNT AS CRITICAL_ALERTS,
            es.AVG_EARLY_DETECTION_DAYS, es.TOTAL_MAINTENANCE_SPEND
        FROM MFGPULSE_DB.ANALYTICS.EXECUTIVE_SUMMARY es
        CROSS JOIN MFGPULSE_DB.ANALYTICS.ALERT_SUMMARY als
    ) s ON t.SNAPSHOT_DATE = s.snapshot_date
    WHEN NOT MATCHED THEN INSERT (
        SNAPSHOT_DATE, PLANT_OEE, CRITICAL_ASSETS, WARNING_ASSETS, HEALTHY_ASSETS,
        TOTAL_COST_AVOIDED, DOWNTIME_HOURS_PREVENTED, MAINTENANCE_ROI_X,
        TOTAL_ALERTS, CRITICAL_ALERTS, AVG_EARLY_DETECTION_DAYS, TOTAL_MAINTENANCE_SPEND
    ) VALUES (
        s.snapshot_date, s.PLANT_OEE, s.CRITICAL_ASSETS, s.WARNING_ASSETS, s.HEALTHY_ASSETS,
        s.TOTAL_COST_AVOIDED, s.DOWNTIME_HOURS_PREVENTED, s.MAINTENANCE_ROI_X,
        s.TOTAL_ALERTS, s.CRITICAL_ALERTS, s.AVG_EARLY_DETECTION_DAYS, s.TOTAL_MAINTENANCE_SPEND
    );
    RETURN 'KPI snapshot captured for ' || CURRENT_DATE()::VARCHAR;
END;

-- 6. ARCHIVE_ALERTS — move resolved alerts to history
CREATE OR REPLACE PROCEDURE ANALYTICS.ARCHIVE_ALERTS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS
BEGIN
    LET archived NUMBER := 0;
    INSERT INTO MFGPULSE_DB.ANALYTICS.ALERT_HISTORY
        (ALERT_ID, ASSET_ID, ASSET_NAME, SEVERITY, ALERT_TYPE, MESSAGE,
         RUL_HOURS, FAILURE_MODE_PRED, FATIGUE_SCORE, CREATED_AT)
    SELECT ALERT_ID, ASSET_ID, ASSET_NAME, SEVERITY, ALERT_TYPE, MESSAGE,
           RUL_HOURS, FAILURE_MODE_PRED, FATIGUE_SCORE, CREATED_AT
    FROM MFGPULSE_DB.ANALYTICS.ACTIVE_ALERTS
    WHERE RESOLVED = TRUE OR ACKNOWLEDGED = TRUE;
    SELECT COUNT(*) INTO :archived FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    RETURN 'Archived ' || :archived || ' resolved alerts';
END;

-- NOTE: GENERATE_SHIFT_HANDOVER_SUMMARY is defined earlier in checkpoint 9.

-- TASK DAG: MFGPULSE_AUTOMATION_DAG
-- Chain: Simulate → Fatigue → DT Refresh → [WO Gen, Drift, Freshness, Archive, Snapshot] → PO Gen → PPO Convert

-- Root task: runs every 12 hours, generates sensor + production data
CREATE OR REPLACE TASK ANALYTICS.MFGPULSE_AUTOMATION_DAG
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    SCHEDULE = '720 MINUTE'
    SUSPEND_TASK_AFTER_NUM_FAILURES = 2
AS
    CALL MFGPULSE_DB.RAW_OT.SIMULATE_ALL_FEEDS_RANDOM();

-- Child 1: Refresh fatigue scores after new sensor data
CREATE OR REPLACE TASK ANALYTICS.DAG_REFRESH_FATIGUE
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.MFGPULSE_AUTOMATION_DAG
AS
    CALL MFGPULSE_DB.ML_MODELS.REFRESH_FATIGUE_SCORES();

-- Child 2: Force DT refresh cascade (with fresh fatigue data)
CREATE OR REPLACE TASK ANALYTICS.DAG_REFRESH_DTS
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.DAG_REFRESH_FATIGUE
AS
    CALL MFGPULSE_DB.ANALYTICS.REFRESH_ALL_DTS();

-- Child 3: Auto-generate work orders (using fresh predictions)
CREATE OR REPLACE TASK ANALYTICS.DAG_GENERATE_WOS
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.DAG_REFRESH_DTS
AS
    CALL MFGPULSE_DB.ANALYTICS.AUTO_GENERATE_WORK_ORDERS();

-- Child 4: Auto-generate purchase orders (for new WOs)
CREATE OR REPLACE TASK ANALYTICS.DAG_GENERATE_POS
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.DAG_GENERATE_WOS
AS
    CALL MFGPULSE_DB.ANALYTICS.AUTO_GENERATE_PURCHASE_ORDERS();

-- Child 5: Auto-convert planned POs to actual POs
CREATE OR REPLACE TASK ANALYTICS.DAG_CONVERT_PPOS
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.DAG_GENERATE_POS
AS
    CALL MFGPULSE_DB.ANALYTICS.AUTO_CONVERT_PLANNED_POS();

-- Child 6: Check data freshness SLA (after root task — parallel with fatigue)
CREATE OR REPLACE TASK ANALYTICS.DAG_CHECK_FRESHNESS
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.MFGPULSE_AUTOMATION_DAG
AS
    CALL MFGPULSE_DB.ANALYTICS.CHECK_DATA_FRESHNESS();

-- Child 7: Snapshot KPIs (after PPO convert — end of chain)
CREATE OR REPLACE TASK ANALYTICS.DAG_SNAPSHOT_KPIS
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.DAG_CONVERT_PPOS
AS
    CALL MFGPULSE_DB.ANALYTICS.SNAPSHOT_KPIS();

-- Child 8: Archive resolved alerts (after DT refresh)
CREATE OR REPLACE TASK ANALYTICS.DAG_ARCHIVE_ALERTS
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.DAG_REFRESH_DTS
AS
    CALL MFGPULSE_DB.ANALYTICS.ARCHIVE_ALERTS();

-- Child 9: Check native model drift (after DT refresh)
CREATE OR REPLACE TASK ANALYTICS.DAG_CHECK_DRIFT
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    AFTER ANALYTICS.DAG_REFRESH_DTS
AS
    CALL MFGPULSE_DB.ML_MODELS.COMPUTE_NATIVE_PREDICTIONS();

-- STARTUP: Resume children first (bottom-up), then root last
-- ALTER TASK ANALYTICS.DAG_SNAPSHOT_KPIS RESUME;
-- ALTER TASK ANALYTICS.DAG_ARCHIVE_ALERTS RESUME;
-- ALTER TASK ANALYTICS.DAG_CHECK_FRESHNESS RESUME;
-- ALTER TASK ANALYTICS.DAG_CHECK_DRIFT RESUME;
-- ALTER TASK ANALYTICS.DAG_CONVERT_PPOS RESUME;
-- ALTER TASK ANALYTICS.DAG_GENERATE_POS RESUME;
-- ALTER TASK ANALYTICS.DAG_GENERATE_WOS RESUME;
-- ALTER TASK ANALYTICS.DAG_REFRESH_DTS RESUME;
-- ALTER TASK ANALYTICS.DAG_REFRESH_FATIGUE RESUME;
-- ALTER TASK ANALYTICS.MFGPULSE_AUTOMATION_DAG RESUME;

-- LEGACY TASKS (deprecated — replaced by DAG above)
-- SIMULATE_ALL_FEEDS, SIMULATE_SENSOR_FEED, SIMULATE_PRODUCTION,
-- AUTO_PROCUREMENT_REVIEW, AUTO_CONVERT_PLANNED_POS_TASK,
-- AUTO_GENERATE_WORK_ORDERS_TASK
-- All suspended. Use the DAG for synchronized automation.


-- ============================================================================
-- CHECKPOINT 12: COMPREHENSIVE VALIDATION
-- Run each SELECT independently to verify deployment. All should return PASS.
-- ============================================================================

-- 12a. Schema existence (expect 7)
SELECT 'SCHEMA' AS OBJ_TYPE, SCHEMA_NAME, 'PASS' AS STATUS
FROM INFORMATION_SCHEMA.SCHEMATA
WHERE SCHEMA_NAME IN ('RAW_OT','RAW_IT','CURATED','ML_FEATURES','ML_MODELS','ANALYTICS','AGENT')
ORDER BY SCHEMA_NAME;

-- 12b. Row count validation (base tables + seed data)
SELECT TABLE_NAME, CNT,
    CASE
        WHEN TABLE_NAME = 'ASSET_MASTER' AND CNT = 10 THEN 'PASS'
        WHEN TABLE_NAME = 'SENSOR_METADATA' AND CNT = 23 THEN 'PASS'
        WHEN TABLE_NAME = 'PARTS_INVENTORY' AND CNT >= 15 THEN 'PASS'
        WHEN TABLE_NAME = 'USERS' AND CNT >= 8 THEN 'PASS'
        WHEN TABLE_NAME = 'SENSOR_READINGS' AND CNT > 170000 THEN 'PASS'
        WHEN TABLE_NAME = 'WORK_ORDERS' AND CNT >= 22 THEN 'PASS'
        WHEN TABLE_NAME = 'MAINTENANCE_LOGS' AND CNT >= 26 THEN 'PASS'
        WHEN TABLE_NAME = 'SUPPLIERS' AND CNT >= 5 THEN 'PASS'
        WHEN TABLE_NAME = 'PART_SUPPLIERS' AND CNT >= 16 THEN 'PASS'
        WHEN TABLE_NAME = 'MODEL_REGISTRY' AND CNT = 12 THEN 'PASS'
        ELSE 'CHECK'
    END AS STATUS
FROM (
    SELECT 'ASSET_MASTER' AS TABLE_NAME, COUNT(*) AS CNT FROM RAW_OT.ASSET_MASTER
    UNION ALL SELECT 'SENSOR_METADATA', COUNT(*) FROM RAW_OT.SENSOR_METADATA
    UNION ALL SELECT 'PARTS_INVENTORY', COUNT(*) FROM RAW_IT.PARTS_INVENTORY
    UNION ALL SELECT 'USERS', COUNT(*) FROM RAW_IT.USERS
    UNION ALL SELECT 'SENSOR_READINGS', COUNT(*) FROM RAW_OT.SENSOR_READINGS
    UNION ALL SELECT 'WORK_ORDERS', COUNT(*) FROM RAW_IT.WORK_ORDERS
    UNION ALL SELECT 'MAINTENANCE_LOGS', COUNT(*) FROM RAW_IT.MAINTENANCE_LOGS
    UNION ALL SELECT 'SUPPLIERS', COUNT(*) FROM RAW_IT.SUPPLIERS
    UNION ALL SELECT 'PART_SUPPLIERS', COUNT(*) FROM RAW_IT.PART_SUPPLIERS
    UNION ALL SELECT 'MODEL_REGISTRY', COUNT(*) FROM ML_MODELS.MODEL_REGISTRY
) t ORDER BY TABLE_NAME;

-- 12c. Date range validation
SELECT SOURCE_TABLE, MIN_DT, MAX_DT,
    CASE WHEN MIN_DT >= '2026-03-01' AND MAX_DT <= '2026-09-30' THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM (
    SELECT 'WORK_ORDERS' AS SOURCE_TABLE, MIN(created_date)::DATE AS MIN_DT, MAX(created_date)::DATE AS MAX_DT FROM RAW_IT.WORK_ORDERS
    UNION ALL SELECT 'MAINTENANCE_LOGS', MIN(timestamp)::DATE, MAX(timestamp)::DATE FROM RAW_IT.MAINTENANCE_LOGS
    UNION ALL SELECT 'PRODUCTION_OUTPUT', MIN(timestamp)::DATE, MAX(timestamp)::DATE FROM RAW_IT.PRODUCTION_OUTPUT
    UNION ALL SELECT 'SHIFT_SCHEDULE', MIN(shift_start)::DATE, MAX(shift_start)::DATE FROM RAW_IT.SHIFT_SCHEDULE
) t;

-- 12d. Referential integrity
SELECT 'SENSOR→ASSET' AS REL, COUNT(*) AS ORPHANS, CASE WHEN COUNT(*)=0 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM RAW_OT.SENSOR_READINGS sr LEFT JOIN RAW_OT.ASSET_MASTER am ON sr.asset_id=am.asset_id WHERE am.asset_id IS NULL
UNION ALL
SELECT 'WO→ASSET', COUNT(*), CASE WHEN COUNT(*)=0 THEN 'PASS' ELSE 'FAIL' END
FROM RAW_IT.WORK_ORDERS wo LEFT JOIN RAW_OT.ASSET_MASTER am ON wo.asset_id=am.asset_id WHERE am.asset_id IS NULL;

-- 12e. ML pipeline validation
SELECT 'LIVE_PREDICTIONS' AS OBJ, COUNT(*) AS CNT, CASE WHEN COUNT(*)=10 THEN 'PASS' ELSE 'FAIL' END AS STATUS FROM ML_MODELS.LIVE_PREDICTIONS
UNION ALL SELECT 'FATIGUE_SCORES', COUNT(*), CASE WHEN COUNT(*)>0 THEN 'PASS' ELSE 'FAIL' END FROM ML_MODELS.FATIGUE_SCORES
UNION ALL SELECT 'ANOMALY_SCORES', COUNT(*), CASE WHEN COUNT(*)>0 THEN 'PASS' ELSE 'FAIL' END FROM ML_MODELS.ANOMALY_SCORES
UNION ALL SELECT 'MODEL_REGISTRY', COUNT(*), CASE WHEN COUNT(*)=12 THEN 'PASS' ELSE 'FAIL' END FROM ML_MODELS.MODEL_REGISTRY;

-- 12f. Prediction value ranges
SELECT MIN(rul_hours) AS MIN_RUL, MAX(rul_hours) AS MAX_RUL,
    MIN(degradation_score) AS MIN_DEG, MAX(degradation_score) AS MAX_DEG,
    MIN(fatigue_score) AS MIN_FAT, MAX(fatigue_score) AS MAX_FAT,
    CASE WHEN MIN(rul_hours)>=0 AND MAX(degradation_score)<=1 AND MAX(fatigue_score)<=1 THEN 'PASS' ELSE 'FAIL' END AS STATUS
FROM ML_MODELS.LIVE_PREDICTIONS;

-- 12g. Analytics layer
SELECT 'ACTIVE_ALERTS' AS OBJ, COUNT(*) AS CNT, CASE WHEN COUNT(*)>0 THEN 'PASS' ELSE 'WARN' END AS STATUS FROM ANALYTICS.ACTIVE_ALERTS
UNION ALL SELECT 'OEE_METRICS', COUNT(*), CASE WHEN COUNT(*)>0 THEN 'PASS' ELSE 'FAIL' END FROM ANALYTICS.OEE_METRICS
UNION ALL SELECT 'PROCUREMENT_RECS', COUNT(*), CASE WHEN COUNT(*)>0 THEN 'PASS' ELSE 'WARN' END FROM ANALYTICS.PROCUREMENT_RECOMMENDATIONS
UNION ALL SELECT 'PARTS_ATP', COUNT(*), CASE WHEN COUNT(*)>0 THEN 'PASS' ELSE 'WARN' END FROM ANALYTICS.PARTS_AVAILABLE_TO_PROMISE;

-- 12h. UDF smoke test
SELECT 'COMPUTE_FATIGUE' AS UDF, ML_MODELS.COMPUTE_FATIGUE_SCORE(3.5,0.5,5.0,65.0,0.5,0.03,48.0,0.3,500.0) AS RESULT,
    CASE WHEN ML_MODELS.COMPUTE_FATIGUE_SCORE(3.5,0.5,5.0,65.0,0.5,0.03,48.0,0.3,500.0) BETWEEN 0 AND 1 THEN 'PASS' ELSE 'FAIL' END AS STATUS;

-- 12i. Persona check
SELECT PERSONA, COUNT(*) AS USER_COUNT, 'PASS' AS STATUS
FROM RAW_IT.USERS WHERE ACTIVE=TRUE GROUP BY PERSONA ORDER BY PERSONA;

-- 12j. Object inventory summary
SELECT
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME IN ('RAW_OT','RAW_IT','CURATED','ML_FEATURES','ML_MODELS','ANALYTICS','AGENT')) AS SCHEMAS,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='BASE TABLE' AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','PUBLIC')) AS BASE_TABLES,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_TYPE='DYNAMIC TABLE') AS DYNAMIC_TABLES,
    (SELECT COUNT(*) FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','PUBLIC')) AS VIEWS,
    (SELECT COUNT(*) FROM RAW_OT.SENSOR_READINGS) AS SENSOR_READINGS,
    (SELECT COUNT(*) FROM ML_MODELS.LIVE_PREDICTIONS) AS PREDICTIONS,
    (SELECT COUNT(*) FROM ANALYTICS.ACTIVE_ALERTS) AS ALERTS,
    (SELECT COUNT(*) FROM ML_MODELS.MODEL_REGISTRY) AS ML_MODELS_REG,
    (SELECT COUNT(*) FROM RAW_IT.USERS WHERE ACTIVE=TRUE) AS ACTIVE_USERS;

-- ============================================================================
-- CHECKPOINT 13: SEMANTIC VIEW + CORTEX AGENT
-- ============================================================================

-- SEMANTIC VIEW: Deploy Maintenance Semantic View (prerequisite for the Cortex Agent)
-- Source: cortex_project/MAINTENANCE_SEMANTIC_VIEW.sv.yaml (inlined below)
CREATE OR REPLACE SEMANTIC VIEW MFGPULSE_DB.AGENT.MAINTENANCE_SEMANTIC_VIEW
  FROM SPECIFICATION
  $$
name: MAINTENANCE_SEMANTIC_VIEW
description: "Predictive maintenance analytics for a manufacturing plant with 10 industrial assets across 3 production lines. Covers asset health predictions, failure mode classification, remaining useful life estimation, degradation staging, fatigue detection, OEE metrics, active alerts, work order management, and user/persona management for role-based dashboard access."
tables:
  - name: ACTIVE_ALERTS
    base_table:
      database: MFGPULSE_DB
      schema: ANALYTICS
      table: ACTIVE_ALERTS
    primary_key:
      columns:
        - ALERT_ID
    dimensions:
      - name: ACKNOWLEDGED
        expr: ACKNOWLEDGED
        data_type: BOOLEAN
        access_modifier: public_access
        description: Whether the alert has been acknowledged by an operator or supervisor.
      - name: ALERT_ID
        description: "Unique alert identifier combining asset, date, and severity code."
        expr: ALERT_ID
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: ALERT_TYPE
        description: "Type of alert (FAILURE_PREDICTION, HIDDEN_FATIGUE, LOW_RUL, DEGRADATION)."
        expr: ALERT_TYPE
        data_type: VARCHAR(18)
        access_modifier: public_access
      - name: ASSET_ID
        expr: ASSET_ID
        data_type: VARCHAR(20)
        access_modifier: public_access
        description: Unique identifier for each industrial asset (ASSET_001 through ASSET_010).
      - name: ASSET_NAME
        expr: ASSET_NAME
        data_type: VARCHAR(100)
        access_modifier: public_access
        description: Human-readable name of the asset (e.g., Compressor A1, Pump P1).
      - name: ASSET_TYPE
        expr: ASSET_TYPE
        data_type: VARCHAR(50)
        access_modifier: public_access
        description: Equipment classification (compressor, centrifugal_pump, electric_motor, axial_fan, gearbox, conveyor_drive, steam_turbine).
      - name: FAILURE_MODE_PRED
        expr: FAILURE_MODE_PRED
        data_type: VARCHAR(19)
        access_modifier: public_access
        description: Predicted failure mode (bearing_wear, thermal_degradation, imbalance, misalignment, normal) from ML classifier.
      - name: IS_CHRONIC
        description: True if asset has more than 2 work orders in 90 days.
        expr: IS_CHRONIC
        data_type: BOOLEAN
        access_modifier: public_access
      - name: LINE_ID
        expr: LINE_ID
        data_type: VARCHAR(20)
        access_modifier: public_access
        description: Production line assignment (LINE_01, LINE_02, LINE_03).
      - name: MESSAGE
        description: "Context-rich alert message with asset name, failure mode, RUL, fatigue, and chronic flag."
        expr: MESSAGE
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: RESOLVED
        expr: RESOLVED
        data_type: BOOLEAN
        access_modifier: public_access
        description: Whether the alert condition has been resolved.
      - name: SEVERITY
        description: "Alert severity level (CRITICAL, WARNING, WATCH, INFO)."
        expr: SEVERITY
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: STAGE_PRED
        expr: STAGE_PRED
        data_type: VARCHAR(8)
        access_modifier: public_access
        description: Predicted degradation stage (Healthy, Warning, Critical) from the ML stager model.
      - name: ESCALATION_AT
        description: Timestamp when the alert was escalated to a higher severity or priority level.
        expr: ESCALATION_AT
        data_type: TIMESTAMP_NTZ(9)
    facts:
      - name: COMPOSITE_HEALTH_SCORE
        expr: COMPOSITE_HEALTH_SCORE
        data_type: FLOAT
        access_modifier: public_access
      - name: DEGRADATION_SCORE
        expr: DEGRADATION_SCORE
        data_type: FLOAT
        access_modifier: public_access
      - name: FATIGUE_SCORE
        expr: FATIGUE_SCORE
        data_type: FLOAT
        access_modifier: public_access
      - name: RUL_HOURS
        expr: RUL_HOURS
        data_type: FLOAT
        access_modifier: public_access
      - name: WO_COUNT_90D
        description: Number of work orders in the last 90 days for the asset. Used for chronic issue detection (IS_CHRONIC flag).
        expr: WO_COUNT_90D
        data_type: NUMBER(18,0)
      - name: FAILURE_MODE_CONFIDENCE
        description: Confidence score for the predicted failure mode (0.0 to 1.0).
        expr: FAILURE_MODE_CONFIDENCE
        data_type: NUMBER(3,2)
      - name: RUL_LOWER_CI
        description: Lower bound of remaining useful life confidence interval (P10 pessimistic estimate).
        expr: RUL_LOWER_CI
        data_type: FLOAT
      - name: RUL_UPPER_CI
        description: Upper bound of remaining useful life confidence interval (P90 optimistic estimate).
        expr: RUL_UPPER_CI
        data_type: FLOAT
      - name: TRANSITION_PROBABILITY
        description: Probability that the asset will transition to a worse degradation stage.
        expr: TRANSITION_PROBABILITY
        data_type: FLOAT
    time_dimensions:
      - name: CREATED_AT
        expr: CREATED_AT
        data_type: TIMESTAMP_NTZ(9)
        access_modifier: public_access
        description: Timestamp when the alert was generated.
  - name: ASSET_MASTER
    base_table:
      database: MFGPULSE_DB
      schema: RAW_OT
      table: ASSET_MASTER
    primary_key:
      columns:
        - ASSET_ID
    dimensions:
      - name: ASSET_ID
        expr: ASSET_ID
        data_type: VARCHAR(20)
        access_modifier: public_access
        description: Unique identifier for each industrial asset (ASSET_001 through ASSET_010).
      - name: ASSET_NAME
        expr: ASSET_NAME
        data_type: VARCHAR(100)
        access_modifier: public_access
        description: Human-readable name of the asset (e.g., Compressor A1, Pump P1).
      - name: ASSET_TYPE
        expr: ASSET_TYPE
        data_type: VARCHAR(50)
        access_modifier: public_access
        description: Equipment classification (compressor, centrifugal_pump, electric_motor, axial_fan, gearbox, conveyor_drive, steam_turbine).
      - name: LINE_ID
        expr: LINE_ID
        data_type: VARCHAR(20)
        access_modifier: public_access
        description: Production line assignment (LINE_01, LINE_02, LINE_03).
      - name: MANUFACTURER
        expr: MANUFACTURER
        data_type: VARCHAR(100)
        access_modifier: public_access
        description: OEM or equipment manufacturer name.
      - name: MODEL_NUMBER
        expr: MODEL_NUMBER
        data_type: VARCHAR(50)
        access_modifier: public_access
        description: Manufacturer model or part number for the asset.
    facts:
      - name: RATED_RPM
        expr: RATED_RPM
        data_type: FLOAT
        access_modifier: public_access
        description: Manufacturer-rated maximum RPM for the asset.
      - name: RATED_TEMP_MAX
        expr: RATED_TEMP_MAX
        data_type: FLOAT
        access_modifier: public_access
        description: Manufacturer-rated maximum operating temperature in degrees Celsius.
    time_dimensions:
      - name: INSTALL_DATE
        expr: INSTALL_DATE
        data_type: DATE
        access_modifier: public_access
        description: Date the asset was installed on the production line. Used for age-based reliability analysis.
  - name: LIVE_PREDICTIONS
    base_table:
      database: MFGPULSE_DB
      schema: ML_MODELS
      table: LIVE_PREDICTIONS
    primary_key:
      columns:
        - ASSET_ID
    dimensions:
      - name: ASSET_ID
        description: Unique identifier for each industrial asset (ASSET_001 through ASSET_010).
        expr: ASSET_ID
        data_type: VARCHAR(20)
        access_modifier: public_access
      - name: ASSET_NAME
        description: "Human-readable name of the asset (e.g. Compressor A1, Pump P1)."
        expr: ASSET_NAME
        data_type: VARCHAR(100)
        access_modifier: public_access
      - name: ASSET_TYPE
        description: "Equipment classification (compressor, centrifugal_pump, electric_motor, axial_fan, gearbox, conveyor_drive, steam_turbine)."
        expr: ASSET_TYPE
        data_type: VARCHAR(50)
        access_modifier: public_access
      - name: FAILURE_MODE_PRED
        description: "Predicted failure mode from M1 classifier (bearing_wear, thermal_degradation, imbalance, misalignment, normal)."
        expr: FAILURE_MODE_PRED
        data_type: VARCHAR(19)
        access_modifier: public_access
      - name: FATIGUE_LEVEL
        description: "Hidden fatigue classification from M4 detector (healthy, accumul, high, critical)."
        expr: FATIGUE_LEVEL
        data_type: VARCHAR(20)
        access_modifier: public_access
      - name: LINE_ID
        description: "Production line assignment (LINE_01, LINE_02, LINE_03)."
        expr: LINE_ID
        data_type: VARCHAR(20)
        access_modifier: public_access
      - name: STAGE_PRED
        description: "Predicted degradation stage from M3 stager (Healthy, Warning, Critical)."
        expr: STAGE_PRED
        data_type: VARCHAR(8)
        access_modifier: public_access
    facts:
      - name: COMPOSITE_HEALTH_SCORE
        description: Overall health score (0 worst to 100 best) from physics-composite analysis.
        expr: COMPOSITE_HEALTH_SCORE
        data_type: FLOAT
        access_modifier: public_access
      - name: DEGRADATION_SCORE
        description: Multi-signal degradation score (0.0 healthy to 1.0 critical).
        expr: DEGRADATION_SCORE
        data_type: FLOAT
        access_modifier: public_access
      - name: FAILURE_MODE_CONFIDENCE
        description: Confidence score for the predicted failure mode (0.0 to 1.0).
        expr: FAILURE_MODE_CONFIDENCE
        data_type: "NUMBER(3,2)"
        access_modifier: public_access
      - name: FATIGUE_SCORE
        description: Hidden fatigue score from M4 (0.0 healthy to 1.0 critical fatigue).
        expr: FATIGUE_SCORE
        data_type: FLOAT
        access_modifier: public_access
      - name: RUL_HOURS
        description: Remaining useful life in hours until predicted failure (M2 estimator output).
        expr: RUL_HOURS
        data_type: FLOAT
        access_modifier: public_access
      - name: RUL_LOWER_CI
        description: Lower bound of RUL confidence interval (P10 pessimistic estimate).
        expr: RUL_LOWER_CI
        data_type: FLOAT
        access_modifier: public_access
      - name: RUL_UPPER_CI
        description: Upper bound of RUL confidence interval (P90 optimistic estimate).
        expr: RUL_UPPER_CI
        data_type: FLOAT
        access_modifier: public_access
      - name: STRESS_INDEX
        description: "Multi-factor operating stress metric combining temperature, vibration, and current."
        expr: STRESS_INDEX
        data_type: FLOAT
        access_modifier: public_access
      - name: TRANSITION_PROBABILITY
        description: Probability that the asset will transition to a worse degradation stage.
        expr: TRANSITION_PROBABILITY
        data_type: FLOAT
        access_modifier: public_access
    time_dimensions:
      - name: PREDICTION_TIME
        description: Timestamp when the prediction was generated.
        expr: PREDICTION_TIME
        data_type: TIMESTAMP_NTZ(9)
        access_modifier: public_access
  - name: OEE_METRICS
    base_table:
      database: MFGPULSE_DB
      schema: ANALYTICS
      table: OEE_METRICS
    dimensions:
      - name: ASSET_ID
        expr: ASSET_ID
        data_type: VARCHAR(20)
        access_modifier: public_access
        description: Unique identifier for each industrial asset (ASSET_001 through ASSET_010).
      - name: ASSET_NAME
        expr: ASSET_NAME
        data_type: VARCHAR(100)
        access_modifier: public_access
        description: Human-readable name of the asset.
      - name: AVAILABILITY_PCT
        description: Availability percentage accounting for degradation-related downtime.
        expr: AVAILABILITY_PCT
        data_type: NUMBER(5,0)
        access_modifier: public_access
      - name: FAILURE_MODE_PRED
        expr: FAILURE_MODE_PRED
        data_type: VARCHAR(19)
        access_modifier: public_access
        description: Predicted failure mode at the time of the shift.
      - name: LINE_ID
        expr: LINE_ID
        data_type: VARCHAR(20)
        access_modifier: public_access
        description: Production line assignment (LINE_01, LINE_02, LINE_03).
      - name: LOSS_ATTRIBUTED_TO
        description: Asset and failure mode causing OEE loss (null for healthy assets).
        expr: LOSS_ATTRIBUTED_TO
        data_type: VARCHAR(16777216)
        access_modifier: public_access
      - name: SHIFT_ID
        expr: SHIFT_ID
        data_type: VARCHAR(20)
        access_modifier: public_access
        description: Shift identifier within the production day (e.g., SHIFT_A, SHIFT_B, SHIFT_C).
      - name: STAGE_PRED
        expr: STAGE_PRED
        data_type: VARCHAR(8)
        access_modifier: public_access
        description: Predicted degradation stage at the time of the shift (Healthy, Warning, Critical).
    facts:
      - name: OEE_PCT
        description: Overall Equipment Effectiveness = Availability x Performance x Quality / 10000.
        expr: OEE_PCT
        data_type: "NUMBER(38,1)"
        access_modifier: public_access
      - name: PERFORMANCE_LOSS_PCT
        expr: PERFORMANCE_LOSS_PCT
        data_type: "NUMBER(38,1)"
        access_modifier: public_access
        description: Percentage of performance lost due to reduced speed or minor stoppages.
      - name: PERFORMANCE_PCT
        expr: PERFORMANCE_PCT
        data_type: "NUMBER(38,1)"
        access_modifier: public_access
      - name: QUALITY_LOSS_PCT
        expr: QUALITY_LOSS_PCT
        data_type: "NUMBER(38,1)"
        access_modifier: public_access
        description: Percentage of quality lost due to defects or rework.
      - name: QUALITY_PCT
        expr: QUALITY_PCT
        data_type: "NUMBER(38,1)"
        access_modifier: public_access
      - name: RUL_HOURS
        expr: RUL_HOURS
        data_type: FLOAT
        access_modifier: public_access
        description: Remaining useful life in hours at the time of the shift.
      - name: AVAILABILITY_LOSS_PCT
        description: Percentage of availability lost due to unplanned downtime or degradation.
        expr: AVAILABILITY_LOSS_PCT
        data_type: NUMBER(3,0)
      - name: GOOD_UNITS
        description: Count of units passing quality checks during the shift.
        expr: GOOD_UNITS
        data_type: NUMBER(38,0)
      - name: UNITS_PRODUCED
        description: Total units produced during the shift, including defective units.
        expr: UNITS_PRODUCED
        data_type: NUMBER(38,0)
    time_dimensions:
      - name: SHIFT_DATE
        expr: SHIFT_DATE
        data_type: TIMESTAMP_NTZ(9)
        access_modifier: public_access
        description: Calendar date of the production shift. Primary time reference for OEE trending.
      - name: SHIFT_TIME
        expr: SHIFT_TIME
        data_type: TIMESTAMP_NTZ(9)
        access_modifier: public_access
        description: Exact timestamp when the shift started.
    primary_key:
      columns:
        - ASSET_ID
        - SHIFT_DATE
        - SHIFT_ID
  - name: USERS
    base_table:
      database: MFGPULSE_DB
      schema: RAW_IT
      table: USERS
    primary_key:
      columns:
        - USER_ID
    dimensions:
      - name: ACTIVE
        expr: ACTIVE
        data_type: BOOLEAN
        access_modifier: public_access
      - name: EMAIL
        expr: EMAIL
        data_type: VARCHAR(200)
        access_modifier: public_access
      - name: LINE_ID
        description: Assigned production line (null for plant-wide roles like Plant Manager).
        expr: LINE_ID
        data_type: VARCHAR(20)
        access_modifier: public_access
      - name: PERSONA
        description: "User persona for role-based access (TECHNICIAN, RELIABILITY_ENGINEER, SHIFT_SUPERVISOR, PLANT_MANAGER, PROCUREMENT_ADMIN)."
        expr: PERSONA
        data_type: VARCHAR(50)
        access_modifier: public_access
      - name: ROLE
        description: Snowflake role mapping for future RBAC integration.
        expr: ROLE
        data_type: VARCHAR(50)
        access_modifier: public_access
      - name: USERNAME
        description: "Display name of the user (e.g. Mike Torres, Sarah Chen)."
        expr: USERNAME
        data_type: VARCHAR(100)
        access_modifier: public_access
      - name: USER_ID
        description: Unique user identifier (USR-001 through USR-008).
        expr: USER_ID
        data_type: VARCHAR(20)
        access_modifier: public_access
    time_dimensions:
      - name: CREATED_AT
        expr: CREATED_AT
        data_type: TIMESTAMP_NTZ(9)
        access_modifier: public_access
  - name: WORK_ORDERS
    base_table:
      database: MFGPULSE_DB
      schema: RAW_IT
      table: WORK_ORDERS
    primary_key:
      columns:
        - WO_ID
    dimensions:
      - name: ASSET_ID
        expr: ASSET_ID
        data_type: VARCHAR(20)
        access_modifier: public_access
      - name: ASSIGNED_TO
        description: Technician assigned to the work order.
        expr: ASSIGNED_TO
        data_type: VARCHAR(100)
        access_modifier: public_access
      - name: PRIORITY
        description: "Priority level (CRITICAL, HIGH, MEDIUM, LOW)."
        expr: PRIORITY
        data_type: VARCHAR(10)
        access_modifier: public_access
      - name: STATUS
        description: "Current status (open, in_progress, completed)."
        expr: STATUS
        data_type: VARCHAR(20)
        access_modifier: public_access
      - name: WO_ID
        expr: WO_ID
        data_type: VARCHAR(50)
        access_modifier: public_access
      - name: WO_TYPE
        description: "Work order type (emergency, corrective, preventive)."
        expr: WO_TYPE
        data_type: VARCHAR(20)
        access_modifier: public_access
    facts:
      - name: LABOR_HOURS
        expr: LABOR_HOURS
        data_type: FLOAT
        access_modifier: public_access
      - name: PARTS_COST
        expr: PARTS_COST
        data_type: FLOAT
        access_modifier: public_access
      - name: TOTAL_COST
        expr: TOTAL_COST
        data_type: FLOAT
        access_modifier: public_access
    time_dimensions:
      - name: COMPLETED_DATE
        expr: COMPLETED_DATE
        data_type: TIMESTAMP_NTZ(9)
        access_modifier: public_access
      - name: CREATED_DATE
        expr: CREATED_DATE
        data_type: TIMESTAMP_NTZ(9)
        access_modifier: public_access
verified_queries:
  - name: HEALTH_STATUS_ALL
    sql: "SELECT ASSET_NAME, STAGE_PRED, RUL_HOURS, FATIGUE_SCORE, FAILURE_MODE_PRED, COMPOSITE_HEALTH_SCORE FROM live_predictions ORDER BY DEGRADATION_SCORE DESC"
    question: What is the current health status of all assets?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: CRITICAL_ASSETS
    sql: "SELECT ASSET_NAME, FAILURE_MODE_PRED, RUL_HOURS, STAGE_PRED, FATIGUE_SCORE FROM live_predictions WHERE STAGE_PRED = 'Critical' ORDER BY RUL_HOURS ASC"
    question: Which assets need immediate attention?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: ALERTS_BY_SEVERITY
    sql: "SELECT SEVERITY, COUNT(*) AS ALERT_COUNT FROM active_alerts GROUP BY SEVERITY ORDER BY CASE SEVERITY WHEN 'CRITICAL' THEN 1 WHEN 'WARNING' THEN 2 WHEN 'WATCH' THEN 3 ELSE 4 END"
    question: How many active alerts are there by severity level?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: CRITICAL_WARNING_ALERTS
    sql: "SELECT ASSET_NAME, SEVERITY, ALERT_TYPE, MESSAGE FROM active_alerts WHERE SEVERITY IN ('CRITICAL', 'WARNING') ORDER BY SEVERITY"
    question: What are all the critical and warning alerts currently active?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: COMPRESSOR_RUL
    sql: "SELECT ASSET_NAME, RUL_HOURS, RUL_LOWER_CI, RUL_UPPER_CI, STAGE_PRED FROM live_predictions WHERE ASSET_TYPE = 'compressor' ORDER BY RUL_HOURS"
    question: What is the remaining useful life for all compressors?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: NEXT_FAILURE
    sql: "SELECT ASSET_NAME, RUL_HOURS, FAILURE_MODE_PRED, STAGE_PRED FROM live_predictions ORDER BY RUL_HOURS ASC LIMIT 1"
    question: Which asset will fail next?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: OEE_LINE_01
    sql: "SELECT LINE_ID, ROUND(AVG(OEE_PCT), 1) AS AVG_OEE, ROUND(AVG(AVAILABILITY_PCT), 1) AS AVG_AVAILABILITY, ROUND(AVG(PERFORMANCE_PCT), 1) AS AVG_PERFORMANCE, ROUND(AVG(QUALITY_PCT), 1) AS AVG_QUALITY FROM oee_metrics WHERE LINE_ID = 'LINE_01' GROUP BY LINE_ID"
    question: What are the average OEE metrics for production line 1?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: OEE_LOSS_CAUSES
    sql: "SELECT LOSS_ATTRIBUTED_TO, ROUND(AVG(AVAILABILITY_LOSS_PCT), 1) AS AVAILABILITY_LOSS, ROUND(AVG(PERFORMANCE_LOSS_PCT), 1) AS PERFORMANCE_LOSS FROM oee_metrics WHERE NOT LOSS_ATTRIBUTED_TO IS NULL GROUP BY LOSS_ATTRIBUTED_TO ORDER BY AVAILABILITY_LOSS DESC"
    question: What are the main causes of OEE losses?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: OEE_BY_LINE
    sql: "SELECT LINE_ID, ROUND(AVG(OEE_PCT), 1) AS AVG_OEE, COUNT(DISTINCT ASSET_ID) AS ASSETS FROM oee_metrics GROUP BY LINE_ID ORDER BY AVG_OEE ASC"
    question: How does OEE compare across all production lines?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: LOWEST_OEE_LINE
    sql: SELECT LINE_ID, ROUND(AVG(OEE_PCT), 1) AS AVG_OEE FROM oee_metrics GROUP BY LINE_ID ORDER BY AVG_OEE ASC LIMIT 1
    question: Which production line has the lowest OEE?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: RECENT_WORK_ORDERS
    sql: SELECT COUNT(*) AS TOTAL_WOS FROM work_orders WHERE CREATED_DATE >= DATEADD(DAY, -30, CURRENT_TIMESTAMP())
    question: How many work orders were created in the last 30 days?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: HEALTHIEST_ASSETS
    sql: SELECT ASSET_NAME, COMPOSITE_HEALTH_SCORE, STAGE_PRED FROM live_predictions ORDER BY COMPOSITE_HEALTH_SCORE DESC LIMIT 3
    question: Which are the top 3 healthiest assets?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: MOST_DEGRADED
    sql: SELECT ASSET_NAME, DEGRADATION_SCORE, RUL_HOURS FROM live_predictions ORDER BY DEGRADATION_SCORE DESC LIMIT 3
    question: Which assets are most degraded?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: MOST_CRITICAL_ASSET
    sql: SELECT ASSET_NAME, ASSET_ID, COMPOSITE_HEALTH_SCORE, RUL_HOURS, STRESS_INDEX, STAGE_PRED, FAILURE_MODE_PRED FROM live_predictions ORDER BY COMPOSITE_HEALTH_SCORE ASC, RUL_HOURS ASC, STRESS_INDEX DESC LIMIT 1
    question: Which asset is most critical?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: LEAST_CRITICAL_ASSET
    sql: SELECT ASSET_NAME, ASSET_ID, COMPOSITE_HEALTH_SCORE, RUL_HOURS, STRESS_INDEX, STAGE_PRED, FAILURE_MODE_PRED FROM live_predictions ORDER BY COMPOSITE_HEALTH_SCORE DESC, RUL_HOURS DESC, STRESS_INDEX ASC LIMIT 1
    question: Which asset is least critical?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: MOST_AND_LEAST_CRITICAL
    sql: SELECT * FROM (SELECT ASSET_NAME, ASSET_ID, COMPOSITE_HEALTH_SCORE, RUL_HOURS, STAGE_PRED, 'MOST_CRITICAL' AS RANKING FROM live_predictions ORDER BY COMPOSITE_HEALTH_SCORE ASC, RUL_HOURS ASC, STRESS_INDEX DESC LIMIT 1) UNION ALL SELECT * FROM (SELECT ASSET_NAME, ASSET_ID, COMPOSITE_HEALTH_SCORE, RUL_HOURS, STAGE_PRED, 'LEAST_CRITICAL' AS RANKING FROM live_predictions ORDER BY COMPOSITE_HEALTH_SCORE DESC, RUL_HOURS DESC, STRESS_INDEX ASC LIMIT 1)
    question: What is the most critical and least critical asset?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: COST_BY_WO_TYPE
    sql: SELECT WO_TYPE, COUNT(*) AS COUNT, ROUND(AVG(TOTAL_COST), 0) AS AVG_COST, ROUND(SUM(TOTAL_COST), 0) AS TOTAL_COST FROM work_orders WHERE NOT TOTAL_COST IS NULL GROUP BY WO_TYPE ORDER BY TOTAL_COST DESC
    question: What is the total maintenance cost breakdown by work order type?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: TECHNICIANS_ON_SHIFT
    sql: SELECT USERNAME, PERSONA, LINE_ID, EMAIL FROM users WHERE PERSONA = 'TECHNICIAN' AND ACTIVE = TRUE ORDER BY LINE_ID
    question: Who are the technicians and what lines do they cover?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: USERS_BY_PERSONA
    sql: SELECT PERSONA, COUNT(*) AS USER_COUNT FROM users WHERE ACTIVE = TRUE GROUP BY PERSONA ORDER BY USER_COUNT DESC
    question: How many users are there for each persona role?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: PARTS_AT_RISK
    sql: SELECT lp.ASSET_NAME, lp.FAILURE_MODE_PRED, lp.RUL_HOURS, lp.STAGE_PRED FROM live_predictions lp WHERE lp.STAGE_PRED IN ('Critical', 'Warning') ORDER BY lp.RUL_HOURS ASC
    question: Which parts or assets are at procurement risk?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: true
  - name: OEE_TREND
    sql: SELECT SHIFT_DATE, LINE_ID, ROUND(AVG(OEE_PCT),1) AS OEE, ROUND(AVG(AVAILABILITY_PCT),1) AS AVAIL, ROUND(AVG(PERFORMANCE_PCT),1) AS PERF, ROUND(AVG(QUALITY_PCT),1) AS QUAL FROM oee_metrics GROUP BY SHIFT_DATE, LINE_ID ORDER BY SHIFT_DATE DESC LIMIT 30
    question: How has OEE changed over time?
    verified_at: 1725580800
    verified_by: MFGPulse AI
    use_as_onboarding_question: false
  - name: RECENT_WORK_ORDER_HISTORY
    question: What are the most recent work orders across all assets?
    sql: SELECT WO_ID, ASSET_ID, WO_TYPE, PRIORITY, STATUS, TOTAL_COST, CREATED_DATE FROM work_orders ORDER BY CREATED_DATE DESC LIMIT 20
    verified_at: 1789538864
    verified_by: MFGPulse AI
relationships:
  - name: live_predictions_to_asset_master
    left_table: LIVE_PREDICTIONS
    right_table: ASSET_MASTER
    join_type: left_outer
    relationship_columns:
      - left_column: ASSET_ID
        right_column: ASSET_ID
  - name: active_alerts_to_asset_master
    left_table: ACTIVE_ALERTS
    right_table: ASSET_MASTER
    join_type: left_outer
    relationship_columns:
      - left_column: ASSET_ID
        right_column: ASSET_ID
  - name: oee_metrics_to_asset_master
    left_table: OEE_METRICS
    right_table: ASSET_MASTER
    join_type: left_outer
    relationship_columns:
      - left_column: ASSET_ID
        right_column: ASSET_ID
  - name: work_orders_to_asset_master
    left_table: WORK_ORDERS
    right_table: ASSET_MASTER
    join_type: left_outer
    relationship_columns:
      - left_column: ASSET_ID
        right_column: ASSET_ID
module_custom_instructions:
  sql_generation: >
    SCORE DIRECTION CONVENTIONS: COMPOSITE_HEALTH_SCORE: 0 = worst, 100 = best. Higher is healthier. For worst or unhealthiest assets, ORDER BY COMPOSITE_HEALTH_SCORE ASC. DEGRADATION_SCORE: 0.0 = healthy, 1.0 = critical. Higher is worse. For most degraded assets, ORDER BY DEGRADATION_SCORE DESC. FATIGUE_SCORE: 0.0 = healthy, 1.0 = critical fatigue. Higher is worse. RUL_HOURS (Remaining Useful Life): lower = more urgent, closer to failure. For which asset will fail next or most urgent, ORDER BY RUL_HOURS ASC. Never AVG(RUL_HOURS) across multiple assets - it is a per-asset point-in-time estimate. Use MIN for soonest failure or list individual values. STRESS_INDEX: higher = more operating stress. Higher is worse. TRANSITION_PROBABILITY: higher = more likely to worsen. Higher is worse. STAGE AND SEVERITY ORDERING: STAGE_PRED values ordered by severity: Critical > Warning > Healthy. Use CASE WHEN STAGE_PRED WHEN 'Critical' THEN 1 WHEN 'Warning' THEN 2 WHEN 'Healthy' THEN 3 END for ORDER BY. Alert SEVERITY ordered: CRITICAL > WARNING > WATCH > INFO. Use CASE WHEN SEVERITY WHEN 'CRITICAL' THEN 1 WHEN 'WARNING' THEN 2 WHEN 'WATCH' THEN 3 ELSE 4 END for ORDER BY. OEE FORMULA: OEE_PCT = AVAILABILITY_PCT x PERFORMANCE_PCT x QUALITY_PCT / 10000. All values are percentage points (0-100), not decimals. World-class OEE benchmark is 85%. BUSINESS RULES: Urgent, at risk, or needs attention means STAGE_PRED IN ('Critical', 'Warning'), sorted by RUL_HOURS ASC. An asset is chronic (repeat offender) when IS_CHRONIC = TRUE, meaning more than 2 work orders in 90 days (WO_COUNT_90D > 2). FATIGUE_LEVEL values ordered: critical > high > accumul > healthy. TABLE ROUTING: Use LIVE_PREDICTIONS for current asset health, condition, and predicted state. Use ACTIVE_ALERTS for the actionable alert queue and severity triage. Use OEE_METRICS for production efficiency trending and shift-level analysis. Use WORK_ORDERS for maintenance history, cost analysis, and technician workload. Use ASSET_MASTER for equipment metadata (manufacturer, model, install date, rated specs). Use USERS for persona/role-based queries and technician assignments.
  question_categorization: >
    This semantic view answers questions about: Asset health, condition, and predicted state (health scores, degradation, fatigue, failure modes). Remaining useful life (RUL) and failure timeline estimates. Active alerts and severity triage. OEE metrics (availability, performance, quality) by asset, line, and shift. Maintenance work orders, costs, priorities, and technician assignments. Production line comparisons and loss attribution. User personas and role-based access. Questions NOT answerable by this view (respond that the data is not available): Spare parts inventory, lead times, purchase orders, or supplier performance - no inventory or procurement tables are modeled. Historical raw sensor readings, real-time telemetry, vibration waveforms, or temperature time series - only ML model outputs (predictions, scores, stages) are available. Financial budgets, capital expenditure, or depreciation - only work order costs (parts + labor) are tracked. Production scheduling, demand forecasting, or order backlog.
  $$;

-- CORTEX AGENT: Deploy Maintenance Copilot (depends on semantic view above)
CREATE OR REPLACE AGENT MFGPULSE_DB.AGENT.MAINTENANCE_COPILOT
  COMMENT = 'Maintenance Copilot: 5-tool agent for predictive maintenance with 7 ML models, Cortex Search RAG, semantic analytics, Monte Carlo simulation, and work order generation.'
  PROFILE = '{"display_name": "Maintenance Copilot", "color": "blue"}'
  FROM SPECIFICATION
  $$
  models:
    orchestration: auto

  orchestration:
    tool_not_accessible: accept
    budget:
      seconds: 120
      tokens: 32000

  instructions:
    response: |
      You are the Maintenance Copilot for a manufacturing plant with 10 industrial assets across 3 production lines. You serve multiple stakeholders with different needs. Adapt your response depth and format based on who is asking.

      PERSONA DETECTION — infer from question style:
      - Technician: asks about specific parts, repairs, what to fix. Give step-by-step actions, part numbers, tool requirements.
      - Reliability Engineer: asks WHY something is failing, root cause, patterns. Give deep technical analysis with evidence from maintenance logs, sensor trends, physics explanations.
      - Shift Supervisor: asks about shift status, handover, what happened. Give structured briefing format.
      - Plant Manager / Director: asks about OEE, cost, ROI, trends. Give executive summary with business impact numbers. Lead with the dollar figure.

      RESPONSE RULES:

      1. HEALTH STATUS: Show all assets sorted by severity. Include: asset_name, stage (Healthy/Warning/Critical), RUL hours, fatigue score, failure mode. End with alert count and plant OEE.

      2. ROOT CAUSE (Reliability Engineer): Search maintenance_history for similar failures. Call predict_all for 7-model diagnosis. Cite specific maintenance log entries. State confidence. Explain the physics: what mechanism is causing degradation and why.

      3. WHAT-IF (Planner/Engineer): Call simulate_scenario. Show failure probability at day 3, 7, 14. Show RUL P10/P50/P90. Compare scenarios. End with recommended intervention window.

      4. WORK ORDER (Technician): Call generate_work_order. Show: parts needed and availability, assigned technician, estimated cost vs failure cost, step-by-step repair scope.

      5. SHIFT HANDOVER (Supervisor): Format as:
      SHIFT HANDOVER
      CRITICAL ACTIONS: assets with RUL < 72hrs — name, mode, RUL, action needed
      WARNINGS: assets in Warning or Watch
      PLANT OEE: current vs 85% target, biggest loss source
      COST: failures avoided, ROI

      6. EXECUTIVE BRIEFING (Manager/Director): Format as:
      EXECUTIVE SUMMARY
      FINANCIAL: cost avoided, maintenance ROI, cost per failure vs planned
      OPERATIONAL: plant OEE, assets at risk, early detection advantage
      RECOMMENDATION: top 1-2 actions with business justification

      7. URGENCY: RUL < 24hrs = URGENT prefix. RUL < 72hrs = ACTION NEEDED. All healthy = All systems nominal.

      8. ALWAYS end at-risk responses with: Repair cost $X vs Failure cost $Y — Cost of inaction: $Z.

    orchestration: |
      Use maintenance_analytics for data queries: health, OEE, alerts, work orders, costs, comparisons, executive summary, shift handover.
      Use maintenance_history for root cause investigation, past failures, technician notes, similar historical events.
      Use predict_all for full 7-model diagnosis of a specific asset.
      Use simulate_scenario for what-if scenarios, delay impact, load changes.
      Use generate_work_order ONLY when explicitly asked to create or file a work order.

    sample_questions:
      - question: "What is the current health status of all assets?"
      - question: "Why is Compressor A1 showing degradation? Give me the root cause."
      - question: "What happens if we delay maintenance on Motor M1 by 3 days?"
      - question: "Generate a work order for the most critical asset"
      - question: "Give me the end-of-shift handover summary"
      - question: "What is our maintenance ROI and total cost avoided?"
      - question: "Which production line is underperforming and why?"

  tools:
    - tool_spec:
        type: cortex_analyst_text_to_sql
        name: maintenance_analytics
        description: "Query structured maintenance data: asset health predictions, failure modes, remaining useful life (RUL), degradation stages, fatigue scores, OEE metrics (availability, performance, quality), active alerts (critical/warning/watch), work order history, and asset metadata across 10 industrial assets on 3 production lines."

    - tool_spec:
        type: cortex_search
        name: maintenance_history
        description: "Search maintenance logs and work order notes for root cause investigation. Use when asked WHY an asset is failing, what happened in the past, or to find similar historical failures. Returns technician notes, repair details, and failure descriptions."

    - tool_spec:
        type: generic
        name: predict_all
        description: "Run full 7-model diagnostic on a specific asset. Returns: failure mode prediction (M1), remaining useful life with confidence intervals (M2), degradation stage (M3), fatigue score (M4), LLM root cause analysis with evidence (M5), Monte Carlo simulation (M6), and prescriptive work order recommendation (M7). Use when asked to diagnose, analyze, or get a complete assessment of a specific asset."
        input_schema:
          type: object
          properties:
            asset_id:
              type: string
              description: "The asset ID to diagnose (e.g. ASSET_001, ASSET_004). Use ASSET_001 for Compressor A1, ASSET_002 for Compressor A2, ASSET_003 for Pump P1, ASSET_004 for Pump P2, ASSET_005 for Motor M1, ASSET_006 for Motor M2, ASSET_007 for Fan F1, ASSET_008 for Gearbox G1, ASSET_009 for Conveyor C1, ASSET_010 for Turbine T1."
          required:
            - asset_id

    - tool_spec:
        type: generic
        name: simulate_scenario
        description: "Run what-if simulation using Monte Carlo method. Shows failure probability at day 3/7/14, RUL distribution (P10/P50/P90), and cost impact under different scenarios. Use when asked what happens if maintenance is delayed, load is reduced, or RPM is adjusted."
        input_schema:
          type: object
          properties:
            current_vib_mag:
              type: number
              description: "Current vibration magnitude in mm/s"
            degradation_velocity:
              type: number
              description: "Rate of degradation per day"
            current_fatigue_score:
              type: number
              description: "Current fatigue score 0-1"
            load_reduction_pct:
              type: number
              description: "Load reduction percentage 0-50"
            maintenance_delay_days:
              type: number
              description: "Days before maintenance 0-14"
            rpm_adjustment_pct:
              type: number
              description: "RPM adjustment percentage -20 to 20"
          required:
            - current_vib_mag
            - degradation_velocity
            - current_fatigue_score
            - load_reduction_pct
            - maintenance_delay_days
            - rpm_adjustment_pct

    - tool_spec:
        type: generic
        name: generate_work_order
        description: "Generate and file a maintenance work order for an asset. Creates the work order in the system, assigns a technician from the shift schedule, checks parts availability, and returns the work order ID. Use when asked to create, generate, or file a work order."
        input_schema:
          type: object
          properties:
            asset_id:
              type: string
              description: "Asset ID (e.g. ASSET_001)"
            priority:
              type: string
              description: "Priority level: EMERGENCY, HIGH, MEDIUM, or LOW"
            action:
              type: string
              description: "Maintenance action description"
            parts_needed:
              type: string
              description: "Parts required for the repair"
            estimated_cost:
              type: number
              description: "Estimated repair cost in dollars"
          required:
            - asset_id
            - priority
            - action
            - parts_needed
            - estimated_cost

  tool_resources:
    maintenance_analytics:
      semantic_view: MFGPULSE_DB.AGENT.MAINTENANCE_SEMANTIC_VIEW
      execution_environment:
        type: warehouse
        warehouse: COMPUTE_WH

    maintenance_history:
      search_service: MFGPULSE_DB.ML_MODELS.MAINTENANCE_SEARCH
      id_column: DOC_ID
      title_column: SEARCH_TEXT
      execution_environment:
        type: warehouse
        warehouse: COMPUTE_WH

    predict_all:
      type: procedure
      identifier: MFGPULSE_DB.ML_MODELS.PREDICT_ALL
      execution_environment:
        type: warehouse
        warehouse: COMPUTE_WH

    simulate_scenario:
      type: function
      name: MFGPULSE_DB.ML_MODELS.SIMULATE_FAILURE_TWIN
      execution_environment:
        type: warehouse
        warehouse: COMPUTE_WH

    generate_work_order:
      type: procedure
      identifier: MFGPULSE_DB.ANALYTICS.GENERATE_WORK_ORDER
      execution_environment:
        type: warehouse
        warehouse: COMPUTE_WH
  $$;

-- AGENT MONITORING: Execution metrics (per-request detail from ACCOUNT_USAGE)
CREATE OR REPLACE VIEW ANALYTICS.AGENT_EXECUTION_METRICS AS
WITH usage AS (
    SELECT
        REQUEST_ID,
        START_TIME,
        END_TIME,
        DATEDIFF('millisecond', START_TIME, END_TIME) AS LATENCY_MS,
        USER_NAME,
        AGENT_NAME,
        TOKENS,
        TOKEN_CREDITS,
        METADATA:role_name::VARCHAR AS ROLE_NAME,
        METADATA:interaction_interface::VARCHAR AS INTERFACE,
        METADATA:ai_functions_credits::FLOAT AS AI_FUNCTIONS_CREDITS,
        METADATA:sql_query_credits::FLOAT AS SQL_QUERY_CREDITS,
        TOKENS_GRANULAR,
        CREDITS_GRANULAR
    FROM SNOWFLAKE.ACCOUNT_USAGE.CORTEX_AGENT_USAGE_HISTORY
    WHERE AGENT_DATABASE_NAME = 'MFGPULSE_DB'
      AND AGENT_SCHEMA_NAME = 'AGENT'
      AND AGENT_NAME = 'MAINTENANCE_COPILOT'
),
tool_breakdown AS (
    SELECT
        REQUEST_ID,
        t.value:service_type::VARCHAR AS SERVICE_TYPE,
        t.value:model::VARCHAR AS MODEL,
        t.value:input::NUMBER AS INPUT_TOKENS,
        t.value:output::NUMBER AS OUTPUT_TOKENS,
        t.value:cache_read_input::NUMBER AS CACHE_READ_TOKENS
    FROM usage,
    LATERAL FLATTEN(input => TOKENS_GRANULAR) t
)
SELECT
    u.REQUEST_ID,
    u.START_TIME,
    u.END_TIME,
    u.LATENCY_MS,
    ROUND(u.LATENCY_MS / 1000.0, 1) AS LATENCY_SECS,
    u.USER_NAME,
    u.ROLE_NAME,
    u.INTERFACE,
    u.TOKENS AS TOTAL_TOKENS,
    u.TOKEN_CREDITS,
    u.AI_FUNCTIONS_CREDITS,
    u.SQL_QUERY_CREDITS,
    COALESCE(u.TOKEN_CREDITS, 0) + COALESCE(u.AI_FUNCTIONS_CREDITS, 0) + COALESCE(u.SQL_QUERY_CREDITS, 0) AS TOTAL_CREDITS,
    ARRAY_SIZE(u.TOKENS_GRANULAR) AS TOOL_CALL_COUNT,
    ARRAY_TO_STRING(ARRAY_DISTINCT(ARRAY_AGG(tb.SERVICE_TYPE) OVER (PARTITION BY u.REQUEST_ID)), ', ') AS SERVICES_USED,
    ARRAY_TO_STRING(ARRAY_DISTINCT(ARRAY_AGG(tb.MODEL) OVER (PARTITION BY u.REQUEST_ID)), ', ') AS MODELS_USED,
    tb.SERVICE_TYPE,
    tb.MODEL,
    tb.INPUT_TOKENS,
    tb.OUTPUT_TOKENS,
    tb.CACHE_READ_TOKENS,
    CASE
        WHEN u.LATENCY_MS < 5000 THEN 'FAST'
        WHEN u.LATENCY_MS < 15000 THEN 'NORMAL'
        WHEN u.LATENCY_MS < 60000 THEN 'SLOW'
        ELSE 'VERY_SLOW'
    END AS PERFORMANCE_TIER,
    u.START_TIME::DATE AS REQUEST_DATE
FROM usage u
LEFT JOIN tool_breakdown tb ON u.REQUEST_ID = tb.REQUEST_ID;

-- AGENT MONITORING: Daily performance summary
CREATE OR REPLACE VIEW ANALYTICS.AGENT_DAILY_SUMMARY AS
SELECT
    START_TIME::DATE AS DAY,
    COUNT(DISTINCT REQUEST_ID) AS TOTAL_REQUESTS,
    COUNT(DISTINCT USER_NAME) AS UNIQUE_USERS,
    ROUND(AVG(LATENCY_MS), 0) AS AVG_LATENCY_MS,
    ROUND(MEDIAN(LATENCY_MS), 0) AS P50_LATENCY_MS,
    ROUND(APPROX_PERCENTILE(LATENCY_MS, 0.95), 0) AS P95_LATENCY_MS,
    MAX(LATENCY_MS) AS MAX_LATENCY_MS,
    SUM(TOTAL_TOKENS) AS TOTAL_TOKENS,
    ROUND(AVG(TOTAL_TOKENS), 0) AS AVG_TOKENS_PER_REQUEST,
    ROUND(SUM(TOKEN_CREDITS), 4) AS TOTAL_TOKEN_CREDITS,
    ROUND(SUM(COALESCE(AI_FUNCTIONS_CREDITS, 0)), 4) AS TOTAL_AI_CREDITS,
    ROUND(SUM(COALESCE(SQL_QUERY_CREDITS, 0)), 4) AS TOTAL_SQL_CREDITS,
    ROUND(SUM(TOTAL_CREDITS), 4) AS TOTAL_CREDITS,
    ROUND(AVG(TOOL_CALL_COUNT), 1) AS AVG_TOOL_CALLS,
    COUNT_IF(PERFORMANCE_TIER = 'FAST') AS FAST_REQUESTS,
    COUNT_IF(PERFORMANCE_TIER = 'NORMAL') AS NORMAL_REQUESTS,
    COUNT_IF(PERFORMANCE_TIER = 'SLOW') AS SLOW_REQUESTS,
    COUNT_IF(PERFORMANCE_TIER = 'VERY_SLOW') AS VERY_SLOW_REQUESTS,
    ROUND(COUNT_IF(PERFORMANCE_TIER IN ('FAST','NORMAL')) * 100.0 / NULLIF(COUNT(DISTINCT REQUEST_ID), 0), 1) AS SLA_PCT
FROM ANALYTICS.AGENT_EXECUTION_METRICS
GROUP BY DAY
ORDER BY DAY DESC;
--
-- ============================================================================
-- DEPLOYMENT COMPLETE
-- ============================================================================
--
-- ---- Data Quality: Validation Rules & DMFs ----
--
-- Documentation tables for data quality issues and validation rules
CREATE TABLE IF NOT EXISTS MFGPULSE_DB.ANALYTICS.DATA_QUALITY_ISSUES (
    ISSUE_ID NUMBER AUTOINCREMENT,
    DISCOVERED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    TABLE_NAME VARCHAR,
    COLUMN_NAME VARCHAR,
    ISSUE_TYPE VARCHAR,
    DESCRIPTION VARCHAR,
    SEVERITY VARCHAR,
    INVALID_VALUES VARCHAR,
    VALID_VALUES VARCHAR,
    ROWS_AFFECTED NUMBER,
    RESOLUTION VARCHAR,
    RESOLVED_AT TIMESTAMP_NTZ
);

CREATE TABLE IF NOT EXISTS MFGPULSE_DB.ANALYTICS.DATA_VALIDATION_RULES (
    RULE_ID NUMBER AUTOINCREMENT,
    TABLE_NAME VARCHAR,
    COLUMN_NAME VARCHAR,
    RULE_TYPE VARCHAR,
    ALLOWED_VALUES VARCHAR,
    DMF_ATTACHED BOOLEAN DEFAULT FALSE,
    CREATED_AT TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    NOTES VARCHAR
);

-- Test results table (used by Admin Panel)
CREATE TABLE IF NOT EXISTS MFGPULSE_DB.ANALYTICS.TEST_RESULTS (
    RUN_ID TIMESTAMP_NTZ DEFAULT CURRENT_TIMESTAMP(),
    TEST_SUITE VARCHAR,
    TEST_ID VARCHAR,
    TEST_NAME VARCHAR,
    EXPECTED VARCHAR,
    ACTUAL VARCHAR,
    STATUS VARCHAR
);

-- Seed validation rules
INSERT INTO MFGPULSE_DB.ANALYTICS.DATA_VALIDATION_RULES (TABLE_NAME, COLUMN_NAME, RULE_TYPE, ALLOWED_VALUES, DMF_ATTACHED, NOTES)
SELECT * FROM VALUES
    ('MFGPULSE_DB.RAW_IT.WORK_ORDERS', 'WO_TYPE', 'ACCEPTED_VALUES',
     'emergency, corrective, preventive', TRUE, 'Work order type classification'),
    ('MFGPULSE_DB.RAW_IT.WORK_ORDERS', 'STATUS', 'ACCEPTED_VALUES',
     'open, in_progress, completed, cancelled', TRUE, 'Work order lifecycle status'),
    ('MFGPULSE_DB.RAW_IT.WORK_ORDERS', 'ROOT_CAUSE_CONFIRMED', 'ACCEPTED_VALUES',
     'bearing_wear, thermal_degradation, imbalance, misalignment, electrical_fault, lubrication_failure, overload, other, unknown, normal, —',
     TRUE, 'Root cause for completed WOs. NULLs allowed (not yet confirmed).'),
    ('MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS', 'STATUS', 'ACCEPTED_VALUES',
     'pending_approval, approved, cancelled, received, ordered, shipped',
     TRUE, 'PO lifecycle: pending_approval → approved → ordered → shipped → received'),
    ('MFGPULSE_DB.ANALYTICS.ACTIVE_ALERTS', 'SEVERITY', 'ACCEPTED_VALUES',
     'WATCH, INFO', FALSE, 'Alert severity levels')
WHERE NOT EXISTS (SELECT 1 FROM MFGPULSE_DB.ANALYTICS.DATA_VALIDATION_RULES LIMIT 1);

-- Attach ACCEPTED_VALUES DMFs for continuous monitoring
ALTER TABLE MFGPULSE_DB.RAW_IT.WORK_ORDERS SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';
ALTER TABLE MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS SET DATA_METRIC_SCHEDULE = 'TRIGGER_ON_CHANGES';

ALTER TABLE MFGPULSE_DB.RAW_IT.WORK_ORDERS
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (WO_TYPE, WO_TYPE -> WO_TYPE IN ('emergency','corrective','preventive'))
  EXPECTATION valid_wo_types (VALUE = 0);

ALTER TABLE MFGPULSE_DB.RAW_IT.WORK_ORDERS
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (STATUS, STATUS -> STATUS IN ('open','in_progress','completed','cancelled'))
  EXPECTATION valid_wo_statuses (VALUE = 0);

ALTER TABLE MFGPULSE_DB.RAW_IT.WORK_ORDERS
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (ROOT_CAUSE_CONFIRMED, ROOT_CAUSE_CONFIRMED -> ROOT_CAUSE_CONFIRMED IS NULL OR ROOT_CAUSE_CONFIRMED IN ('bearing_wear','thermal_degradation','imbalance','misalignment','electrical_fault','lubrication_failure','overload','other','unknown','normal','—'))
  EXPECTATION valid_root_causes (VALUE = 0);

ALTER TABLE MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS
  ADD DATA METRIC FUNCTION SNOWFLAKE.CORE.ACCEPTED_VALUES
  ON (STATUS, STATUS -> STATUS IN ('pending_approval','approved','cancelled','received','ordered','shipped'))
  EXPECTATION valid_po_statuses (VALUE = 0);

--
-- NEXT STEPS:
--
-- 1. STREAMLIT APP: Copy the MFGPulse_AI_App/ directory to a Snowsight Workspace
--    and click Run. The app connects to MFGPULSE_DB automatically.
--
-- 2. DAG RESUME (optional, bottom-up — resume leaf tasks first):
--    ALTER TASK ANALYTICS.DAG_CONVERT_PPOS RESUME;
--    ALTER TASK ANALYTICS.DAG_GENERATE_POS RESUME;
--    ALTER TASK ANALYTICS.DAG_GENERATE_WOS RESUME;
--    ALTER TASK ANALYTICS.DAG_SNAPSHOT_KPIS RESUME;
--    ALTER TASK ANALYTICS.DAG_ARCHIVE_ALERTS RESUME;
--    ALTER TASK ANALYTICS.DAG_CHECK_DRIFT RESUME;
--    ALTER TASK ANALYTICS.DAG_REFRESH_DTS RESUME;
--    ALTER TASK ANALYTICS.DAG_REFRESH_FATIGUE RESUME;
--    ALTER TASK ANALYTICS.DAG_CHECK_FRESHNESS RESUME;
--    ALTER TASK ANALYTICS.DAG_SIMULATE_FEEDS RESUME;
--    ALTER TASK ANALYTICS.MFGPULSE_AUTOMATION_DAG RESUME;
--
-- 3. CLEANUP (optional): Drop the ML training warehouse if not needed:
--    DROP WAREHOUSE IF EXISTS MFGPULSE_ML_TRAINING_WH;
--
-- ============================================================================