-- ============================================================================
-- MFGPulse AI: ddl_objects.sql — Complete Object DDL for Cross-Instance Deployment
-- ============================================================================
-- Contains CREATE OR REPLACE statements for all derived objects (UDFs, procedures,
-- views, dynamic tables). Run AFTER deploy_all.sql phases 1-9 (infrastructure,
-- base tables, seed data, streams).
--
-- Execution order matters — objects are listed in dependency order.
-- Run with: USE DATABASE MFGPULSE_DB; USE WAREHOUSE COMPUTE_WH;
-- ============================================================================

USE DATABASE MFGPULSE_DB;
USE WAREHOUSE COMPUTE_WH;

-- ============================================================================
-- 1. ML_MODELS UDFs (5)
-- ============================================================================

CREATE OR REPLACE FUNCTION ML_MODELS.PREDICT_FAILURE_MODE(
    VIB_MAG_MEAN_6H FLOAT, VIB_MAG_STD_6H FLOAT, VIB_MAG_MAX_6H FLOAT, VIB_CREST_FACTOR_6H FLOAT,
    VIB_PEAK_TO_PEAK_6H FLOAT, VIB_RMS_6H FLOAT, VIB_COEFF_VAR_6H FLOAT,
    TEMP_MEAN_6H FLOAT, TEMP_STD_6H FLOAT, CURRENT_MEAN_6H FLOAT, CURRENT_STD_6H FLOAT,
    VIB_MAG_MEAN_24H FLOAT, VIB_MAG_STD_24H FLOAT, VIB_CREST_FACTOR_24H FLOAT, VIB_RMS_24H FLOAT,
    TEMP_MEAN_24H FLOAT, CURRENT_MEAN_24H FLOAT, ACOUSTIC_MEAN_24H FLOAT,
    VIB_RATE_OF_CHANGE_1H FLOAT, VIB_ACCELERATION_1H FLOAT,
    VIB_XY_CORRELATION FLOAT, VIB_TEMP_COUPLING FLOAT, CURRENT_RPM_RATIO FLOAT,
    VIB_AXIS_DOMINANCE FLOAT, ACOUSTIC_VIB_RATIO FLOAT,
    STRESS_INDEX FLOAT, ISO_SEVERITY FLOAT, COMPOSITE_HEALTH FLOAT
)
RETURNS OBJECT
LANGUAGE SQL
AS '
    SELECT OBJECT_CONSTRUCT(
        ''predicted_failure_mode'', CASE
            WHEN vib_crest_factor_6h > 1.5 AND acoustic_vib_ratio > 20 AND vib_rms_24h > 5.0 THEN ''bearing_wear''
            WHEN temp_mean_24h > 70 AND vib_rms_24h < 4.0 AND stress_index > 0.5 THEN ''thermal_degradation''
            WHEN ABS(vib_xy_correlation) > 0.6 AND current_rpm_ratio > 8.0 AND vib_axis_dominance < 0.7 THEN ''misalignment''
            WHEN vib_axis_dominance > 0.75 AND vib_rms_24h > 4.0 AND current_rpm_ratio < 7.0 THEN ''imbalance''
            ELSE ''normal'' END,
        ''confidence'', CASE WHEN composite_health < 30 THEN 0.95 WHEN composite_health < 60 THEN 0.80 WHEN composite_health < 80 THEN 0.65 ELSE 0.90 END
    )';

