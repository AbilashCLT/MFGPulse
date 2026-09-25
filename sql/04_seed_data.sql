-- ============================================================================
-- MFGPulse AI: 04 Seed Data
-- Populates all reference/seed tables required before sensor generation,
-- dynamic tables, and analytics layers.
-- ============================================================================
-- Prerequisites: Run 01_infrastructure.sql, 02_base_tables.sql, 03_streams.sql first.
-- Date range: March – September 2026
-- ============================================================================

USE DATABASE MFGPULSE_DB;
USE SCHEMA PUBLIC;


-- ============================================================================
-- 1. ASSET_MASTER (10 assets across 3 production lines)
-- ============================================================================
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


-- ============================================================================
-- 2. SENSOR_METADATA (23 sensors, 2-3 per asset)
-- ============================================================================
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


-- ============================================================================
-- 3. USERS (9 users, 6 personas)
-- ============================================================================
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


-- ============================================================================
-- 4. PARTS_INVENTORY (15 parts with compatible asset arrays)
-- ============================================================================
INSERT INTO RAW_IT.PARTS_INVENTORY
    (PART_ID, PART_NAME, COMPATIBLE_ASSETS, QUANTITY_ON_HAND, LEAD_TIME_DAYS, UNIT_COST)
VALUES
    ('PART-001', 'Bearing 6205-2RS',           ARRAY_CONSTRUCT('ASSET_001','ASSET_002','ASSET_005','ASSET_006'),   12, 5,  45.00),
    ('PART-002', 'Bearing 6308-ZZ',            ARRAY_CONSTRUCT('ASSET_005','ASSET_006'),                            4, 7,  120.00),
    ('PART-003', 'Vibratory Seal Kit',          ARRAY_CONSTRUCT('ASSET_001','ASSET_002'),                            8, 3,  15.00),
    ('PART-004', 'Oil Filter - Medium',         ARRAY_CONSTRUCT('ASSET_001','ASSET_002','ASSET_008'),               20, 2,   8.00),
    ('PART-005', 'V-Belt Kit',                  ARRAY_CONSTRUCT('ASSET_001','ASSET_002','ASSET_005','ASSET_006'),    6, 4,  25.00),
    ('PART-006', 'Impeller - Centrifugal',      ARRAY_CONSTRUCT('ASSET_003','ASSET_004'),                            2, 14, 850.00),
    ('PART-007', 'Mechanical Seal - Pump',      ARRAY_CONSTRUCT('ASSET_003','ASSET_004'),                            3, 10, 320.00),
    ('PART-008', 'Roller Bearing NUP310',       ARRAY_CONSTRUCT('ASSET_005','ASSET_006','ASSET_008'),                5, 6,  95.00),
    ('PART-009', 'Heater Coil 3kW',            ARRAY_CONSTRUCT('ASSET_006'),                                         1, 12, 280.00),
    ('PART-010', 'Flexible Coupling',           ARRAY_CONSTRUCT('ASSET_003','ASSET_004','ASSET_009'),                4, 5,  180.00),
    ('PART-011', 'Bearing 6310-2RS',            ARRAY_CONSTRUCT('ASSET_008','ASSET_009'),                            3, 7,  150.00),
    ('PART-012', 'Gear Set G1',                 ARRAY_CONSTRUCT('ASSET_008'),                                         1, 21, 1200.00),
    ('PART-013', 'Conveyor Roller Set',         ARRAY_CONSTRUCT('ASSET_009'),                                         4, 3,  65.00),
    ('PART-014', 'Shaft Sleeve - Compressor',   ARRAY_CONSTRUCT('ASSET_001','ASSET_002'),                            2, 12, 450.00),
    ('PART-015', 'Turbine Blade Set',           ARRAY_CONSTRUCT('ASSET_010'),                                         0, 28, 2200.00);


-- ============================================================================
-- 5. MODEL_REGISTRY (12 models: 8 UDF/Proc + 4 native)
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


