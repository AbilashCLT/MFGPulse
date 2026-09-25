import streamlit as st
import pandas as pd
import hashlib

DB = "MFGPULSE_DB"

EXEC_SUMMARY_PROMPT = """Act as a senior executive communications specialist. Review the information provided and create a concise executive summary intended for leadership stakeholders.
Output ONLY clean HTML suitable for embedding inside a <div>. Use <b> for section headers, <ul><li> for bullet points, and <br> for spacing between sections.
Do NOT use markdown syntax (no **, no ##, no - bullets, no asterisks). Do NOT include <html>, <head>, <body>, or <script> tags.
Requirements:
- Focus on business outcomes, impact, risks, opportunities, and decisions.
- Remove operational noise and unnecessary technical details.
- Highlight key achievements, progress, and measurable results.
- Clearly call out blockers, risks, and required leadership actions.
- Use confident, professional, executive-level language.
Structure:
<b>Executive Summary</b><ul><li>Overall status and key message</li></ul>
<b>Key Business Outcomes</b><ul><li>Outcome 1</li><li>Outcome 2</li></ul>
<b>Risks &amp; Concerns</b><ul><li>Risk 1</li><li>Risk 2</li></ul>
<b>Next Steps</b><ul><li>Action 1</li><li>Action 2</li></ul>
Tone: Boardroom-ready, crisp and data-driven. Maximum 200 words.
Information to summarize:
"""

def generate_executive_summary(data_block, page_key):
    cache_key = f"_llm_summary_{page_key}"
    hash_key = f"_llm_hash_{page_key}"
    data_hash = hashlib.md5(data_block.encode()).hexdigest()[:12]
    if st.session_state.get(hash_key) == data_hash and cache_key in st.session_state:
        return st.session_state[cache_key]
    try:
        prompt = EXEC_SUMMARY_PROMPT + data_block
        result = get_conn().query(
            "SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-8b', ?) AS SUMMARY",
            params=[prompt],
        )
        summary = result.iloc[0]["SUMMARY"] if len(result) > 0 else "Summary unavailable."
        st.session_state[cache_key] = summary
        st.session_state[hash_key] = data_hash
        return summary
    except Exception as ex:
        return f"Summary generation failed: {ex}"

C = {
    "critical": "#EF4444", "warning": "#F59E0B", "watch": "#3B82F6",
    "healthy": "#10B981", "info": "#6B7280", "bg": "#0E1117",
    "card": "#1E293B", "accent": "#8B5CF6",
}

PERSONA_CONFIG = {
    "TECHNICIAN": {
        "label": "Technician",
        "icon": ":material/build:",
        "pages": ["maintenance", "wo_po", "operations", "procurement", "copilot"],
    },
    "RELIABILITY_ENGINEER": {
        "label": "Reliability engineer",
        "icon": ":material/troubleshoot:",
        "pages": ["maintenance", "digital_twin", "wo_po", "operations", "procurement", "copilot"],
    },
    "SHIFT_SUPERVISOR": {
        "label": "Shift supervisor",
        "icon": ":material/swap_horiz:",
        "pages": ["operations", "wo_po", "maintenance", "procurement", "executive", "copilot"],
    },
    "PLANT_MANAGER": {
        "label": "Plant manager",
        "icon": ":material/analytics:",
        "pages": ["executive", "operations", "wo_po", "maintenance", "procurement", "admin", "copilot"],
    },
    "PROCUREMENT_ADMIN": {
        "label": "Procurement admin",
        "icon": ":material/local_shipping:",
        "pages": ["procurement", "wo_po", "maintenance", "operations", "copilot"],
    },
    "APP_ADMIN": {
        "label": "Application admin",
        "icon": ":material/shield_person:",
        "pages": ["executive", "operations", "wo_po", "maintenance", "procurement", "digital_twin", "admin", "copilot"],
    },
}

def get_conn():
    return st.session_state.conn

def fmt_currency(val):
    if val is None or pd.isna(val):
        return "$0"
    return f"${int(val):,}"

def fmt_hours(val):
    if val is None or pd.isna(val):
        return "N/A"
    return f"{int(val):,}h"

def fmt_pct(val):
    if val is None or pd.isna(val):
        return "0%"
    return f"{val:.1f}%"

