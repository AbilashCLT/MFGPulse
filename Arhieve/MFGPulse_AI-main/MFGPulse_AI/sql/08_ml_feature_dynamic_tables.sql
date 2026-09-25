-- ============================================================================
-- MFGPulse AI: 08 ML Feature Dynamic Tables
-- 7 dynamic tables in ML_FEATURES schema
-- ============================================================================
-- All DTs: TARGET_LAG = '2 days', REFRESH_MODE = AUTO, WAREHOUSE = COMPUTE_WH
-- To get full DDL: GET_DDL('DYNAMIC TABLE', 'MFGPULSE_DB.ML_FEATURES.<name>')

-- ROLLING_STATS: 6h and 24h rolling window statistics for vibration, temperature, current, acoustic.
--   Key features: vib_rms, crest_factor, peak_to_peak, coeff_var, rate_of_change, acceleration. 172K rows.

-- SENSOR_INTERACTIONS: Cross-sensor correlations and ratios.
--   Key features: vib_xy_correlation, vib_temp_coupling, current_rpm_ratio, vib_axis_dominance, acoustic_vib_ratio. 172K rows.

-- PHYSICS_COMPOSITE: Physics-based composite indicators.
--   Key features: mechanical_power_proxy, thermal_efficiency, iso_10816_severity, bearing_defect_indicator,
--   energy_balance_ratio, stress_index, operating_regime, composite_health_score (0-100). 172K rows. INCREMENTAL refresh.

-- TEMPORAL_MEMORY: Long-term degradation memory.
--   Key features: hours_since_first_breach, degradation_velocity_30d, trend_reversal_count_7d,
--   above_normal_count_24h, vib_trend_72h, degradation_acceleration. 172K rows.

-- CROSS_DOMAIN: Cross-domain features combining maintenance history with sensor data.
--   Key features: days_since_last_maintenance, cumulative_operating_hours, historical_failure_count,
--   maintenance_effectiveness, workload_intensity_7d, wo_frequency_per_1000h. 172K rows.

-- FLEET_COMPARISON: Fleet-level z-scores and percentiles.
--   Key features: vib_zscore_vs_fleet, temp_zscore_vs_fleet, vib_percentile_in_fleet,
--   vib_ratio_to_fleet_mean, is_worst_in_fleet. 1.8K rows (daily).

-- LABELED_DATA: Training labels derived from work order history.
--   Key features: failure_mode, hours_to_failure, is_failure_event, degradation_stage (0-4),
--   failure_severity, is_degrading. 172K rows.
