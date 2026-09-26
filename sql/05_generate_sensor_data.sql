-- ============================================================================
-- MFGPulse AI: 05 Generate Sensor Data (v2 — Realistic Plant Lifecycle)
-- Physics-based sensor reading generation with per-asset lifecycle personas,
-- maintenance reset events, burst spike injection, and differentiated
-- degradation curves (~172K readings)
-- ============================================================================
-- Lifecycle distribution across 10 assets:
--   3 HEALTHY   (ASSET_001 recovering, ASSET_003 fresh, ASSET_007 young)
--   3 ACCUMULATING (ASSET_002 mid-life, ASSET_008 watch-list, ASSET_010 mature)
--   3 HIGH      (ASSET_004 aging, ASSET_005 degrading, ASSET_009 recurring)
--   1 CRITICAL  (ASSET_006 emergency)
--
-- Key techniques:
--   - Piecewise degradation curves shaped by maintenance WO history
--   - Maintenance reset events (WO completions reduce degradation)
--   - Burst spike injection: intermittent high-amplitude spikes on degraded
--     assets to drive crest factor and CoV up (fatigue UDF inputs)
--   - Noise scaling proportional to degradation state
--   - Thermal acoustic decoupling for thermal_degradation failure mode
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
                WHEN ''ASSET_001'' THEN ''bearing_wear''
                WHEN ''ASSET_002'' THEN ''thermal_degradation''
                WHEN ''ASSET_003'' THEN ''imbalance''
                WHEN ''ASSET_004'' THEN ''misalignment''
                WHEN ''ASSET_005'' THEN ''bearing_wear''
                WHEN ''ASSET_006'' THEN ''thermal_degradation''
                WHEN ''ASSET_007'' THEN ''healthy''
                WHEN ''ASSET_008'' THEN ''imbalance''
                WHEN ''ASSET_009'' THEN ''misalignment''
                WHEN ''ASSET_010'' THEN ''healthy''
            END AS failure_mode
        FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER
    ),
    combined AS (
        SELECT a.asset_id, t.ts, a.rated_rpm, a.rated_temp_max, a.failure_mode,
            DATEDIFF(''minute'', :start_date::TIMESTAMP_NTZ, t.ts) /
                DATEDIFF(''minute'', :start_date::TIMESTAMP_NTZ, :end_date::TIMESTAMP_NTZ)::FLOAT AS timeline_pct,
            UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS noise1,
            UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS noise2,
            UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS noise3,
            UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS missing_rnd,
            UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS burst_rnd,
            SIN(DATEDIFF(''hour'', :start_date::TIMESTAMP_NTZ, t.ts) / 500.0) * 0.3 AS sensor_drift
        FROM time_series t CROSS JOIN assets a
    ),
    -- ================================================================
    -- LIFECYCLE-SHAPED DEGRADATION CURVES
    -- Each asset has a piecewise curve shaped by its maintenance history.
    -- Timeline key dates as fractions of Mar 1 - Aug 28 (180 days):
    --   Apr 10~0.22, Apr 15~0.25, Apr 22~0.29, May 01~0.34
    --   May 08~0.38, May 10~0.39, May 20~0.44, Jun 01~0.51
    --   Jun 05~0.53, Jun 10~0.56, Jun 15~0.59, Jun 20~0.62
    --   Jul 01~0.67, Jul 05~0.69, Jul 15~0.75, Aug 10~0.89
    --   Aug 18~0.94, Aug 20~0.95, Aug 25~0.97
    -- ================================================================
    lifecycle AS (
        SELECT c.*,
            CASE c.asset_id
                -- ASSET_001: RECOVERING - repaired Apr 10, Jun 10, Aug 10 in-progress
                WHEN ''ASSET_001'' THEN
                    CASE
                        WHEN timeline_pct < 0.22 THEN timeline_pct * 1.6
                        WHEN timeline_pct < 0.24 THEN 0.05
                        WHEN timeline_pct < 0.56 THEN 0.05 + (timeline_pct - 0.24) * 1.1
                        WHEN timeline_pct < 0.58 THEN 0.08
                        WHEN timeline_pct < 0.89 THEN 0.08 + (timeline_pct - 0.58) * 1.4
                        ELSE GREATEST(0.03, 0.51 - (timeline_pct - 0.89) * 4.0)
                    END
                -- ASSET_002: MID-LIFE STEADY - preventive May 25, slow climb
                WHEN ''ASSET_002'' THEN
                    CASE
                        WHEN timeline_pct < 0.47 THEN timeline_pct * 0.65
                        WHEN timeline_pct < 0.49 THEN 0.12
                        ELSE 0.12 + (timeline_pct - 0.49) * 0.50
                    END
                -- ASSET_003: FRESHLY MAINTAINED - corrective Apr 15, seal May 10
                WHEN ''ASSET_003'' THEN
                    CASE
                        WHEN timeline_pct < 0.25 THEN timeline_pct * 1.4
                        WHEN timeline_pct < 0.27 THEN 0.05
                        WHEN timeline_pct < 0.39 THEN 0.05 + (timeline_pct - 0.27) * 1.0
                        WHEN timeline_pct < 0.41 THEN 0.03
                        ELSE 0.03 + (timeline_pct - 0.41) * 0.10
                    END
                -- ASSET_004: AGING - emergency Jun 01, preventive Jun 20, coupling cracking
                WHEN ''ASSET_004'' THEN
                    CASE
                        WHEN timeline_pct < 0.51 THEN timeline_pct * 0.80
                        WHEN timeline_pct < 0.53 THEN 0.15
                        WHEN timeline_pct < 0.62 THEN 0.15 + (timeline_pct - 0.53) * 1.5
                        WHEN timeline_pct < 0.64 THEN 0.18
                        ELSE 0.18 + (timeline_pct - 0.64) * 1.6
                    END
                -- ASSET_005: DEGRADING - emergency May 08, corrective Jul 01, not resolved
                WHEN ''ASSET_005'' THEN
                    CASE
                        WHEN timeline_pct < 0.38 THEN timeline_pct * 1.5
                        WHEN timeline_pct < 0.40 THEN 0.25
                        WHEN timeline_pct < 0.67 THEN 0.25 + (timeline_pct - 0.40) * 1.8
                        WHEN timeline_pct < 0.69 THEN 0.35
                        ELSE 0.35 + (timeline_pct - 0.69) * 2.0
                    END
                -- ASSET_006: CRITICAL - corrective May 01, preventive Jun 05, insulation failing
                WHEN ''ASSET_006'' THEN
                    CASE
                        WHEN timeline_pct < 0.34 THEN timeline_pct * 1.2
                        WHEN timeline_pct < 0.36 THEN 0.15
                        WHEN timeline_pct < 0.53 THEN 0.15 + (timeline_pct - 0.36) * 1.0
                        WHEN timeline_pct < 0.55 THEN 0.18
                        WHEN timeline_pct < 0.94 THEN 0.18 + POWER((timeline_pct - 0.55) / 0.39, 1.8) * 0.70
                        ELSE 0.88 + (timeline_pct - 0.94) * 2.0
                    END
                -- ASSET_007: YOUNG ASSET - installed 2023, minimal wear
                WHEN ''ASSET_007'' THEN
                    0.02 + timeline_pct * 0.05 + SIN(timeline_pct * 6.28) * 0.01
                -- ASSET_008: WATCH LIST - corrective Jun 15, preventive Jul 15, plateau
                WHEN ''ASSET_008'' THEN
                    CASE
                        WHEN timeline_pct < 0.59 THEN timeline_pct * 0.90
                        WHEN timeline_pct < 0.61 THEN 0.22
                        WHEN timeline_pct < 0.75 THEN 0.22 + (timeline_pct - 0.61) * 0.60
                        WHEN timeline_pct < 0.77 THEN 0.25
                        ELSE 0.25 + (timeline_pct - 0.77) * 0.55
                    END
                -- ASSET_009: RECURRING ISSUE - corrective May 20, preventive Jul 05, sawtooth
                WHEN ''ASSET_009'' THEN
                    CASE
                        WHEN timeline_pct < 0.44 THEN timeline_pct * 1.3
                        WHEN timeline_pct < 0.46 THEN 0.12
                        WHEN timeline_pct < 0.69 THEN 0.12 + (timeline_pct - 0.46) * 2.0
                        WHEN timeline_pct < 0.71 THEN 0.18
                        ELSE 0.18 + (timeline_pct - 0.71) * 2.2
                    END
                -- ASSET_010: MATURE STABLE - preventive Apr 15, very slow climb
                WHEN ''ASSET_010'' THEN
                    CASE
                        WHEN timeline_pct < 0.25 THEN 0.10 + timeline_pct * 0.40
                        WHEN timeline_pct < 0.27 THEN 0.08
                        ELSE 0.08 + (timeline_pct - 0.27) * 0.25
                    END
                ELSE 0.0
            END AS degradation_pct_raw
        FROM combined c
    ),
    shaped AS (
        SELECT l.*,
            LEAST(1.0, GREATEST(0.0, degradation_pct_raw)) AS degradation_pct,
            -- Noise scaling (moderate to avoid uniform inflation of crest factor)
            CASE
                WHEN degradation_pct_raw < 0.15 THEN 1.0
                WHEN degradation_pct_raw < 0.35 THEN 1.3
                WHEN degradation_pct_raw < 0.60 THEN 1.6
                WHEN degradation_pct_raw < 0.80 THEN 2.0
                ELSE 2.5
            END AS noise_scale,
            -- Intermittent burst spike: fires on ~15% of readings when degradation is high
            -- Rare large spikes drive crest factor up (max/rms ratio) and CoV up
            CASE
                WHEN degradation_pct_raw > 0.70 AND burst_rnd > 0.85 THEN degradation_pct_raw * 12.0
                WHEN degradation_pct_raw > 0.50 AND burst_rnd > 0.90 THEN degradation_pct_raw * 8.0
                WHEN degradation_pct_raw > 0.30 AND burst_rnd > 0.95 THEN degradation_pct_raw * 4.0
                ELSE 0.0
            END AS burst_spike
        FROM lifecycle l
    )
    SELECT asset_id, ts,
        -- VIBRATION_X
        CASE WHEN missing_rnd < 0.002 THEN NULL
            WHEN failure_mode = ''bearing_wear'' THEN
                2.0 + noise1*0.5*noise_scale + sensor_drift
                + degradation_pct*8.0*(1 + degradation_pct)
                + burst_spike * (1.0 + ABS(noise2))
                + CASE WHEN degradation_pct > 0.8 THEN ABS(noise2)*15.0 ELSE 0 END
            WHEN failure_mode = ''misalignment'' THEN
                2.5 + noise1*0.4*noise_scale + sensor_drift
                + degradation_pct*5.0 + degradation_pct*SIN(timeline_pct*200)*3.0
                + burst_spike * 0.8
            WHEN failure_mode = ''imbalance'' THEN
                1.8 + noise1*0.3*noise_scale + sensor_drift
                + degradation_pct*4.0*(1 + degradation_pct*0.5)
                + burst_spike * 0.6
            WHEN failure_mode = ''thermal_degradation'' THEN
                1.6 + noise1*0.3*noise_scale + sensor_drift
                + degradation_pct*1.5
                + burst_spike * 0.3
            ELSE 1.5 + noise1*0.4 + sensor_drift
        END,
        -- VIBRATION_Y
        CASE WHEN missing_rnd < 0.002 THEN NULL
            WHEN failure_mode = ''bearing_wear'' THEN
                1.8 + noise2*0.4*noise_scale
                + degradation_pct*6.0*(1 + degradation_pct*0.5)
                + burst_spike * (0.8 + ABS(noise1)*0.5)
            WHEN failure_mode = ''misalignment'' THEN
                2.2 + noise2*0.5*noise_scale
                + degradation_pct*6.5 + degradation_pct*COS(timeline_pct*200)*2.5
                + burst_spike * 0.9
            WHEN failure_mode = ''imbalance'' THEN
                1.5 + noise2*0.3*noise_scale
                + degradation_pct*7.0*(1 + degradation_pct)
                + burst_spike * 0.7
            WHEN failure_mode = ''thermal_degradation'' THEN
                1.4 + noise2*0.3*noise_scale
                + degradation_pct*1.2
            ELSE 1.3 + noise2*0.35
        END,
        -- VIBRATION_Z
        CASE WHEN missing_rnd < 0.002 THEN NULL
            WHEN failure_mode = ''bearing_wear'' THEN
                1.5 + noise3*0.3*noise_scale + degradation_pct*4.0
                + burst_spike * 0.5
            WHEN failure_mode = ''misalignment'' THEN
                2.0 + noise3*0.5*noise_scale + degradation_pct*5.5
                + burst_spike * 0.7
            WHEN failure_mode = ''imbalance'' THEN
                1.2 + noise3*0.25*noise_scale + degradation_pct*3.5*(1 + degradation_pct*0.3)
                + burst_spike * 0.4
            WHEN failure_mode = ''thermal_degradation'' THEN
                1.2 + noise3*0.25*noise_scale + degradation_pct*0.8
            ELSE 1.1 + noise3*0.3
        END,
        -- TEMPERATURE
        CASE WHEN missing_rnd < 0.001 THEN NULL
            WHEN failure_mode = ''thermal_degradation'' THEN
                rated_temp_max*0.55 + noise1*2.0*noise_scale
                + degradation_pct*rated_temp_max*0.40*(1 + degradation_pct*0.3)
                + SIN(timeline_pct*48)*3.0
            WHEN failure_mode = ''bearing_wear'' THEN
                rated_temp_max*0.50 + noise1*1.5
                + degradation_pct*rated_temp_max*0.20
                + CASE WHEN degradation_pct > 0.7 THEN degradation_pct*rated_temp_max*0.08 ELSE 0 END
            WHEN failure_mode = ''misalignment'' THEN
                rated_temp_max*0.52 + noise1*1.5 + degradation_pct*rated_temp_max*0.10
            ELSE rated_temp_max*0.50 + noise1*2.0 + SIN(timeline_pct*48)*2.5
        END,
        -- RPM
        CASE
            WHEN failure_mode = ''imbalance'' THEN rated_rpm*(1.0 + noise1*0.005 - degradation_pct*0.08)
            WHEN failure_mode = ''bearing_wear'' AND degradation_pct > 0.6 THEN rated_rpm*(1.0 + noise1*0.003 - degradation_pct*0.02)
            ELSE rated_rpm*(1.0 + noise1*0.003)
        END,
        -- PRESSURE
        CASE
            WHEN failure_mode = ''bearing_wear'' THEN 6.5 + noise2*0.2 + degradation_pct*1.5
            WHEN failure_mode = ''misalignment'' AND degradation_pct > 0.5 THEN 6.2 + noise2*0.3 + degradation_pct*0.8
            ELSE 6.0 + noise2*0.2
        END,
        -- CURRENT_AMPS
        CASE
            WHEN failure_mode = ''misalignment'' THEN
                12.0 + noise3*0.5*noise_scale + degradation_pct*8.0*(1 + degradation_pct)
            WHEN failure_mode = ''bearing_wear'' THEN
                11.5 + noise3*0.4 + degradation_pct*3.0
                + CASE WHEN degradation_pct > 0.7 THEN degradation_pct*2.5 ELSE 0 END
            WHEN failure_mode = ''imbalance'' THEN
                11.0 + noise3*0.4 + degradation_pct*2.0
            ELSE 10.5 + noise3*0.4
        END,
        -- ACOUSTIC_DB
        CASE
            WHEN failure_mode = ''bearing_wear'' THEN
                72 + noise1*2.0*noise_scale + degradation_pct*18.0
                + burst_spike * 2.0
                + CASE WHEN degradation_pct > 0.7 THEN ABS(noise2)*8.0 ELSE 0 END
            WHEN failure_mode = ''misalignment'' THEN
                70 + noise1*1.5*noise_scale + degradation_pct*12.0
                + burst_spike * 1.5
            WHEN failure_mode = ''imbalance'' THEN
                68 + noise1*1.5 + degradation_pct*8.0
            WHEN failure_mode = ''thermal_degradation'' THEN
                66 + noise1*2.0 + degradation_pct*20.0
                + CASE WHEN degradation_pct > 0.5 THEN degradation_pct*10.0 ELSE 0 END
            ELSE 65 + noise1*2.0
        END
    FROM shaped WHERE missing_rnd > 0.003;

    SELECT COUNT(*) INTO :row_count FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS;
    RETURN ''Generated '' || :row_count || '' sensor readings (lifecycle-shaped v2)'';
END;
';

-- To run: CALL MFGPULSE_DB.RAW_OT.GENERATE_SENSOR_DATA();