RISK_COLOR = {"CRITICAL_SHORTAGE": "red", "EXPEDITE": "orange", "REPLENISH_NOW": "orange", "ORDER_NOW": "blue", "RESERVED": "green", "NO_RISK": "green", "UNKNOWN": "gray"}
FAILURE_MODE_LABEL = {
    "bearing_wear": "Bearing wear", "thermal_degradation": "Thermal degradation",
    "misalignment": "Misalignment", "imbalance": "Imbalance",
    "undetermined_degradation": "Undetermined degradation", "normal": "Normal",
}

@st.cache_data(ttl=120)
def load_executive_summary():
    return get_conn().query(f"SELECT * FROM {DB}.ANALYTICS.EXECUTIVE_SUMMARY")

@st.cache_data(ttl=120)
def load_predictions():
    return get_conn().query(f"SELECT * FROM {DB}.ANALYTICS.PREDICTIONS_WITH_COST ORDER BY RUL_HOURS ASC")

@st.cache_data(ttl=120)
def load_alerts():
    return get_conn().query(f"SELECT * FROM {DB}.ANALYTICS.ACTIVE_ALERTS ORDER BY SEVERITY DESC, RUL_HOURS ASC")

@st.cache_data(ttl=120)
def load_oee_by_line():
    return get_conn().query(f"""
        SELECT LINE_ID, ROUND(AVG(OEE_PCT),1) AS OEE, ROUND(AVG(AVAILABILITY_PCT),1) AS AVAIL,
            ROUND(AVG(PERFORMANCE_PCT),1) AS PERF, ROUND(AVG(QUALITY_PCT),1) AS QUAL
        FROM {DB}.ANALYTICS.OEE_METRICS GROUP BY LINE_ID ORDER BY LINE_ID
    """)

@st.cache_data(ttl=120)
def load_oee_daily_trend():
    return get_conn().query(f"""
        SELECT SHIFT_DATE::DATE AS DAY, LINE_ID, ASSET_NAME,
            ROUND(AVG(OEE_PCT),1) AS OEE,
            ROUND(AVG(AVAILABILITY_PCT),1) AS AVAIL,
            ROUND(AVG(PERFORMANCE_PCT),1) AS PERF,
            ROUND(AVG(QUALITY_PCT),1) AS QUAL
        FROM {DB}.ANALYTICS.OEE_METRICS
        GROUP BY DAY, LINE_ID, ASSET_NAME ORDER BY DAY
    """)

@st.cache_data(ttl=120)
def load_oee_loss():
    return get_conn().query(f"""
        SELECT ASSET_NAME, ROUND(AVG(AVAILABILITY_LOSS_PCT),1) AS AVAIL_LOSS,
            ROUND(AVG(PERFORMANCE_LOSS_PCT),1) AS PERF_LOSS, ROUND(AVG(QUALITY_LOSS_PCT),1) AS QUAL_LOSS
        FROM {DB}.ANALYTICS.OEE_METRICS WHERE LOSS_ATTRIBUTED_TO IS NOT NULL GROUP BY ASSET_NAME
    """)

@st.cache_data(ttl=120)
def load_cost_by_asset():
    return get_conn().query(f"SELECT * FROM {DB}.ANALYTICS.COST_IMPACT_BY_ASSET ORDER BY TOTAL_COST DESC")

@st.cache_data(ttl=120)
def load_open_work_orders():
    return get_conn().query(f"SELECT * FROM {DB}.RAW_IT.WORK_ORDERS WHERE STATUS NOT IN ('completed','cancelled') ORDER BY CREATED_DATE DESC")

@st.cache_data(ttl=120)
def load_live_predictions():
    df = get_conn().query(f"SELECT * FROM {DB}.ML_MODELS.LIVE_PREDICTIONS_WITH_ANOMALY ORDER BY RUL_HOURS ASC")
    return df.drop_duplicates(subset=["ASSET_ID"], keep="first") if len(df) > 0 else df

@st.cache_data(ttl=120)
def load_users():
    return get_conn().query(f"SELECT * FROM {DB}.RAW_IT.USERS WHERE ACTIVE = TRUE ORDER BY USERNAME")

