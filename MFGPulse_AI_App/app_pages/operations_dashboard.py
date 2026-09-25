import streamlit as st
import pandas as pd
import altair as alt
from app_pages._shared import (
    load_alerts, load_live_predictions, load_open_work_orders, load_all_work_orders,
    load_procurement_recs, load_open_pos, load_latest_sensor_readings, procurement_available,
    load_predictions, load_oee_by_line, load_cost_by_asset, load_fatigue_trend,
    load_kpi_snapshots, load_data_freshness,
    fmt_hours, fmt_currency, C, DB, get_conn, RISK_COLOR, FAILURE_MODE_LABEL,
    generate_executive_summary,
)

alt.renderers.enable("mimetype")

# ─── Helper: glow card (same pattern as executive_dashboard.py & digital_twin.py) ───
def _glow_card(title, content_html, border_color="#00D4FF", icon=""):
    st.html(f"""
    <div style="
        background: rgba(17, 24, 39, 0.8);
        border: 1px solid {border_color}33;
        border-left: 3px solid {border_color};
        border-radius: 8px;
        padding: 16px;
        margin-bottom: 8px;
        box-shadow: 0 0 15px {border_color}11;
    ">
        <div style="color: {border_color}; font-size: 0.7rem; text-transform: uppercase;
                    letter-spacing: 0.1em; margin-bottom: 8px; font-weight: 600;">
            {icon} {title}
        </div>
        {content_html}
    </div>
    """)

def _section_header(icon, title, color="#00D4FF"):
    st.html(f"""
    <div style="display:flex; align-items:center; gap:12px; margin: 20px 0 12px 0;">
        <div style="color:{color}; font-size:0.75rem; text-transform:uppercase; letter-spacing:0.1em;
                    font-weight:700;">{icon} {title}</div>
        <div style="flex:1; height:1px; background:{color}22;"></div>
    </div>
    """)

def _risk_row_color(val, low, mid):
    if val < low:
        return "#EF4444"
    if val < mid:
        return "#F59E0B"
    return "#10B981"

# ─── Load data ───
conn = get_conn()
alerts = load_alerts()
preds = load_live_predictions()
preds_cost = load_predictions()
wos = load_open_work_orders()
all_wo = load_all_work_orders()

# Merge anomaly scores from live predictions into preds_cost
if len(preds) > 0 and len(preds_cost) > 0 and "ANOMALY_SCORE" in preds.columns:
    anomaly_map = preds.set_index("ASSET_ID")[["ANOMALY_SCORE"]].to_dict("index")
    preds_cost["ANOMALY_SCORE"] = preds_cost["ASSET_ID"].map(lambda x: anomaly_map.get(x, {}).get("ANOMALY_SCORE", 0))
else:
    preds_cost["ANOMALY_SCORE"] = 0

avg_anomaly = round(preds_cost["ANOMALY_SCORE"].mean(), 2) if len(preds_cost) > 0 else 0
high_fatigue_count = len(preds_cost[preds_cost["FATIGUE_LEVEL"] == "HIGH"]) if len(preds_cost) > 0 and "FATIGUE_LEVEL" in preds_cost.columns else 0

proc = load_procurement_recs() if procurement_available() else pd.DataFrame()
parts_at_risk = len(proc[proc["PROCUREMENT_RISK"].isin(["CRITICAL_SHORTAGE", "EXPEDITE"])]) if len(proc) > 0 and "PROCUREMENT_RISK" in proc.columns else 0

emergency_wo = len(all_wo[(all_wo["WO_TYPE"] == "emergency") & (all_wo["STATUS"].isin(["open", "in_progress"]))]) if len(all_wo) > 0 else 0
completed_wo = len(all_wo[all_wo["STATUS"] == "completed"]) if len(all_wo) > 0 else 0
completion_rate = round(completed_wo / len(all_wo) * 100) if len(all_wo) > 0 else 0

# OEE data
oee = load_oee_by_line()
plant_oee = round(oee["OEE"].mean(), 1) if len(oee) > 0 else 0

# Cost of inaction
total_inaction = preds_cost["COST_OF_INACTION"].fillna(0).sum() if len(preds_cost) > 0 and "COST_OF_INACTION" in preds_cost.columns else 0

# Fatigue trend
fatigue_df = load_fatigue_trend()
degrading_count = 0
fatigue_slopes = {}
if len(fatigue_df) > 0:
    for asset_id, grp in fatigue_df.groupby("ASSET_ID"):
        if len(grp) >= 2:
            recent = grp.head(min(5, len(grp)))["FATIGUE_SCORE"].mean()
            older = grp.tail(min(5, len(grp)))["FATIGUE_SCORE"].mean()
            slope = recent - older
            name = grp.iloc[0]["ASSET_NAME"]
            fatigue_slopes[name] = slope
            if slope > 0.01:
                degrading_count += 1

# Plant status verdict (matching executive dashboard pattern)
crit = len(preds[preds["STAGE_PRED"] == "Critical"]) if len(preds) > 0 else 0
warn = len(preds[preds["STAGE_PRED"] == "Warning"]) if len(preds) > 0 else 0
total_assets = len(preds) if len(preds) > 0 else 10

has_critical_supply = len(proc[proc["PROCUREMENT_RISK"] == "CRITICAL_SHORTAGE"]) > 0 if len(proc) > 0 and "PROCUREMENT_RISK" in proc.columns else False

if crit > 0 or has_critical_supply:
    plant_status, status_color, status_icon = "AT RISK", "#EF4444", "🔴"
elif warn >= total_assets * 0.5 or plant_oee < 70:
    plant_status, status_color, status_icon = "DEGRADED", "#F59E0B", "🟡"
else:
    plant_status, status_color, status_icon = "OPERATIONAL", "#10B981", "🟢"

# Data freshness (matching executive dashboard pattern)
try:
    freshness = load_data_freshness()
    sensor_fresh = freshness[freshness['SOURCE_TABLE'] == 'SENSOR_READINGS'].iloc[0] if len(freshness) > 0 else {}
    stale_min = sensor_fresh.get('STALENESS_MINUTES', '?') if sensor_fresh is not None and len(sensor_fresh) > 0 else '?'
except Exception:
    stale_min = '?'

# ═══════════════════════════════════════════════════════════════
# HEADER (matching executive dashboard styling exactly)
# ═══════════════════════════════════════════════════════════════
st.html(f"""
<div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:4px; flex-wrap:wrap; gap:10px;">
    <div style="display:flex; align-items:center; gap:14px;">
        <div style="font-size:1.5rem; font-weight:800; color:#E0E7FF;">🏭 Operations center</div>
        <div style="padding:4px 14px; border-radius:12px; font-size:0.65rem; font-weight:700;
                    text-transform:uppercase; letter-spacing:0.08em;
                    background:{status_color}18; color:{status_color}; border:1px solid {status_color}44;
                    box-shadow: 0 0 12px {status_color}22;">
            {status_icon} {plant_status}
        </div>
    </div>
    <div style="display:flex; align-items:center; gap:8px;">
        <div style="padding:2px 8px; border-radius:8px; font-size:0.6rem; font-weight:600;
                    background:#10B98118; color:#10B981; border:1px solid #10B98133;">● LIVE</div>
        <span style="font-size:0.65rem; color:#64748B;">Sensor data: {stale_min} min ago</span>
    </div>
</div>
""")
st.caption("Fleet status, alert triage, shift handover, and work orders — action-oriented for plant managers")