CREATE OR REPLACE FUNCTION ML_MODELS.PREDICT_RUL(
    VIB_RMS_24H FLOAT, VIB_RATE_OF_CHANGE FLOAT, VIB_ACCELERATION FLOAT,
    DEGRADATION_VELOCITY FLOAT, HOURS_SINCE_BREACH FLOAT,
    STRESS_INDEX FLOAT, COMPOSITE_HEALTH FLOAT, FATIGUE_SCORE FLOAT
)
RETURNS OBJECT
LANGUAGE SQL
AS '
    SELECT OBJECT_CONSTRUCT(
        ''predicted_rul_hours'', ROUND(GREATEST(0, LEAST(2000,
            CASE WHEN COALESCE(degradation_velocity, 0) > 0.01 THEN (1.0 - COALESCE(fatigue_score, stress_index)) / (degradation_velocity / 24.0)
                 ELSE 2000.0 * POWER(1.0 - LEAST(1.0, stress_index * 0.40 + COALESCE(fatigue_score, 0) * 0.35 + composite_health / 400.0 + 0.10), 3.0) END)), 1),
        ''rul_lower_ci'', ROUND(GREATEST(0, LEAST(2000,
            CASE WHEN COALESCE(degradation_velocity, 0) > 0.01 THEN (1.0 - COALESCE(fatigue_score, stress_index)) / (degradation_velocity * 1.5 / 24.0)
                 ELSE 2000.0 * POWER(1.0 - LEAST(1.0, stress_index * 0.40 + COALESCE(fatigue_score, 0) * 0.35 + composite_health / 400.0 + 0.10) * 1.15, 3.0) END)), 1),
        ''rul_upper_ci'', ROUND(GREATEST(0, LEAST(2000,
            CASE WHEN COALESCE(degradation_velocity, 0) > 0.01 THEN (1.0 - COALESCE(fatigue_score, stress_index)) / (degradation_velocity * 0.5 / 24.0)
                 ELSE 2000.0 * POWER(1.0 - LEAST(1.0, stress_index * 0.40 + COALESCE(fatigue_score, 0) * 0.35 + composite_health / 400.0 + 0.10) * 0.85, 3.0) END)), 1),
        ''confidence_level'', CASE WHEN COALESCE(degradation_velocity, 0) > 0.1 THEN ''HIGH'' WHEN COALESCE(degradation_velocity, 0) > 0.01 THEN ''MEDIUM'' ELSE ''LOW'' END
    )';

CREATE OR REPLACE FUNCTION ML_MODELS.PREDICT_DEGRADATION_STAGE(
    VIB_RMS_24H FLOAT, VIB_CREST_FACTOR_6H FLOAT, STRESS_INDEX FLOAT,
    COMPOSITE_HEALTH_SCORE FLOAT, DEGRADATION_VELOCITY_30D FLOAT,
    HOURS_SINCE_FIRST_BREACH FLOAT, ABOVE_NORMAL_COUNT_24H FLOAT
)
RETURNS OBJECT
LANGUAGE SQL
AS '
    SELECT OBJECT_CONSTRUCT(
        ''predicted_stage'', CASE 
            WHEN (LEAST(1.0, GREATEST(0, (vib_rms_24h - 2.5)/10.0)) * 0.25 + LEAST(1.0, GREATEST(0, (vib_crest_factor_6h - 1.2)/1.5)) * 0.15 + LEAST(1.0, stress_index) * 0.15 + LEAST(1.0, GREATEST(0, COALESCE(degradation_velocity_30d, 0)/0.5)) * 0.20 + CASE WHEN hours_since_first_breach IS NULL THEN 0 ELSE LEAST(1.0, hours_since_first_breach/2000.0) END * 0.10 + LEAST(1.0, COALESCE(above_normal_count_24h, 0)/80.0) * 0.15) < 0.25 THEN ''Healthy''
            WHEN (LEAST(1.0, GREATEST(0, (vib_rms_24h - 2.5)/10.0)) * 0.25 + LEAST(1.0, GREATEST(0, (vib_crest_factor_6h - 1.2)/1.5)) * 0.15 + LEAST(1.0, stress_index) * 0.15 + LEAST(1.0, GREATEST(0, COALESCE(degradation_velocity_30d, 0)/0.5)) * 0.20 + CASE WHEN hours_since_first_breach IS NULL THEN 0 ELSE LEAST(1.0, hours_since_first_breach/2000.0) END * 0.10 + LEAST(1.0, COALESCE(above_normal_count_24h, 0)/80.0) * 0.15) < 0.55 THEN ''Warning''
            ELSE ''Critical'' END,
        ''degradation_score'', ROUND(LEAST(1.0, GREATEST(0, (vib_rms_24h - 2.5)/10.0)) * 0.25 + LEAST(1.0, GREATEST(0, (vib_crest_factor_6h - 1.2)/1.5)) * 0.15 + LEAST(1.0, stress_index) * 0.15 + LEAST(1.0, GREATEST(0, COALESCE(degradation_velocity_30d, 0)/0.5)) * 0.20 + CASE WHEN hours_since_first_breach IS NULL THEN 0 ELSE LEAST(1.0, hours_since_first_breach/2000.0) END * 0.10 + LEAST(1.0, COALESCE(above_normal_count_24h, 0)/80.0) * 0.15, 4),
        ''transition_probability'', ROUND(LEAST(1.0, GREATEST(0, COALESCE(degradation_velocity_30d, 0)/0.5)) * 0.5 + LEAST(1.0, COALESCE(above_normal_count_24h, 0)/80.0) * 0.5, 4)
    )';