@st.cache_data(ttl=60)
def load_all_users_admin():
    return get_conn().query(f"SELECT * FROM {DB}.RAW_IT.USERS ORDER BY ACTIVE DESC, USERNAME")

@st.cache_data(ttl=120)
def load_maintenance_logs():
    return get_conn().query(f"""
        SELECT ml.LOG_ID, ml.WO_ID, ml.ASSET_ID, am.ASSET_NAME, ml.TIMESTAMP, ml.TECHNICIAN, ml.NOTES_TEXT,
            wo.WO_TYPE, wo.PRIORITY, wo.STATUS
        FROM {DB}.RAW_IT.MAINTENANCE_LOGS ml
        JOIN {DB}.RAW_OT.ASSET_MASTER am ON ml.ASSET_ID = am.ASSET_ID
        LEFT JOIN {DB}.RAW_IT.WORK_ORDERS wo ON ml.WO_ID = wo.WO_ID
        ORDER BY ml.TIMESTAMP DESC
    """)

@st.cache_data(ttl=120)
def load_procurement_recs():
    try:
        return get_conn().query(f"SELECT * FROM {DB}.ANALYTICS.PROCUREMENT_RECOMMENDATIONS ORDER BY RUL_HOURS")
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=120)
def load_safety_stock_policy():
    try:
        return get_conn().query(f"SELECT PART_ID, MIN_STOCK, REORDER_POINT, REORDER_QTY, AT_RISK_ASSETS FROM {DB}.ANALYTICS.SAFETY_STOCK_POLICY")
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=120)
def load_open_pos():
    try:
        return get_conn().query(f"""
            SELECT po.PO_ID, s.SUPPLIER_NAME, po.STATUS, po.PRIORITY, po.REQUIRED_BY_DATE,
                po.EXPECTED_ARRIVAL_DATE, po.TOTAL_COST, pol.PART_ID, pol.ASSET_ID, pol.PROCUREMENT_RISK
            FROM {DB}.RAW_IT.PURCHASE_ORDERS po
            JOIN {DB}.RAW_IT.PURCHASE_ORDER_LINES pol ON po.PO_ID = pol.PO_ID
            LEFT JOIN {DB}.RAW_IT.SUPPLIERS s ON po.SUPPLIER_ID = s.SUPPLIER_ID
            WHERE po.STATUS NOT IN ('cancelled','received')
            ORDER BY po.CREATED_DATE DESC
        """)
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=120)
def load_parts_atp():
    try:
        return get_conn().query(f"""
            SELECT PART_ID, PART_NAME, QUANTITY_ON_HAND, RESERVED_QUANTITY, AVAILABLE_TO_PROMISE,
                LEAD_TIME_DAYS, UNIT_COST, SUPPLIER_NAME
            FROM {DB}.ANALYTICS.PARTS_AVAILABLE_TO_PROMISE ORDER BY AVAILABLE_TO_PROMISE ASC
        """)
    except Exception:
        return pd.DataFrame()

def procurement_available():
    try:
        get_conn().query(f"SELECT 1 FROM {DB}.ANALYTICS.PROCUREMENT_RECOMMENDATIONS LIMIT 0")
        return True
    except Exception:
        return False

@st.cache_data(ttl=120)
def load_all_work_orders():
    df = get_conn().query(f"""
        SELECT wo.*, am.ASSET_NAME, am.LINE_ID
        FROM {DB}.RAW_IT.WORK_ORDERS wo
        JOIN {DB}.RAW_OT.ASSET_MASTER am ON wo.ASSET_ID = am.ASSET_ID
        ORDER BY wo.CREATED_DATE DESC
    """)
    return df.drop_duplicates(subset=["WO_ID"], keep="first") if len(df) > 0 else df