-- ============================================================================
-- 6. WORK_ORDERS (22 orders: mix of emergency, corrective, preventive)
-- ============================================================================
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
    -- Preventive WOs (scheduled maintenance)
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


-- ============================================================================
-- 7. MAINTENANCE_LOGS (26 logs linked to work orders)
-- ============================================================================
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


-- ============================================================================
-- 8. SUPPLIERS (5 suppliers) — also in 15_procurement_tables.sql
-- ============================================================================
INSERT INTO RAW_IT.SUPPLIERS
    (SUPPLIER_ID, SUPPLIER_NAME, CONTACT_EMAIL, PHONE)
VALUES
    ('SUP-001', 'Industrial Parts Co',       'orders@indparts.com',      '+1-555-0101'),
    ('SUP-002', 'Atlas Copco Parts Direct',  'parts@atlascopco.com',     '+1-555-0102'),
    ('SUP-003', 'Bearing World Inc',         'sales@bearingworld.com',   '+1-555-0103'),
    ('SUP-004', 'ThermalTech Supply',        'orders@thermaltech.com',   '+1-555-0104'),
    ('SUP-005', 'PumpParts Global',          'sales@pumpparts.com',      '+1-555-0105');


-- ============================================================================
-- 9. PART_SUPPLIERS (16 mappings) — also in 15_procurement_tables.sql
-- ============================================================================
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
    ('PART-015', 'SUP-004', 'TT-BLADE-STM',    28, 14,  1, 2200.00, TRUE);


-- ============================================================================
-- 10. SHIFT_SCHEDULE (~1710 rows: 3 shifts × 3 lines × 190 days)
-- Generated procedurally to keep this file manageable.
-- ============================================================================
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
    'SH-' || l.LINE_ID || '-' || TO_CHAR(d.shift_date, 'YYYYMMDD') || '-S' || s.shift_num AS SHIFT_ID,
    l.LINE_ID,
    DATEADD('hour', s.start_hour, d.shift_date::TIMESTAMP_NTZ) AS SHIFT_START,
    DATEADD('hour', s.start_hour + 8, DATEADD('day', s.end_offset, d.shift_date)::TIMESTAMP_NTZ) AS SHIFT_END,
    o.OPERATOR_NAME,
    480 AS PLANNED_PRODUCTION_TIME_MINS
FROM date_range d
CROSS JOIN lines l
CROSS JOIN shifts s
JOIN operators o ON o.LINE_ID = l.LINE_ID AND o.shift_num = s.shift_num;


-- ============================================================================
-- 11. PRODUCTION_OUTPUT (~3330 rows: ~18 records/day for producing assets)
-- Only assets that produce output (not turbine or fan in this model).
-- ============================================================================
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
    'P-' || a.ASSET_ID || '-' || TO_CHAR(d.prod_date, 'YYYYMMDD') || '-S' || s.shift_num AS RECORD_ID,
    a.ASSET_ID,
    'SH-' || a.LINE_ID || '-' || TO_CHAR(d.prod_date, 'YYYYMMDD') || '-S' || s.shift_num AS SHIFT_ID,
    DATEADD('hour', s.start_hour + 4, d.prod_date::TIMESTAMP_NTZ) AS TIMESTAMP,
    GREATEST(80, LEAST(200, ROUND(150 + UNIFORM(-30::FLOAT, 30::FLOAT, RANDOM()))))::INT AS UNITS_PRODUCED,
    GREATEST(70, LEAST(195, ROUND(145 + UNIFORM(-30::FLOAT, 25::FLOAT, RANDOM()))))::INT AS GOOD_UNITS,
    2.5 AS IDEAL_CYCLE_TIME_SEC
FROM date_range d
CROSS JOIN producing_assets a
CROSS JOIN shifts s
WHERE UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) > 0.15;


-- ============================================================================
-- 12. AMBIENT_CONDITIONS (190 days of daily weather data)
-- ============================================================================
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


-- ============================================================================
-- SEED DATA COMPLETE
-- ============================================================================
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