CREATE OR REPLACE FUNCTION ML_MODELS.COMPUTE_FATIGUE_SCORE(
    VIB_CREST_FACTOR_6H FLOAT, VIB_COEFF_VAR_6H FLOAT, VIB_PEAK_TO_PEAK_6H FLOAT,
    VIB_RATE_OF_CHANGE_1H FLOAT, VIB_ACCELERATION_1H FLOAT,
    ENERGY_BALANCE_RATIO FLOAT, STRESS_INDEX FLOAT,
    VIB_XY_CORRELATION FLOAT, ACOUSTIC_VIB_RATIO FLOAT
)
RETURNS FLOAT
LANGUAGE SQL
AS '
    LEAST(1.0, GREATEST(0.0,
        LEAST(1.0, GREATEST(0, (vib_crest_factor_6h - 1.2) / 1.5)) * 0.25
        + LEAST(1.0, GREATEST(0, (vib_coeff_var_6h - 0.15) / 0.4)) * 0.15
        + LEAST(1.0, GREATEST(0, vib_acceleration_1h / 2.0)) * 0.20
        + LEAST(1.0, GREATEST(0, ABS(energy_balance_ratio - 1.0) / 0.5)) * 0.15
        + LEAST(1.0, GREATEST(0, ABS(vib_xy_correlation - 0.3) / 0.5)) * 0.10
        + LEAST(1.0, GREATEST(0, (acoustic_vib_ratio - 25.0) / 20.0)) * 0.15
    ))';