@st.cache_data(ttl=120)
def load_all_purchase_orders():
    try:
        return get_conn().query(f"""
            SELECT po.PO_ID, po.SUPPLIER_ID, s.SUPPLIER_NAME, po.CREATED_DATE, po.REQUIRED_BY_DATE,
                po.EXPECTED_ARRIVAL_DATE, po.STATUS, po.PRIORITY, po.TOTAL_COST, po.CREATED_BY, po.SOURCE,
                po.REJECTION_REASON, po.REJECTED_BY, po.REJECTED_AT,
                pol.PART_ID, pi.PART_NAME,
                LISTAGG(DISTINCT am.ASSET_NAME, ', ') AS ASSET_NAME,
                LISTAGG(DISTINCT pol.ASSET_ID, ', ') AS ASSET_ID,
                LISTAGG(DISTINCT pol.WO_ID, ', ') AS WO_ID,
                SUM(pol.QUANTITY_ORDERED) AS QUANTITY_ORDERED,
                MAX(pol.UNIT_COST) AS UNIT_COST,
                SUM(pol.LINE_COST) AS LINE_COST,
                MIN(pol.RUL_HOURS_AT_ORDER) AS RUL_HOURS_AT_ORDER,
                MAX(pol.FAILURE_MODE_PRED) AS FAILURE_MODE_PRED,
                MAX(pol.PROCUREMENT_RISK) AS PROCUREMENT_RISK
            FROM {DB}.RAW_IT.PURCHASE_ORDERS po
            JOIN {DB}.RAW_IT.PURCHASE_ORDER_LINES pol ON po.PO_ID = pol.PO_ID
            LEFT JOIN {DB}.RAW_IT.SUPPLIERS s ON po.SUPPLIER_ID = s.SUPPLIER_ID
            LEFT JOIN {DB}.RAW_IT.PARTS_INVENTORY pi ON pol.PART_ID = pi.PART_ID
            LEFT JOIN {DB}.RAW_OT.ASSET_MASTER am ON pol.ASSET_ID = am.ASSET_ID
            GROUP BY po.PO_ID, po.SUPPLIER_ID, s.SUPPLIER_NAME, po.CREATED_DATE, po.REQUIRED_BY_DATE,
                po.EXPECTED_ARRIVAL_DATE, po.STATUS, po.PRIORITY, po.TOTAL_COST, po.CREATED_BY, po.SOURCE,
                po.REJECTION_REASON, po.REJECTED_BY, po.REJECTED_AT,
                pol.PART_ID, pi.PART_NAME
            ORDER BY po.CREATED_DATE DESC
        """)
    except Exception:
        return pd.DataFrame()

WO_TYPE_COLOR = {"emergency": "red", "corrective": "orange", "preventive": "green"}
WO_STATUS_COLOR = {"open": "blue", "in_progress": "orange", "completed": "green", "cancelled": "gray"}
PO_STATUS_COLOR = {"draft": "gray", "pending_approval": "orange", "approved": "blue", "ordered": "blue", "shipped": "violet", "received": "green", "cancelled": "red"}
NOTIF_ICON = {"WO_CREATED": ":material/add_task:", "WO_STARTED": ":material/play_arrow:", "WO_COMPLETED": ":material/check_circle:", "PO_CREATED": ":material/receipt_long:", "PO_APPROVED": ":material/thumb_up:", "PO_REJECTED": ":material/thumb_down:", "PO_RECEIVED": ":material/inventory:"}

@st.cache_data(ttl=15)
def load_unread_notifications(persona):
    try:
        return get_conn().query(
            f"SELECT NOTIF_ID, CREATED_AT, EVENT_TYPE, TITLE, MESSAGE, ENTITY_ID, PRIORITY FROM {DB}.RAW_IT.APP_NOTIFICATIONS WHERE PERSONA_TARGET = ? AND IS_READ = FALSE AND DISMISSED = FALSE ORDER BY CREATED_AT DESC LIMIT 20",
            params=[persona],
        )
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=60)
def load_notification_settings():
    try:
        return get_conn().query(f"SELECT * FROM {DB}.RAW_IT.NOTIFICATION_SETTINGS ORDER BY EVENT_TYPE")
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=120)
def load_parts_lifecycle():
    try:
        return get_conn().query(f"SELECT * FROM {DB}.ANALYTICS.PARTS_LIFECYCLE_INSIGHTS")
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=120)
def load_wo_parts_info():
    try:
        return get_conn().query(f"""
            SELECT pr.ASSET_ID, pr.PART_ID, pr.PART_NAME, pr.PROCUREMENT_RISK,
                pr.RECOMMENDED_PROCUREMENT_ACTION, pr.OPEN_PO_ID, pr.AVAILABLE_TO_PROMISE
            FROM {DB}.ANALYTICS.PROCUREMENT_RECOMMENDATIONS pr
        """)
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=30)
def load_wo_activity_log(wo_id):
    try:
        return get_conn().query(
            f"SELECT MIN(CREATED_AT) AS CREATED_AT, EVENT_TYPE, MIN(TITLE) AS TITLE, MIN(MESSAGE) AS MESSAGE, MIN(PRIORITY) AS PRIORITY FROM {DB}.RAW_IT.APP_NOTIFICATIONS WHERE ENTITY_ID = ? AND EVENT_TYPE IN ('WO_REASSIGNED','WO_FOLLOWUP','WO_STARTED','WO_COMPLETED') GROUP BY EVENT_TYPE, CREATED_AT ORDER BY CREATED_AT DESC LIMIT 20",
            params=[wo_id],
        )
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=120)
def load_planned_pos():
    try:
        return get_conn().query(f"SELECT * FROM {DB}.ANALYTICS.PLANNED_PURCHASE_ORDERS ORDER BY PRIORITY_SCORE DESC")
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=60)
def load_active_reservations():
    try:
        return get_conn().query(f"""
            SELECT WO_ID, ASSET_ID, PART_ID, QUANTITY_RESERVED, STATUS, CREATED_AT
            FROM {DB}.RAW_IT.PART_RESERVATIONS
            WHERE STATUS = 'active'
        """)
    except Exception:
        return pd.DataFrame()

