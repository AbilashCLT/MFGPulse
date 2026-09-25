1 row(s) returned.

GET_DDL('DATABASE', 'MFGPULSE_DB')

"create or replace database MFGPULSE_DB;

create or replace schema AGENT;

create or replace schema ANALYTICS;

create or replace dynamic table ACTIVE_ALERTS(
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
) target_lag = '2 days' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
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
create or replace dynamic table OEE_METRICS(
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
) target_lag = '2 days' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
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
create or replace view ALERT_SUMMARY(
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
create or replace view COST_IMPACT(
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
        DATEDIFF('day', fatigue_first_warning, threshold_first_alert) AS days_early_vs_threshold,
        DATEDIFF('day', fatigue_first_warning, first_failure_date) AS days_before_failure,
        COALESCE(avg_emergency_cost, 12000) AS emergency_cost,
        COALESCE(avg_corrective_cost, 2000) AS planned_repair_cost,
        COALESCE(avg_emergency_cost, 12000) - COALESCE(avg_corrective_cost, 2000) AS cost_avoided_per_event
    FROM early_detections
    WHERE threshold_first_alert IS NOT NULL
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
create or replace view COST_IMPACT_BY_ASSET(
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
create or replace view EXECUTIVE_SUMMARY(
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

create or replace view PREDICTIONS_WITH_COST(
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
create or replace view SHIFT_HANDOVER_VIEW(
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
CREATE OR REPLACE PROCEDURE ""AUTO_GENERATE_WORK_ORDERS""()
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
            AND NOT EXISTS (SELECT 1 FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS wo WHERE wo.ASSET_ID = p.ASSET_ID AND wo.STATUS = ''open'')
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
    RETURN ''Work orders generated at '' || CURRENT_TIMESTAMP()::VARCHAR;
END;
';
CREATE OR REPLACE PROCEDURE ""GENERATE_SHIFT_HANDOVER_SUMMARY""()
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
CREATE OR REPLACE PROCEDURE ""GENERATE_WORK_ORDER""(""P_ASSET_ID"" VARCHAR, ""P_PRIORITY"" VARCHAR, ""P_ACTION"" VARCHAR, ""P_PARTS_NEEDED"" VARCHAR, ""P_ESTIMATED_COST"" FLOAT)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    v_wo_id VARCHAR;
    v_technician VARCHAR DEFAULT ''Unassigned'';
    v_parts_available BOOLEAN DEFAULT FALSE;
    v_line_id VARCHAR;
BEGIN
    -- Generate WO ID
    v_wo_id := ''WO-AUTO-'' || TO_CHAR(CURRENT_TIMESTAMP(), ''YYYYMMDD-HH24MISS'');
    
    -- Get asset''s line
    SELECT line_id INTO :v_line_id FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER WHERE asset_id = :p_asset_id;
    
    -- Find next available technician from shift schedule
    BEGIN
        SELECT operator_name INTO :v_technician
        FROM MFGPULSE_DB.RAW_IT.SHIFT_SCHEDULE
        WHERE line_id = :v_line_id AND shift_start > CURRENT_TIMESTAMP()
        ORDER BY shift_start LIMIT 1;
    EXCEPTION WHEN OTHER THEN v_technician := ''Next available technician'';
    END;
    
    -- Check parts availability
    BEGIN
        SELECT COUNT(*) > 0 INTO :v_parts_available
        FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY
        WHERE ARRAY_CONTAINS(:p_asset_id::VARIANT, compatible_assets)
            AND quantity_on_hand > 0;
    EXCEPTION WHEN OTHER THEN v_parts_available := FALSE;
    END;
    
    -- Insert work order
    INSERT INTO MFGPULSE_DB.RAW_IT.WORK_ORDERS 
    (wo_id, asset_id, wo_type, created_date, priority, status, assigned_to, parts_cost)
    VALUES (
        :v_wo_id, :p_asset_id, 
        CASE WHEN :p_priority = ''EMERGENCY'' THEN ''emergency'' ELSE ''corrective'' END,
        CURRENT_TIMESTAMP(), :p_priority, ''open'', :v_technician, :p_estimated_cost
    );
    
    RETURN OBJECT_CONSTRUCT(
        ''wo_id'', :v_wo_id,
        ''asset_id'', :p_asset_id,
        ''priority'', :p_priority,
        ''status'', ''open'',
        ''action'', :p_action,
        ''assigned_to'', :v_technician,
        ''parts_needed'', :p_parts_needed,
        ''parts_available'', :v_parts_available,
        ''estimated_cost'', :p_estimated_cost,
        ''created_at'', CURRENT_TIMESTAMP()::VARCHAR,
        ''message'', ''Work order '' || :v_wo_id || '' created for '' || :p_asset_id || ''. Assigned to: '' || :v_technician
    );
END;
';
create or replace schema CURATED;

create or replace dynamic table ASSET_HEALTH_CURRENT(
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
) target_lag = '2 days' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
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
create or replace dynamic table FAILURE_HISTORY(
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
) target_lag = '2 days' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
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
create or replace dynamic table SENSOR_WITH_CONTEXT(
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
) target_lag = '2 days' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
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
create or replace schema ML_FEATURES;

create or replace dynamic table CROSS_DOMAIN(
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
) target_lag = '2 days' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
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
create or replace dynamic table FLEET_COMPARISON(
	ASSET_ID,
	READING_DATE,
	VIB_ZSCORE_VS_FLEET,
	TEMP_ZSCORE_VS_FLEET,
	VIB_PERCENTILE_IN_FLEET,
	VIB_RATIO_TO_FLEET_MEAN,
	IS_WORST_IN_FLEET
) target_lag = '2 days' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
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
create or replace dynamic table LABELED_DATA(
	ASSET_ID,
	TIMESTAMP,
	FAILURE_MODE,
	HOURS_TO_FAILURE,
	IS_FAILURE_EVENT,
	DEGRADATION_STAGE,
	FAILURE_SEVERITY,
	IS_DEGRADING
) target_lag = '2 days' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
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
create or replace dynamic table PHYSICS_COMPOSITE(
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
) target_lag = '2 days' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
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
create or replace dynamic table ROLLING_STATS(
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
) target_lag = '2 days' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
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
create or replace dynamic table SENSOR_INTERACTIONS(
	ASSET_ID,
	TIMESTAMP,
	VIB_XY_CORRELATION_DAILY,
	VIB_TEMP_COUPLING_DAILY,
	CURRENT_RPM_RATIO,
	TEMP_LOAD_RATIO,
	VIB_AXIS_DOMINANCE,
	ACOUSTIC_VIB_RATIO,
	CURRENT_VIB_COUPLING_DAILY
) target_lag = '2 days' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
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
create or replace dynamic table TEMPORAL_MEMORY(
	ASSET_ID,
	TIMESTAMP,
	HOURS_SINCE_FIRST_BREACH,
	DEGRADATION_VELOCITY_30D,
	TREND_REVERSAL_COUNT_7D,
	ABOVE_NORMAL_COUNT_24H,
	VIB_TREND_72H,
	DEGRADATION_ACCELERATION
) target_lag = '2 days' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
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
        
        -- 1. Hours since first threshold breach
        DATEDIFF('hour', fb.first_breach_ts, l.timestamp) AS hours_since_first_breach,
        
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
create or replace view ALL_DERIVED_FEATURES(
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
create or replace view ALL_DERIVED_FEATURES_INFERENCE(
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
create or replace view FEATURE_CATALOG(
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
create or replace view HEALTHY_DERIVED_FEATURES(
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
create or replace view HEALTHY_DERIVED_FEATURES_TRAIN(
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
create or replace view TRAIN_ANOMALY(
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
create or replace view TRAIN_ANOMALY_SMALL(
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
create or replace view TRAIN_FAILURE_MODE(
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
   OR (ld.failure_mode = 'normal' AND UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) < 0.15);
create or replace view TRAIN_RUL(
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
create or replace view TRAIN_TRAJECTORY(
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
create or replace view TRAIN_TRAJECTORY_3CLASS(
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
        WHEN ld.degradation_stage IN (0, 1) THEN 0  -- Healthy
        WHEN ld.degradation_stage = 2 THEN 1         -- Warning
        WHEN ld.degradation_stage IN (3, 4) THEN 2   -- Critical
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
create or replace schema ML_MODELS;

create or replace TABLE ANOMALY_SCORES (
	SERIES VARIANT,
	TS TIMESTAMP_NTZ(9),
	Y FLOAT,
	FORECAST FLOAT,
	LOWER_BOUND FLOAT,
	UPPER_BOUND FLOAT,
	IS_ANOMALY BOOLEAN,
	PERCENTILE FLOAT,
	DISTANCE FLOAT
);
create or replace TABLE FATIGUE_SCORES (
	ASSET_ID VARCHAR(20),
	TIMESTAMP TIMESTAMP_NTZ(9),
	FATIGUE_SCORE FLOAT,
	FATIGUE_LEVEL VARCHAR(20)
);
create or replace dynamic table LIVE_PREDICTIONS(
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
) target_lag = '2 days' refresh_mode = AUTO initialize = ON_CREATE warehouse = COMPUTE_WH
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
CREATE OR REPLACE PROCEDURE ""ANALYZE_ROOT_CAUSE""(""P_ASSET_ID"" VARCHAR, ""P_CURRENT_VIB_MAG"" FLOAT, ""P_CURRENT_TEMP"" FLOAT, ""P_CURRENT_RPM"" FLOAT, ""P_CURRENT_AMPS"" FLOAT, ""P_FATIGUE_SCORE"" FLOAT, ""P_PREDICTED_FAILURE_MODE"" VARCHAR, ""P_PREDICTED_RUL_HOURS"" FLOAT, ""P_DEGRADATION_STAGE"" NUMBER(38,0))
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
CREATE OR REPLACE PROCEDURE ""ANALYZE_ROOT_CAUSE""(""P_ASSET_ID"" VARCHAR, ""P_VIB_MAG"" FLOAT, ""P_TEMP"" FLOAT, ""P_RPM"" FLOAT, ""P_AMPS"" FLOAT, ""P_FATIGUE"" FLOAT, ""P_FAILURE_MODE"" VARCHAR, ""P_RUL_HOURS"" FLOAT, ""P_STAGE"" VARCHAR)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS OWNER
AS 'BEGIN
    LET asset_ctx VARCHAR := '''';
    LET fleet_ctx VARCHAR := '''';
    
    SELECT ARRAY_TO_STRING(
        ARRAY_AGG(r.value:search_text::VARCHAR), ''\\n''
    ) INTO :asset_ctx
    FROM TABLE(FLATTEN(
        input => PARSE_JSON(
            SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                ''MFGPULSE_DB.ML_MODELS.MAINTENANCE_SEARCH'',
                ''{
                    ""query"": ""'' || :p_failure_mode || '' '' || :p_asset_id || '' failure degradation"",
                    ""columns"": [""search_text"",""asset_id"",""wo_type""],
                    ""filter"": {""@eq"": {""asset_id"": ""'' || :p_asset_id || ''""}},
                    ""limit"": 5
                }''
            )
        )[''results'']
    )) r;

    SELECT ARRAY_TO_STRING(
        ARRAY_AGG(r.value:search_text::VARCHAR), ''\\n''
    ) INTO :fleet_ctx
    FROM TABLE(FLATTEN(
        input => PARSE_JSON(
            SNOWFLAKE.CORTEX.SEARCH_PREVIEW(
                ''MFGPULSE_DB.ML_MODELS.MAINTENANCE_SEARCH'',
                ''{
                    ""query"": ""'' || :p_failure_mode || '' failure root cause repair"",
                    ""columns"": [""search_text"",""asset_id"",""wo_type""],
                    ""limit"": 5
                }''
            )
        )[''results'']
    )) r;

    LET prompt VARCHAR := 
        ''You are an expert reliability engineer. Analyze this asset condition and provide root cause diagnosis.\\n\\n'' ||
        ''## CURRENT STATE:\\n'' ||
        ''- Asset: '' || :p_asset_id || ''\\n'' ||
        ''- Vibration: '' || :p_vib_mag::VARCHAR || '' mm/s\\n'' ||
        ''- Temperature: '' || :p_temp::VARCHAR || '' C\\n'' ||
        ''- RPM: '' || :p_rpm::VARCHAR || ''\\n'' ||
        ''- Current: '' || :p_amps::VARCHAR || '' A\\n'' ||
        ''- Fatigue Score: '' || :p_fatigue::VARCHAR || ''/1.0\\n'' ||
        ''- Predicted Failure: '' || :p_failure_mode || ''\\n'' ||
        ''- Remaining Life: '' || :p_rul_hours::VARCHAR || '' hours\\n'' ||
        ''- Stage: '' || :p_stage || ''\\n\\n'' ||
        ''## MAINTENANCE HISTORY:\\n'' || COALESCE(:asset_ctx, ''None available'') || ''\\n\\n'' ||
        ''## SIMILAR FLEET FAILURES:\\n'' || COALESCE(:fleet_ctx, ''None available'') || ''\\n\\n'' ||
        ''RESPOND IN VALID JSON ONLY. No markdown, no explanation outside JSON:\\n'' ||
        ''{""root_cause"":""<specific mechanical root cause in 1-2 sentences>"",'' ||
        ''""confidence"":<0.0 to 1.0>,'' ||
        ''""failure_mechanism"":""<bearing_wear|thermal_degradation|imbalance|misalignment|unknown>"",'' ||
        ''""evidence"":[""<evidence 1>"",""<evidence 2>"",""<evidence 3>""],'' ||
        ''""risk_level"":""<CRITICAL|HIGH|MEDIUM|LOW>"",'' ||
        ''""recommended_action"":""<specific action with part numbers if applicable>""}'';

    LET llm_response VARCHAR;
    SELECT SNOWFLAKE.CORTEX.COMPLETE(''llama3.1-70b'', :prompt) INTO :llm_response;

    LET result VARIANT;
    SELECT TRY_PARSE_JSON(REGEXP_SUBSTR(:llm_response, ''\\\\{[\\\\s\\\\S]*\\\\}'')) INTO :result;
    
    RETURN :result;
END';
CREATE OR REPLACE FUNCTION ""COMPUTE_FATIGUE_SCORE""(""VIB_CREST_FACTOR_6H"" FLOAT, ""VIB_COEFF_VAR_6H"" FLOAT, ""VIB_PEAK_TO_PEAK_6H"" FLOAT, ""VIB_RATE_OF_CHANGE_1H"" FLOAT, ""VIB_ACCELERATION_1H"" FLOAT, ""ENERGY_BALANCE_RATIO"" FLOAT, ""STRESS_INDEX"" FLOAT, ""VIB_XY_CORRELATION"" FLOAT, ""ACOUSTIC_VIB_RATIO"" FLOAT)
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
CREATE OR REPLACE PROCEDURE ""DEBUG_M7""(""P_ASSET_ID"" VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    LET parts_info VARCHAR := ''None'';
    SELECT COALESCE(ARRAY_TO_STRING(ARRAY_AGG(
        part_name || '' (qty:'' || quantity_on_hand || '', $'' || unit_cost || '')''
    ), ''; ''), ''None'') INTO :parts_info
    FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY
    WHERE ARRAY_CONTAINS(:p_asset_id::VARIANT, compatible_assets);

    LET prompt VARCHAR := CONCAT(
        ''Maintenance AI. Asset '', :p_asset_id, '' has bearing_wear, 72hrs RUL, Critical. Parts:'', :parts_info,
        ''. Reply JSON only no markdown no backticks: {""action"":""x"",""priority"":""EMERGENCY"",""parts_needed"":[""x""],""parts_available"":true,""optimal_window"":""x"",""estimated_repair_cost"":520,""estimated_failure_cost"":12000,""cost_savings"":""x"",""risk_if_delayed"":""x"",""work_order_summary"":""x""}''
    );

    LET llm_response VARCHAR;
    SELECT SNOWFLAKE.CORTEX.COMPLETE(''llama3.1-70b'', :prompt) INTO :llm_response;
    
    LET cleaned VARCHAR;
    SELECT REPLACE(REPLACE(:llm_response, ''```json'', ''''), ''```'', '''') INTO :cleaned;
    
    LET parsed VARIANT;
    SELECT TRY_PARSE_JSON(TRIM(:cleaned)) INTO :parsed;

    RETURN CONCAT(''RAW: '', :llm_response, '' ||| CLEANED: '', :cleaned, '' ||| PARSED_NULL: '', :parsed IS NULL);
END;
';
CREATE OR REPLACE PROCEDURE ""DEBUG_M7_RAW""(""P_ASSET_ID"" VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    LET parts_info VARCHAR := ''None'';
    SELECT COALESCE(ARRAY_TO_STRING(ARRAY_AGG(
        part_name || '' (qty:'' || quantity_on_hand || '', $'' || unit_cost || '')''
    ), ''; ''), ''None'') INTO :parts_info
    FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY
    WHERE ARRAY_CONTAINS(:p_asset_id::VARIANT, compatible_assets);

    LET prompt VARCHAR := CONCAT(
        ''Maintenance AI. Asset '', :p_asset_id, '' has bearing_wear, 72hrs RUL, Critical. Parts:'', :parts_info,
        ''. Reply JSON only no markdown: {""action"":""x"",""priority"":""EMERGENCY"",""parts_needed"":[""x""],""parts_available"":true,""optimal_window"":""x"",""estimated_repair_cost"":520,""estimated_failure_cost"":12000,""cost_savings"":""x"",""risk_if_delayed"":""x"",""work_order_summary"":""x""}''
    );

    LET llm_response VARCHAR;
    SELECT SNOWFLAKE.CORTEX.COMPLETE(''llama3.1-70b'', :prompt) INTO :llm_response;
    
    RETURN :llm_response;
END;
';
CREATE OR REPLACE PROCEDURE ""DEBUG_PRESCRIBE""(""P_ASSET_ID"" VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    LET parts_info VARCHAR := ''No parts data'';
    SELECT COALESCE(ARRAY_TO_STRING(ARRAY_AGG(
        part_name || '' (qty:'' || quantity_on_hand || '')''
    ), ''; ''), ''None'') INTO :parts_info
    FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY
    WHERE ARRAY_CONTAINS(:p_asset_id::VARIANT, compatible_assets);

    LET prompt VARCHAR :=
        ''You are a maintenance AI. Asset:'' || :p_asset_id || '' has bearing_wear, RUL:72hrs, Critical stage. '' ||
        ''Parts available: '' || :parts_info || ''. '' ||
        ''Reply ONLY in this JSON format, no extra text: '' ||
        ''{""action"":""replace bearing"",""priority"":""EMERGENCY"",""parts_needed"":[""SKF 6310""],""estimated_repair_cost"":520,""estimated_failure_cost"":12000,""work_order_summary"":""description""}'';

    LET llm_response VARCHAR;
    SELECT SNOWFLAKE.CORTEX.COMPLETE(''llama3.1-70b'', :prompt) INTO :llm_response;

    RETURN :llm_response;
END;
';
CREATE OR REPLACE PROCEDURE ""DEMO_VALIDATION""()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
DECLARE
    pred_count INTEGER;
    alert_count INTEGER;
    oee_count INTEGER;
    fatigue_count INTEGER;
BEGIN
    SELECT COUNT(*) INTO :pred_count FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS;
    SELECT COUNT(*) INTO :alert_count FROM MFGPULSE_DB.ANALYTICS.ACTIVE_ALERTS;
    SELECT COUNT(*) INTO :oee_count FROM MFGPULSE_DB.ANALYTICS.OEE_METRICS;
    SELECT COUNT(*) INTO :fatigue_count FROM MFGPULSE_DB.ML_MODELS.FATIGUE_SCORES;
    
    RETURN ''DEMO READY | Predictions: '' || :pred_count || '' | Alerts: '' || :alert_count || '' | OEE rows: '' || :oee_count || '' | Fatigue scores: '' || :fatigue_count;
END;
';
CREATE OR REPLACE PROCEDURE ""GENERATE_PRESCRIPTION""(""P_ASSET_ID"" VARCHAR, ""P_FAILURE_MODE"" VARCHAR, ""P_FAILURE_CONFIDENCE"" FLOAT, ""P_RUL_HOURS"" FLOAT, ""P_RUL_LOWER"" FLOAT, ""P_RUL_UPPER"" FLOAT, ""P_DEGRADATION_STAGE"" NUMBER(38,0), ""P_FATIGUE_SCORE"" FLOAT, ""P_ROOT_CAUSE"" VARCHAR, ""P_RISK_LEVEL"" VARCHAR, ""P_SIM_INTERVENTION_DAY"" NUMBER(38,0), ""P_SIM_REPAIR_COST"" FLOAT, ""P_SIM_FAILURE_COST"" FLOAT)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python','numpy')
HANDLER = 'run'
EXECUTE AS CALLER
AS '
import json
import numpy as np

def run(session, p_asset_id, p_failure_mode, p_failure_confidence,
        p_rul_hours, p_rul_lower, p_rul_upper, p_degradation_stage,
        p_fatigue_score, p_root_cause, p_risk_level,
        p_sim_intervention_day, p_sim_repair_cost, p_sim_failure_cost):

    asset_id = str(p_asset_id)

    asset_rows = session.sql(""SELECT asset_name, asset_type, line_id, manufacturer, model_number FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER WHERE asset_id = ''"" + asset_id + ""''"").collect()
    asset = asset_rows[0] if asset_rows else None
    asset_name = str(asset[""ASSET_NAME""]) if asset else asset_id
    asset_type = str(asset[""ASSET_TYPE""]) if asset else ""unknown""
    line_id = str(asset[""LINE_ID""]) if asset else ""unknown""

    parts_rows = session.sql(""SELECT part_id, part_name, quantity_on_hand, lead_time_days, unit_cost FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY WHERE ARRAY_CONTAINS(''"" + asset_id + ""''::VARIANT, compatible_assets) ORDER BY unit_cost DESC"").collect()

    parts_available = []
    parts_needed = []
    total_parts_cost = 0.0
    parts_in_stock = True

    for p in parts_rows:
        part_info = {""part_id"": str(p[""PART_ID""]), ""part_name"": str(p[""PART_NAME""]), ""quantity_on_hand"": int(p[""QUANTITY_ON_HAND""]), ""lead_time_days"": int(p[""LEAD_TIME_DAYS""]), ""unit_cost"": float(p[""UNIT_COST""])}
        parts_available.append(part_info)
        fm = str(p_failure_mode).lower()
        pn = str(p[""PART_NAME""]).lower()
        needed = False
        if fm == ""bearing_wear"" and (""bearing"" in pn or ""seal"" in pn):
            needed = True
        elif fm == ""misalignment"" and (""coupling"" in pn or ""bearing"" in pn):
            needed = True
        elif fm == ""imbalance"" and (""impeller"" in pn or ""blade"" in pn):
            needed = True
        elif fm == ""thermal_degradation"" and (""filter"" in pn or ""separator"" in pn or ""bearing"" in pn):
            needed = True
        if needed:
            parts_needed.append(part_info)
            total_parts_cost += float(p[""UNIT_COST""])
            if int(p[""QUANTITY_ON_HAND""]) == 0:
                parts_in_stock = False

    shift_rows = session.sql(""SELECT shift_id, shift_start, shift_end, operator_name FROM MFGPULSE_DB.RAW_IT.SHIFT_SCHEDULE WHERE line_id = ''"" + line_id + ""'' AND shift_start >= CURRENT_TIMESTAMP() AND shift_start <= DATEADD(day, 7, CURRENT_TIMESTAMP()) ORDER BY shift_start LIMIT 5"").collect()

    optimal_window = None
    if shift_rows:
        for s in shift_rows:
            start_hour = int(str(s[""SHIFT_START""])[11:13]) if len(str(s[""SHIFT_START""])) > 13 else 8
            if 6 <= start_hour <= 14:
                optimal_window = {""shift_id"": str(s[""SHIFT_ID""]), ""start"": str(s[""SHIFT_START""]), ""end"": str(s[""SHIFT_END""]), ""operator"": str(s[""OPERATOR_NAME""])}
                break
        if not optimal_window:
            optimal_window = {""shift_id"": str(shift_rows[0][""SHIFT_ID""]), ""start"": str(shift_rows[0][""SHIFT_START""]), ""end"": str(shift_rows[0][""SHIFT_END""]), ""operator"": str(shift_rows[0][""OPERATOR_NAME""])}

    rul = float(p_rul_hours) if p_rul_hours else 999
    stage = int(p_degradation_stage) if p_degradation_stage else 0
    fatigue = float(p_fatigue_score) if p_fatigue_score else 0

    if stage >= 4 or rul < 24:
        urgency = ""EMERGENCY""
        wo_type = ""emergency""
        action = ""Immediate shutdown and emergency repair required""
    elif stage >= 3 or rul < 72 or str(p_risk_level) == ""CRITICAL"":
        urgency = ""URGENT""
        wo_type = ""corrective""
        action = ""Schedule corrective maintenance within 48 hours""
    elif stage >= 2 or rul < 336 or fatigue > 0.6:
        urgency = ""PLANNED""
        wo_type = ""corrective""
        action = ""Schedule repair during next planned outage window""
    else:
        urgency = ""MONITOR""
        wo_type = ""preventive""
        action = ""Continue monitoring. Add to next PM cycle.""

    labor_hours_map = {""bearing_wear"": {""compressor"": 16, ""centrifugal_pump"": 12, ""electric_motor"": 8, ""default"": 10}, ""misalignment"": {""centrifugal_pump"": 14, ""conveyor_drive"": 10, ""default"": 8}, ""imbalance"": {""centrifugal_pump"": 8, ""axial_fan"": 6, ""default"": 8}, ""thermal_degradation"": {""compressor"": 6, ""electric_motor"": 4, ""default"": 6}}
    fm_map = labor_hours_map.get(str(p_failure_mode), {""default"": 8})
    est_labor_hours = fm_map.get(asset_type, fm_map.get(""default"", 8))
    labor_rate = 100.0
    labor_cost = est_labor_hours * labor_rate

    total_repair_cost = total_parts_cost + labor_cost
    failure_cost = float(p_sim_failure_cost) if p_sim_failure_cost else 50000
    savings = failure_cost - total_repair_cost
    roi = (savings / total_repair_cost * 100) if total_repair_cost > 0 else 0

    work_order = {""wo_type"": wo_type, ""asset_id"": asset_id, ""priority"": urgency, ""status"": ""pending_approval"", ""assigned_to"": optimal_window[""operator""] if optimal_window else ""Unassigned"", ""estimated_labor_hours"": est_labor_hours, ""estimated_parts_cost"": round(total_parts_cost, 2), ""estimated_total_cost"": round(total_repair_cost, 2), ""description"": str(p_failure_mode) + "" detected on "" + asset_name + "". "" + str(p_root_cause) + "". RUL: "" + str(round(rul)) + ""h. Stage: "" + str(stage) + ""/4.""}

    prompt_lines = [""You are a maintenance operations advisor. Generate a concise, actionable maintenance recommendation."", """", ""ASSET: "" + asset_name + "" ("" + asset_type + "") on "" + line_id, ""FAILURE MODE: "" + str(p_failure_mode) + "" (confidence: "" + str(round(float(p_failure_confidence)*100)) + ""%)"", ""ROOT CAUSE: "" + str(p_root_cause), ""RUL: "" + str(round(rul)) + "" hours ("" + str(round(rul/24, 1)) + "" days)"", ""DEGRADATION STAGE: "" + str(stage) + ""/4"", ""RISK LEVEL: "" + str(p_risk_level), ""URGENCY: "" + urgency, """", ""PARTS NEEDED: "" + ("", "".join([p[""part_name""] + "" ($"" + str(p[""unit_cost""]) + "", qty: "" + str(p[""quantity_on_hand""]) + "")"" for p in parts_needed]) if parts_needed else ""None identified""), ""PARTS IN STOCK: "" + (""Yes"" if parts_in_stock else ""No - ORDER IMMEDIATELY""), ""REPAIR COST: $"" + str(round(total_repair_cost)), ""FAILURE COST: $"" + str(round(failure_cost)), ""SAVINGS: $"" + str(round(savings)), """", ""Write a 3-4 sentence recommendation for a plant manager. Include action, timeline, cost justification, and risk if delayed. Plain text only.""]
    prompt = chr(10).join(prompt_lines)
    safe_prompt = prompt.replace(""''"", ""''''"")

    try:
        llm_sql = ""SELECT SNOWFLAKE.CORTEX.COMPLETE(''llama3.3-70b'', ''"" + safe_prompt + ""'') AS response""
        llm_rows = session.sql(llm_sql).collect()
        recommendation_text = str(llm_rows[0][""RESPONSE""]).strip()
    except Exception as e:
        recommendation_text = action + "" "" + str(p_root_cause)

    prescription = {""asset_id"": asset_id, ""asset_name"": asset_name, ""urgency"": urgency, ""action"": action, ""recommendation"": recommendation_text, ""failure_mode"": str(p_failure_mode), ""root_cause"": str(p_root_cause), ""rul_hours"": round(rul, 1), ""degradation_stage"": stage, ""parts_needed"": parts_needed, ""parts_in_stock"": parts_in_stock, ""optimal_maintenance_window"": optimal_window, ""cost_analysis"": {""repair_cost"": round(total_repair_cost, 2), ""failure_cost"": round(failure_cost, 2), ""savings"": round(savings, 2), ""roi_percent"": round(roi, 1)}, ""work_order_payload"": work_order}

    return prescription
';
CREATE OR REPLACE PROCEDURE ""PREDICT_ALL""(""P_ASSET_ID"" VARCHAR)
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
CREATE OR REPLACE FUNCTION ""PREDICT_DEGRADATION_STAGE""(""VIB_RMS_24H"" FLOAT, ""VIB_CREST_FACTOR_6H"" FLOAT, ""STRESS_INDEX"" FLOAT, ""COMPOSITE_HEALTH_SCORE"" FLOAT, ""DEGRADATION_VELOCITY_30D"" FLOAT, ""HOURS_SINCE_FIRST_BREACH"" FLOAT, ""ABOVE_NORMAL_COUNT_24H"" FLOAT)
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
            ) < 0.25 THEN ''Healthy''
            WHEN (LEAST(1.0, GREATEST(0, (vib_rms_24h - 2.5)/10.0)) * 0.25 +
                  LEAST(1.0, GREATEST(0, (vib_crest_factor_6h - 1.2)/1.5)) * 0.15 +
                  LEAST(1.0, stress_index) * 0.15 +
                  LEAST(1.0, GREATEST(0, COALESCE(degradation_velocity_30d, 0)/0.5)) * 0.20 +
                  CASE WHEN hours_since_first_breach IS NULL THEN 0 ELSE LEAST(1.0, hours_since_first_breach/2000.0) END * 0.10 +
                  LEAST(1.0, COALESCE(above_normal_count_24h, 0)/80.0) * 0.15
            ) < 0.55 THEN ''Warning''
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
CREATE OR REPLACE FUNCTION ""PREDICT_FAILURE_MODE""(""VIB_MAG_MEAN_6H"" FLOAT, ""VIB_MAG_STD_6H"" FLOAT, ""VIB_MAG_MAX_6H"" FLOAT, ""VIB_CREST_FACTOR_6H"" FLOAT, ""VIB_PEAK_TO_PEAK_6H"" FLOAT, ""VIB_RMS_6H"" FLOAT, ""VIB_COEFF_VAR_6H"" FLOAT, ""TEMP_MEAN_6H"" FLOAT, ""TEMP_STD_6H"" FLOAT, ""CURRENT_MEAN_6H"" FLOAT, ""CURRENT_STD_6H"" FLOAT, ""VIB_MAG_MEAN_24H"" FLOAT, ""VIB_MAG_STD_24H"" FLOAT, ""VIB_CREST_FACTOR_24H"" FLOAT, ""VIB_RMS_24H"" FLOAT, ""TEMP_MEAN_24H"" FLOAT, ""CURRENT_MEAN_24H"" FLOAT, ""ACOUSTIC_MEAN_24H"" FLOAT, ""VIB_RATE_OF_CHANGE_1H"" FLOAT, ""VIB_ACCELERATION_1H"" FLOAT, ""VIB_XY_CORRELATION"" FLOAT, ""VIB_TEMP_COUPLING"" FLOAT, ""CURRENT_RPM_RATIO"" FLOAT, ""VIB_AXIS_DOMINANCE"" FLOAT, ""ACOUSTIC_VIB_RATIO"" FLOAT, ""STRESS_INDEX"" FLOAT, ""ISO_SEVERITY"" FLOAT, ""COMPOSITE_HEALTH"" FLOAT)
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
CREATE OR REPLACE FUNCTION ""PREDICT_RUL""(""VIB_RMS_24H"" FLOAT, ""VIB_RATE_OF_CHANGE"" FLOAT, ""VIB_ACCELERATION"" FLOAT, ""DEGRADATION_VELOCITY"" FLOAT, ""HOURS_SINCE_BREACH"" FLOAT, ""STRESS_INDEX"" FLOAT, ""COMPOSITE_HEALTH"" FLOAT, ""FATIGUE_SCORE"" FLOAT)
RETURNS OBJECT
LANGUAGE SQL
AS '
    -- Physics-based RUL estimation with confidence intervals (recalibrated)
    -- Uses degradation rate + remaining capacity, with composite fallback to avoid ceiling saturation
    SELECT OBJECT_CONSTRUCT(
        ''predicted_rul_hours'', ROUND(GREATEST(0, LEAST(2000,
            CASE 
                WHEN COALESCE(degradation_velocity, 0) > 0.01 THEN
                    (1.0 - COALESCE(fatigue_score, stress_index)) / (degradation_velocity / 24.0)
                ELSE
                    2000.0 * POWER(1.0 - LEAST(1.0, stress_index * 0.40 + COALESCE(fatigue_score, 0) * 0.35 + composite_health / 400.0 + 0.10), 3.0)
            END
        )), 1),
        ''rul_lower_ci'', ROUND(GREATEST(0, LEAST(2000,
            CASE 
                WHEN COALESCE(degradation_velocity, 0) > 0.01 THEN
                    (1.0 - COALESCE(fatigue_score, stress_index)) / (degradation_velocity * 1.5 / 24.0)
                ELSE
                    2000.0 * POWER(1.0 - LEAST(1.0, stress_index * 0.40 + COALESCE(fatigue_score, 0) * 0.35 + composite_health / 400.0 + 0.10) * 1.15, 3.0)
            END
        )), 1),
        ''rul_upper_ci'', ROUND(GREATEST(0, LEAST(2000,
            CASE 
                WHEN COALESCE(degradation_velocity, 0) > 0.01 THEN
                    (1.0 - COALESCE(fatigue_score, stress_index)) / (degradation_velocity * 0.5 / 24.0)
                ELSE
                    2000.0 * POWER(1.0 - LEAST(1.0, stress_index * 0.40 + COALESCE(fatigue_score, 0) * 0.35 + composite_health / 400.0 + 0.10) * 0.85, 3.0)
            END
        )), 1),
        ''confidence_level'', CASE
            WHEN COALESCE(degradation_velocity, 0) > 0.1 THEN ''HIGH''
            WHEN COALESCE(degradation_velocity, 0) > 0.01 THEN ''MEDIUM''
            ELSE ''LOW''
        END
    )
';
CREATE OR REPLACE PROCEDURE ""PRESCRIBE_MAINTENANCE""(""P_ASSET_ID"" VARCHAR, ""P_FAILURE_MODE"" VARCHAR, ""P_RUL_HOURS"" FLOAT, ""P_STAGE"" VARCHAR, ""P_FATIGUE_SCORE"" FLOAT, ""P_ROOT_CAUSE"" VARCHAR, ""P_SIM_RESULT"" VARCHAR)
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
CREATE OR REPLACE PROCEDURE ""RETRAIN_DEGRADATION_STAGER_3CLASS""()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python','snowflake-ml-python','xgboost','scikit-learn','pandas','numpy')
HANDLER = 'train'
EXECUTE AS CALLER
AS '
def train(session):
    import pandas as pd
    import numpy as np
    from xgboost import XGBClassifier
    from sklearn.metrics import classification_report, f1_score
    from snowflake.ml.registry import Registry
    from snowflake.ml.model import custom_model
    import os

    session.sql(""USE DATABASE MFGPULSE_DB"").collect()
    session.sql(""USE SCHEMA ML_MODELS"").collect()

    df = session.table(""MFGPULSE_DB.ML_FEATURES.TRAIN_TRAJECTORY_3CLASS"").to_pandas()

    exclude = [''ASSET_ID'',''TIMESTAMP'',''FAILURE_MODE'',''ORIGINAL_STAGE'',''STAGE_3CLASS'']
    feat_cols = [c for c in df.columns if c not in exclude]
    df[feat_cols] = df[feat_cols].replace([np.inf, -np.inf], np.nan).fillna(0)

    df = df.sort_values(''TIMESTAMP'').reset_index(drop=True)
    split = int(len(df) * 0.8)
    X_train, X_test = df.iloc[:split][feat_cols].values, df.iloc[split:][feat_cols].values
    y_train, y_test = df.iloc[:split][''STAGE_3CLASS''].values, df.iloc[split:][''STAGE_3CLASS''].values

    # Aggressive weights for rare Warning class
    weights = {0: 0.5, 1: 5.0, 2: 2.0}
    sample_w = np.array([weights[s] for s in y_train])

    model = XGBClassifier(
        n_estimators=300, max_depth=5, learning_rate=0.08,
        objective=''multi:softprob'', num_class=3,
        reg_alpha=0.1, reg_lambda=1.0, min_child_weight=3,
        random_state=42, n_jobs=-1
    )
    model.fit(X_train, y_train, sample_weight=sample_w, eval_set=[(X_test, y_test)], verbose=False)

    y_pred = model.predict(X_test)
    f1 = f1_score(y_test, y_pred, average=''macro'')
    report = classification_report(y_test, y_pred, target_names=[''Healthy'',''Warning'',''Critical''])

    # Save model artifact
    model_path = ""/tmp/stager_3class.json""
    model.save_model(model_path)

    class Stager3Class(custom_model.CustomModel):
        def __init__(self, context):
            super().__init__(context)
        @custom_model.inference_api
        def predict(self, input_df: pd.DataFrame) -> pd.DataFrame:
            import numpy as np, xgboost as xgb
            xgb_model = xgb.XGBClassifier()
            xgb_model.load_model(self.context.path(""xgb_model""))
            exclude = {''ASSET_ID'',''TIMESTAMP'',''FAILURE_MODE'',''DEGRADATION_STAGE'',''ORIGINAL_STAGE'',''STAGE_3CLASS''}
            cols = [c for c in input_df.columns if c not in exclude]
            X = input_df[cols].replace([np.inf, -np.inf], np.nan).fillna(0).values
            preds = xgb_model.predict(X)
            proba = xgb_model.predict_proba(X)
            labels = [''Healthy'',''Warning'',''Critical'']
            transition = []
            for i in range(len(preds)):
                s = int(preds[i])
                transition.append(0.0 if s >= 2 else float(proba[i, s+1:].sum()))
            return pd.DataFrame({
                ''PREDICTED_STAGE'': [labels[p] for p in preds],
                ''STAGE_CONFIDENCE'': proba.max(axis=1).round(4),
                ''TRANSITION_PROBABILITY'': np.round(transition, 4),
                ''PROB_HEALTHY'': proba[:, 0].round(4),
                ''PROB_WARNING'': proba[:, 1].round(4),
                ''PROB_CRITICAL'': proba[:, 2].round(4)
            })

    reg = Registry(session=session, database_name=""MFGPULSE_DB"", schema_name=""ML_MODELS"")
    try:
        reg.delete_model(""DEGRADATION_STAGER"")
    except:
        pass

    stager = Stager3Class(context=custom_model.ModelContext(artifacts={""xgb_model"": model_path}))
    sample = pd.DataFrame(np.zeros((1, len(feat_cols))), columns=feat_cols)

    reg.log_model(
        stager, model_name=""DEGRADATION_STAGER"", version_name=""V2"",
        metrics={""f1_macro"": float(f1)},
        sample_input_data=sample,
        target_platforms=[""WAREHOUSE""],
        comment=f""3-class stager (Healthy/Warning/Critical). F1={f1:.4f}""
    )
    return f""SUCCESS | F1 Macro: {f1:.4f}\\n{report}""
';
CREATE OR REPLACE FUNCTION ""SIMULATE_FAILURE_TWIN""(""CURRENT_VIB_MAG"" FLOAT, ""DEGRADATION_VELOCITY"" FLOAT, ""CURRENT_FATIGUE_SCORE"" FLOAT, ""LOAD_REDUCTION_PCT"" FLOAT, ""MAINTENANCE_DELAY_DAYS"" FLOAT, ""RPM_ADJUSTMENT_PCT"" FLOAT)
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
CREATE OR REPLACE PROCEDURE ""SIMULATE_FAILURE_TWIN""(""P_ASSET_ID"" VARCHAR, ""P_CURRENT_VIB_MAG"" FLOAT, ""P_CURRENT_TEMP"" FLOAT, ""P_DEGRADATION_VELOCITY"" FLOAT, ""P_CURRENT_RUL_HOURS"" FLOAT, ""P_LOAD_REDUCTION_PCT"" FLOAT, ""P_MAINTENANCE_DELAY_DAYS"" FLOAT, ""P_RPM_ADJUSTMENT_PCT"" FLOAT)
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python','numpy')
HANDLER = 'run'
EXECUTE AS CALLER
AS '
import numpy as np
import json

def run(session, p_asset_id, p_current_vib_mag, p_current_temp,
        p_degradation_velocity, p_current_rul_hours,
        p_load_reduction_pct, p_maintenance_delay_days, p_rpm_adjustment_pct):

    np.random.seed(42)
    N_SIMS = 1000
    HORIZON_DAYS = 30
    HOURS_PER_DAY = 24

    # Base degradation rate (mm/s per hour)
    base_rate = float(p_degradation_velocity) / HOURS_PER_DAY if p_degradation_velocity else 0.01

    # Adjust degradation rate based on scenario parameters
    load_factor = 1.0 - (float(p_load_reduction_pct) / 100.0) * 0.6
    rpm_factor = 1.0 + (float(p_rpm_adjustment_pct) / 100.0) * 0.8
    adjusted_rate = base_rate * load_factor * rpm_factor

    # Failure threshold (ISO 10816 unacceptable = 18 mm/s)
    FAILURE_THRESHOLD = 18.0
    current_vib = float(p_current_vib_mag)

    # Monte Carlo simulation
    failure_times = []
    daily_failure_probs = [0.0] * HORIZON_DAYS
    daily_vib_mean = [0.0] * HORIZON_DAYS
    daily_vib_p10 = [0.0] * HORIZON_DAYS
    daily_vib_p90 = [0.0] * HORIZON_DAYS

    all_trajectories = np.zeros((N_SIMS, HORIZON_DAYS))

    for sim in range(N_SIMS):
        vib = current_vib
        failed = False
        for day in range(HORIZON_DAYS):
            # Stochastic degradation: base rate + noise + occasional spikes
            daily_noise = np.random.normal(0, adjusted_rate * 0.3)
            spike = np.random.exponential(adjusted_rate * 2) if np.random.random() < 0.05 else 0
            vib += (adjusted_rate * HOURS_PER_DAY) + daily_noise + spike
            vib = max(vib, current_vib * 0.8)  # can''t go much below current

            all_trajectories[sim, day] = vib

            if vib >= FAILURE_THRESHOLD and not failed:
                failure_times.append(day)
                failed = True

        if not failed:
            failure_times.append(HORIZON_DAYS + 1)

    failure_times = np.array(failure_times)

    # Compute daily statistics
    for day in range(HORIZON_DAYS):
        daily_vib_mean[day] = round(float(np.mean(all_trajectories[:, day])), 2)
        daily_vib_p10[day] = round(float(np.percentile(all_trajectories[:, day], 10)), 2)
        daily_vib_p90[day] = round(float(np.percentile(all_trajectories[:, day], 90)), 2)
        daily_failure_probs[day] = round(float(np.mean(failure_times <= day)), 4)

    # RUL distribution statistics
    median_rul = float(np.median(failure_times)) * HOURS_PER_DAY
    p10_rul = float(np.percentile(failure_times, 10)) * HOURS_PER_DAY
    p90_rul = float(np.percentile(failure_times, 90)) * HOURS_PER_DAY

    # Optimal intervention window
    # Find the day where P(failure) crosses 20% — repair before this
    intervention_day = HORIZON_DAYS
    for day in range(HORIZON_DAYS):
        if daily_failure_probs[day] >= 0.20:
            intervention_day = day
            break

    # Cost analysis
    REPAIR_COST = 2500.0
    FAILURE_COST_PER_HOUR = 12000.0
    AVG_DOWNTIME_HOURS = 48.0

    cost_if_repair_now = REPAIR_COST
    cost_if_failure = FAILURE_COST_PER_HOUR * AVG_DOWNTIME_HOURS + REPAIR_COST * 2.5

    # Delay cost: probability of failure during delay * failure cost
    delay_days = int(float(p_maintenance_delay_days))
    prob_failure_during_delay = daily_failure_probs[min(delay_days, HORIZON_DAYS - 1)] if delay_days > 0 else 0
    expected_cost_if_delayed = prob_failure_during_delay * cost_if_failure + (1 - prob_failure_during_delay) * REPAIR_COST

    result = {
        ""asset_id"": str(p_asset_id),
        ""scenario"": {
            ""load_reduction_pct"": float(p_load_reduction_pct),
            ""maintenance_delay_days"": float(p_maintenance_delay_days),
            ""rpm_adjustment_pct"": float(p_rpm_adjustment_pct)
        },
        ""rul_distribution"": {
            ""median_hours"": round(median_rul, 1),
            ""p10_hours"": round(p10_rul, 1),
            ""p90_hours"": round(p90_rul, 1),
            ""simulations"": N_SIMS
        },
        ""failure_probability_by_day"": daily_failure_probs,
        ""vibration_forecast"": {
            ""mean"": daily_vib_mean,
            ""p10"": daily_vib_p10,
            ""p90"": daily_vib_p90
        },
        ""intervention_window"": {
            ""recommended_day"": intervention_day,
            ""recommended_hours"": intervention_day * HOURS_PER_DAY,
            ""rationale"": f""P(failure) reaches 20% at day {intervention_day}""
        },
        ""cost_analysis"": {
            ""repair_now_cost"": cost_if_repair_now,
            ""expected_failure_cost"": round(cost_if_failure, 0),
            ""expected_cost_if_delayed"": round(expected_cost_if_delayed, 0),
            ""savings_from_early_action"": round(cost_if_failure - cost_if_repair_now, 0),
            ""delay_risk_multiplier"": round(expected_cost_if_delayed / cost_if_repair_now, 2) if cost_if_repair_now > 0 else 0
        }
    }

    return result
';
CREATE OR REPLACE PROCEDURE ""TEST_COMPLETE""()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS '
BEGIN
    LET response VARCHAR;
    SELECT SNOWFLAKE.CORTEX.COMPLETE(''llama3.1-70b'', ''Say hello in JSON: {""greeting"":""x""}'') INTO :response;
    RETURN :response;
END;
';
CREATE OR REPLACE PROCEDURE ""TRAIN_DEGRADATION_STAGER""()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python','snowflake-ml-python==1.9.2','scikit-learn','pandas','numpy','xgboost','joblib')
HANDLER = 'train_model'
EXECUTE AS CALLER
AS '
import pandas as pd
import numpy as np
from snowflake.snowpark import Session
from snowflake.ml.registry import Registry
from snowflake.ml.model import custom_model
from xgboost import XGBClassifier
from sklearn.metrics import f1_score, accuracy_score
import joblib, tempfile, os

class DegradationStagerModel(custom_model.CustomModel):
    def __init__(self, context: custom_model.ModelContext) -> None:
        super().__init__(context)
        self.model = joblib.load(context.path(""model.joblib""))
    
    @custom_model.inference_api
    def predict(self, input_df: pd.DataFrame) -> pd.DataFrame:
        predictions = self.model.predict(input_df.values)
        probas = self.model.predict_proba(input_df.values)
        return pd.DataFrame({
            ""PREDICTED_STAGE"": predictions.astype(int),
            ""STAGE_CONFIDENCE"": probas.max(axis=1)
        })

def train_model(session: Session) -> dict:
    session.sql(""USE DATABASE MFGPULSE_DB"").collect()
    session.sql(""USE SCHEMA ML_MODELS"").collect()
    
    df = session.table(""MFGPULSE_DB.ML_FEATURES.TRAIN_TRAJECTORY"").to_pandas()
    
    feature_cols = [c for c in df.columns if c not in 
                    [''ASSET_ID'', ''TIMESTAMP'', ''DEGRADATION_STAGE'', ''FAILURE_MODE'']]
    
    df[feature_cols] = df[feature_cols].fillna(0)
    
    df[''TIMESTAMP''] = pd.to_datetime(df[''TIMESTAMP''])
    train = df[df[''TIMESTAMP''] < ''2024-05-15'']
    test = df[df[''TIMESTAMP''] >= ''2024-05-15'']
    
    X_train, y_train = train[feature_cols].values, train[''DEGRADATION_STAGE''].values
    X_test, y_test = test[feature_cols].values, test[''DEGRADATION_STAGE''].values
    
    # XGBoost ordinal-aware classifier
    # Use sample weights to oversample rare stages (3, 4)
    sample_weights = np.ones(len(y_train))
    sample_weights[y_train == 3] = 3.0
    sample_weights[y_train == 4] = 5.0
    
    model = XGBClassifier(
        n_estimators=200, max_depth=6, learning_rate=0.1,
        objective=''multi:softprob'', num_class=5,
        eval_metric=''mlogloss''
    )
    model.fit(X_train, y_train, sample_weight=sample_weights)
    
    y_pred = model.predict(X_test)
    f1 = f1_score(y_test, y_pred, average=''macro'')
    acc = accuracy_score(y_test, y_pred)
    
    # Save and register
    tmpdir = tempfile.mkdtemp()
    model_path = os.path.join(tmpdir, ""model.joblib"")
    joblib.dump(model, model_path)
    
    reg = Registry(session=session, database_name=""MFGPULSE_DB"", schema_name=""ML_MODELS"")
    mc = custom_model.ModelContext(models={}, artifacts={""model.joblib"": model_path})
    custom = DegradationStagerModel(mc)
    
    sample_input = train[feature_cols].head(10)
    mv = reg.log_model(
        model_name=""DEGRADATION_STAGER"",
        version_name=""v1"",
        model=custom,
        sample_input_data=sample_input,
        comment=f""XGBoost 5-stage degradation. F1-macro: {f1:.4f}, Acc: {acc:.4f}""
    )
    
    return {
        ""status"": ""success"",
        ""model"": ""DEGRADATION_STAGER"",
        ""f1_macro"": round(float(f1), 4),
        ""accuracy"": round(float(acc), 4),
        ""train_samples"": len(train),
        ""test_samples"": len(test)
    }
';
CREATE OR REPLACE PROCEDURE ""TRAIN_FAILURE_MODE_CLASSIFIER""()
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python','snowflake-ml-python','xgboost','scikit-learn','pandas','numpy','joblib')
HANDLER = 'train_model'
EXECUTE AS CALLER
AS '
def train_model(session):
    import pandas as pd
    import numpy as np
    from xgboost import XGBClassifier
    from sklearn.preprocessing import LabelEncoder
    from sklearn.metrics import classification_report, f1_score
    from snowflake.ml.registry import Registry
    
    session.sql(""USE DATABASE MFGPULSE_DB"").collect()
    session.sql(""USE SCHEMA ML_MODELS"").collect()
    
    # Load training data
    df = session.table(""MFGPULSE_DB.ML_FEATURES.TRAIN_FAILURE_MODE"").to_pandas()
    
    if len(df) == 0:
        return ""ERROR: No training data available.""
    
    # Feature columns
    exclude_cols = [''ASSET_ID'', ''TIMESTAMP'', ''FAILURE_MODE'', ''DEGRADATION_STAGE'']
    feature_cols = [c for c in df.columns if c not in exclude_cols]
    
    # Handle nulls and infinities
    df[feature_cols] = df[feature_cols].replace([np.inf, -np.inf], np.nan).fillna(0)
    
    # Encode target
    le = LabelEncoder()
    df[''FAILURE_MODE_ENCODED''] = le.fit_transform(df[''FAILURE_MODE''])
    
    # Time-based split
    df = df.sort_values(''TIMESTAMP'')
    split_idx = int(len(df) * 0.8)
    
    X_train = df.iloc[:split_idx][feature_cols].values
    y_train = df.iloc[:split_idx][''FAILURE_MODE_ENCODED''].values
    X_test = df.iloc[split_idx:][feature_cols].values
    y_test = df.iloc[split_idx:][''FAILURE_MODE_ENCODED''].values
    
    # Train XGBoost natively
    model = XGBClassifier(
        n_estimators=200,
        max_depth=6,
        learning_rate=0.1,
        objective=''multi:softprob'',
        num_class=len(le.classes_),
        eval_metric=''mlogloss'',
        random_state=42
    )
    model.fit(X_train, y_train)
    
    # Evaluate
    y_pred = model.predict(X_test)
    f1 = f1_score(y_test, y_pred, average=''macro'')
    report = classification_report(y_test, y_pred, target_names=le.classes_)
    
    # Create a wrapper class for the registry
    from snowflake.ml.model import custom_model
    
    class FailureModeModel(custom_model.CustomModel):
        def __init__(self, context):
            super().__init__(context)
            self.model = model
            self.label_encoder = le
            self.feature_cols = feature_cols
            
        @custom_model.inference_api
        def predict(self, input_df: pd.DataFrame) -> pd.DataFrame:
            # Use only feature columns that exist
            cols = [c for c in self.feature_cols if c in input_df.columns]
            X = input_df[cols].replace([np.inf, -np.inf], np.nan).fillna(0).values
            preds = self.model.predict(X)
            proba = self.model.predict_proba(X)
            result = pd.DataFrame({
                ''PREDICTED_FAILURE_MODE'': self.label_encoder.inverse_transform(preds),
                ''CONFIDENCE'': proba.max(axis=1)
            })
            return result
    
    # Register
    reg = Registry(session=session, database_name=""MFGPULSE_DB"", schema_name=""ML_MODELS"")
    
    fm_model = FailureModeModel(custom_model.ModelContext())
    
    # Create sample input
    sample_input = pd.DataFrame(
        np.zeros((1, len(feature_cols))), 
        columns=feature_cols
    )
    
    mv = reg.log_model(
        fm_model,
        model_name=""FAILURE_MODE_CLASSIFIER"",
        version_name=""V1"",
        metrics={""f1_macro"": float(f1), ""train_size"": int(len(X_train)), ""test_size"": int(len(X_test))},
        sample_input_data=sample_input,
        comment=f""XGBoost 5-class failure mode classifier. F1={f1:.4f}""
    )
    
    return f""SUCCESS | F1 Macro: {f1:.4f} | Train: {len(X_train)} | Test: {len(X_test)}\\n\\n{report}""
';
CREATE OR REPLACE PROCEDURE ""TRAIN_RUL_ESTIMATOR""()
RETURNS VARIANT
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
ARTIFACT_REPOSITORY = snowflake.snowpark.pypi_shared_repository
PACKAGES = ('snowflake-snowpark-python','snowflake-ml-python==1.9.2','scikit-learn','pandas','numpy','xgboost','joblib')
HANDLER = 'train_model'
EXECUTE AS CALLER
AS '
import pandas as pd
import numpy as np
from snowflake.snowpark import Session
from snowflake.ml.registry import Registry
from snowflake.ml.model import custom_model
from xgboost import XGBRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error
import joblib, tempfile, os

class RULModel(custom_model.CustomModel):
    def __init__(self, context: custom_model.ModelContext) -> None:
        super().__init__(context)
        self.model = joblib.load(context.path(""model.joblib""))
    
    @custom_model.inference_api
    def predict(self, input_df: pd.DataFrame) -> pd.DataFrame:
        predictions = self.model.predict(input_df.values)
        # Clamp to non-negative
        predictions = np.maximum(predictions, 0)
        return pd.DataFrame({""PREDICTED_RUL_HOURS"": predictions})

def train_model(session: Session) -> dict:
    session.sql(""USE DATABASE MFGPULSE_DB"").collect()
    session.sql(""USE SCHEMA ML_MODELS"").collect()
    
    df = session.table(""MFGPULSE_DB.ML_FEATURES.TRAIN_RUL"").to_pandas()
    
    feature_cols = [c for c in df.columns if c not in 
                    [''ASSET_ID'', ''TIMESTAMP'', ''HOURS_TO_FAILURE'', ''FAILURE_MODE'', ''DEGRADATION_STAGE'']]
    
    df[feature_cols] = df[feature_cols].fillna(0)
    
    # Time-based split
    df[''TIMESTAMP''] = pd.to_datetime(df[''TIMESTAMP''])
    train = df[df[''TIMESTAMP''] < ''2024-05-15'']
    test = df[df[''TIMESTAMP''] >= ''2024-05-15'']
    
    X_train, y_train = train[feature_cols].values, train[''HOURS_TO_FAILURE''].values
    X_test, y_test = test[feature_cols].values, test[''HOURS_TO_FAILURE''].values
    
    # Train Gradient Boosted Regressor
    model = XGBRegressor(
        n_estimators=300, max_depth=7, learning_rate=0.08,
        objective=''reg:squarederror'', eval_metric=''mae''
    )
    model.fit(X_train, y_train)
    
    y_pred = model.predict(X_test)
    y_pred = np.maximum(y_pred, 0)
    
    mae = mean_absolute_error(y_test, y_pred)
    rmse = np.sqrt(mean_squared_error(y_test, y_pred))
    
    # Save and register
    tmpdir = tempfile.mkdtemp()
    model_path = os.path.join(tmpdir, ""model.joblib"")
    joblib.dump(model, model_path)
    
    reg = Registry(session=session, database_name=""MFGPULSE_DB"", schema_name=""ML_MODELS"")
    
    mc = custom_model.ModelContext(
        models={}, artifacts={""model.joblib"": model_path}
    )
    custom = RULModel(mc)
    
    sample_input = train[feature_cols].head(10)
    
    mv = reg.log_model(
        model_name=""RUL_ESTIMATOR"",
        version_name=""v1"",
        model=custom,
        sample_input_data=sample_input,
        comment=f""XGBoost RUL regressor. MAE: {mae:.1f}hrs, RMSE: {rmse:.1f}hrs""
    )
    
    return {
        ""status"": ""success"",
        ""model"": ""RUL_ESTIMATOR"",
        ""mae_hours"": round(float(mae), 1),
        ""rmse_hours"": round(float(rmse), 1),
        ""train_samples"": len(train),
        ""test_samples"": len(test)
    }
';
create or replace cortex search service MAINTENANCE_SEARCH
	ON SEARCH_TEXT
	attributes ASSET_ID,WO_TYPE,PRIORITY
	warehouse='COMPUTE_WH'
	target_lag='2 days'
	refresh_mode=INCREMENTAL
	as (
    SELECT 
        ml.log_id AS doc_id,
        ml.asset_id,
        ml.notes_text || ' | Work Order: ' || wo.wo_type || ' | Priority: ' || wo.priority || 
        ' | Asset: ' || am.asset_name || ' (' || am.asset_type || ')' ||
        ' | Date: ' || TO_CHAR(ml.timestamp, 'YYYY-MM-DD') AS search_text,
        wo.wo_type,
        wo.priority,
        ml.timestamp AS log_date
    FROM MFGPULSE_DB.RAW_IT.MAINTENANCE_LOGS ml
    JOIN MFGPULSE_DB.RAW_IT.WORK_ORDERS wo ON ml.wo_id = wo.wo_id
    JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON ml.asset_id = am.asset_id
);
create or replace schema PUBLIC;

create or replace schema RAW_IT;

create or replace TABLE MAINTENANCE_LOGS (
	LOG_ID VARCHAR(20) NOT NULL,
	WO_ID VARCHAR(20),
	ASSET_ID VARCHAR(20) NOT NULL,
	TIMESTAMP TIMESTAMP_NTZ(9) NOT NULL,
	TECHNICIAN VARCHAR(100),
	NOTES_TEXT VARCHAR(2000),
	primary key (LOG_ID)
);
create or replace TABLE PARTS_INVENTORY (
	PART_ID VARCHAR(20) NOT NULL,
	PART_NAME VARCHAR(200) NOT NULL,
	COMPATIBLE_ASSETS ARRAY,
	QUANTITY_ON_HAND NUMBER(38,0),
	LEAD_TIME_DAYS NUMBER(38,0),
	UNIT_COST FLOAT,
	primary key (PART_ID)
);
create or replace TABLE PRODUCTION_OUTPUT (
	RECORD_ID VARCHAR(20) NOT NULL,
	ASSET_ID VARCHAR(20) NOT NULL,
	SHIFT_ID VARCHAR(20),
	TIMESTAMP TIMESTAMP_NTZ(9) NOT NULL,
	UNITS_PRODUCED NUMBER(38,0),
	GOOD_UNITS NUMBER(38,0),
	IDEAL_CYCLE_TIME_SEC FLOAT,
	primary key (RECORD_ID)
);
create or replace TABLE SHIFT_SCHEDULE (
	SHIFT_ID VARCHAR(20) NOT NULL,
	LINE_ID VARCHAR(20) NOT NULL,
	SHIFT_START TIMESTAMP_NTZ(9) NOT NULL,
	SHIFT_END TIMESTAMP_NTZ(9) NOT NULL,
	OPERATOR_NAME VARCHAR(100),
	PLANNED_PRODUCTION_TIME_MINS NUMBER(38,0),
	primary key (SHIFT_ID)
);
create or replace TABLE WORK_ORDERS (
	WO_ID VARCHAR(50) NOT NULL,
	ASSET_ID VARCHAR(20) NOT NULL,
	WO_TYPE VARCHAR(20) NOT NULL,
	CREATED_DATE TIMESTAMP_NTZ(9) NOT NULL,
	COMPLETED_DATE TIMESTAMP_NTZ(9),
	PRIORITY VARCHAR(10),
	STATUS VARCHAR(20),
	ASSIGNED_TO VARCHAR(100),
	LABOR_HOURS FLOAT,
	PARTS_COST FLOAT,
	TOTAL_COST FLOAT,
	primary key (WO_ID)
);
create or replace stream MAINTENANCE_LOGS_STREAM on table MAINTENANCE_LOGS append_only = true;
create or replace stream WORK_ORDERS_STREAM on table WORK_ORDERS;
create or replace task SIMULATE_PRODUCTION
	warehouse=COMPUTE_WH
	schedule='720 MINUTE'
	SUSPEND_TASK_AFTER_NUM_FAILURES=1
	as INSERT INTO MFGPULSE_DB.RAW_IT.PRODUCTION_OUTPUT 
(record_id, asset_id, shift_id, timestamp, units_produced, good_units, ideal_cycle_time_sec)
WITH asset_lines AS (
    SELECT asset_id, line_id FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER
    WHERE asset_type IN ('compressor', 'centrifugal_pump', 'electric_motor', 'conveyor_drive')
)
SELECT 
    'P' || RIGHT(al.asset_id,3) || TO_CHAR(CURRENT_DATE(),'MMDD') || '1' AS record_id,
    al.asset_id,
    'S' || RIGHT(al.line_id,2) || TO_CHAR(CURRENT_DATE(),'MMDD') || '1' AS shift_id,
    CURRENT_TIMESTAMP() AS timestamp,
    ROUND(UNIFORM(120::FLOAT, 180::FLOAT, RANDOM()))::INTEGER AS units_produced,
    ROUND(UNIFORM(110::FLOAT, 175::FLOAT, RANDOM()))::INTEGER AS good_units,
    2.5 AS ideal_cycle_time_sec
FROM asset_lines al;
create or replace schema RAW_OT;

create or replace TABLE ASSET_MASTER (
	ASSET_ID VARCHAR(20) NOT NULL,
	ASSET_NAME VARCHAR(100) NOT NULL,
	ASSET_TYPE VARCHAR(50) NOT NULL,
	LINE_ID VARCHAR(20) NOT NULL,
	INSTALL_DATE DATE,
	MANUFACTURER VARCHAR(100),
	MODEL_NUMBER VARCHAR(50),
	RATED_RPM FLOAT,
	RATED_TEMP_MAX FLOAT,
	primary key (ASSET_ID)
);
create or replace TABLE SENSOR_METADATA (
	SENSOR_ID VARCHAR(30) NOT NULL,
	ASSET_ID VARCHAR(20) NOT NULL,
	SENSOR_TYPE VARCHAR(50) NOT NULL,
	LOCATION VARCHAR(100),
	CALIBRATION_DATE DATE,
	SAMPLING_RATE_HZ FLOAT,
	primary key (SENSOR_ID)
);
create or replace TABLE SENSOR_READINGS (
	READING_ID NUMBER(38,0) autoincrement start 1 increment 1 noorder,
	ASSET_ID VARCHAR(20) NOT NULL,
	TIMESTAMP TIMESTAMP_NTZ(9) NOT NULL,
	VIBRATION_X FLOAT,
	VIBRATION_Y FLOAT,
	VIBRATION_Z FLOAT,
	TEMPERATURE FLOAT,
	RPM FLOAT,
	PRESSURE FLOAT,
	CURRENT_AMPS FLOAT,
	ACOUSTIC_DB FLOAT,
	INGESTION_TS TIMESTAMP_NTZ(9) DEFAULT CURRENT_TIMESTAMP()
);
CREATE OR REPLACE PROCEDURE ""GENERATE_SENSOR_DATA""()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS OWNER
AS '
DECLARE
    start_date DATE := ''2024-01-01'';
    end_date DATE := ''2024-06-28'';
    row_count INTEGER := 0;
BEGIN
    -- Generate sensor readings for all 10 assets, ~4 readings per hour (every 15 min) for 180 days
    -- Each asset has assigned failure mode:
    -- ASSET_001: bearing_wear (gradual vibration increase + high-freq spike)
    -- ASSET_002: thermal_degradation (slow temp climb + efficiency drop)
    -- ASSET_003: imbalance (RPM fluctuation + vibration in Y-axis)
    -- ASSET_004: misalignment (multi-axis vibration + current spike)
    -- ASSET_005: bearing_wear (second instance, different timeline)
    -- ASSET_006: thermal_degradation (second instance)
    -- ASSET_007: healthy (control asset - no failure)
    -- ASSET_008: imbalance (develops late)
    -- ASSET_009: misalignment (develops early)
    -- ASSET_010: healthy (control asset - no failure)

    INSERT INTO MFGPULSE_DB.RAW_OT.SENSOR_READINGS 
        (asset_id, timestamp, vibration_x, vibration_y, vibration_z, temperature, rpm, pressure, current_amps, acoustic_db)
    WITH time_series AS (
        SELECT DATEADD(''minute'', seq4() * 15, :start_date::TIMESTAMP_NTZ) AS ts
        FROM TABLE(GENERATOR(ROWCOUNT => 17280))  -- 180 days * 96 readings/day
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
            END AS failure_mode,
            CASE asset_id
                WHEN ''ASSET_001'' THEN 0.55
                WHEN ''ASSET_002'' THEN 0.60
                WHEN ''ASSET_003'' THEN 0.50
                WHEN ''ASSET_004'' THEN 0.45
                WHEN ''ASSET_005'' THEN 0.65
                WHEN ''ASSET_006'' THEN 0.70
                WHEN ''ASSET_007'' THEN 1.0
                WHEN ''ASSET_008'' THEN 0.75
                WHEN ''ASSET_009'' THEN 0.40
                WHEN ''ASSET_010'' THEN 1.0
            END AS failure_start_pct  -- when degradation begins (% of timeline)
        FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER
    ),
    combined AS (
        SELECT 
            a.asset_id,
            t.ts,
            a.rated_rpm,
            a.rated_temp_max,
            a.failure_mode,
            a.failure_start_pct,
            -- Progress through timeline (0 to 1)
            DATEDIFF(''minute'', :start_date::TIMESTAMP_NTZ, t.ts) / 
                DATEDIFF(''minute'', :start_date::TIMESTAMP_NTZ, :end_date::TIMESTAMP_NTZ)::FLOAT AS timeline_pct,
            -- Degradation progress (0 before start, ramps 0->1 after start)
            GREATEST(0, 
                (DATEDIFF(''minute'', :start_date::TIMESTAMP_NTZ, t.ts) / 
                 DATEDIFF(''minute'', :start_date::TIMESTAMP_NTZ, :end_date::TIMESTAMP_NTZ)::FLOAT 
                 - a.failure_start_pct) / (1 - a.failure_start_pct)
            ) AS degradation_pct,
            -- Random noise components
            UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS noise1,
            UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS noise2,
            UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS noise3,
            UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS missing_rnd,
            -- Simulate sensor drift (slow offset that accumulates)
            SIN(DATEDIFF(''hour'', :start_date::TIMESTAMP_NTZ, t.ts) / 500.0) * 0.3 AS sensor_drift
        FROM time_series t
        CROSS JOIN assets a
    )
    SELECT 
        asset_id,
        ts,
        -- VIBRATION X
        CASE 
            WHEN missing_rnd < 0.002 THEN NULL  -- 0.2% missing data
            WHEN failure_mode = ''bearing_wear'' THEN
                2.0 + noise1 * 0.5 + sensor_drift +
                degradation_pct * 8.0 * (1 + degradation_pct) +  -- exponential ramp
                CASE WHEN degradation_pct > 0.8 THEN ABS(noise2) * 15.0 ELSE 0 END  -- spike near failure
            WHEN failure_mode = ''misalignment'' THEN
                2.5 + noise1 * 0.4 + sensor_drift +
                degradation_pct * 5.0 +
                degradation_pct * SIN(timeline_pct * 200) * 3.0  -- periodic multi-axis
            WHEN failure_mode = ''imbalance'' THEN
                1.8 + noise1 * 0.3 + sensor_drift +
                degradation_pct * 2.0  -- mild X increase
            ELSE  -- healthy / thermal
                1.5 + noise1 * 0.4 + sensor_drift
        END AS vibration_x,
        
        -- VIBRATION Y
        CASE 
            WHEN missing_rnd < 0.002 THEN NULL
            WHEN failure_mode = ''bearing_wear'' THEN
                1.8 + noise2 * 0.4 + degradation_pct * 6.0 * (1 + degradation_pct * 0.5)
            WHEN failure_mode = ''misalignment'' THEN
                2.2 + noise2 * 0.5 + degradation_pct * 6.5 +
                degradation_pct * COS(timeline_pct * 200) * 2.5
            WHEN failure_mode = ''imbalance'' THEN
                1.5 + noise2 * 0.3 +
                degradation_pct * 7.0 * (1 + degradation_pct)  -- dominant Y-axis
            ELSE
                1.3 + noise2 * 0.35
        END AS vibration_y,
        
        -- VIBRATION Z
        CASE 
            WHEN missing_rnd < 0.002 THEN NULL
            WHEN failure_mode = ''bearing_wear'' THEN
                1.5 + noise3 * 0.3 + degradation_pct * 4.0
            WHEN failure_mode = ''misalignment'' THEN
                2.0 + noise3 * 0.5 + degradation_pct * 5.5 +
                degradation_pct * SIN(timeline_pct * 150) * 2.0
            WHEN failure_mode = ''imbalance'' THEN
                1.2 + noise3 * 0.25 + degradation_pct * 1.5
            ELSE
                1.1 + noise3 * 0.3
        END AS vibration_z,
        
        -- TEMPERATURE
        CASE 
            WHEN missing_rnd < 0.001 THEN NULL
            WHEN failure_mode = ''thermal_degradation'' THEN
                rated_temp_max * 0.55 + noise1 * 2.0 +
                degradation_pct * rated_temp_max * 0.40 * (1 + degradation_pct * 0.3) +
                SIN(timeline_pct * 48) * 3.0  -- diurnal cycle
            WHEN failure_mode = ''bearing_wear'' THEN
                rated_temp_max * 0.50 + noise1 * 1.5 +
                degradation_pct * rated_temp_max * 0.15 +  -- mild temp rise from friction
                SIN(timeline_pct * 48) * 2.0
            ELSE
                rated_temp_max * 0.50 + noise1 * 2.0 +
                SIN(timeline_pct * 48) * 2.5
        END AS temperature,
        
        -- RPM
        CASE 
            WHEN failure_mode = ''imbalance'' THEN
                rated_rpm * (1.0 + noise1 * 0.005 - degradation_pct * 0.08 +
                degradation_pct * SIN(timeline_pct * 300) * 0.05)  -- RPM fluctuation
            WHEN failure_mode = ''thermal_degradation'' THEN
                rated_rpm * (1.0 + noise1 * 0.003 - degradation_pct * 0.03)  -- efficiency drop
            ELSE
                rated_rpm * (1.0 + noise1 * 0.003)
        END AS rpm,
        
        -- PRESSURE
        CASE
            WHEN failure_mode = ''bearing_wear'' THEN
                6.5 + noise2 * 0.2 + degradation_pct * 1.5
            WHEN failure_mode = ''misalignment'' THEN
                6.2 + noise2 * 0.3 + degradation_pct * 0.8
            ELSE
                6.0 + noise2 * 0.2
        END AS pressure,
        
        -- CURRENT (AMPS)
        CASE
            WHEN failure_mode = ''misalignment'' THEN
                12.0 + noise3 * 0.5 + degradation_pct * 8.0 * (1 + degradation_pct)  -- current spike
            WHEN failure_mode = ''bearing_wear'' THEN
                11.5 + noise3 * 0.4 + degradation_pct * 3.0  -- drag increases current
            WHEN failure_mode = ''thermal_degradation'' THEN
                11.0 + noise3 * 0.3 + degradation_pct * 2.0
            ELSE
                10.5 + noise3 * 0.4
        END AS current_amps,
        
        -- ACOUSTIC (dB)
        CASE
            WHEN failure_mode = ''bearing_wear'' THEN
                72 + noise1 * 2.0 + degradation_pct * 18.0 +
                CASE WHEN degradation_pct > 0.7 THEN ABS(noise2) * 8.0 ELSE 0 END
            WHEN failure_mode = ''misalignment'' THEN
                70 + noise1 * 1.5 + degradation_pct * 12.0
            WHEN failure_mode = ''imbalance'' THEN
                68 + noise1 * 2.0 + degradation_pct * 8.0
            ELSE
                65 + noise1 * 2.0
        END AS acoustic_db
    FROM combined
    WHERE missing_rnd > 0.003;  -- randomly drop 0.3% of rows entirely (missing data points)
    
    SELECT COUNT(*) INTO :row_count FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS;
    RETURN ''Generated '' || :row_count || '' sensor readings'';
END;
';
create or replace stream SENSOR_READINGS_STREAM on table SENSOR_READINGS append_only = true;
create or replace task SIMULATE_SENSOR_FEED
	warehouse=COMPUTE_WH
	schedule='720 MINUTE'
	SUSPEND_TASK_AFTER_NUM_FAILURES=1
	as INSERT INTO MFGPULSE_DB.RAW_OT.SENSOR_READINGS 
    (asset_id, timestamp, vibration_x, vibration_y, vibration_z, temperature, rpm, pressure, current_amps, acoustic_db)
WITH current_max AS (
    SELECT MAX(timestamp) AS max_ts FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS
),
new_readings AS (
    SELECT 
        am.asset_id,
        DATEADD('minute', seq4() * 15, (SELECT max_ts FROM current_max)) AS ts,
        am.rated_rpm,
        am.rated_temp_max,
        CASE am.asset_id
            WHEN 'ASSET_001' THEN 'bearing_wear'
            WHEN 'ASSET_002' THEN 'thermal_degradation'
            WHEN 'ASSET_003' THEN 'imbalance'
            WHEN 'ASSET_004' THEN 'misalignment'
            WHEN 'ASSET_005' THEN 'bearing_wear'
            WHEN 'ASSET_006' THEN 'thermal_degradation'
            WHEN 'ASSET_007' THEN 'healthy'
            WHEN 'ASSET_008' THEN 'imbalance'
            WHEN 'ASSET_009' THEN 'misalignment'
            WHEN 'ASSET_010' THEN 'healthy'
        END AS failure_mode,
        UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS n1,
        UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS n2,
        UNIFORM(-1::FLOAT, 1::FLOAT, RANDOM()) AS n3,
        0.95 AS deg  -- high degradation level for new data (near failure)
    FROM TABLE(GENERATOR(ROWCOUNT => 48)) -- 12 hours of data at 15-min intervals
    CROSS JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am
)
SELECT 
    asset_id, ts,
    CASE 
        WHEN failure_mode = 'bearing_wear' THEN 2.0 + n1*0.5 + deg*8.0*(1+deg) + ABS(n2)*12.0
        WHEN failure_mode = 'misalignment' THEN 2.5 + n1*0.4 + deg*5.0 + deg*SIN(seq4())*3.0
        WHEN failure_mode = 'imbalance' THEN 1.8 + n1*0.3 + deg*2.0
        ELSE 1.5 + n1*0.4
    END,
    CASE 
        WHEN failure_mode = 'bearing_wear' THEN 1.8 + n2*0.4 + deg*6.0*(1+deg*0.5)
        WHEN failure_mode = 'misalignment' THEN 2.2 + n2*0.5 + deg*6.5
        WHEN failure_mode = 'imbalance' THEN 1.5 + n2*0.3 + deg*7.0*(1+deg)
        ELSE 1.3 + n2*0.35
    END,
    CASE 
        WHEN failure_mode = 'bearing_wear' THEN 1.5 + n3*0.3 + deg*4.0
        WHEN failure_mode = 'misalignment' THEN 2.0 + n3*0.5 + deg*5.5
        WHEN failure_mode = 'imbalance' THEN 1.2 + n3*0.25 + deg*1.5
        ELSE 1.1 + n3*0.3
    END,
    CASE 
        WHEN failure_mode = 'thermal_degradation' THEN rated_temp_max*0.55 + n1*2.0 + deg*rated_temp_max*0.40
        WHEN failure_mode = 'bearing_wear' THEN rated_temp_max*0.50 + n1*1.5 + deg*rated_temp_max*0.15
        ELSE rated_temp_max*0.50 + n1*2.0
    END,
    CASE 
        WHEN failure_mode = 'imbalance' THEN rated_rpm*(1.0 + n1*0.005 - deg*0.08)
        ELSE rated_rpm*(1.0 + n1*0.003)
    END,
    CASE WHEN failure_mode = 'bearing_wear' THEN 6.5+n2*0.2+deg*1.5 ELSE 6.0+n2*0.2 END,
    CASE 
        WHEN failure_mode = 'misalignment' THEN 12.0 + n3*0.5 + deg*8.0*(1+deg)
        WHEN failure_mode = 'bearing_wear' THEN 11.5 + n3*0.4 + deg*3.0
        ELSE 10.5 + n3*0.4
    END,
    CASE 
        WHEN failure_mode = 'bearing_wear' THEN 72 + n1*2.0 + deg*18.0 + ABS(n2)*8.0
        WHEN failure_mode = 'misalignment' THEN 70 + n1*1.5 + deg*12.0
        ELSE 65 + n1*2.0
    END
FROM new_readings;


-- ============================================================================
-- SESSION 4+ OBJECTS: Procurement Engine, Notifications, Planned POs
-- Added after initial DDL export. Required for full deployment.
-- ============================================================================

-- PLANNED_PURCHASE_ORDERS view — dynamic PPO recommendations aggregated by part
create or replace view ANALYTICS.PLANNED_PURCHASE_ORDERS(
	PPO_ID, PART_ID, PART_NAME, SUPPLIER_ID, SUPPLIER_NAME,
	ASSET_COUNT, ASSET_LIST, TOTAL_QTY_NEEDED, ESTIMATED_TOTAL_COST, UNIT_COST,
	LEAD_TIME_DAYS, MIN_RUL_HOURS, MIN_RUL_DAYS, EARLIEST_REQUIRED_BY,
	AVAILABLE_TO_PROMISE, INCOMING_PO_QTY, NET_POSITION,
	STANDARD_ORDER_DATE, STANDARD_ARRIVAL_DATE, EXPEDITE_ARRIVAL_DATE,
	ORDER_BY_DEADLINE, EXPEDITE_DEADLINE, AUTO_CONVERT_DUE, DAYS_UNTIL_AUTO_CONVERT,
	PRIORITY_CLASSIFICATION, PRIORITY_SCORE, PPO_STATUS,
	HAS_CRITICAL_ASSET, HAS_CRITICAL_SHORTAGE, HAS_EXPEDITE_RISK
) as
WITH demand_by_part AS (
    SELECT
        pr.PART_ID, pr.PART_NAME, pr.SUPPLIER_ID, pr.SUPPLIER_NAME,
        pr.LEAD_TIME_DAYS, pr.UNIT_COST,
        COUNT(DISTINCT pr.ASSET_ID) AS ASSET_COUNT,
        LISTAGG(DISTINCT pr.ASSET_NAME, ', ') AS ASSET_LIST,
        SUM(pr.REQUIRED_QUANTITY) AS TOTAL_QTY_NEEDED,
        MIN(pr.RUL_HOURS) AS MIN_RUL_HOURS,
        MIN(pr.REQUIRED_BY_DATE) AS EARLIEST_REQUIRED_BY,
        MAX(CASE WHEN pr.STAGE_PRED = 'Critical' THEN 1 ELSE 0 END) AS HAS_CRITICAL_ASSET,
        MAX(CASE WHEN pr.PROCUREMENT_RISK = 'CRITICAL_SHORTAGE' THEN 1 ELSE 0 END) AS HAS_CRITICAL_SHORTAGE,
        MAX(CASE WHEN pr.PROCUREMENT_RISK = 'EXPEDITE' THEN 1 ELSE 0 END) AS HAS_EXPEDITE_RISK,
        pr.AVAILABLE_TO_PROMISE, pr.INCOMING_PO_QTY, pr.NET_POSITION
    FROM MFGPULSE_DB.ANALYTICS.PROCUREMENT_RECOMMENDATIONS pr
    WHERE pr.RECOMMENDED_PROCUREMENT_ACTION IN ('CREATE_PO', 'EXPEDITE_PO', 'ESCALATE', 'RESERVE_AND_ORDER')
      AND pr.OPEN_PO_ID IS NULL
    GROUP BY pr.PART_ID, pr.PART_NAME, pr.SUPPLIER_ID, pr.SUPPLIER_NAME,
             pr.LEAD_TIME_DAYS, pr.UNIT_COST, pr.AVAILABLE_TO_PROMISE,
             pr.INCOMING_PO_QTY, pr.NET_POSITION
),
with_timing AS (
    SELECT d.*,
        'PPO-' || d.PART_ID || '-' || TO_CHAR(CURRENT_DATE(), 'YYYYMMDD') AS PPO_ID,
        CURRENT_DATE() AS STANDARD_ORDER_DATE,
        DATEADD('day', d.LEAD_TIME_DAYS, CURRENT_DATE()) AS STANDARD_ARRIVAL_DATE,
        DATEADD('day', GREATEST(CEIL(d.LEAD_TIME_DAYS / 2.0), 1), CURRENT_DATE()) AS EXPEDITE_ARRIVAL_DATE,
        DATEADD('day', -1 * d.LEAD_TIME_DAYS, d.EARLIEST_REQUIRED_BY) AS ORDER_BY_DEADLINE,
        DATEADD('day', -1 * GREATEST(CEIL(d.LEAD_TIME_DAYS / 2.0), 1), d.EARLIEST_REQUIRED_BY) AS EXPEDITE_DEADLINE,
        d.TOTAL_QTY_NEEDED * d.UNIT_COST AS ESTIMATED_TOTAL_COST,
        ROUND(
            LEAST(1.0, GREATEST(0, (336.0 - COALESCE(d.MIN_RUL_HOURS, 336)) / 336.0)) * 0.40
            + LEAST(1.0, GREATEST(0, (0.0 - COALESCE(d.NET_POSITION, 0)) / GREATEST(d.TOTAL_QTY_NEEDED, 1))) * 0.30
            + LEAST(1.0, (d.ASSET_COUNT - 1.0) / 4.0) * 0.20
            + d.HAS_CRITICAL_ASSET * 0.10
        , 3) AS PRIORITY_SCORE
    FROM demand_by_part d
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
FROM with_timing t;

-- LOG_APP_NOTIFICATION — sends in-app and email notifications per event config
CREATE OR REPLACE PROCEDURE RAW_IT.LOG_APP_NOTIFICATION(
    P_EVENT_TYPE VARCHAR, P_TITLE VARCHAR, P_MESSAGE VARCHAR, P_ENTITY_ID VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE
    v_email_enabled BOOLEAN DEFAULT FALSE; v_in_app_enabled BOOLEAN DEFAULT TRUE;
    v_recipients VARCHAR DEFAULT ''; v_personas VARCHAR DEFAULT '';
    v_priority VARCHAR DEFAULT 'NORMAL'; v_notif_count NUMBER DEFAULT 0;
    v_email_result VARCHAR DEFAULT 'SKIPPED';
BEGIN
    BEGIN
        SELECT EMAIL_ENABLED, IN_APP_ENABLED, EMAIL_RECIPIENTS, NOTIFY_PERSONAS, PRIORITY
        INTO :v_email_enabled, :v_in_app_enabled, :v_recipients, :v_personas, :v_priority
        FROM MFGPULSE_DB.RAW_IT.NOTIFICATION_SETTINGS
        WHERE EVENT_TYPE = :p_event_type;
    EXCEPTION WHEN OTHER THEN
        v_in_app_enabled := TRUE;
        v_personas := 'PLANT_MANAGER,APP_ADMIN';
    END;
    IF (:v_in_app_enabled) THEN
        INSERT INTO MFGPULSE_DB.RAW_IT.APP_NOTIFICATIONS
            (NOTIF_ID, EVENT_TYPE, PERSONA_TARGET, TITLE, MESSAGE, ENTITY_ID, PRIORITY)
        SELECT :p_event_type || '-' || TRIM(value) || '-' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS'),
            :p_event_type, TRIM(value), :p_title, :p_message, :p_entity_id, :v_priority
        FROM TABLE(SPLIT_TO_TABLE(:v_personas, ','));
        SELECT COUNT(*) INTO :v_notif_count
        FROM MFGPULSE_DB.RAW_IT.APP_NOTIFICATIONS
        WHERE ENTITY_ID = :p_entity_id AND EVENT_TYPE = :p_event_type;
    END IF;
    IF (:v_email_enabled AND LENGTH(TRIM(COALESCE(:v_recipients, ''))) > 0) THEN
        LET email_subject VARCHAR := 'MFGPulse ' || :v_priority || ': ' || :p_title;
        LET email_body VARCHAR := '<div style="font-family:sans-serif;"><h3>' || :p_title || '</h3><p>' || :p_message || '</p><p style="color:#666;font-size:12px;">Entity: ' || COALESCE(:p_entity_id, 'N/A') || ' | ' || CURRENT_TIMESTAMP()::VARCHAR || '</p></div>';
        CALL MFGPULSE_DB.RAW_IT.SEND_MFGPULSE_EMAIL(:email_subject, :email_body, :v_recipients);
        SELECT * INTO :v_email_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    END IF;
    RETURN OBJECT_CONSTRUCT('status', 'OK', 'event_type', :p_event_type, 'in_app_sent', :v_notif_count, 'email_result', :v_email_result);
END;
$$;

-- GENERATE_PURCHASE_ORDER — creates a PO for a specific asset + part
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
    v_po_id := 'PO-' || TO_CHAR(CURRENT_DATE(), 'YYYYMMDD') || '-' || :p_asset_id;
    INSERT INTO MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS
        (PO_ID, SUPPLIER_ID, REQUIRED_BY_DATE, EXPECTED_ARRIVAL_DATE, STATUS, PRIORITY, TOTAL_COST, CREATED_BY, SOURCE)
    VALUES (:v_po_id, :v_supplier_id, :p_required_by_date, :v_expected_arrival, 'pending_approval',
        COALESCE(:p_priority, 'NORMAL'), :v_unit_cost * :p_quantity, CURRENT_USER(), 'prediction');
    INSERT INTO MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES
        (PO_LINE_ID, PO_ID, PART_ID, ASSET_ID, WO_ID, QUANTITY_ORDERED, UNIT_COST, LINE_COST,
         RUL_HOURS_AT_ORDER, FAILURE_MODE_PRED, PROCUREMENT_RISK)
    VALUES (:v_po_id || '-L1', :v_po_id, :p_part_id, :p_asset_id, :p_wo_id, :p_quantity,
        :v_unit_cost, :v_unit_cost * :p_quantity, :v_rul_hours, :v_failure_mode, :v_risk);
    RETURN OBJECT_CONSTRUCT('status', 'CREATED', 'po_id', :v_po_id, 'supplier', :v_supplier_name,
        'expected_arrival', :v_expected_arrival::VARCHAR, 'procurement_risk', :v_risk,
        'total_cost', :v_unit_cost * :p_quantity);
END;
$$;

-- AUTO_GENERATE_PURCHASE_ORDERS — bulk PO creation for all at-risk assets
CREATE OR REPLACE PROCEDURE ANALYTICS.AUTO_GENERATE_PURCHASE_ORDERS()
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE
    v_created NUMBER DEFAULT 0; v_skipped NUMBER DEFAULT 0; v_result VARIANT;
    c_asset_id VARCHAR; c_part_id VARCHAR; c_required_by DATE; c_wo_id VARCHAR; c_risk VARCHAR;
    rec_cursor CURSOR FOR
        SELECT ASSET_ID, PART_ID, REQUIRED_BY_DATE, WO_ID, PROCUREMENT_RISK
        FROM MFGPULSE_DB.ANALYTICS.PROCUREMENT_RECOMMENDATIONS
        WHERE RECOMMENDED_PROCUREMENT_ACTION IN ('CREATE_PO', 'EXPEDITE_PO', 'ESCALATE_CRITICAL_SHORTAGE')
          AND OPEN_PO_ID IS NULL
          AND (RUL_HOURS < 336 OR STAGE_PRED IN ('Warning', 'Critical') OR FAILURE_MODE_PRED != 'normal');
BEGIN
    OPEN rec_cursor;
    FOR rec IN rec_cursor DO
        c_asset_id := rec.ASSET_ID;
        c_part_id := rec.PART_ID;
        c_required_by := rec.REQUIRED_BY_DATE;
        c_wo_id := rec.WO_ID;
        c_risk := rec.PROCUREMENT_RISK;
        LET priority VARCHAR := CASE
            WHEN :c_risk = 'CRITICAL_SHORTAGE' THEN 'EMERGENCY'
            WHEN :c_risk = 'EXPEDITE' THEN 'EXPEDITE'
            ELSE 'HIGH' END;
        CALL MFGPULSE_DB.ANALYTICS.GENERATE_PURCHASE_ORDER(
            :c_asset_id, :c_part_id, 1, :c_required_by, :c_wo_id, :priority);
        SELECT * INTO :v_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
        IF (v_result:status::VARCHAR = 'CREATED') THEN v_created := :v_created + 1;
        ELSE v_skipped := :v_skipped + 1; END IF;
    END FOR;
    CLOSE rec_cursor;
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETE', 'pos_created', :v_created, 'pos_skipped', :v_skipped);
END;
$$;

-- RESERVE_PART_FOR_WORK_ORDER — reserves ATP for a specific WO
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

-- AUTO_CONVERT_PLANNED_POS — converts overdue PPOs to actual POs
CREATE OR REPLACE PROCEDURE ANALYTICS.AUTO_CONVERT_PLANNED_POS()
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE
    v_converted NUMBER DEFAULT 0; v_skipped NUMBER DEFAULT 0;
    c_ppo_id VARCHAR; c_part_id VARCHAR; c_supplier_id VARCHAR;
    c_total_qty NUMBER; c_required_by DATE; c_asset_list VARCHAR; c_priority VARCHAR;
    existing_po VARCHAR; v_supplier_id VARCHAR; v_supplier_name VARCHAR;
    v_lead_time NUMBER; v_unit_cost FLOAT; v_po_id VARCHAR; v_expected_arrival DATE;
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
        existing_po := NULL;
        BEGIN
            SELECT po.PO_ID INTO :existing_po
            FROM MFGPULSE_DB.RAW_IT.PURCHASE_ORDER_LINES pol
            JOIN MFGPULSE_DB.RAW_IT.PURCHASE_ORDERS po ON pol.PO_ID = po.PO_ID
            WHERE pol.PART_ID = :c_part_id AND po.STATUS NOT IN ('cancelled', 'received')
              AND po.SOURCE = 'auto_planned' LIMIT 1;
        EXCEPTION WHEN OTHER THEN existing_po := NULL;
        END;
        IF (:existing_po IS NOT NULL) THEN
            v_skipped := :v_skipped + 1;
        ELSE
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
              AND pr.RECOMMENDED_PROCUREMENT_ACTION IN ('CREATE_PO', 'EXPEDITE_PO', 'ESCALATE', 'RESERVE_AND_ORDER')
              AND pr.OPEN_PO_ID IS NULL;
            BEGIN
                CALL MFGPULSE_DB.RAW_IT.LOG_APP_NOTIFICATION(
                    'PO_CREATED', 'Auto-converted PPO to PO: ' || :v_po_id,
                    'Planned PO ' || :c_ppo_id || ' auto-converted. Part: ' || :c_part_id || ', Qty: ' || :c_total_qty || ', Assets: ' || :c_asset_list,
                    :v_po_id);
            EXCEPTION WHEN OTHER THEN NULL;
            END;
            v_converted := :v_converted + 1;
        END IF;
    END FOR;
    CLOSE ppo_cursor;
    RETURN OBJECT_CONSTRUCT('status', 'COMPLETE', 'converted', :v_converted, 'skipped', :v_skipped, 'run_at', CURRENT_TIMESTAMP()::VARCHAR);
END;
$$;

-- AUTO_CONVERT_PLANNED_POS_TASK — runs every 12 hours (created suspended)
CREATE OR REPLACE TASK ANALYTICS.AUTO_CONVERT_PLANNED_POS_TASK
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '720 MINUTE'
AS CALL MFGPULSE_DB.ANALYTICS.AUTO_CONVERT_PLANNED_POS();
-- Note: Task created SUSPENDED. To enable: ALTER TASK ANALYTICS.AUTO_CONVERT_PLANNED_POS_TASK RESUME;

-- SIMULATE_ALL_FEEDS_RANDOM — unified sensor + production feed with persistent degradation
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

-- SIMULATE_ALL_FEEDS task — unified feed, replaces SIMULATE_SENSOR_FEED + SIMULATE_PRODUCTION
CREATE OR REPLACE TASK RAW_OT.SIMULATE_ALL_FEEDS
    WAREHOUSE = COMPUTE_WH
    SCHEDULE = '720 MINUTE'
    SUSPEND_TASK_AFTER_NUM_FAILURES = 2
AS CALL MFGPULSE_DB.RAW_OT.SIMULATE_ALL_FEEDS_RANDOM();
-- Note: Task created SUSPENDED. To enable: ALTER TASK RAW_OT.SIMULATE_ALL_FEEDS RESUME;"