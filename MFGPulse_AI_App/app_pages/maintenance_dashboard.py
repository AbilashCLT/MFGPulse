import streamlit as st
import pandas as pd
import altair as alt
from app_pages._shared import (
    load_live_predictions, load_alerts, load_maintenance_logs, load_all_work_orders,
    load_procurement_recs, load_parts_atp, procurement_available, load_data_freshness,
    fmt_hours, fmt_currency, C, DB, get_conn, RISK_COLOR, generate_executive_summary,
    FAILURE_MODE_LABEL,
)

alt.renderers.enable("mimetype")

# ─── Helpers (matching exec/ops/digital_twin) ───
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

# ─── Load data ───
conn = get_conn()
preds = load_live_predictions()
alerts = load_alerts()
logs = load_maintenance_logs()
all_wo = load_all_work_orders()

# Computed metrics
crit = len(preds[preds["STAGE_PRED"] == "Critical"]) if len(preds) > 0 else 0
warn = len(preds[preds["STAGE_PRED"] == "Warning"]) if len(preds) > 0 else 0
healthy_count = len(preds[preds["STAGE_PRED"] == "Healthy"]) if len(preds) > 0 else 0
total_assets = len(preds) if len(preds) > 0 else 0
high_fatigue = len(preds[preds["FATIGUE_SCORE"] > 0.4]) if len(preds) > 0 else 0
avg_health = round(preds["COMPOSITE_HEALTH_SCORE"].mean(), 1) if len(preds) > 0 else 0
open_wo = len(all_wo[all_wo["STATUS"].isin(["open", "in_progress"])]) if len(all_wo) > 0 else 0
emergency_wo = len(all_wo[(all_wo["WO_TYPE"] == "emergency") & (all_wo["STATUS"].isin(["open", "in_progress"]))]) if len(all_wo) > 0 else 0

# Data freshness
try:
    freshness = load_data_freshness()
    sensor_fresh = freshness[freshness['SOURCE_TABLE'] == 'SENSOR_READINGS'].iloc[0] if len(freshness) > 0 else {}
    stale_min = sensor_fresh.get('STALENESS_MINUTES', '?') if sensor_fresh is not None and len(sensor_fresh) > 0 else '?'
except Exception:
    stale_min = '?'

# ═══════════════════════════════════════════════════════════════
# HEADER
# ═══════════════════════════════════════════════════════════════
if crit > 0:
    maint_status, mstat_color, mstat_icon = "CRITICAL", "#EF4444", "🔴"
elif warn > 0 or high_fatigue > 0:
    maint_status, mstat_color, mstat_icon = "ATTENTION", "#F59E0B", "🟡"
else:
    maint_status, mstat_color, mstat_icon = "HEALTHY", "#10B981", "🟢"

st.html(f"""
<div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:4px; flex-wrap:wrap; gap:10px;">
    <div style="display:flex; align-items:center; gap:14px;">
        <div style="font-size:1.5rem; font-weight:800; color:#E0E7FF;">🔧 Maintenance hub</div>
        <div style="padding:4px 14px; border-radius:12px; font-size:0.65rem; font-weight:700;
                    text-transform:uppercase; letter-spacing:0.08em;
                    background:{mstat_color}18; color:{mstat_color}; border:1px solid {mstat_color}44;
                    box-shadow: 0 0 12px {mstat_color}22;">
            {mstat_icon} {maint_status}
        </div>
    </div>
    <div style="display:flex; align-items:center; gap:8px;">
        <div style="padding:2px 8px; border-radius:8px; font-size:0.6rem; font-weight:600;
                    background:#10B98118; color:#10B981; border:1px solid #10B98133;">● LIVE</div>
        <span style="font-size:0.65rem; color:#64748B;">Sensor data: {stale_min} min ago</span>
    </div>
</div>
""")
st.caption("Fleet health matrix, asset deep-dive, and work order management")