CREATE OR REPLACE FUNCTION ML_MODELS.SIMULATE_FAILURE_TWIN(
    CURRENT_VIB_MAG FLOAT, DEGRADATION_VELOCITY FLOAT, CURRENT_FATIGUE_SCORE FLOAT,
    LOAD_REDUCTION_PCT FLOAT, MAINTENANCE_DELAY_DAYS FLOAT, RPM_ADJUSTMENT_PCT FLOAT
)
RETURNS OBJECT
LANGUAGE SQL
AS '
    WITH params AS (
        SELECT GREATEST(0.001, COALESCE(degradation_velocity, 0.1)) * (1.0 - load_reduction_pct / 100.0 * 0.6) * (1.0 + rpm_adjustment_pct / 100.0 * 0.3) AS adj_rate,
            current_fatigue_score AS base_fatigue, maintenance_delay_days AS delay_days
    ),
    simulations AS (
        SELECT seq4() AS sim_id, p.adj_rate * (0.5 + UNIFORM(0::FLOAT, 1.5::FLOAT, RANDOM())) AS sim_rate,
            UNIFORM(0::FLOAT, 1::FLOAT, RANDOM()) AS shock_rnd
        FROM TABLE(GENERATOR(ROWCOUNT => 100)) CROSS JOIN params p
    ),
    projections AS (
        SELECT s.sim_id,
            LEAST(1.0, p.base_fatigue + s.sim_rate * 3 + CASE WHEN s.shock_rnd < 0.15 THEN 0.1 ELSE 0 END) AS fatigue_day3,
            LEAST(1.0, p.base_fatigue + s.sim_rate * 7 + CASE WHEN s.shock_rnd < 0.35 THEN 0.15 ELSE 0 END) AS fatigue_day7,
            LEAST(1.0, p.base_fatigue + s.sim_rate * 14 + CASE WHEN s.shock_rnd < 0.50 THEN 0.2 ELSE 0 END) AS fatigue_day14,
            CASE WHEN s.sim_rate > 0 THEN (1.0 - p.base_fatigue) / s.sim_rate ELSE 999 END AS days_to_failure,
            CASE WHEN p.delay_days < (1.0 - p.base_fatigue) / NULLIF(s.sim_rate, 0) THEN 0 ELSE 1 END AS fails_before_maintenance
        FROM simulations s CROSS JOIN params p
    )
    SELECT OBJECT_CONSTRUCT(
        ''num_simulations'', 100,
        ''failure_prob_day_3'', ROUND((SELECT COUNT(*) FROM projections WHERE fatigue_day3 > 0.9) / 100.0, 3),
        ''failure_prob_day_7'', ROUND((SELECT COUNT(*) FROM projections WHERE fatigue_day7 > 0.9) / 100.0, 3),
        ''failure_prob_day_14'', ROUND((SELECT COUNT(*) FROM projections WHERE fatigue_day14 > 0.9) / 100.0, 3),
        ''rul_days_p10'', ROUND((SELECT PERCENTILE_CONT(0.10) WITHIN GROUP (ORDER BY days_to_failure) FROM projections), 1),
        ''rul_days_p50'', ROUND((SELECT PERCENTILE_CONT(0.50) WITHIN GROUP (ORDER BY days_to_failure) FROM projections), 1),
        ''rul_days_p90'', ROUND((SELECT PERCENTILE_CONT(0.90) WITHIN GROUP (ORDER BY days_to_failure) FROM projections), 1),
        ''fails_before_maintenance_pct'', ROUND((SELECT SUM(fails_before_maintenance) FROM projections) / 100.0 * 100, 1),
        ''recommended_intervention'', CASE
            WHEN current_fatigue_score > 0.8 THEN ''IMMEDIATE - within 24 hours''
            WHEN current_fatigue_score > 0.6 THEN ''URGENT - within 3 days''
            WHEN current_fatigue_score > 0.4 THEN ''PLANNED - within 7 days''
            ELSE ''MONITOR - next scheduled PM'' END,
        ''expected_cost'', ROUND(520 + 12000 * (SELECT COUNT(*) FROM projections WHERE fatigue_day14 > 0.9) / 100.0, 0)
    )';


-- ============================================================================
-- 2. KEY PROCEDURES
-- ============================================================================
-- Note: ANALYZE_ROOT_CAUSE uses Cortex Complete LLM. For the procedure body,
-- extract from the source instance: GET_DDL('PROCEDURE', 'MFGPULSE_DB.ML_MODELS.ANALYZE_ROOT_CAUSE(...)');
-- The remaining procedures with full bodies are included below.

-- PRESCRIBE_MAINTENANCE (uses Cortex Complete llama3.1-70b)
CREATE OR REPLACE PROCEDURE ML_MODELS.PRESCRIBE_MAINTENANCE(
    P_ASSET_ID VARCHAR, P_FAILURE_MODE VARCHAR, P_RUL_HOURS FLOAT,
    P_STAGE VARCHAR, P_FATIGUE_SCORE FLOAT, P_ROOT_CAUSE VARCHAR, P_SIM_RESULT VARCHAR
)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE
    parts_info VARCHAR DEFAULT 'None';
    avg_cost FLOAT DEFAULT 1000;
    fail_cost FLOAT DEFAULT 5000;
    prompt VARCHAR;
    llm_response VARCHAR;