with st.expander("About this page", expanded=False, icon=":material/info:"):
    st.markdown("""
**Purpose**: Real-time operational awareness — the page a Shift Supervisor or Plant Manager monitors throughout the shift.

**Stage classification** (ISO 13381-1):
- **Critical** = RUL < 48h or degradation >= 0.65 | **Warning** = RUL < 168h or degradation >= 0.30 | **Healthy** = All other

**Alert severity**: Critical > Warning > Watch > Info

**Key metrics**: Fleet status (critical/warning/healthy counts), alert summary, plant OEE vs 85% target, parts at risk count.

**Tabs**:
- **Action queue** — Asset risk matrix sorted by urgency with stage, RUL, degradation, anomaly, failure cost, cost-of-inaction, parts status, and action window. Risk heatmap (degradation vs anomaly scatter), cost exposure by action window, fatigue trend chart, and AI-generated shift action plan.
- **Fleet status** — Per-asset cards with labeled Stage/Fatigue/Trend indicators, RUL, degradation score, anomaly score, transition probability, parts status, and action badges. Fatigue trend shows ↑ Degrading / → Stable / ↓ Improving based on slope.
- **Alert triage** — Filterable by severity. Color-coded alert cards with asset context, RUL, and degradation score.
- **Shift handover** — OEE summary by line, cost exposure callout, AI-generated shift briefing with regenerate option.
- **Work orders** — Open work orders with priority, asset, cost, assignee, and aging indicators.
- **Sensor feed** — Live 24-hour sensor sparklines for each asset (vibration, temperature, pressure, RPM, current, acoustic).

**Fatigue trend chart**: Daily-averaged fatigue scores for all 10 assets with a shaded band showing intraday peak severity. Filterable by time period (7d/14d/30d/All) and asset selection. Smooths sensor noise while preserving critical spikes.

**Data sources**: `ML_MODELS.LIVE_PREDICTIONS`, `ML_MODELS.FATIGUE_SCORES`, `ANALYTICS.ACTIVE_ALERTS`, `ANALYTICS.OEE_METRICS`, `RAW_OT.SENSOR_READINGS`, `RAW_IT.WORK_ORDERS`
""")

# ═══════════════════════════════════════════════════════════════
# KPI BAR (using styled HTML cards matching executive dashboard)
# ═══════════════════════════════════════════════════════════════
_section_header("📊", "Key metrics")

k1, k2, k3, k4 = st.columns(4)
with k1:
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid #00D4FF33; border-radius:10px;
                padding:16px; text-align:center; box-shadow: 0 0 15px #00D4FF11;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">🏭 Fleet status</div>
        <div style="display:flex; justify-content:center; gap:16px; margin-bottom:8px;">
            <div>
                <div style="font-size:1.6rem; font-weight:800; color:#EF4444;">{crit}</div>
                <div style="font-size:0.55rem; color:#EF4444; text-transform:uppercase;">Critical</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.6rem; font-weight:800; color:#F59E0B;">{warn}</div>
                <div style="font-size:0.55rem; color:#F59E0B; text-transform:uppercase;">Warning</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.6rem; font-weight:800; color:#10B981;">{total_assets - crit - warn}</div>
                <div style="font-size:0.55rem; color:#10B981; text-transform:uppercase;">Healthy</div>
            </div>
        </div>
        <div style="background:rgba(255,255,255,0.04); border-radius:4px; height:6px; overflow:hidden; display:flex;">
            <div style="width:{crit/max(total_assets,1)*100:.0f}%; background:#EF4444; height:100%;"></div>
            <div style="width:{warn/max(total_assets,1)*100:.0f}%; background:#F59E0B; height:100%;"></div>
            <div style="width:{(total_assets-crit-warn)/max(total_assets,1)*100:.0f}%; background:#10B981; height:100%;"></div>
        </div>
        <div style="font-size:0.6rem; color:#64748B; margin-top:6px;">{total_assets} total assets</div>
    </div>
    """)

with k2:
    # Highest Risk Asset card
    if len(preds_cost) > 0:
        top_risk = preds_cost.iloc[0]  # already sorted by RUL ASC
        tr_name = top_risk["ASSET_NAME"]
        tr_rul = top_risk.get("RUL_HOURS", 0) or 0
        tr_deg = top_risk.get("DEGRADATION_SCORE", 0) or 0
        tr_fatigue = top_risk.get("FATIGUE_LEVEL", "?")
        tr_color = "#EF4444" if tr_deg > 0.30 else "#F59E0B" if tr_deg > 0.15 else "#10B981"
        fl_color = "#EF4444" if tr_fatigue == "HIGH" else "#F59E0B" if tr_fatigue == "ACCUMULATING" else "#10B981"
    else:
        tr_name, tr_rul, tr_deg, tr_fatigue = "N/A", 0, 0, "?"
        tr_color, fl_color = "#64748B", "#64748B"
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid {tr_color}33; border-left:3px solid {tr_color};
                border-radius:10px; padding:16px; text-align:center; box-shadow: 0 0 15px {tr_color}11;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">🎯 Highest risk asset</div>
        <div style="font-size:1.2rem; font-weight:800; color:#E0E7FF; margin-bottom:4px;">{tr_name}</div>
        <div style="display:flex; justify-content:center; gap:14px; margin-bottom:8px;">
            <div>
                <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase;">RUL</div>
                <div style="font-size:1rem; font-weight:700; color:{tr_color};">{tr_rul:.0f}h</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase;">Degradation</div>
                <div style="font-size:1rem; font-weight:700; color:{tr_color};">{tr_deg:.3f}</div>
            </div>
        </div>
        <div style="display:inline-block; padding:2px 10px; border-radius:10px; font-size:0.55rem; font-weight:700;
                    background:{fl_color}18; color:{fl_color}; border:1px solid {fl_color}33;">
            Fatigue: {tr_fatigue}</div>
        <div style="font-size:0.6rem; color:#64748B; margin-top:8px;">Plant OEE: <span style="color:{'#EF4444' if plant_oee < 60 else '#F59E0B' if plant_oee < 80 else '#10B981'}; font-weight:600;">{plant_oee}%</span></div>
    </div>
    """)