with st.expander("About this page", expanded=False, icon=":material/info:"):
    st.markdown("""
**Purpose**: Deep asset-level diagnostics — where Technicians and Reliability Engineers spend most of their time investigating failure modes, fatigue patterns, and maintenance history.

**Stage classification** (ISO 13381-1):
- **Critical** = RUL < 48h or degradation >= 0.65 | **Warning** = RUL < 168h or degradation >= 0.30 | **Healthy** = All other

**Failure modes** (M1 classifier): bearing_wear, thermal_degradation, misalignment, imbalance, undetermined_degradation, normal

**Key metrics**: Critical/Warning/Healthy asset counts, open work orders, average RUL across fleet.

**Tabs**:
- **Fleet matrix** — All 10 assets in card format with labeled Stage and Fatigue badges, RUL, degradation score, fatigue score (numeric), anomaly score, health score (/100), and work order count. Sorted by urgency.
- **Asset deep-dive** — Select any asset for detailed diagnostics:
  - **Failure DNA** — Predicted failure mode with confidence, degradation stage with transition probability, RUL with confidence interval, and fatigue level
  - **Active alerts** — Asset-specific alert cards with severity and message
  - **Maintenance history** — Work order timeline with type badges (emergency/corrective/preventive), priority, assigned technician, timestamps, and technician notes
  - **Sensor trends** — 30-day charts for vibration, temperature, pressure, and RPM with threshold lines

**Data sources**: `ML_MODELS.LIVE_PREDICTIONS`, `ANALYTICS.ACTIVE_ALERTS`, `RAW_IT.WORK_ORDERS`, `RAW_IT.MAINTENANCE_LOGS`, `RAW_OT.SENSOR_READINGS`
""")

# ═══════════════════════════════════════════════════════════════
# AI SUMMARY (always visible)
# ═══════════════════════════════════════════════════════════════
_section_header("🤖", "Maintenance brief", "#8B5CF6")

if len(preds) > 0:
    crit_df = preds[preds["STAGE_PRED"] == "Critical"]
    warn_df = preds[preds["STAGE_PRED"] == "Warning"]
    high_fat_df = preds[preds["FATIGUE_SCORE"] > 0.4]
    worst_info = ""
    if len(crit_df) > 0:
        w = crit_df.iloc[0]
        worst_info = f"Most urgent: {w['ASSET_NAME']} — RUL {w['RUL_HOURS']:.0f}h, degradation {w['DEGRADATION_SCORE']:.2f}, fatigue {w['FATIGUE_SCORE']:.3f}."
    elif len(preds) > 0:
        w = preds.iloc[0]
        worst_info = f"Lowest RUL: {w['ASSET_NAME']} at {w['RUL_HOURS']:.0f}h, degradation {w['DEGRADATION_SCORE']:.2f}."
    fat_names = ", ".join(high_fat_df["ASSET_NAME"].tolist()) if len(high_fat_df) > 0 else "none"

    data_block = f"""Fleet health: {crit} Critical, {warn} Warning, {healthy_count} Healthy out of {total_assets} assets. {worst_info} Assets with elevated fatigue (>0.4): {fat_names}. Average fleet health score: {avg_health:.0f}/100. Open work orders: {open_wo}, emergency: {emergency_wo}."""

    summary = generate_executive_summary(data_block, "maintenance")
    _glow_card("Fleet health brief", f'<div style="color:#E0E7FF; font-size:0.82rem; line-height:1.7;">{summary}</div>', "#8B5CF6", "✦")
    if st.button("Regenerate", key="regen_maint", icon=":material/refresh:"):
        st.session_state.pop("_llm_summary_maintenance", None)
        st.session_state.pop("_llm_hash_maintenance", None)
        st.rerun()

# ═══════════════════════════════════════════════════════════════
# KPI STRIP
# ═══════════════════════════════════════════════════════════════
_section_header("📊", "Key metrics")