BEGIN
    SELECT COALESCE(ARRAY_TO_STRING(ARRAY_AGG(
        part_name || ' (qty:' || quantity_on_hand || ', $' || unit_cost || ')'
    ), '; '), 'None') INTO :parts_info
    FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY
    WHERE ARRAY_CONTAINS(:p_asset_id::VARIANT, compatible_assets);

    fail_cost := CASE WHEN :p_stage = 'Critical' THEN 12000 ELSE 5000 END;

    prompt := CONCAT(
        'Maintenance AI. Asset ', :p_asset_id, ' has ', :p_failure_mode, ', ', :p_rul_hours::VARCHAR, 'hrs RUL, ', :p_stage,
        '. Fatigue:', :p_fatigue_score::VARCHAR, '. Root cause:', COALESCE(:p_root_cause, 'Unknown'),
        '. Parts:', :parts_info, '. Repair:$', :avg_cost::VARCHAR, ' FailureCost:$', :fail_cost::VARCHAR,
        '. Reply JSON only no markdown: {"action":"x","priority":"EMERGENCY","parts_needed":["x"],"parts_available":true,"optimal_window":"x","estimated_repair_cost":520,"estimated_failure_cost":12000,"cost_savings":"x","risk_if_delayed":"x","work_order_summary":"x"}'
    );

    SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', :prompt) INTO :llm_response;
    RETURN :llm_response;
EXCEPTION
    WHEN OTHER THEN RETURN CONCAT('ERROR: ', SQLERRM);
END;
$$;

