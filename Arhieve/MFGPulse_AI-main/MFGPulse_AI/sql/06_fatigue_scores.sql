-- ============================================================================
-- MFGPulse AI: 06 Fatigue Scores
-- Compute and store cumulative fatigue scores for all assets
-- ============================================================================

USE DATABASE MFGPULSE_DB;

-- Populate FATIGUE_SCORES using the COMPUTE_FATIGUE_SCORE UDF (defined in 10_udfs)
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
WHERE MOD(ROW_NUMBER() OVER (PARTITION BY rs.asset_id ORDER BY rs.timestamp), 25) = 0;
-- Samples every 25th reading per asset to reduce volume (~6.7K rows)