k1, k2, k3, k4 = st.columns(4)
with k1:
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid #00D4FF33; border-radius:10px;
                padding:16px; text-align:center; box-shadow: 0 0 15px #00D4FF11;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">🏭 Fleet health</div>
        <div style="display:flex; justify-content:center; gap:14px; margin-bottom:8px;">
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:#EF4444;">{crit}</div>
                <div style="font-size:0.55rem; color:#EF4444; text-transform:uppercase;">Critical</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:#F59E0B;">{warn}</div>
                <div style="font-size:0.55rem; color:#F59E0B; text-transform:uppercase;">Warning</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:#10B981;">{healthy_count}</div>
                <div style="font-size:0.55rem; color:#10B981; text-transform:uppercase;">Healthy</div>
            </div>
        </div>
        <div style="background:rgba(255,255,255,0.04); border-radius:4px; height:6px; overflow:hidden; display:flex;">
            <div style="width:{crit/max(total_assets,1)*100:.0f}%; background:#EF4444; height:100%;"></div>
            <div style="width:{warn/max(total_assets,1)*100:.0f}%; background:#F59E0B; height:100%;"></div>
            <div style="width:{healthy_count/max(total_assets,1)*100:.0f}%; background:#10B981; height:100%;"></div>
        </div>
    </div>
    """)

with k2:
    if len(preds) > 0:
        lr = preds.iloc[0]
        lr_name = lr["ASSET_NAME"]
        lr_rul = lr.get("RUL_HOURS", 0) or 0
        lr_deg = lr.get("DEGRADATION_SCORE", 0) or 0
        lr_color = "#EF4444" if lr_deg > 0.30 else "#F59E0B" if lr_deg > 0.15 else "#10B981"
    else:
        lr_name, lr_rul, lr_deg, lr_color = "N/A", 0, 0, "#64748B"
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid {lr_color}33; border-left:3px solid {lr_color};
                border-radius:10px; padding:16px; text-align:center; box-shadow: 0 0 15px {lr_color}11;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">🎯 Lowest RUL asset</div>
        <div style="font-size:1.1rem; font-weight:800; color:#E0E7FF; margin-bottom:4px;">{lr_name}</div>
        <div style="font-size:1.6rem; font-weight:800; color:{lr_color};">{lr_rul:.0f}h</div>
        <div style="font-size:0.6rem; color:#64748B; margin-top:4px;">Degradation: <span style="color:{lr_color}; font-weight:600;">{lr_deg:.3f}</span></div>
    </div>
    """)

with k3:
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid #3B82F633; border-radius:10px;
                padding:16px; text-align:center; box-shadow: 0 0 15px #3B82F611;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">📋 Work orders</div>
        <div style="display:flex; justify-content:center; gap:14px;">
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:#3B82F6;">{open_wo}</div>
                <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">Open</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:#EF4444;">{emergency_wo}</div>
                <div style="font-size:0.55rem; color:#EF4444; text-transform:uppercase;">Emergency</div>
            </div>
        </div>
        <div style="font-size:0.6rem; color:#64748B; margin-top:8px;">
            Total: {len(all_wo) if len(all_wo) > 0 else 0}</div>
    </div>
    """)

with k4:
    fat_color = "#EF4444" if high_fatigue > 0 else "#10B981"
    health_color = "#EF4444" if avg_health < 60 else "#F59E0B" if avg_health < 80 else "#10B981"
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid {fat_color}33; border-radius:10px;
                padding:16px; text-align:center; box-shadow: 0 0 15px {fat_color}11;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">⚡ Fatigue & health</div>
        <div style="display:flex; justify-content:center; gap:14px;">
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:{fat_color};">{high_fatigue}</div>
                <div style="font-size:0.55rem; color:{fat_color}; text-transform:uppercase;">High fatigue</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:{health_color};">{avg_health:.0f}</div>
                <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">Avg health</div>
            </div>
        </div>
    </div>
    """)

# ═══════════════════════════════════════════════════════════════
# TABS
# ═══════════════════════════════════════════════════════════════
tab_matrix, tab_dive = st.tabs(["Fleet matrix", "Asset deep-dive"])

