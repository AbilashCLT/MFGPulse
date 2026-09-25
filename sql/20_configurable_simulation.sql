-- ============================================================================
-- MFGPulse AI: 20 Configurable Simulation
-- Parameterized sensor feed + production simulation with admin control
-- ============================================================================

USE DATABASE MFGPULSE_DB;

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
        'SIM-' || asset_id || '-' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDDHH24MISS'),
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