@st.cache_data(ttl=60)
def load_latest_sensor_readings():
    return get_conn().query(f"""
        SELECT sr.ASSET_ID, am.ASSET_NAME, sr.TIMESTAMP,
            sr.VIBRATION_X, sr.VIBRATION_Y, sr.VIBRATION_Z,
            SQRT(POWER(sr.VIBRATION_X,2)+POWER(sr.VIBRATION_Y,2)+POWER(sr.VIBRATION_Z,2)) AS VIB_MAG,
            sr.TEMPERATURE, sr.RPM, sr.PRESSURE, sr.CURRENT_AMPS, sr.ACOUSTIC_DB
        FROM {DB}.RAW_OT.SENSOR_READINGS sr
        JOIN {DB}.RAW_OT.ASSET_MASTER am ON sr.ASSET_ID = am.ASSET_ID
        WHERE sr.TIMESTAMP >= DATEADD('hour', -24, CURRENT_TIMESTAMP())
        ORDER BY sr.TIMESTAMP DESC
    """)

def clear_all_caches():
    load_executive_summary.clear()
    load_predictions.clear()
    load_alerts.clear()
    load_oee_by_line.clear()
    load_oee_daily_trend.clear()
    load_oee_loss.clear()
    load_cost_by_asset.clear()
    load_open_work_orders.clear()
    load_live_predictions.clear()
    load_users.clear()
    load_all_users_admin.clear()
    load_maintenance_logs.clear()
    load_procurement_recs.clear()
    load_safety_stock_policy.clear()
    load_open_pos.clear()
    load_parts_atp.clear()
    load_all_work_orders.clear()
    load_all_purchase_orders.clear()
    load_unread_notifications.clear()
    load_notification_settings.clear()
    load_wo_parts_info.clear()
    load_parts_lifecycle.clear()
    load_wo_activity_log.clear()
    load_planned_pos.clear()
    load_latest_sensor_readings.clear()
    load_fatigue_trend.clear()

# --- Feature: Data Freshness SLA ---
@st.cache_data(ttl=60)
def load_data_freshness():
    return get_conn().query(f"SELECT * FROM {DB}.ANALYTICS.DATA_FRESHNESS_SLA")

def freshness_badge(status):
    colors = {"LIVE": "green", "RECENT": "blue", "APPROACHING_SLA": "orange", "SLA_BREACH": "red"}
    return f":{colors.get(status, 'gray')}[{status}]"

# --- Feature: Time-Range Comparison ---
@st.cache_data(ttl=120)
def load_kpi_snapshots():
    return get_conn().query(f"SELECT * FROM {DB}.ANALYTICS.KPI_SNAPSHOTS ORDER BY SNAPSHOT_DATE DESC")

@st.cache_data(ttl=120)
def load_oee_period_comparison():
    return get_conn().query(f"SELECT * FROM {DB}.ANALYTICS.OEE_PERIOD_COMPARISON")