with k3:
    exp_color = "#EF4444" if total_inaction > 30000 else "#F59E0B" if total_inaction > 10000 else "#10B981"
    anom_color = "#EF4444" if avg_anomaly > 0.5 else "#F59E0B" if avg_anomaly > 0.3 else "#10B981"
    fat_color = "#EF4444" if high_fatigue_count > 0 else "#10B981"
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid {exp_color}33; border-left:3px solid {exp_color};
                border-radius:10px; padding:16px; text-align:center; box-shadow: 0 0 15px {exp_color}11;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">💰 Cost & health signals</div>
        <div style="font-size:1.8rem; font-weight:800; color:{exp_color};
                    text-shadow: 0 0 12px {exp_color}55;">${total_inaction:,.0f}</div>
        <div style="font-size:0.68rem; color:#94A3B8; margin-top:2px;">Total cost of inaction</div>
        <div style="display:flex; justify-content:center; gap:14px; margin-top:10px;">
            <div>
                <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase;">Avg anomaly</div>
                <div style="font-size:0.95rem; font-weight:700; color:{anom_color};">{avg_anomaly}</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase;">HIGH fatigue</div>
                <div style="font-size:0.95rem; font-weight:700; color:{fat_color};">{high_fatigue_count}</div>
            </div>
        </div>
    </div>
    """)

with k4:
    with st.container(horizontal=True):
        st.html(f"""
        <div style="background:rgba(17,24,39,0.9); border:1px solid #00D4FF33; border-radius:10px;
                    padding:16px; text-align:center; box-shadow: 0 0 15px #00D4FF11;">
            <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                        font-weight:600; margin-bottom:10px;">📋 Work orders & alerts</div>
            <div style="display:flex; justify-content:center; gap:16px;">
                <div>
                    <div style="font-size:1.4rem; font-weight:800; color:#3B82F6;">{len(wos)}</div>
                    <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">Open WOs</div>
                </div>
                <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
                <div>
                    <div style="font-size:1.4rem; font-weight:800; color:#EF4444;">{emergency_wo}</div>
                    <div style="font-size:0.55rem; color:#EF4444; text-transform:uppercase;">Emergency</div>
                </div>
                <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
                <div>
                    <div style="font-size:1.4rem; font-weight:800; color:#F59E0B;">{len(alerts)}</div>
                    <div style="font-size:0.55rem; color:#F59E0B; text-transform:uppercase;">Alerts</div>
                </div>
            </div>
            <div style="font-size:0.6rem; color:#64748B; margin-top:8px;">
                WO completion: <span style="color:#10B981; font-weight:600;">{completion_rate}%</span>
                · Degrading: <span style="color:{'#EF4444' if degrading_count > 0 else '#10B981'}; font-weight:600;">{degrading_count}</span>
                · Parts at risk: <span style="color:{'#EF4444' if parts_at_risk > 0 else '#10B981'}; font-weight:600;">{parts_at_risk}</span>
            </div>
        </div>
        """)

# ═══════════════════════════════════════════════════════════════
# TABS
# ═══════════════════════════════════════════════════════════════
tab_action, tab_fleet, tab_alerts, tab_handover, tab_wo, tab_sensor = st.tabs([
    "Action queue", "Fleet status", "Alert triage", "Shift handover", "Work orders", "Sensor feed"
])

# ─── TAB 1: ACTION QUEUE ───
with tab_action:
    if len(preds_cost) == 0:
        st.info("No prediction data available.")
    else:
        # Risk matrix table
        _section_header("🎯", "Asset risk matrix — sorted by urgency")

        rows_html = ""
        for _, row in preds_cost.iterrows():
            name = row.get("ASSET_NAME", "?")
            stage = row.get("STAGE_PRED", "?")
            rul = row.get("RUL_HOURS", 0) or 0
            fm = FAILURE_MODE_LABEL.get(row.get("FAILURE_MODE_PRED", ""), row.get("FAILURE_MODE_PRED", "?"))
            fail_cost = row.get("ESTIMATED_FAILURE_COST", 0) or 0
            repair_cost = row.get("PLANNED_REPAIR_COST", 0) or 0
            inaction = row.get("COST_OF_INACTION", 0) or 0
            parts = row.get("PARTS_STATUS", "?")
            action_w = row.get("ACTION_WINDOW", "SCHEDULED")
            deg = row.get("DEGRADATION_SCORE", 0) or 0
            anomaly = row.get("ANOMALY_SCORE", 0) or 0
            fat_level = row.get("FATIGUE_LEVEL", "?")

            sc = "#EF4444" if stage == "Critical" else "#F59E0B" if stage == "Warning" else "#10B981"
            rc = _risk_row_color(rul, 500, 800)
            dc = "#EF4444" if deg > 0.30 else "#F59E0B" if deg > 0.15 else "#10B981"
            anc = "#EF4444" if anomaly > 0.5 else "#F59E0B" if anomaly > 0.3 else "#10B981"
            ic = "#EF4444" if inaction > 5000 else "#F59E0B" if inaction > 2000 else "#94A3B8"
            pc = "#EF4444" if parts == "ORDER NEEDED" else "#10B981"
            ac = "#EF4444" if action_w == "IMMEDIATE" else "#F59E0B" if action_w == "THIS WEEK" else "#3B82F6" if action_w == "NEXT WEEK" else "#64748B"
            flc = "#EF4444" if fat_level == "HIGH" else "#F59E0B" if fat_level == "ACCUMULATING" else "#10B981"

            slope = fatigue_slopes.get(name, 0)
            if slope > 0.01:
                trend_html = '<span style="color:#EF4444; font-weight:700;">↑</span>'
            elif slope < -0.01:
                trend_html = '<span style="color:#10B981; font-weight:700;">↓</span>'
            else:
                trend_html = '<span style="color:#64748B;">→</span>'

            fat_badge = f'<span style="padding:1px 6px; border-radius:6px; font-size:0.5rem; font-weight:700; background:{flc}18; color:{flc}; border:1px solid {flc}33;">{fat_level}</span>'

            rows_html += f"""
            <tr>
                <td style="padding:8px 10px; font-weight:600; color:#E0E7FF; border-bottom:1px solid rgba(255,255,255,0.03);">
                    {name} {trend_html}<br>{fat_badge}</td>
                <td style="padding:8px 10px; text-align:center; border-bottom:1px solid rgba(255,255,255,0.03);">
                    <span style="padding:2px 8px; border-radius:8px; font-size:0.6rem; font-weight:700;
                        background:{sc}18; color:{sc}; border:1px solid {sc}33;">{stage}</span></td>
                <td style="padding:8px 10px; text-align:center; color:{rc}; font-weight:700; font-size:0.85rem;
                    border-bottom:1px solid rgba(255,255,255,0.03);">{rul:.0f}h</td>
                <td style="padding:8px 10px; text-align:center; color:{dc}; font-weight:700; font-size:0.85rem;
                    border-bottom:1px solid rgba(255,255,255,0.03);">{deg:.3f}</td>
                <td style="padding:8px 10px; text-align:center; color:{anc}; font-weight:700; font-size:0.85rem;
                    border-bottom:1px solid rgba(255,255,255,0.03);">{anomaly:.2f}</td>
                <td style="padding:8px 10px; text-align:center; color:#EF4444; font-size:0.8rem;
                    border-bottom:1px solid rgba(255,255,255,0.03);">${fail_cost:,.0f}</td>
                <td style="padding:8px 10px; text-align:center; color:{ic}; font-weight:700; font-size:0.85rem;
                    border-bottom:1px solid rgba(255,255,255,0.03);">${inaction:,.0f}</td>
                <td style="padding:8px 10px; text-align:center; border-bottom:1px solid rgba(255,255,255,0.03);">
                    <span style="padding:2px 8px; border-radius:8px; font-size:0.6rem; font-weight:700;
                        background:{pc}18; color:{pc}; border:1px solid {pc}33;">{parts}</span></td>
                <td style="padding:8px 10px; text-align:center; border-bottom:1px solid rgba(255,255,255,0.03);">
                    <span style="padding:2px 8px; border-radius:8px; font-size:0.58rem; font-weight:700;
                        background:{ac}18; color:{ac}; border:1px solid {ac}33;">{action_w}</span></td>
            </tr>"""

        th_style = 'style="padding:10px 10px; text-align:center; font-size:0.6rem; text-transform:uppercase; letter-spacing:0.06em; color:#64748B; font-weight:600; border-bottom:1px solid rgba(0,212,255,0.12);"'
        th_left = th_style.replace("text-align:center", "text-align:left")
        st.html(f"""
        <div style="background:rgba(17,24,39,0.8); border:1px solid rgba(0,212,255,0.12); border-radius:8px; overflow:hidden;">
            <table style="width:100%; border-collapse:collapse; font-size:0.78rem;">
                <thead><tr>
                    <th {th_left}>Asset</th><th {th_style}>Stage</th><th {th_style}>RUL</th>
                    <th {th_style}>Degradation</th><th {th_style}>Anomaly</th><th {th_style}>Failure $</th>
                    <th {th_style}>At Stake</th><th {th_style}>Parts</th><th {th_style}>Action</th>
                </tr></thead>
                <tbody>{rows_html}</tbody>
            </table>
        </div>
        """)

        # Risk scatter plot + cost exposure side by side
        col_scatter, col_cost = st.columns([3, 2])

        with col_scatter:
            _section_header("⚠️", "Risk heatmap — degradation vs anomaly")
            with st.container(border=True):
                scatter_df = preds_cost[["ASSET_NAME", "DEGRADATION_SCORE", "ANOMALY_SCORE", "COST_OF_INACTION", "STAGE_PRED"]].copy()
                scatter_df["COST_OF_INACTION"] = scatter_df["COST_OF_INACTION"].fillna(0)
                scatter_df["ANOMALY_SCORE"] = scatter_df["ANOMALY_SCORE"].fillna(0)
                scatter = alt.Chart(scatter_df).mark_circle(opacity=0.8).encode(
                    x=alt.X("DEGRADATION_SCORE:Q", title="Degradation score", scale=alt.Scale(zero=True)),
                    y=alt.Y("ANOMALY_SCORE:Q", title="Anomaly score", scale=alt.Scale(zero=True)),
                    size=alt.Size("COST_OF_INACTION:Q", title="Cost at stake", scale=alt.Scale(range=[60, 600])),
                    color=alt.Color("STAGE_PRED:N", title="Stage", scale=alt.Scale(
                        domain=["Critical", "Warning", "Healthy"],
                        range=["#EF4444", "#F59E0B", "#10B981"])),
                    tooltip=["ASSET_NAME", alt.Tooltip("DEGRADATION_SCORE:Q", format=".3f"),
                              alt.Tooltip("ANOMALY_SCORE:Q", format=".2f"),
                              alt.Tooltip("COST_OF_INACTION:Q", format="$,.0f"), "STAGE_PRED"],
                ).properties(height=280)
                st.altair_chart(scatter.configure_view(strokeWidth=0).configure_axis(
                    gridColor="rgba(255,255,255,0.04)", labelColor="#64748B", titleColor="#94A3B8"),
                    use_container_width=True)

        with col_cost:
            _section_header("💰", "Cost exposure by action window")
            with st.container(border=True):
                if "ACTION_WINDOW" in preds_cost.columns and "COST_OF_INACTION" in preds_cost.columns:
                    cost_by_action = preds_cost.groupby("ACTION_WINDOW")["COST_OF_INACTION"].sum().reset_index()
                    cost_by_action.columns = ["Window", "Cost"]
                    bar = alt.Chart(cost_by_action).mark_bar(cornerRadiusTopRight=4, cornerRadiusBottomRight=4).encode(
                        y=alt.Y("Window:N", title="", sort=["IMMEDIATE", "THIS WEEK", "NEXT WEEK", "SCHEDULED"]),
                        x=alt.X("Cost:Q", title="Cost ($)"),
                        color=alt.Color("Window:N", scale=alt.Scale(
                            domain=["IMMEDIATE", "THIS WEEK", "NEXT WEEK", "SCHEDULED"],
                            range=["#EF4444", "#F59E0B", "#3B82F6", "#64748B"]), legend=None),
                        tooltip=["Window", alt.Tooltip("Cost:Q", format="$,.0f")],
                    ).properties(height=280)
                    st.altair_chart(bar.configure_view(strokeWidth=0).configure_axis(
                        gridColor="rgba(255,255,255,0.04)", labelColor="#64748B", titleColor="#94A3B8"),
                        use_container_width=True)

        # Fatigue trend sparklines for all assets
        if len(fatigue_df) > 0:
            all_asset_names = preds_cost["ASSET_NAME"].tolist() if len(preds_cost) > 0 else []
            fatigue_chart_df = fatigue_df[fatigue_df["ASSET_NAME"].isin(all_asset_names)] if all_asset_names else pd.DataFrame()
            if len(fatigue_chart_df) > 0:
                _section_header("📈", "Fatigue trend (all assets)")
                with st.container(border=True):
                    st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Fatigue accumulation trend</div>')

                    # Filters: time range + asset selection
                    ft_col1, ft_col2 = st.columns([1, 3])
                    with ft_col1:
                        time_range = st.segmented_control(
                            "Period", ["7d", "14d", "30d", "All"],
                            default="30d", key="fatigue_time_range")
                    with ft_col2:
                        selected_assets = st.multiselect(
                            "Assets", all_asset_names, default=all_asset_names,
                            key="fatigue_asset_filter")

                    fatigue_chart_df = fatigue_chart_df.copy()
                    fatigue_chart_df["TS"] = pd.to_datetime(fatigue_chart_df["TIMESTAMP"])

                    # Apply time filter
                    if time_range and time_range != "All":
                        days_map = {"7d": 7, "14d": 14, "30d": 30}
                        cutoff = pd.Timestamp.now() - pd.Timedelta(days=days_map[time_range])
                        fatigue_chart_df = fatigue_chart_df[fatigue_chart_df["TS"] >= cutoff]

                    # Apply asset filter
                    if selected_assets:
                        fatigue_chart_df = fatigue_chart_df[fatigue_chart_df["ASSET_NAME"].isin(selected_assets)]

                    if len(fatigue_chart_df) == 0:
                        st.info("No fatigue data for the selected filters.", icon=":material/info:")
                    else:
                        # Aggregate to daily avg + max to smooth noise while preserving peak severity
                        fatigue_daily = fatigue_chart_df.groupby(
                            [fatigue_chart_df["ASSET_NAME"], fatigue_chart_df["TS"].dt.date]
                        )["FATIGUE_SCORE"].agg(["mean", "max"]).reset_index()
                        fatigue_daily.columns = ["ASSET_NAME", "DAY", "AVG_FATIGUE", "MAX_FATIGUE"]
                        fatigue_daily["DAY"] = pd.to_datetime(fatigue_daily["DAY"])

                        base_x = alt.X("DAY:T", title="", axis=alt.Axis(labelColor="#64748B", format="%b %d"))
                        base_color = alt.Color("ASSET_NAME:N", title="Asset")

                        # Daily max as faint band upper bound (shows spike severity)
                        band = alt.Chart(fatigue_daily).mark_area(
                            opacity=0.12, interpolate="monotone"
                        ).encode(
                            x=base_x,
                            y=alt.Y("AVG_FATIGUE:Q", title="Fatigue score",
                                     axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                            y2="MAX_FATIGUE:Q",
                            color=base_color,
                        )

                        # Daily average as the primary trend line
                        line = alt.Chart(fatigue_daily).mark_line(
                            strokeWidth=2, interpolate="monotone"
                        ).encode(
                            x=base_x,
                            y="AVG_FATIGUE:Q",
                            color=base_color,
                            tooltip=["ASSET_NAME", "DAY:T",
                                     alt.Tooltip("AVG_FATIGUE:Q", title="Avg", format=".3f"),
                                     alt.Tooltip("MAX_FATIGUE:Q", title="Peak", format=".3f")],
                        )

                        spark = (band + line).properties(height=200)
                        st.altair_chart(spark.configure_view(strokeWidth=0).configure_axis(
                            gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

        # AI action plan (using _glow_card with purple accent)
        _section_header("🤖", "AI action plan", "#8B5CF6")
        if len(preds_cost) > 0:
            crit_assets = preds_cost[preds_cost["STAGE_PRED"] == "Critical"]["ASSET_NAME"].tolist()
            warn_assets = preds_cost[preds_cost["STAGE_PRED"] == "Warning"]["ASSET_NAME"].tolist()
            immediate = preds_cost[preds_cost["ACTION_WINDOW"] == "IMMEDIATE"]
            imm_detail = "; ".join([f"{r['ASSET_NAME']} (RUL {r['RUL_HOURS']:.0f}h, ${r.get('COST_OF_INACTION',0):,.0f} at stake, parts: {r.get('PARTS_STATUS','?')})" for _, r in immediate.iterrows()]) if len(immediate) > 0 else "none"

            data_block = f"""OPERATIONS ACTION PLAN for incoming shift. {len(preds_cost)} assets: {len(crit_assets)} Critical ({', '.join(crit_assets) if crit_assets else 'none'}), {len(warn_assets)} Warning. Immediate actions: {imm_detail}. Open WOs: {len(wos)}, Emergency: {emergency_wo}. Parts at risk: {parts_at_risk}. Plant OEE: {plant_oee}%. Total cost exposure: ${total_inaction:,.0f}. Degrading assets (fatigue rising): {degrading_count}. Provide: (1) top 3 actions ranked by urgency and cost impact, (2) assets to monitor this shift, (3) parts/procurement blockers."""

            plan = generate_executive_summary(data_block, "ops_action_plan")
            _glow_card("Shift action plan", f'<div style="color:#E0E7FF; font-size:0.82rem; line-height:1.7;">{plan}</div>', "#8B5CF6", "✦")
            if st.button("Regenerate action plan", key="regen_action", icon=":material/refresh:"):
                st.session_state.pop("_llm_summary_ops_action_plan", None)
                st.session_state.pop("_llm_hash_ops_action_plan", None)
                st.rerun()

# ─── TAB 2: FLEET STATUS ───
with tab_fleet:
    if len(preds_cost) == 0:
        st.info("No prediction data available.")
    else:
        for _, r in preds_cost.iterrows():
            stage = r["STAGE_PRED"]
            name = r["ASSET_NAME"]
            rul = r.get("RUL_HOURS", 0) or 0
            inaction = r.get("COST_OF_INACTION", 0) or 0
            parts = r.get("PARTS_STATUS", "?")
            action = r.get("ACTION_WINDOW", "")
            fm = FAILURE_MODE_LABEL.get(r.get("FAILURE_MODE_PRED", ""), r.get("FAILURE_MODE_PRED", "?"))
            wo_id = r.get("OPEN_WO_ID", None)
            wo_assigned = r.get("WO_ASSIGNED_TO", None)
            deg = r.get("DEGRADATION_SCORE", 0) or 0
            anomaly = r.get("ANOMALY_SCORE", 0) or 0
            fat_level = r.get("FATIGUE_LEVEL", "?")
            trans_prob = r.get("TRANSITION_PROBABILITY", 0) or 0

            slope = fatigue_slopes.get(name, 0)
            if slope > 0.01:
                trend_icon, trend_label, trend_color = "↑", "Degrading", "#EF4444"
            elif slope < -0.01:
                trend_icon, trend_label, trend_color = "↓", "Improving", "#10B981"
            else:
                trend_icon, trend_label, trend_color = "→", "Stable", "#64748B"

            flc = "#EF4444" if fat_level == "HIGH" else "#F59E0B" if fat_level == "ACCUMULATING" else "#10B981"
            dc = "#EF4444" if deg > 0.30 else "#F59E0B" if deg > 0.15 else "#10B981"
            anc = "#EF4444" if anomaly > 0.5 else "#F59E0B" if anomaly > 0.3 else "#10B981"

            with st.container(border=True):
                c1, c2, c3, c4, c5 = st.columns([2.5, 1.2, 1.5, 1.5, 2])
                with c1:
                    st.markdown(f"**{name}**")
                    st.caption(f"{r.get('ASSET_TYPE', '')} | {r.get('LINE_ID', '')} | Mode: {fm}")
                with c2:
                    st.html('<span style="font-size:0.6rem; color:#64748B;">Stage:</span>')
                    st.badge(stage, color="red" if stage == "Critical" else "orange" if stage == "Warning" else "green")
                    st.html('<span style="font-size:0.6rem; color:#64748B;">Fatigue:</span>')
                    st.badge(fat_level, color="red" if fat_level == "HIGH" else "orange" if fat_level == "ACCUMULATING" else "green")
                    st.html(f'<span style="font-size:0.6rem; color:#64748B;">Trend:</span> <span style="font-size:0.7rem; color:{trend_color}; font-weight:600;">{trend_icon} {trend_label}</span>')
                with c3:
                    st.metric("RUL", fmt_hours(rul))
                    st.html(f'<div style="font-size:0.65rem; color:#64748B;">Degradation: <span style="color:{dc}; font-weight:700;">{deg:.3f}</span></div>')
                with c4:
                    st.html(f'<div style="font-size:0.65rem; color:#64748B; margin-bottom:4px;">Anomaly: <span style="color:{anc}; font-weight:700;">{anomaly:.2f}</span></div>')
                    if trans_prob > 0:
                        st.html(f'<div style="font-size:0.65rem; color:#64748B;">Transition: <span style="color:#F59E0B; font-weight:600;">{trans_prob:.1%}</span></div>')
                    parts_color = "red" if parts == "ORDER NEEDED" else "green"
                    st.badge(parts, color=parts_color)
                    if inaction > 0:
                        st.caption(f"At stake: {fmt_currency(inaction)}")
                with c5:
                    if action:
                        action_color = "red" if action == "IMMEDIATE" else "orange" if action == "THIS WEEK" else "blue"
                        st.badge(f"Action: {action}", color=action_color)
                    if wo_id:
                        st.caption(f"WO: {wo_id} → {wo_assigned or 'Unassigned'}")

# ─── TAB 3: ALERT TRIAGE ───
with tab_alerts:
    if len(alerts) == 0:
        st.success("No active alerts.")
    else:
        sev_filter = st.segmented_control("Severity", ["All", "CRITICAL", "WARNING", "WATCH", "INFO"],
                                           default="All", key="alert_sev_filter")
        filtered_alerts = alerts if sev_filter == "All" else alerts[alerts["SEVERITY"] == sev_filter]

        sev_counts = alerts["SEVERITY"].value_counts().to_dict()
        sev_color_map = {"CRITICAL": "#EF4444", "WARNING": "#F59E0B", "WATCH": "#3B82F6", "INFO": "#64748B"}
        counts_html = " · ".join([
            f'<span style="color:{sev_color_map.get(s, "#64748B")}; font-weight:700;">{s}: {c}</span>'
            for s, c in sev_counts.items()
        ])
        st.html(f'<div style="font-size:0.72rem; margin-bottom:8px;">{counts_html}</div>')

        pred_lookup = {}
        if len(preds) > 0:
            for _, p in preds.iterrows():
                pred_lookup[p["ASSET_NAME"]] = {
                    "STAGE_PRED": p.get("STAGE_PRED", "?"),
                    "DEGRADATION_SCORE": p.get("DEGRADATION_SCORE", 0),
                }

        for _, a in filtered_alerts.iterrows():
            sev = a["SEVERITY"]
            sev_color = "red" if sev == "CRITICAL" else "orange" if sev == "WARNING" else "blue" if sev == "WATCH" else "gray"
            asset_ctx = pred_lookup.get(a["ASSET_NAME"], {})

            with st.container(border=True):
                c1, c2, c3 = st.columns([1, 3, 1])
                with c1:
                    st.badge(sev, color=sev_color)
                    st.caption(f"RUL: {fmt_hours(a['RUL_HOURS'])}")
                with c2:
                    st.markdown(f"**{a['ASSET_NAME']}** — {a['ALERT_TYPE']}")
                    st.caption(a["MESSAGE"][:300])
                with c3:
                    if asset_ctx:
                        st.caption(f"Stage: {asset_ctx.get('STAGE_PRED', '?')}")
                        deg = asset_ctx.get("DEGRADATION_SCORE", 0)
                        if deg > 0:
                            st.caption(f"Degradation: {deg:.3f}")

# ─── TAB 4: SHIFT HANDOVER ───
with tab_handover:
    # OEE summary
    if len(oee) > 0:
        _section_header("📊", "OEE summary")
        oee_cols = st.columns(len(oee) + 1)
        with oee_cols[0]:
            st.metric("Plant OEE", f"{plant_oee}%", border=True)
        for i, (_, line) in enumerate(oee.iterrows()):
            with oee_cols[i + 1]:
                st.metric(line["LINE_ID"], f"{line['OEE']}%", border=True)

    # Cost exposure callout (styled to match executive dashboard pattern)
    if total_inaction > 0:
        exp_color = "#EF4444" if total_inaction > 30000 else "#F59E0B" if total_inaction > 10000 else "#10B981"
        st.html(f"""
        <div style="background:rgba(17,24,39,0.8); border:1px solid {exp_color}33; border-left:3px solid {exp_color};
                    border-radius:8px; padding:14px; margin:8px 0; box-shadow: 0 0 15px {exp_color}11;">
            <div style="color:{exp_color}; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.1em;
                        font-weight:600; margin-bottom:4px;">⚠ Cost exposure — if no action taken</div>
            <div style="font-size:1.4rem; font-weight:800; color:{exp_color}; text-shadow: 0 0 12px {exp_color}55;">${total_inaction:,.0f}</div>
        </div>
        """)

    # AI shift briefing (using _glow_card like other pages)
    _section_header("🤖", "AI shift briefing", "#8B5CF6")
    if len(preds) > 0:
        crit_assets = preds[preds["STAGE_PRED"] == "Critical"]["ASSET_NAME"].tolist()
        warn_assets = preds[preds["STAGE_PRED"] == "Warning"]["ASSET_NAME"].tolist()
        shortage_details = ""
        if len(proc) > 0 and "PROCUREMENT_RISK" in proc.columns:
            shortages_df = proc[proc["PROCUREMENT_RISK"].isin(["CRITICAL_SHORTAGE", "EXPEDITE"])]
            if len(shortages_df) > 0:
                shortage_details = "; ".join([f"{r['ASSET_NAME']} needs {r.get('PART_NAME', '?')} ({r['PROCUREMENT_RISK']})" for _, r in shortages_df.head(5).iterrows()])
        lowest_rul = preds.iloc[0]

        handover_block = f"""SHIFT HANDOVER BRIEFING — {len(preds)} assets monitored. Plant OEE: {plant_oee}%. Critical: {', '.join(crit_assets) if crit_assets else 'none'}. Warning: {', '.join(warn_assets) if warn_assets else 'none'}. Lowest RUL: {lowest_rul['ASSET_NAME']} at {lowest_rul['RUL_HOURS']:.0f}h ({lowest_rul['FAILURE_MODE_PRED']}). Open WOs: {len(wos)}, Emergency: {emergency_wo}. Parts at risk: {parts_at_risk}. {shortage_details}. Degrading assets (fatigue rising): {degrading_count}. Total cost exposure: ${total_inaction:,.0f}. Provide a concise shift handover: (1) immediate actions for incoming shift, (2) assets to monitor closely, (3) parts/procurement status, (4) any WOs needing attention."""

        briefing = generate_executive_summary(handover_block, "shift_handover")
        _glow_card("Shift briefing", f'<div style="color:#E0E7FF; font-size:0.82rem; line-height:1.7;">{briefing}</div>', "#8B5CF6", "✦")
        if st.button("Regenerate briefing", key="regen_handover", icon=":material/refresh:"):
            st.session_state.pop("_llm_summary_shift_handover", None)
            st.session_state.pop("_llm_hash_shift_handover", None)
            st.rerun()

    # Shift KPIs
    try:
        handover = conn.query(f"SELECT * FROM {DB}.ANALYTICS.SHIFT_HANDOVER_VIEW LIMIT 1")
        if len(handover) > 0:
            h = handover.iloc[0]
            with st.container(horizontal=True):
                st.metric("Critical actions", f"{h.get('CRITICAL_ACTION_COUNT', 0)}", border=True)
                st.metric("Warnings", f"{h.get('WARNING_COUNT', 0)}", border=True)
                st.metric("Plant OEE", f"{h.get('PLANT_OEE', 0)}%", border=True)
                st.metric("Active alerts", f"{h.get('TOTAL_ALERTS', 0)}", border=True)
    except Exception:
        pass

    # Supply chain risk summary (styled HTML cards matching executive dashboard)
    if len(proc) > 0 and procurement_available():
        _section_header("🔗", "Supply chain readiness", "#EF4444")
        shortages = proc[proc["PROCUREMENT_RISK"].isin(["CRITICAL_SHORTAGE", "EXPEDITE"])] if "PROCUREMENT_RISK" in proc.columns else pd.DataFrame()
        replenish = proc[proc["PROCUREMENT_RISK"] == "REPLENISH_NOW"] if "PROCUREMENT_RISK" in proc.columns else pd.DataFrame()
        pos = load_open_pos()

        crit_short = len(proc[proc["PROCUREMENT_RISK"] == "CRITICAL_SHORTAGE"]) if "PROCUREMENT_RISK" in proc.columns else 0
        exp_count = len(proc[proc["PROCUREMENT_RISK"] == "EXPEDITE"]) if "PROCUREMENT_RISK" in proc.columns else 0

        sc1, sc2, sc3, sc4 = st.columns(4)
        with sc1:
            st.html(f"""
            <div style="background:rgba(17,24,39,0.9); border:1px solid #EF444433; border-left:3px solid #EF4444;
                        border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 12px #EF444411;">
                <div style="font-size:0.55rem; color:#EF4444; text-transform:uppercase; letter-spacing:0.08em; font-weight:600;">Critical shortage</div>
                <div style="font-size:1.5rem; font-weight:800; color:#EF4444;">{crit_short}</div>
            </div>""")
        with sc2:
            st.html(f"""
            <div style="background:rgba(17,24,39,0.9); border:1px solid #F59E0B33; border-left:3px solid #F59E0B;
                        border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 12px #F59E0B11;">
                <div style="font-size:0.55rem; color:#F59E0B; text-transform:uppercase; letter-spacing:0.08em; font-weight:600;">Expedite needed</div>
                <div style="font-size:1.5rem; font-weight:800; color:#F59E0B;">{exp_count}</div>
            </div>""")
        with sc3:
            st.html(f"""
            <div style="background:rgba(17,24,39,0.9); border:1px solid #00D4FF33; border-left:3px solid #00D4FF;
                        border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 12px #00D4FF11;">
                <div style="font-size:0.55rem; color:#00D4FF; text-transform:uppercase; letter-spacing:0.08em; font-weight:600;">Replenish now</div>
                <div style="font-size:1.5rem; font-weight:800; color:#00D4FF;">{len(replenish)}</div>
            </div>""")
        with sc4:
            st.html(f"""
            <div style="background:rgba(17,24,39,0.9); border:1px solid #8B5CF633; border-left:3px solid #8B5CF6;
                        border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 12px #8B5CF611;">
                <div style="font-size:0.55rem; color:#8B5CF6; text-transform:uppercase; letter-spacing:0.08em; font-weight:600;">Open POs</div>
                <div style="font-size:1.5rem; font-weight:800; color:#8B5CF6;">{len(pos)}</div>
            </div>""")

        if len(shortages) > 0:
            st.dataframe(
                shortages[["ASSET_NAME", "PART_NAME", "AVAILABLE_TO_PROMISE", "PROCUREMENT_RISK", "RECOMMENDED_PROCUREMENT_ACTION"]].head(8),
                use_container_width=True, hide_index=True,
                column_config={"ASSET_NAME": "Asset", "PART_NAME": "Part", "AVAILABLE_TO_PROMISE": "ATP",
                               "PROCUREMENT_RISK": "Risk", "RECOMMENDED_PROCUREMENT_ACTION": "Action"},
            )

# ─── TAB 5: WORK ORDERS ───
with tab_wo:
    if len(all_wo) == 0:
        st.success("No work orders.")
    else:
        # Filters
        fc1, fc2, fc3 = st.columns(3)
        with fc1:
            wo_status_filter = st.multiselect("Status", ["open", "in_progress", "completed", "cancelled"],
                                               default=["open", "in_progress"], key="wo_status_f")
        with fc2:
            wo_type_filter = st.multiselect("Type", ["emergency", "corrective", "preventive"],
                                             default=["emergency", "corrective", "preventive"], key="wo_type_f")
        with fc3:
            wo_priority_filter = st.multiselect("Priority", sorted(all_wo["PRIORITY"].dropna().unique().tolist()),
                                                 default=sorted(all_wo["PRIORITY"].dropna().unique().tolist()), key="wo_prio_f")

        filtered_wo = all_wo[
            all_wo["STATUS"].isin(wo_status_filter) &
            all_wo["WO_TYPE"].isin(wo_type_filter) &
            all_wo["PRIORITY"].isin(wo_priority_filter)
        ] if len(wo_status_filter) > 0 and len(wo_type_filter) > 0 and len(wo_priority_filter) > 0 else all_wo

        # Cost summary + status chart
        col_wo_kpi, col_wo_chart = st.columns([1, 1])
        with col_wo_kpi:
            open_cost = filtered_wo[filtered_wo["STATUS"].isin(["open", "in_progress"])]["TOTAL_COST"].sum() if len(filtered_wo) > 0 else 0
            emerg_cost = filtered_wo[filtered_wo["WO_TYPE"] == "emergency"]["TOTAL_COST"].sum() if len(filtered_wo) > 0 else 0
            with st.container(horizontal=True):
                st.metric("Filtered WOs", f"{len(filtered_wo)}", border=True)
                st.metric("Open cost", fmt_currency(open_cost), border=True)
                st.metric("Emergency cost", fmt_currency(emerg_cost), border=True)

        with col_wo_chart:
            if len(filtered_wo) > 0:
                with st.container(border=True):
                    st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Status distribution</div>')
                    status_dist = filtered_wo["STATUS"].value_counts().reset_index()
                    status_dist.columns = ["Status", "Count"]
                    bar = alt.Chart(status_dist).mark_bar(cornerRadiusTopRight=4, cornerRadiusBottomRight=4).encode(
                        y=alt.Y("Status:N", title=""),
                        x=alt.X("Count:Q", title="Count"),
                        color=alt.Color("Status:N", scale=alt.Scale(
                            domain=["open", "in_progress", "completed", "cancelled"],
                            range=["#3B82F6", "#F59E0B", "#10B981", "#64748B"]), legend=None),
                        tooltip=["Status", "Count"],
                    ).properties(height=120)
                    st.altair_chart(bar.configure_view(strokeWidth=0).configure_axis(
                        gridColor="rgba(255,255,255,0.04)", labelColor="#64748B", titleColor="#94A3B8"),
                        use_container_width=True)

        # Dataframe
        display_cols = ["WO_ID", "ASSET_NAME", "WO_TYPE", "PRIORITY", "STATUS", "ASSIGNED_TO", "CREATED_DATE", "TOTAL_COST"]
        available_cols = [c for c in display_cols if c in filtered_wo.columns]
        st.dataframe(
            filtered_wo[available_cols],
            use_container_width=True, hide_index=True,
            column_config={
                "WO_ID": "WO", "ASSET_NAME": "Asset", "WO_TYPE": "Type", "PRIORITY": "Priority",
                "STATUS": "Status", "ASSIGNED_TO": "Assigned", "CREATED_DATE": "Created",
                "TOTAL_COST": st.column_config.NumberColumn("Cost", format="$%d"),
            },
        )

# ─── TAB 6: SENSOR FEED ───
with tab_sensor:
    sensor_data = load_latest_sensor_readings()
    if len(sensor_data) == 0:
        st.info("No sensor readings in the last 24 hours.")
    else:
        max_ts = pd.to_datetime(sensor_data["TIMESTAMP"]).max()
        ts_str = max_ts.strftime("%Y-%m-%d %H:%M:%S") if pd.notna(max_ts) else "Unknown"
        try:
            sf_now = pd.to_datetime(conn.query("SELECT CURRENT_TIMESTAMP()::TIMESTAMP_NTZ AS NOW").iloc[0]["NOW"])
            age_minutes = (sf_now - max_ts).total_seconds() / 60
        except Exception:
            age_minutes = 999
        live_color = "green" if age_minutes < 10 else "orange" if age_minutes > 60 else "blue"
        live_label = "LIVE" if age_minutes < 10 else "STALE" if age_minutes > 60 else "RECENT"

        sh1, sh2 = st.columns([3, 1])
        with sh1:
            st.badge(live_label, color=live_color)
            st.caption(f"Last reading: {ts_str}")

        sf1, sf2 = st.columns([2, 1])
        with sf1:
            asset_options = ["All assets"] + sorted(sensor_data["ASSET_NAME"].unique().tolist())
            sel_asset = st.selectbox("Asset", asset_options, index=0, key="sensor_asset")
        with sf2:
            time_range = st.selectbox("Time range", ["Last 1h", "Last 6h", "Last 12h", "Last 24h"], index=3, key="sensor_range")

        hours_map = {"Last 1h": 1, "Last 6h": 6, "Last 12h": 12, "Last 24h": 24}
        cutoff_hours = hours_map.get(time_range, 24)
        cutoff_ts = max_ts - pd.Timedelta(hours=cutoff_hours)

        filtered = sensor_data.copy()
        filtered["TS"] = pd.to_datetime(filtered["TIMESTAMP"])
        filtered = filtered[filtered["TS"] >= cutoff_ts]
        if sel_asset != "All assets":
            filtered = filtered[filtered["ASSET_NAME"] == sel_asset]

        if len(filtered) == 0:
            st.info("No readings in the selected time range.")
        else:
            latest = filtered.iloc[0]

            THRESHOLDS = {
                "VIB_MAG": {"warn": 12.0, "crit": 15.0},
                "TEMPERATURE": {"warn": 100.0, "crit": 270.0},
                "CURRENT_AMPS": {"warn": 20.0, "crit": 23.0},
                "ACOUSTIC_DB": {"warn": 85.0, "crit": 90.0},
            }

            with st.container(horizontal=True):
                vib = latest.get("VIB_MAG", 0)
                temp = latest.get("TEMPERATURE", 0)
                rpm = latest.get("RPM", 0)
                pres = latest.get("PRESSURE", 0)
                amps = latest.get("CURRENT_AMPS", 0)
                acoustic = latest.get("ACOUSTIC_DB", 0)
                st.metric("Vibration (mag)", f"{vib:.2f} mm/s", border=True)
                st.metric("Temperature", f"{temp:.1f} °C", border=True)
                st.metric("RPM", f"{rpm:.0f}", border=True)
                st.metric("Pressure", f"{pres:.2f} bar", border=True)
                st.metric("Current", f"{amps:.1f} A", border=True)
                st.metric("Acoustic", f"{acoustic:.0f} dB", border=True)

            # Threshold breach alerts
            breaches = []
            if vib >= THRESHOLDS["VIB_MAG"]["crit"]:
                breaches.append(f"Vibration {vib:.1f} mm/s exceeds critical threshold")
            elif vib >= THRESHOLDS["VIB_MAG"]["warn"]:
                breaches.append(f"Vibration {vib:.1f} mm/s exceeds warning threshold")
            if temp >= THRESHOLDS["TEMPERATURE"]["crit"]:
                breaches.append(f"Temperature {temp:.1f}°C exceeds critical threshold")
            elif temp >= THRESHOLDS["TEMPERATURE"]["warn"]:
                breaches.append(f"Temperature {temp:.1f}°C exceeds warning threshold")
            if amps >= THRESHOLDS["CURRENT_AMPS"]["crit"]:
                breaches.append(f"Current {amps:.1f}A exceeds critical threshold")
            elif amps >= THRESHOLDS["CURRENT_AMPS"]["warn"]:
                breaches.append(f"Current {amps:.1f}A exceeds warning threshold")
            if acoustic >= THRESHOLDS["ACOUSTIC_DB"]["crit"]:
                breaches.append(f"Acoustic {acoustic:.0f}dB exceeds critical threshold")
            elif acoustic >= THRESHOLDS["ACOUSTIC_DB"]["warn"]:
                breaches.append(f"Acoustic {acoustic:.0f}dB exceeds warning threshold")

            if breaches:
                st.warning("Threshold breaches detected: " + " | ".join(breaches))

            channels = ["VIB_MAG", "TEMPERATURE", "RPM", "CURRENT_AMPS"]
            channel_labels = {"VIB_MAG": "Vibration (mm/s)", "TEMPERATURE": "Temperature (°C)", "RPM": "RPM", "CURRENT_AMPS": "Current (A)"}
            sel_channel = st.selectbox("Channel", channels, format_func=lambda x: channel_labels.get(x, x), key="sensor_ch")

            with st.container(border=True):
                st.html(f'<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">{channel_labels.get(sel_channel, sel_channel)} — {time_range.lower()}</div>')
                chart_data = filtered[["TS", "ASSET_NAME", sel_channel]].copy()
                chart_data = chart_data.rename(columns={sel_channel: "Value"})
                line_chart = alt.Chart(chart_data).mark_line(strokeWidth=1.5).encode(
                    x=alt.X("TS:T", title="Time", axis=alt.Axis(labelColor="#64748B", format="%H:%M")),
                    y=alt.Y("Value:Q", title=channel_labels.get(sel_channel, sel_channel),
                             axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                    color=alt.Color("ASSET_NAME:N", title="Asset"),
                    tooltip=["TS:T", "ASSET_NAME:N", alt.Tooltip("Value:Q", format=".2f")],
                ).properties(height=300)

                thresh = THRESHOLDS.get(sel_channel)
                if thresh:
                    warn_rule = alt.Chart(pd.DataFrame({"y": [thresh["warn"]]})).mark_rule(
                        strokeDash=[4, 4], color="#F59E0B", opacity=0.5).encode(y="y:Q")
                    crit_rule = alt.Chart(pd.DataFrame({"y": [thresh["crit"]]})).mark_rule(
                        strokeDash=[4, 4], color="#EF4444", opacity=0.5).encode(y="y:Q")
                    line_chart = line_chart + warn_rule + crit_rule

                st.altair_chart(line_chart.configure_view(strokeWidth=0).configure_axis(
                    gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

            with st.expander("Raw sensor data", expanded=False):
                display_cols = ["ASSET_NAME", "TIMESTAMP", "VIB_MAG", "TEMPERATURE", "RPM", "PRESSURE", "CURRENT_AMPS", "ACOUSTIC_DB"]
                st.dataframe(
                    filtered[[c for c in display_cols if c in filtered.columns]].head(200),
                    use_container_width=True, hide_index=True,
                    column_config={
                        "ASSET_NAME": "Asset", "TIMESTAMP": "Time",
                        "VIB_MAG": st.column_config.NumberColumn("Vibration", format="%.2f"),
                        "TEMPERATURE": st.column_config.NumberColumn("Temp (°C)", format="%.1f"),
                        "RPM": st.column_config.NumberColumn("RPM", format="%.0f"),
                        "PRESSURE": st.column_config.NumberColumn("Pressure", format="%.2f"),
                        "CURRENT_AMPS": st.column_config.NumberColumn("Current (A)", format="%.1f"),
                        "ACOUSTIC_DB": st.column_config.NumberColumn("Acoustic (dB)", format="%.0f"),
                    },
                )
