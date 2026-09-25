-- ============================================================================
-- MFGPulse AI: 05 Generate Sensor Data
-- Physics-based sensor reading generation procedure (~172K readings)
-- ============================================================================

USE DATABASE MFGPULSE_DB;

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