@st.cache_data(ttl=120)
def load_alert_history():
    return get_conn().query(f"SELECT * FROM {DB}.ANALYTICS.ALERT_HISTORY ORDER BY ARCHIVED_AT DESC LIMIT 200")

def delta_badge(current, previous):
    if previous is None or previous == 0:
        return ""
    delta = current - previous
    if abs(delta) < 0.05:
        return ""
    arrow = "▲" if delta > 0 else "▼"
    color = "green" if delta > 0 else "red"
    return f":{color}[{arrow} {abs(delta):.1f}]"

# --- Feature: Model Drift Detection ---
@st.cache_data(ttl=300)
def load_drift_metrics():
    return get_conn().query(f"SELECT * FROM {DB}.ML_MODELS.DRIFT_METRICS")

@st.cache_data(ttl=300)
def load_drift_comparison():
    return get_conn().query(f"SELECT * FROM {DB}.ML_MODELS.DRIFT_COMPARISON ORDER BY COMPARISON_DATE DESC")

# --- Feature: Closed-Loop Model Improvement ---
@st.cache_data(ttl=300)
def load_model_accuracy():
    return get_conn().query(f"SELECT * FROM {DB}.ML_MODELS.MODEL_ACCURACY_LIVE")

@st.cache_data(ttl=300)
def load_feedback_log():
    return get_conn().query(f"SELECT * FROM {DB}.ML_MODELS.FEEDBACK_LOG ORDER BY CONFIRMED_AT DESC LIMIT 100")

# --- Feature: Board-Ready Executive Summary ---
BOARD_READY_PROMPT = """You are a manufacturing plant executive communications specialist writing for the C-suite and board of directors.
Produce a concise, structured briefing in THREE short paragraphs with NO markdown headers, NO bullet lists, NO asterisks, NO HTML tags.
Use plain text only with line breaks between paragraphs.

Paragraph 1 — STATUS: Open with the plant verdict (OPERATIONAL / DEGRADED / AT RISK). State Plant OEE vs 85% target. State critical and warning asset counts.
Paragraph 2 — FINANCIAL IMPACT: Cost avoided by predictive maintenance, ROI multiplier, cost-of-inaction exposure. Compare average failure cost vs planned repair cost to show the cost multiplier.
Paragraph 3 — ACTIONS REQUIRED: Name the top 2-3 assets needing leadership decisions. State what must happen (approve repair, expedite parts, schedule maintenance) and the financial consequence of delay.

Rules: Maximum 150 words. Every sentence must contain a number. No filler phrases. No technical jargon (no RUL, no degradation score). Write as if presenting to a board that has 60 seconds to read this.
Data:
"""

def generate_board_summary(data_block, page_key):
    cache_key = f"_llm_summary_{page_key}"
    hash_key = f"_llm_hash_{page_key}"
    data_hash = hashlib.md5(data_block.encode()).hexdigest()[:12]
    if st.session_state.get(hash_key) == data_hash and cache_key in st.session_state:
        return st.session_state[cache_key]
    try:
        prompt = BOARD_READY_PROMPT + data_block
        result = get_conn().query(
            "SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', ?) AS SUMMARY",
            params=[prompt],
        )
        summary = result.iloc[0]["SUMMARY"] if len(result) > 0 else "Summary unavailable."
        st.session_state[cache_key] = summary
        st.session_state[hash_key] = data_hash
        return summary
    except Exception as ex:
        return f"Summary generation failed: {ex}"

# --- Feature: Fatigue Trend (for Operations Dashboard) ---
@st.cache_data(ttl=120)
def load_fatigue_trend():
    try:
        return get_conn().query(f"""
            SELECT f.ASSET_ID, am.ASSET_NAME, f.TIMESTAMP, f.FATIGUE_SCORE, f.FATIGUE_LEVEL
            FROM {DB}.ML_MODELS.FATIGUE_SCORES f
            JOIN {DB}.RAW_OT.ASSET_MASTER am ON f.ASSET_ID = am.ASSET_ID
            WHERE f.TIMESTAMP >= DATEADD('day', -30, CURRENT_TIMESTAMP())
            ORDER BY f.ASSET_ID, f.TIMESTAMP DESC
        """)
    except Exception:
        return pd.DataFrame()