# ─── TAB 1: FLEET HEALTH MATRIX ───
with tab_matrix:
    wo_counts = all_wo.groupby("ASSET_ID").size().to_dict() if len(all_wo) > 0 else {}
    open_wo_counts = all_wo[all_wo["STATUS"].isin(["open", "in_progress"])].groupby("ASSET_ID").size().to_dict() if len(all_wo) > 0 else {}

    if len(preds) > 0:
        # Scatter plot: degradation vs fatigue
        _section_header("⚠️", "Risk landscape — degradation vs fatigue")
        with st.container(border=True):
            st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Asset risk positioning</div>')
            scatter_df = preds[["ASSET_NAME", "DEGRADATION_SCORE", "FATIGUE_SCORE", "STAGE_PRED", "RUL_HOURS"]].copy()
            scatter = alt.Chart(scatter_df).mark_circle(opacity=0.8, size=200).encode(
                x=alt.X("DEGRADATION_SCORE:Q", title="Degradation score", scale=alt.Scale(zero=True)),
                y=alt.Y("FATIGUE_SCORE:Q", title="Fatigue score", scale=alt.Scale(zero=True)),
                color=alt.Color("STAGE_PRED:N", title="Stage", scale=alt.Scale(
                    domain=["Critical", "Warning", "Healthy"],
                    range=["#EF4444", "#F59E0B", "#10B981"])),
                tooltip=["ASSET_NAME", alt.Tooltip("DEGRADATION_SCORE:Q", format=".3f"),
                          alt.Tooltip("FATIGUE_SCORE:Q", format=".3f"),
                          alt.Tooltip("RUL_HOURS:Q", format=",.0f"), "STAGE_PRED"],
            ).properties(height=250)
            st.altair_chart(scatter.configure_view(strokeWidth=0).configure_axis(
                gridColor="rgba(255,255,255,0.04)", labelColor="#64748B", titleColor="#94A3B8"),
                use_container_width=True)

        # Asset cards
        _section_header("🏭", "All assets")
        for _, r in preds.iterrows():
            stage = r["STAGE_PRED"]
            asset_id = r["ASSET_ID"]
            rul = r.get("RUL_HOURS", 0) or 0
            deg = r.get("DEGRADATION_SCORE", 0) or 0
            fatigue = r.get("FATIGUE_SCORE", 0) or 0
            fat_level = r.get("FATIGUE_LEVEL", "HEALTHY")
            health = r.get("COMPOSITE_HEALTH_SCORE", 0) or 0
            anomaly = r.get("ANOMALY_SCORE", 0) if "ANOMALY_SCORE" in r.index else 0
            fm = FAILURE_MODE_LABEL.get(r.get("FAILURE_MODE_PRED", ""), r.get("FAILURE_MODE_PRED", "?"))

            dc = "#EF4444" if deg > 0.30 else "#F59E0B" if deg > 0.15 else "#10B981"
            flc = "#EF4444" if fat_level == "HIGH" else "#F59E0B" if fat_level == "ACCUMULATING" else "#10B981"
            anc = "#EF4444" if anomaly > 0.5 else "#F59E0B" if anomaly > 0.3 else "#10B981"

            total_wo_count = wo_counts.get(asset_id, 0)
            open_wo_count = open_wo_counts.get(asset_id, 0)

            with st.container(border=True):
                c1, c2, c3, c4, c5, c6 = st.columns([2.2, 1, 1.2, 1.2, 1.2, 1.2])
                with c1:
                    st.markdown(f"**{r['ASSET_NAME']}**")
                    st.caption(f"{r.get('ASSET_TYPE', '')} | {r.get('LINE_ID', '')} | {fm}")
                with c2:
                    st.html('<span style="font-size:0.6rem; color:#64748B;">Stage:</span>')
                    st.badge(stage, color="red" if stage == "Critical" else "orange" if stage == "Warning" else "green")
                    st.html('<span style="font-size:0.6rem; color:#64748B;">Fatigue:</span>')
                    st.badge(fat_level, color="red" if fat_level == "HIGH" else "orange" if fat_level == "ACCUMULATING" else "green")
                with c3:
                    st.metric("RUL", fmt_hours(rul))
                    st.html(f'<div style="font-size:0.65rem; color:#64748B;">Deg: <span style="color:{dc}; font-weight:700;">{deg:.3f}</span></div>')
                with c4:
                    st.html(f'<div style="font-size:0.65rem; color:#64748B;">Fatigue: <span style="color:{flc}; font-weight:700;">{fatigue:.3f}</span></div>')
                    st.html(f'<div style="font-size:0.65rem; color:#64748B;">Anomaly: <span style="color:{anc}; font-weight:700;">{anomaly:.2f}</span></div>')
                with c5:
                    st.html(f'<div style="font-size:0.65rem; color:#64748B;">Health: <span style="font-weight:700;">{health:.0f}</span>/100</div>')
                with c6:
                    wo_label = f"WOs: {total_wo_count}" + (f" ({open_wo_count} open)" if open_wo_count > 0 else "")
                    st.caption(wo_label)