-- GENERATE_WORK_ORDER
CREATE OR REPLACE PROCEDURE ANALYTICS.GENERATE_WORK_ORDER(
    P_ASSET_ID VARCHAR, P_PRIORITY VARCHAR, P_ACTION VARCHAR,
    P_PARTS_NEEDED VARCHAR, P_ESTIMATED_COST FLOAT
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE
    v_wo_id VARCHAR;
    v_technician VARCHAR DEFAULT 'Unassigned';
    v_parts_available BOOLEAN DEFAULT FALSE;
    v_line_id VARCHAR;
BEGIN
    v_wo_id := 'WO-AUTO-' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD-HH24MISS');
    SELECT line_id INTO :v_line_id FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER WHERE asset_id = :p_asset_id;
    BEGIN
        SELECT operator_name INTO :v_technician
        FROM MFGPULSE_DB.RAW_IT.SHIFT_SCHEDULE
        WHERE line_id = :v_line_id AND shift_start > CURRENT_TIMESTAMP()
        ORDER BY shift_start LIMIT 1;
    EXCEPTION WHEN OTHER THEN v_technician := 'Next available technician';
    END;
    BEGIN
        SELECT COUNT(*) > 0 INTO :v_parts_available
        FROM MFGPULSE_DB.RAW_IT.PARTS_INVENTORY
        WHERE ARRAY_CONTAINS(:p_asset_id::VARIANT, compatible_assets) AND quantity_on_hand > 0;
    EXCEPTION WHEN OTHER THEN v_parts_available := FALSE;
    END;
    INSERT INTO MFGPULSE_DB.RAW_IT.WORK_ORDERS
    (wo_id, asset_id, wo_type, created_date, priority, status, assigned_to, parts_cost)
    VALUES (:v_wo_id, :p_asset_id,
        CASE WHEN :p_priority = 'EMERGENCY' THEN 'emergency' ELSE 'corrective' END,
        CURRENT_TIMESTAMP(), :p_priority, 'open', :v_technician, :p_estimated_cost);
    RETURN OBJECT_CONSTRUCT(
        'wo_id', :v_wo_id, 'asset_id', :p_asset_id, 'priority', :p_priority,
        'status', 'open', 'action', :p_action, 'assigned_to', :v_technician,
        'parts_needed', :p_parts_needed, 'parts_available', :v_parts_available,
        'estimated_cost', :p_estimated_cost, 'created_at', CURRENT_TIMESTAMP()::VARCHAR,
        'message', 'Work order ' || :v_wo_id || ' created for ' || :p_asset_id || '. Assigned to: ' || :v_technician);
END;
$$;

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

-- AUTO_GENERATE_PURCHASE_ORDERS
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

-- LOG_APP_NOTIFICATION
CREATE OR REPLACE PROCEDURE RAW_IT.LOG_APP_NOTIFICATION(
    P_EVENT_TYPE VARCHAR, P_TITLE VARCHAR, P_MESSAGE VARCHAR, P_ENTITY_ID VARCHAR
)
RETURNS VARIANT
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE
    v_email_enabled BOOLEAN DEFAULT FALSE; v_in_app_enabled BOOLEAN DEFAULT TRUE;
    v_recipients VARCHAR DEFAULT ''; v_personas VARCHAR DEFAULT ''; v_priority VARCHAR DEFAULT 'NORMAL';
    v_notif_count NUMBER DEFAULT 0; v_email_result VARCHAR DEFAULT 'SKIPPED';
BEGIN
    BEGIN
        SELECT EMAIL_ENABLED, IN_APP_ENABLED, EMAIL_RECIPIENTS, NOTIFY_PERSONAS, PRIORITY
        INTO :v_email_enabled, :v_in_app_enabled, :v_recipients, :v_personas, :v_priority
        FROM MFGPULSE_DB.RAW_IT.NOTIFICATION_SETTINGS WHERE EVENT_TYPE = :p_event_type;
    EXCEPTION WHEN OTHER THEN v_in_app_enabled := TRUE; v_personas := 'PLANT_MANAGER,APP_ADMIN';
    END;
    IF (:v_in_app_enabled) THEN
        INSERT INTO MFGPULSE_DB.RAW_IT.APP_NOTIFICATIONS
            (NOTIF_ID, EVENT_TYPE, PERSONA_TARGET, TITLE, MESSAGE, ENTITY_ID, PRIORITY)
        SELECT :p_event_type || '-' || TRIM(value) || '-' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS'),
            :p_event_type, TRIM(value), :p_title, :p_message, :p_entity_id, :v_priority
        FROM TABLE(SPLIT_TO_TABLE(:v_personas, ','));
        SELECT COUNT(*) INTO :v_notif_count FROM MFGPULSE_DB.RAW_IT.APP_NOTIFICATIONS
        WHERE ENTITY_ID = :p_entity_id AND EVENT_TYPE = :p_event_type;
    END IF;
    IF (:v_email_enabled AND LENGTH(TRIM(COALESCE(:v_recipients, ''))) > 0) THEN
        LET email_subject VARCHAR := 'MFGPulse ' || :v_priority || ': ' || :p_title;
        LET email_body VARCHAR := '<div style="font-family:sans-serif;"><h3>' || :p_title || '</h3><p>' || :p_message || '</p></div>';
        CALL MFGPULSE_DB.RAW_IT.SEND_MFGPULSE_EMAIL(:email_subject, :email_body, :v_recipients);
        SELECT * INTO :v_email_result FROM TABLE(RESULT_SCAN(LAST_QUERY_ID()));
    END IF;
    RETURN OBJECT_CONSTRUCT('status', 'OK', 'event_type', :p_event_type, 'in_app_sent', :v_notif_count, 'email_result', :v_email_result);
END;
$$;

-- SEND_MFGPULSE_EMAIL
CREATE OR REPLACE PROCEDURE RAW_IT.SEND_MFGPULSE_EMAIL(P_SUBJECT VARCHAR, P_BODY_HTML VARCHAR, P_RECIPIENTS VARCHAR)
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
BEGIN
    IF (:p_recipients IS NULL OR LENGTH(TRIM(:p_recipients)) = 0) THEN RETURN 'SKIPPED: No recipients'; END IF;
    BEGIN
        CALL SYSTEM$SEND_SNOWFLAKE_NOTIFICATION(
            SNOWFLAKE.NOTIFICATION.TEXT_HTML(:p_body_html),
            SNOWFLAKE.NOTIFICATION.EMAIL_INTEGRATION_CONFIG('MFGPULSE_EMAIL', :p_subject, SPLIT(:p_recipients, ',')));
        RETURN 'SENT';
    EXCEPTION WHEN OTHER THEN RETURN 'EMAIL_ERROR: ' || SQLERRM;
    END;
END;
$$;


-- ============================================================================
-- 3. PLANNED PURCHASE ORDER ENGINE
-- ============================================================================

-- PLANNED_PURCHASE_ORDERS view — dynamic PPO recommendations aggregated by part
CREATE OR REPLACE VIEW ANALYTICS.PLANNED_PURCHASE_ORDERS AS
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

-- AUTO_CONVERT_PLANNED_POS procedure
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
AS
    CALL MFGPULSE_DB.ANALYTICS.AUTO_CONVERT_PLANNED_POS();
-- Note: Task created SUSPENDED. To enable: ALTER TASK ANALYTICS.AUTO_CONVERT_PLANNED_POS_TASK RESUME;


-- ============================================================================
-- 4. CROSS-INSTANCE DEPLOYMENT NOTES
-- ============================================================================
-- For objects not included above (Dynamic Tables, Views), extract from the
-- source instance using the GET_DDL commands in deploy_all.sql Phase 10,
-- then execute the returned SQL on the target instance.
--
-- The full DDL for all 13 DTs, 19 views, and remaining procedures is also
-- available in docs/full_ddl_export.sql (3800+ lines).
--
-- Cortex Agent and Semantic View: deploy from cortex_project/ directory.
-- ============================================================================

-- AUTO_GENERATE_WORK_ORDERS — auto-creates WOs for at-risk assets
CREATE OR REPLACE PROCEDURE ANALYTICS.AUTO_GENERATE_WORK_ORDERS()
RETURNS VARCHAR
LANGUAGE SQL
EXECUTE AS CALLER
AS $$
DECLARE
    v_created NUMBER DEFAULT 0;
    c_asset_id VARCHAR; c_asset_name VARCHAR; c_rul FLOAT; c_deg FLOAT;
    c_failure_mode VARCHAR; c_wo_type VARCHAR; c_priority VARCHAR;
    c_assigned_to VARCHAR; c_wo_id VARCHAR; c_cost FLOAT; c_hours FLOAT;
    c_part_id VARCHAR; c_has_po BOOLEAN;
    wo_cursor CURSOR FOR
        SELECT p.ASSET_ID, am.ASSET_NAME, p.RUL_HOURS, p.DEGRADATION_SCORE, p.FAILURE_MODE_PRED,
            pr.PART_ID,
            CASE WHEN pr.OPEN_PO_ID IS NOT NULL THEN TRUE ELSE FALSE END AS HAS_PO
        FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS p
        JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON p.ASSET_ID = am.ASSET_ID
        LEFT JOIN MFGPULSE_DB.ANALYTICS.PROCUREMENT_RECOMMENDATIONS pr ON p.ASSET_ID = pr.ASSET_ID
        WHERE (p.RUL_HOURS < 200 OR p.DEGRADATION_SCORE > 0.6 OR p.FAILURE_MODE_PRED != 'normal')
            AND NOT EXISTS (
                SELECT 1 FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS wo
                WHERE wo.ASSET_ID = p.ASSET_ID AND wo.STATUS IN ('open', 'in_progress')
            );
BEGIN
    OPEN wo_cursor;
    FOR rec IN wo_cursor DO
        c_asset_id := rec.ASSET_ID;
        c_asset_name := rec.ASSET_NAME;
        c_rul := rec.RUL_HOURS;
        c_deg := rec.DEGRADATION_SCORE;
        c_failure_mode := rec.FAILURE_MODE_PRED;
        c_part_id := rec.PART_ID;
        c_has_po := rec.HAS_PO;
        c_wo_type := CASE WHEN :c_rul < 48 THEN 'emergency' WHEN :c_rul < 120 THEN 'corrective' ELSE 'preventive' END;
        c_priority := CASE WHEN :c_rul < 48 THEN 'EMERGENCY' WHEN :c_rul < 120 THEN 'HIGH' WHEN :c_deg > 0.7 THEN 'MEDIUM' ELSE 'LOW' END;
        c_hours := CASE WHEN :c_rul < 48 THEN 8 WHEN :c_rul < 120 THEN 6 ELSE 4 END;
        c_cost := CASE WHEN :c_rul < 48 THEN 1300 WHEN :c_rul < 120 THEN 1100 ELSE 900 END;
        LET tech_idx NUMBER := MOD(:v_created, 4);
        c_assigned_to := CASE :tech_idx WHEN 0 THEN 'Mike Torres' WHEN 1 THEN 'Sarah Chen' WHEN 2 THEN 'James Wright' ELSE 'Maria Garcia' END;
        c_wo_id := 'WO-AUTO-' || REPLACE(:c_asset_id, 'ASSET_', '') || '-' || TO_CHAR(CURRENT_TIMESTAMP(), 'YYYYMMDD_HH24MISS');
        INSERT INTO MFGPULSE_DB.RAW_IT.WORK_ORDERS
            (WO_ID, ASSET_ID, WO_TYPE, CREATED_DATE, PRIORITY, STATUS, ASSIGNED_TO, LABOR_HOURS, PARTS_COST, TOTAL_COST)
        VALUES (:c_wo_id, :c_asset_id, :c_wo_type, CURRENT_TIMESTAMP(), :c_priority, 'open', :c_assigned_to, :c_hours, 500, :c_cost);
        BEGIN
            CALL MFGPULSE_DB.RAW_IT.LOG_APP_NOTIFICATION(
                'WO_CREATED', 'New WO: ' || :c_wo_id || ' — ' || :c_asset_name,
                :c_asset_name || ': ' || UPPER(:c_wo_type) || ' work order auto-generated. RUL=' || ROUND(:c_rul, 0)::VARCHAR || 'h, Mode=' || :c_failure_mode || ', Priority=' || :c_priority || '. Assigned to ' || :c_assigned_to || '.',
                :c_wo_id);
        EXCEPTION WHEN OTHER THEN NULL;
        END;
        IF (:c_part_id IS NOT NULL AND NOT :c_has_po AND :c_rul < 120) THEN
            BEGIN
                CALL MFGPULSE_DB.RAW_IT.LOG_APP_NOTIFICATION(
                    'PART_SHORTAGE_ALERT', 'Parts needed for ' || :c_wo_id,
                    :c_asset_name || ' needs part ' || :c_part_id || ' (no open PO). RUL=' || ROUND(:c_rul, 0)::VARCHAR || 'h. Create PO urgently.',
                    :c_wo_id);
            EXCEPTION WHEN OTHER THEN NULL;
            END;
        END IF;
        v_created := :v_created + 1;
    END FOR;
    CLOSE wo_cursor;
    RETURN 'Work orders generated: ' || :v_created || ' at ' || CURRENT_TIMESTAMP()::VARCHAR;
END;
$$;

-- AUTO_GENERATE_WORK_ORDERS_TASK — runs every 12 hours (created suspended)
CREATE OR REPLACE TASK ANALYTICS.AUTO_GENERATE_WORK_ORDERS_TASK
    WAREHOUSE = MFGPULSE_AUTOMATION_WH
    SCHEDULE = '720 MINUTE'
    SUSPEND_TASK_AFTER_NUM_FAILURES = 2
AS CALL MFGPULSE_DB.ANALYTICS.AUTO_GENERATE_WORK_ORDERS();
-- Note: Task created SUSPENDED. To enable: ALTER TASK ANALYTICS.AUTO_GENERATE_WORK_ORDERS_TASK RESUME;