# ─── TAB 2: ASSET DEEP-DIVE ───
with tab_dive:
    asset_names = preds["ASSET_NAME"].tolist() if len(preds) > 0 else []
    selected_asset = st.selectbox("Select asset", asset_names, index=0 if asset_names else None)

    if selected_asset and len(preds) > 0:
        asset = preds[preds["ASSET_NAME"] == selected_asset].iloc[0]
        asset_id = asset["ASSET_ID"]
        stage = asset["STAGE_PRED"]
        rul = asset["RUL_HOURS"]
        health = asset["COMPOSITE_HEALTH_SCORE"]
        fatigue = asset["FATIGUE_SCORE"]
        deg = asset["DEGRADATION_SCORE"]
        stress = asset["STRESS_INDEX"]
        mode = asset["FAILURE_MODE_PRED"]
        conf = asset["FAILURE_MODE_CONFIDENCE"]
        trans = asset["TRANSITION_PROBABILITY"]
        anomaly = asset.get("ANOMALY_SCORE", 0) if "ANOMALY_SCORE" in asset.index else 0
        fat_level = asset.get("FATIGUE_LEVEL", "HEALTHY")

        stage_color = "#EF4444" if stage == "Critical" else "#F59E0B" if stage == "Warning" else "#10B981"

        # Primary KPIs
        _section_header("📊", f"{selected_asset} — diagnostics", stage_color)

        pk1, pk2, pk3, pk4 = st.columns(4)
        with pk1:
            st.html(f"""
            <div style="background:rgba(17,24,39,0.9); border:1px solid {stage_color}33; border-left:3px solid {stage_color};
                        border-radius:10px; padding:14px; text-align:center; box-shadow: 0 0 12px {stage_color}11;">
                <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase; font-weight:600;">Stage</div>
                <div style="display:inline-block; margin-top:6px; padding:4px 14px; border-radius:10px; font-size:0.7rem; font-weight:700;
                            background:{stage_color}18; color:{stage_color}; border:1px solid {stage_color}33;">{stage}</div>
                <div style="font-size:0.6rem; color:#64748B; margin-top:6px;">{mode.replace('_', ' ').title()}</div>
                <div style="font-size:0.55rem; color:#64748B;">{conf:.0%} confidence</div>
            </div>
            """)
        with pk2:
            rul_color = "#EF4444" if rul < 500 else "#F59E0B" if rul < 800 else "#10B981"
            st.html(f"""
            <div style="background:rgba(17,24,39,0.9); border:1px solid {rul_color}33; border-radius:10px;
                        padding:14px; text-align:center; box-shadow: 0 0 12px {rul_color}11;">
                <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase; font-weight:600;">Remaining useful life</div>
                <div style="font-size:1.8rem; font-weight:800; color:{rul_color}; margin-top:4px;">{rul:.0f}h</div>
                <div style="font-size:0.55rem; color:#64748B; margin-top:4px;">CI: {asset.get('RUL_LOWER_CI', 0):.0f}h – {asset.get('RUL_UPPER_CI', 0):.0f}h</div>
            </div>
            """)
        with pk3:
            hc = "#EF4444" if health < 60 else "#F59E0B" if health < 80 else "#10B981"
            st.html(f"""
            <div style="background:rgba(17,24,39,0.9); border:1px solid {hc}33; border-radius:10px;
                        padding:14px; text-align:center; box-shadow: 0 0 12px {hc}11;">
                <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase; font-weight:600;">Health score</div>
                <div style="font-size:1.8rem; font-weight:800; color:{hc}; margin-top:4px;">{health:.0f}</div>
                <div style="font-size:0.55rem; color:#64748B; margin-top:4px;">out of 100</div>
            </div>
            """)
        with pk4:
            dc = "#EF4444" if deg > 0.30 else "#F59E0B" if deg > 0.15 else "#10B981"
            st.html(f"""
            <div style="background:rgba(17,24,39,0.9); border:1px solid {dc}33; border-radius:10px;
                        padding:14px; text-align:center; box-shadow: 0 0 12px {dc}11;">
                <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase; font-weight:600;">Degradation</div>
                <div style="font-size:1.8rem; font-weight:800; color:{dc}; margin-top:4px;">{deg:.3f}</div>
                <div style="font-size:0.55rem; color:#64748B; margin-top:4px;">Trans prob: {trans:.1%}</div>
            </div>
            """)

        # Risk indicators row
        with st.container(horizontal=True):
            flc = "#EF4444" if fat_level == "HIGH" else "#F59E0B" if fat_level == "ACCUMULATING" else "#10B981"
            st.metric("Fatigue", f"{fatigue:.3f}",
                       delta=fat_level, delta_color="inverse" if fatigue > 0.25 else "off", border=True)
            st.metric("Stress index", f"{stress:.2f}",
                       delta="Overstressed" if stress > 0.7 else "Moderate" if stress > 0.4 else "Normal",
                       delta_color="inverse" if stress > 0.4 else "off", border=True)
            st.metric("Anomaly score", f"{anomaly:.2f}",
                       delta="Anomalous" if anomaly > 0.5 else "Elevated" if anomaly > 0.3 else "Normal",
                       delta_color="inverse" if anomaly > 0.3 else "off", border=True)
            st.metric("Transition prob", f"{trans:.1%}",
                       help="Likelihood of moving to a worse stage", border=True)

        # Failure DNA chart
        _section_header("🧬", "Failure DNA", "#00D4FF")
        with st.container(border=True):
            st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Normalized risk signals</div>')
            dna_data = pd.DataFrame({
                "Metric": ["Degradation", "Fatigue", "Anomaly", "Transition", "Stress", "1 - Health/100"],
                "Value": [deg, fatigue, anomaly, trans, min(stress, 1.0), 1 - health / 100],
            })
            chart = alt.Chart(dna_data).mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4).encode(
                x=alt.X("Metric:N", sort=None, axis=alt.Axis(labelAngle=0, labelColor="#64748B")),
                y=alt.Y("Value:Q", scale=alt.Scale(domain=[0, 1]), title="Score (0-1)",
                         axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                color=alt.when(alt.datum.Value > 0.7).then(alt.value(C["critical"]))
                    .when(alt.datum.Value > 0.4).then(alt.value(C["warning"]))
                    .otherwise(alt.value(C["healthy"])),
                tooltip=[alt.Tooltip("Metric:N"), alt.Tooltip("Value:Q", format=".3f")],
            ).properties(height=220)
            st.altair_chart(chart.configure_view(strokeWidth=0).configure_axis(
                gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

        # Bottom panels
        col_parts, col_alerts = st.columns(2)

        with col_parts:
            _section_header("📦", "Parts status", "#F59E0B")
            proc = load_procurement_recs() if procurement_available() else pd.DataFrame()
            asset_proc = proc[proc["ASSET_ID"] == asset_id] if len(proc) > 0 and "ASSET_ID" in proc.columns else pd.DataFrame()
            if len(asset_proc) > 0:
                p = asset_proc.iloc[0]
                risk = p.get("PROCUREMENT_RISK", "UNKNOWN")
                risk_c = "#EF4444" if "SHORTAGE" in str(risk) else "#F59E0B" if "EXPEDITE" in str(risk) else "#10B981"
                _glow_card(f"Part: {p.get('PART_NAME', 'N/A')}", f"""
                    <div style="display:flex; gap:16px; margin-bottom:8px;">
                        <div><span style="font-size:0.6rem; color:#64748B;">ATP</span><br>
                            <span style="font-size:1rem; font-weight:700; color:#E0E7FF;">{p.get('AVAILABLE_TO_PROMISE', 'N/A')}</span></div>
                        <div><span style="font-size:0.6rem; color:#64748B;">On hand</span><br>
                            <span style="font-size:1rem; font-weight:700; color:#E0E7FF;">{p.get('QUANTITY_ON_HAND', 'N/A')}</span></div>
                        <div><span style="font-size:0.6rem; color:#64748B;">Lead time</span><br>
                            <span style="font-size:1rem; font-weight:700; color:#E0E7FF;">{p.get('LEAD_TIME_DAYS', 'N/A')}d</span></div>
                    </div>
                    <div style="display:inline-block; padding:2px 8px; border-radius:8px; font-size:0.6rem; font-weight:700;
                        background:{risk_c}18; color:{risk_c}; border:1px solid {risk_c}33;">{risk}</div>
                    <div style="font-size:0.65rem; color:#64748B; margin-top:6px;">Gap: {p.get('LEAD_TIME_GAP_DAYS', 'N/A')}d | Arrival: {str(p.get('EXPECTED_ARRIVAL_DATE', 'N/A'))[:10]}</div>
                """, risk_c, "📦")

                action = p.get("RECOMMENDED_PROCUREMENT_ACTION", "")
                open_po = p.get("OPEN_PO_ID")
                has_open_po = open_po is not None and str(open_po) not in ("None", "", "nan")
                if has_open_po:
                    st.caption(f":material/local_shipping: PO in progress: **{open_po}**")
                elif action and action not in ("RESERVE_STOCK", "NO_ACTION", "USE_STOCK", "MONITOR_PO"):
                    st.caption(f"Action: **{action}**")
                    if st.button("Create PO", key=f"po_{asset_id}", type="primary", icon=":material/add_shopping_cart:"):
                        try:
                            session = conn.session()
                            session.sql(
                                f"CALL {DB}.ANALYTICS.GENERATE_PURCHASE_ORDER(:1, :2, :3, :4, :5, :6)",
                                params=[
                                    str(p.get("PART_ID", "")), str(p.get("SUPPLIER_ID", "")),
                                    int(p.get("REQUIRED_QUANTITY", 1)),
                                    str(p.get("REQUIRED_BY_DATE", ""))[:10],
                                    str(asset_id), str(p.get("WO_ID") or ""),
                                ],
                            ).collect()
                            st.success("PO created")
                        except Exception as ex:
                            st.error(f"Failed: {ex}")
            else:
                st.info("No procurement data for this asset.")

        with col_alerts:
            _section_header("🚨", "Alerts & maintenance", "#EF4444")
            asset_alerts = alerts[alerts["ASSET_ID"] == asset_id] if len(alerts) > 0 else pd.DataFrame()
            if len(asset_alerts) > 0:
                for _, a in asset_alerts.head(3).iterrows():
                    sev = a["SEVERITY"]
                    sev_c = "red" if sev == "CRITICAL" else "orange" if sev == "WARNING" else "blue"
                    with st.container(border=True):
                        c1, c2 = st.columns([1, 4])
                        with c1:
                            st.badge(sev, color=sev_c)
                        with c2:
                            st.caption(a["MESSAGE"][:200])
            else:
                st.success("No active alerts.", icon=":material/check_circle:")

            st.html('<div style="margin-top:8px;"></div>')
            st.markdown("**Recent maintenance**")
            asset_logs = logs[logs["ASSET_ID"] == asset_id] if len(logs) > 0 else pd.DataFrame()
            if len(asset_logs) > 0:
                for _, l in asset_logs.head(6).iterrows():
                    wo_type = l.get("WO_TYPE") or "unknown"
                    priority = l.get("PRIORITY") or ""
                    ts = str(l["TIMESTAMP"])[:16]
                    tech = l["TECHNICIAN"]
                    notes = l["NOTES_TEXT"][:250] if l["NOTES_TEXT"] else ""

                    type_icon = ":material/warning:" if wo_type == "emergency" else ":material/build:" if wo_type == "corrective" else ":material/check_circle:"
                    type_color = "red" if wo_type == "emergency" else "orange" if wo_type == "corrective" else "green"

                    with st.container(border=True):
                        header_cols = st.columns([3, 1, 1, 1])
                        with header_cols[0]:
                            st.markdown(f"{type_icon} **{l.get('WO_ID', '')}** — {tech}")
                        with header_cols[1]:
                            st.badge(wo_type, color=type_color)
                        with header_cols[2]:
                            st.badge(priority, color="red" if priority in ("CRITICAL", "HIGH") else "blue" if priority == "MEDIUM" else "gray")
                        with header_cols[3]:
                            st.caption(ts)
                        st.caption(notes)
            else:
                st.info("No maintenance history for this asset.")
