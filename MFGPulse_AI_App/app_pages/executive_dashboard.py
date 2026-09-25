import streamlit as st
import altair as alt
import pandas as pd
from app_pages._shared import (
    load_executive_summary, load_predictions, load_oee_by_line, load_oee_daily_trend,
    load_oee_loss, load_cost_by_asset, load_procurement_recs, load_open_pos,
    load_all_work_orders, fmt_currency, fmt_pct, C, RISK_COLOR, procurement_available,
    generate_executive_summary, generate_board_summary, load_data_freshness, freshness_badge,
    load_kpi_snapshots, load_oee_period_comparison, fmt_hours,
    FAILURE_MODE_LABEL,
)

alt.renderers.enable("mimetype")

# ─── Helper: glow card (same pattern as digital_twin.py) ───
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
exe = load_executive_summary()
preds = load_predictions()
oee = load_oee_by_line()
oee_trend = load_oee_daily_trend()
loss = load_oee_loss()
cost_asset = load_cost_by_asset()
e = exe.iloc[0] if len(exe) > 0 else {}

# Pre-compute cost metrics used across sections
avg_fail_cost = preds["ESTIMATED_FAILURE_COST"].mean() if len(preds) > 0 and "ESTIMATED_FAILURE_COST" in preds.columns else 0
avg_repair_cost = preds["PLANNED_REPAIR_COST"].mean() if len(preds) > 0 and "PLANNED_REPAIR_COST" in preds.columns else 0

# Period-over-period data
try:
    kpi_snaps = load_kpi_snapshots()
    prev_snap = kpi_snaps.iloc[1] if len(kpi_snaps) > 1 else None
except Exception:
    kpi_snaps = pd.DataFrame()
    prev_snap = None

try:
    oee_comparison = load_oee_period_comparison()
except Exception:
    oee_comparison = pd.DataFrame()

# ═══════════════════════════════════════════════════════════════
# SECTION 1: Header + Plant Status Verdict
# ═══════════════════════════════════════════════════════════════
oee_val = e.get("PLANT_OEE", 0) or 0
crit_count = e.get("CRITICAL_ASSETS", 0) or 0
warn_count = e.get("WARNING_ASSETS", 0) or 0
total_assets = e.get("TOTAL_ASSETS", 10) or 10

# Determine plant status
proc_avail = procurement_available()
has_critical_supply = False
if proc_avail:
    try:
        proc = load_procurement_recs()
        has_critical_supply = len(proc[proc["PROCUREMENT_RISK"] == "CRITICAL_SHORTAGE"]) > 0 if "PROCUREMENT_RISK" in proc.columns else False
    except Exception:
        proc = pd.DataFrame()

if crit_count > 0 or has_critical_supply:
    plant_status, status_color, status_icon = "AT RISK", "#EF4444", "🔴"
elif warn_count >= total_assets * 0.5 or oee_val < 70:
    plant_status, status_color, status_icon = "DEGRADED", "#F59E0B", "🟡"
else:
    plant_status, status_color, status_icon = "OPERATIONAL", "#10B981", "🟢"

freshness = load_data_freshness()
sensor_fresh = freshness[freshness['SOURCE_TABLE'] == 'SENSOR_READINGS'].iloc[0] if len(freshness) > 0 else {}
stale_min = sensor_fresh.get('STALENESS_MINUTES', '?') if sensor_fresh is not None and len(sensor_fresh) > 0 else '?'

st.html(f"""
<div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:4px; flex-wrap:wrap; gap:10px;">
    <div style="display:flex; align-items:center; gap:14px;">
        <div style="font-size:1.5rem; font-weight:800; color:#E0E7FF;">⚙ Executive dashboard</div>
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
st.caption("Strategic plant health, financial exposure, and decisions requiring ELT action")

with st.expander("About this page", expanded=False, icon=":material/info:"):
    st.markdown("""
**Purpose**: Board-ready command view for Plant Managers and Directors — plant health verdict, financial exposure, and decisions requiring leadership action.

**Plant status verdict**: OPERATIONAL (OEE on target, no critical assets) · DEGRADED (OEE < 70% or >= 50% assets in Warning) · AT RISK (any Critical asset or critical supply shortage)

**Sections**:
- **Executive brief** — AI-generated board-ready briefing (Cortex Complete, llama3.1-70b) with financial impact, key risks, and required actions
- **Plant OEE** — Overall Equipment Effectiveness vs 85% target, with availability/performance/quality breakdown by production line
- **OEE trend** — 30-day daily OEE trend chart with period-over-period comparison
- **Financial exposure** — Cost avoided by predictive maintenance, maintenance ROI multiplier, cost-of-inaction by asset, repair vs failure cost comparison
- **Asset risk overview** — All 10 assets sorted by urgency with stage, RUL, failure mode, and cost impact
- **Procurement status** — Supply chain risk summary (if procurement module is active)
- **Data freshness** — Sensor data staleness monitoring against SLA

**Data sources**: `ANALYTICS.EXECUTIVE_SUMMARY`, `ANALYTICS.PREDICTIONS_WITH_COST`, `ANALYTICS.OEE_METRICS`, `ANALYTICS.COST_IMPACT_BY_ASSET`
""")


# ═══════════════════════════════════════════════════════════════
# SECTION 2: AI Executive Brief (always visible)
# ═══════════════════════════════════════════════════════════════
_section_header("🤖", "Executive brief", "#8B5CF6")

if len(exe) > 0:
    cost_avoided = e.get("TOTAL_COST_AVOIDED", 0) or 0
    roi = e.get("MAINTENANCE_ROI_X", 0) or 0
    spend = e.get("TOTAL_MAINTENANCE_SPEND", 0) or 0
    emerg = e.get("TOTAL_EMERGENCY_WOS", 0) or 0
    early_det = e.get("AVG_EARLY_DETECTION_DAYS", 0) or 0
    oee_lines = "; ".join([f"{r['LINE_ID']}: OEE {r['OEE']}%" for _, r in oee.iterrows()]) if len(oee) > 0 else "N/A"

    delta_context = ""
    if len(oee_comparison) > 0:
        worst_line = oee_comparison.loc[oee_comparison["OEE_DELTA"].idxmin()] if "OEE_DELTA" in oee_comparison.columns else None
        if worst_line is not None:
            delta_context = f" Worst performing line: {worst_line['LINE_ID']} with OEE delta {worst_line['OEE_DELTA']:+.1f}% vs previous period."

    avg_fail_cost = preds["ESTIMATED_FAILURE_COST"].mean() if len(preds) > 0 and "ESTIMATED_FAILURE_COST" in preds.columns else 0
    avg_repair_cost = preds["PLANNED_REPAIR_COST"].mean() if len(preds) > 0 and "PLANNED_REPAIR_COST" in preds.columns else 0
    cost_multiplier = round(avg_fail_cost / max(avg_repair_cost, 1), 1)
    total_inaction = preds["COST_OF_INACTION"].fillna(0).sum() if len(preds) > 0 and "COST_OF_INACTION" in preds.columns else 0

    top_risk_assets = ""
    if len(preds) > 0:
        urgent = preds[preds["STAGE_PRED"].isin(["Critical", "Warning"])].head(3)
        top_risk_assets = "; ".join([f"{r['ASSET_NAME']} ({r.get('FAILURE_MODE_PRED','?')}, {r['RUL_HOURS']:.0f}h RUL, ${r.get('COST_OF_INACTION',0):,.0f} at stake)" for _, r in urgent.iterrows()])

    data_block = f"""Plant status: {plant_status}. Plant OEE: {oee_val:.1f}% (target: 85%, gap: {85-oee_val:.1f}%). Critical assets: {crit_count}/{total_assets}. Warning assets: {warn_count}. Cost avoided by predictive maintenance: ${cost_avoided:,.0f}. Maintenance ROI: {roi}x on ${spend:,.0f} total spend. Average failure cost: ${avg_fail_cost:,.0f}. Average planned repair cost: ${avg_repair_cost:,.0f}. Cost multiplier if undetected: {cost_multiplier}x. Total cost-of-inaction exposure: ${total_inaction:,.0f}. Emergency WOs: {emerg}. Early detection window: {int(early_det)} days avg. OEE by line: {oee_lines}.{delta_context} Top at-risk assets: {top_risk_assets}. Supply chain: {'critical shortages detected' if has_critical_supply else 'no critical shortages'}."""

    summary = generate_board_summary(data_block, "executive_board")

    brief_col, kpi_col = st.columns([3, 1])
    with brief_col:
        st.html(f"""
        <div style="background:rgba(17,24,39,0.8); border:1px solid #8B5CF633; border-left:3px solid #8B5CF6;
                    border-radius:8px; padding:20px; box-shadow:0 0 15px #8B5CF611;">
            <div style="color:#8B5CF6; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.1em;
                        font-weight:600; margin-bottom:12px;">✦ Board-ready briefing</div>
            <div style="color:#E0E7FF; font-size:0.82rem; line-height:1.8; white-space:pre-line;">{summary}</div>
        </div>
        """)
    with kpi_col:
        st.html(f"""
        <div style="background:rgba(17,24,39,0.8); border:1px solid rgba(0,212,255,0.12); border-radius:8px; padding:16px;">
            <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:12px;">Quick reference</div>
            <div style="margin-bottom:14px;">
                <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">Plant OEE</div>
                <div style="font-size:1.3rem; font-weight:800; color:{'#EF4444' if oee_val < 60 else '#F59E0B' if oee_val < 80 else '#10B981'};">{oee_val:.1f}%</div>
            </div>
            <div style="margin-bottom:14px;">
                <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">Cost avoided</div>
                <div style="font-size:1.3rem; font-weight:800; color:#10B981;">${cost_avoided:,.0f}</div>
            </div>
            <div style="margin-bottom:14px;">
                <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">ROI</div>
                <div style="font-size:1.3rem; font-weight:800; color:#00D4FF;">{roi}×</div>
            </div>
            <div style="margin-bottom:14px;">
                <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">Exposure</div>
                <div style="font-size:1.3rem; font-weight:800; color:#EF4444;">${total_inaction:,.0f}</div>
            </div>
            <div>
                <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">Cost multiplier</div>
                <div style="font-size:1.3rem; font-weight:800; color:#F59E0B;">{cost_multiplier}×</div>
                <div style="font-size:0.55rem; color:#64748B;">if undetected</div>
            </div>
        </div>
        """)

    if st.button("Regenerate brief", key="regen_exec", icon=":material/refresh:"):
        st.session_state.pop("_llm_summary_executive_board", None)
        st.session_state.pop("_llm_hash_executive_board", None)
        st.rerun()
else:
    st.caption("No executive summary data available.")


# ═══════════════════════════════════════════════════════════════
# SECTION 3: Hero KPI Strip with period-over-period deltas
# ═══════════════════════════════════════════════════════════════
_section_header("📊", "Key performance indicators")

# Period toggle
kpi_period = st.segmented_control("KPI period", ["Last 7 days", "Last 30 days", "All time"],
                                   default="All time", label_visibility="collapsed", key="kpi_period")
period_days = {"Last 7 days": 7, "Last 30 days": 30}.get(kpi_period, None)

# Compute period-specific OEE from trend data
if period_days is not None and len(oee_trend) > 0:
    max_day = oee_trend["DAY"].max()
    cutoff = max_day - pd.Timedelta(days=period_days)
    period_oee_data = oee_trend[oee_trend["DAY"] >= cutoff]
    period_oee_val = float(period_oee_data["OEE"].mean()) if len(period_oee_data) > 0 else float(oee_val)

    # Previous period for delta (e.g. 7d before the 7d window)
    prev_cutoff = cutoff - pd.Timedelta(days=period_days)
    prev_period_data = oee_trend[(oee_trend["DAY"] >= prev_cutoff) & (oee_trend["DAY"] < cutoff)]
    prev_period_oee = float(prev_period_data["OEE"].mean()) if len(prev_period_data) > 0 else None
else:
    period_oee_val = float(oee_val)
    prev_period_oee = float(prev_snap["PLANT_OEE"]) if prev_snap is not None and "PLANT_OEE" in prev_snap.index else None

# Period-specific WO costs
all_wo = load_all_work_orders()
if period_days is not None and len(all_wo) > 0 and "CREATED_DATE" in all_wo.columns:
    wo_max = pd.to_datetime(all_wo["CREATED_DATE"]).max()
    wo_cutoff = wo_max - pd.Timedelta(days=period_days)
    period_wo = all_wo[pd.to_datetime(all_wo["CREATED_DATE"]) >= wo_cutoff]
else:
    period_wo = all_wo

period_spend = period_wo["TOTAL_COST"].sum() if len(period_wo) > 0 else 0
period_emergency = len(period_wo[(period_wo["WO_TYPE"] == "emergency") & (period_wo["STATUS"].isin(["open", "in_progress"]))]) if len(period_wo) > 0 else 0

# Compute financial exposure (total cost of inaction — always current, not period-filtered)
financial_exposure = 0
if len(preds) > 0 and "COST_OF_INACTION" in preds.columns:
    financial_exposure = preds["COST_OF_INACTION"].fillna(0).sum()

# Period deltas
oee_delta_html = ""
if prev_period_oee is not None and prev_period_oee > 0:
    d = period_oee_val - prev_period_oee
    if abs(d) >= 0.1:
        arrow = "▲" if d > 0 else "▼"
        dc = "#10B981" if d > 0 else "#EF4444"
        period_label = f"vs prior {period_days}d" if period_days else "vs prior"
        oee_delta_html = f'<div style="font-size:0.72rem; color:{dc}; font-weight:600; margin-top:4px;">{arrow} {abs(d):.1f}% {period_label}</div>'

cost_avoided_val = float(e.get("TOTAL_COST_AVOIDED", 0) or 0)
avoided_delta_html = ""
prev_avoided = float(prev_snap["TOTAL_COST_AVOIDED"]) if prev_snap is not None and "TOTAL_COST_AVOIDED" in prev_snap.index else None
if prev_avoided is not None and prev_avoided > 0:
    d = cost_avoided_val - prev_avoided
    if abs(d) >= 100:
        arrow = "▲" if d > 0 else "▼"
        dc = "#10B981" if d > 0 else "#EF4444"
        avoided_delta_html = f'<div style="font-size:0.72rem; color:{dc}; font-weight:600; margin-top:4px;">{arrow} ${abs(d):,.0f}</div>'

# OEE gauge percentage for CSS
oee_pct = float(max(0, min(100, period_oee_val)))
oee_color = "#EF4444" if oee_pct < 60 else "#F59E0B" if oee_pct < 80 else "#10B981"
gauge_dasharray = f"{oee_pct * 2.51:.0f} 251"

k1, k2, k3, k4 = st.columns(4)

with k1:
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid {oee_color}33; border-radius:10px;
                padding:16px; text-align:center; box-shadow: 0 0 15px {oee_color}11;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">⚡ Plant OEE</div>
        <div style="position:relative; width:90px; height:90px; margin:0 auto 8px auto;">
            <svg viewBox="0 0 100 100" width="90" height="90">
                <circle cx="50" cy="50" r="40" fill="none" stroke="rgba(255,255,255,0.06)" stroke-width="8"/>
                <circle cx="50" cy="50" r="40" fill="none" stroke="{oee_color}" stroke-width="8"
                    stroke-linecap="round" stroke-dasharray="{gauge_dasharray}"
                    transform="rotate(-90 50 50)"
                    style="filter: drop-shadow(0 0 8px {oee_color}88);"/>
            </svg>
            <div style="position:absolute; top:50%; left:50%; transform:translate(-50%,-50%); text-align:center;">
                <div style="font-size:1.6rem; font-weight:800; color:{oee_color};">{period_oee_val:.1f}</div>
                <div style="font-size:0.55rem; color:#64748B;">%</div>
            </div>
        </div>
        <div style="font-size:0.68rem; color:#64748B;">Target: <span style="color:#10B981;">85%</span></div>
        {oee_delta_html}
    </div>
    """)

with k2:
    exp_color = "#EF4444" if financial_exposure > 30000 else "#F59E0B" if financial_exposure > 10000 else "#10B981"
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid {exp_color}33; border-left:3px solid {exp_color};
                border-radius:10px; padding:16px; text-align:center; box-shadow: 0 0 15px {exp_color}11;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">💰 Financial exposure</div>
        <div style="font-size:2rem; font-weight:800; color:{exp_color};
                    text-shadow: 0 0 12px {exp_color}55;">${financial_exposure:,.0f}</div>
        <div style="font-size:0.68rem; color:#94A3B8; margin-top:4px;">Total cost of inaction</div>
        <div style="font-size:0.65rem; color:#64748B; margin-top:6px;">
            Across {len(preds) if len(preds) > 0 else 0} assets at risk
        </div>
    </div>
    """)

with k3:
    roi_val = e.get("MAINTENANCE_ROI_X", 0) or 0
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid #10B98133; border-left:3px solid #10B981;
                border-radius:10px; padding:16px; text-align:center; box-shadow: 0 0 15px #10B98111;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">✅ Cost avoided</div>
        <div style="font-size:2rem; font-weight:800; color:#10B981;
                    text-shadow: 0 0 12px #10B98155;">${cost_avoided_val:,.0f}</div>
        <div style="font-size:0.68rem; color:#94A3B8; margin-top:4px;">
            ROI: <span style="color:#00D4FF; font-weight:700;">{roi_val}×</span> on ${e.get('TOTAL_MAINTENANCE_SPEND',0):,.0f} spend
        </div>
        <div style="margin-top:6px;">
            <span style="padding:2px 10px; border-radius:10px; font-size:0.58rem; font-weight:700;
                background:#F59E0B18; color:#F59E0B; border:1px solid #F59E0B44;">
                {round(avg_fail_cost / max(avg_repair_cost, 1), 1) if len(preds) > 0 else 0}× cost if undetected</span>
        </div>
        {avoided_delta_html}
    </div>
    """)

with k4:
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid {'#EF444433' if crit_count > 0 else '#F59E0B33'};
                border-radius:10px; padding:16px; text-align:center;
                box-shadow: 0 0 15px {'#EF444411' if crit_count > 0 else '#F59E0B11'};">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">⚠ Asset health</div>
        <div style="display:flex; justify-content:center; gap:16px; margin-bottom:8px;">
            <div>
                <div style="font-size:1.6rem; font-weight:800; color:#EF4444;">{crit_count}</div>
                <div style="font-size:0.55rem; color:#EF4444; text-transform:uppercase;">Critical</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.6rem; font-weight:800; color:#F59E0B;">{warn_count}</div>
                <div style="font-size:0.55rem; color:#F59E0B; text-transform:uppercase;">Warning</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.6rem; font-weight:800; color:#10B981;">{e.get('HEALTHY_ASSETS',0)}</div>
                <div style="font-size:0.55rem; color:#10B981; text-transform:uppercase;">Healthy</div>
            </div>
        </div>
        <div style="background:rgba(255,255,255,0.04); border-radius:4px; height:6px; overflow:hidden; display:flex;">
            <div style="width:{crit_count/max(total_assets,1)*100:.0f}%; background:#EF4444; height:100%;"></div>
            <div style="width:{warn_count/max(total_assets,1)*100:.0f}%; background:#F59E0B; height:100%;"></div>
            <div style="width:{e.get('HEALTHY_ASSETS',0)/max(total_assets,1)*100:.0f}%; background:#10B981; height:100%;"></div>
        </div>
        <div style="font-size:0.6rem; color:#64748B; margin-top:6px;">{total_assets} total assets</div>
        <div style="font-size:0.6rem; color:#F59E0B; margin-top:4px; font-weight:600;">
            {round(warn_count / max(total_assets, 1) * 100)}% in warning stage</div>
    </div>
    """)


# ═══════════════════════════════════════════════════════════════
# SECTION 4: "Requires Your Decision" — Action Cards
# ═══════════════════════════════════════════════════════════════
_section_header("🎯", "Requires your decision", "#F59E0B")

decision_cards = []

# Build decision cards from predictions (highest cost-of-inaction first)
if len(preds) > 0:
    urgent = preds[preds["STAGE_PRED"].isin(["Critical", "Warning"])].copy()
    if "COST_OF_INACTION" in urgent.columns:
        urgent = urgent.sort_values("COST_OF_INACTION", ascending=False)

    # Get procurement data for supply chain context
    proc_data = pd.DataFrame()
    if proc_avail:
        try:
            proc_data = load_procurement_recs()
        except Exception:
            pass

    for _, row in urgent.head(3).iterrows():
        asset_name = row.get("ASSET_NAME", "Unknown")
        stage = row.get("STAGE_PRED", "Unknown")
        rul = row.get("RUL_HOURS", 0) or 0
        failure_cost = row.get("ESTIMATED_FAILURE_COST", 0) or 0
        repair_cost = row.get("PLANNED_REPAIR_COST", 0) or 0
        inaction_cost = row.get("COST_OF_INACTION", 0) or 0
        failure_mode = FAILURE_MODE_LABEL.get(row.get("FAILURE_MODE_PRED", ""), row.get("FAILURE_MODE_PRED", "Unknown"))
        parts_status = row.get("PARTS_STATUS", "Unknown")

        # Determine action
        if rul < 72:
            action = f"APPROVE EMERGENCY REPAIR — ${repair_cost:,.0f}"
            urgency = "URGENT"
            urgency_color = "#EF4444"
        elif parts_status == "ORDER NEEDED":
            action = f"APPROVE PO FOR PARTS — ${repair_cost:,.0f}"
            urgency = "ACTION NEEDED"
            urgency_color = "#F59E0B"
        else:
            action = f"SCHEDULE MAINTENANCE — ${repair_cost:,.0f}"
            urgency = "PLAN"
            urgency_color = "#00D4FF"

        # Supply chain context
        supply_html = ""
        if len(proc_data) > 0 and "ASSET_ID" in proc_data.columns:
            asset_proc = proc_data[proc_data["ASSET_NAME"] == asset_name] if "ASSET_NAME" in proc_data.columns else proc_data[proc_data["ASSET_ID"] == row.get("ASSET_ID", "")]
            if len(asset_proc) > 0:
                worst_risk = asset_proc["PROCUREMENT_RISK"].iloc[0] if "PROCUREMENT_RISK" in asset_proc.columns else "N/A"
                risk_color = "#EF4444" if "SHORTAGE" in str(worst_risk) else "#F59E0B" if "EXPEDITE" in str(worst_risk) else "#10B981"
                supply_html = f'<span style="color:{risk_color}; font-weight:600;">{worst_risk}</span>'

        stage_color = "#EF4444" if stage == "Critical" else "#F59E0B"

        decision_cards.append({
            "asset": asset_name, "stage": stage, "stage_color": stage_color,
            "rul": rul, "failure_mode": failure_mode,
            "failure_cost": failure_cost, "repair_cost": repair_cost, "inaction_cost": inaction_cost,
            "action": action, "urgency": urgency, "urgency_color": urgency_color,
            "parts_status": parts_status, "supply_html": supply_html,
        })

if decision_cards:
    cols = st.columns(len(decision_cards))
    for col, card in zip(cols, decision_cards):
        with col:
            st.html(f"""
            <div style="background:rgba(17,24,39,0.9); border:1px solid {card['urgency_color']}33;
                        border-top:3px solid {card['urgency_color']}; border-radius:10px; padding:16px;
                        box-shadow: 0 0 15px {card['urgency_color']}11;">
                <!-- Urgency badge -->
                <div style="display:inline-block; padding:2px 10px; border-radius:10px; font-size:0.58rem;
                            font-weight:700; text-transform:uppercase; letter-spacing:0.06em;
                            background:{card['urgency_color']}18; color:{card['urgency_color']};
                            border:1px solid {card['urgency_color']}44; margin-bottom:10px;">
                    {card['urgency']}
                </div>
                <!-- Asset + Stage -->
                <div style="font-size:1rem; font-weight:700; color:#E0E7FF; margin-bottom:2px;">
                    {card['asset']}
                </div>
                <div style="font-size:0.7rem; color:{card['stage_color']}; margin-bottom:10px;">
                    {card['stage']} · {card['failure_mode']} · RUL {card['rul']:.0f}h
                </div>
                <!-- Financial impact -->
                <div style="display:flex; gap:8px; margin-bottom:10px;">
                    <div style="flex:1; padding:8px; background:rgba(255,255,255,0.03); border-radius:6px; text-align:center;">
                        <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase;">If fails</div>
                        <div style="font-size:0.95rem; font-weight:700; color:#EF4444;">${card['failure_cost']:,.0f}</div>
                    </div>
                    <div style="flex:1; padding:8px; background:rgba(255,255,255,0.03); border-radius:6px; text-align:center;">
                        <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase;">To repair</div>
                        <div style="font-size:0.95rem; font-weight:700; color:#10B981;">${card['repair_cost']:,.0f}</div>
                    </div>
                    <div style="flex:1; padding:8px; background:rgba(255,255,255,0.03); border-radius:6px; text-align:center;">
                        <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase;">At stake</div>
                        <div style="font-size:0.95rem; font-weight:700; color:#F59E0B;">${card['inaction_cost']:,.0f}</div>
                    </div>
                </div>
                <!-- Supply chain -->
                <div style="font-size:0.68rem; color:#94A3B8; margin-bottom:10px;">
                    Parts: <span style="color:#E0E7FF; font-weight:600;">{card['parts_status']}</span>
                    {(' · Supply: ' + card['supply_html']) if card['supply_html'] else ''}
                </div>
                <!-- Action -->
                <div style="padding:8px 12px; background:{card['urgency_color']}15; border:1px solid {card['urgency_color']}33;
                            border-radius:6px; text-align:center;">
                    <div style="font-size:0.68rem; font-weight:700; color:{card['urgency_color']}; text-transform:uppercase;
                                letter-spacing:0.06em;">{card['action']}</div>
                </div>
            </div>
            """)
else:
    st.html("""
    <div style="background:rgba(16,185,129,0.08); border:1px solid #10B98133; border-left:3px solid #10B981;
                border-radius:8px; padding:16px; text-align:center;">
        <div style="color:#10B981; font-weight:700; font-size:0.9rem;">✦ No ELT decisions pending</div>
        <div style="color:#94A3B8; font-size:0.75rem; margin-top:4px;">All assets within operational parameters</div>
    </div>
    """)


# ═══════════════════════════════════════════════════════════════
# SECTION 5: Trend Snapshot — OEE + Cost (compact, no controls)
# ═══════════════════════════════════════════════════════════════
_section_header("📈", "Trend snapshot — 30 day")

col_trend_oee, col_trend_cost = st.columns(2)

with col_trend_oee:
    with st.container(border=True):
        st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Plant OEE trend</div>')
        if len(oee_trend) > 0:
            plant_avg = oee_trend.groupby("DAY")["OEE"].mean().reset_index()
            plant_avg.columns = ["DAY", "OEE"]
            trend_chart = alt.Chart(plant_avg).mark_area(
                line={"color": "#00D4FF", "strokeWidth": 2},
                color=alt.Gradient(gradient="linear", stops=[
                    alt.GradientStop(color="rgba(0,212,255,0.3)", offset=0),
                    alt.GradientStop(color="rgba(0,212,255,0.02)", offset=1),
                ], x1=1, x2=1, y1=1, y2=0),
            ).encode(
                x=alt.X("DAY:T", title="", axis=alt.Axis(labelColor="#64748B", format="%b %d")),
                y=alt.Y("OEE:Q", title="OEE %", scale=alt.Scale(domain=[0, 100]),
                         axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                tooltip=["DAY:T", alt.Tooltip("OEE:Q", format=".1f")],
            ).properties(height=200)
            target = alt.Chart(pd.DataFrame({"y": [85]})).mark_rule(
                strokeDash=[4, 4], color="#10B981", opacity=0.5
            ).encode(y="y:Q")
            st.altair_chart((trend_chart + target).configure_view(strokeWidth=0).configure_axis(
                gridColor="rgba(255,255,255,0.04)"), use_container_width=True)
        else:
            st.caption("No OEE trend data")

with col_trend_cost:
    with st.container(border=True):
        st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Maintenance spend by type</div>')
        all_wo = load_all_work_orders()
        if len(all_wo) > 0:
            cost_by_type = all_wo.groupby("WO_TYPE")["TOTAL_COST"].sum().reset_index()
            cost_by_type.columns = ["Type", "Cost"]
            wo_chart = alt.Chart(cost_by_type).mark_arc(innerRadius=50).encode(
                theta=alt.Theta("Cost:Q"),
                color=alt.Color("Type:N", scale=alt.Scale(
                    domain=["emergency", "corrective", "preventive"],
                    range=["#EF4444", "#F59E0B", "#10B981"]
                )),
                tooltip=["Type", alt.Tooltip("Cost:Q", format="$,.0f")],
            ).properties(height=200)
            st.altair_chart(wo_chart.configure_view(strokeWidth=0), use_container_width=True)

            total_wo_cost = all_wo["TOTAL_COST"].sum()
            emergency_pct = (all_wo[all_wo["WO_TYPE"] == "emergency"]["TOTAL_COST"].sum() / max(total_wo_cost, 1)) * 100
            st.html(f"""
            <div style="text-align:center; font-size:0.68rem; color:#94A3B8;">
                Total: <span style="color:#E0E7FF; font-weight:600;">${total_wo_cost:,.0f}</span> ·
                Emergency: <span style="color:{'#EF4444' if emergency_pct > 40 else '#F59E0B'}; font-weight:600;">{emergency_pct:.0f}%</span>
            </div>
            """)
        else:
            st.caption("No work order data")


# ═══════════════════════════════════════════════════════════════
# SECTION 6: Risk Heatmap
# ═══════════════════════════════════════════════════════════════
_section_header("⚠️", "Risk heatmap")

if len(preds) > 0:
    risk_df = preds.copy()
    rows_html = ""
    for _, row in risk_df.iterrows():
        name = row.get("ASSET_NAME", "?")
        stage = row.get("STAGE_PRED", "?")
        rul = row.get("RUL_HOURS", 0) or 0
        fail_cost = row.get("ESTIMATED_FAILURE_COST", 0) or 0
        inaction = row.get("COST_OF_INACTION", 0) or 0
        parts = row.get("PARTS_STATUS", "?")

        # Color coding
        sc = "#EF4444" if stage == "Critical" else "#F59E0B" if stage == "Warning" else "#10B981"
        rc = "#EF4444" if rul < 72 else "#F59E0B" if rul < 200 else "#10B981"
        fc = "#EF4444" if fail_cost > 8000 else "#F59E0B" if fail_cost > 4000 else "#10B981"
        ic = "#EF4444" if inaction > 5000 else "#F59E0B" if inaction > 2000 else "#10B981"
        pc = "#EF4444" if parts == "ORDER NEEDED" else "#10B981"

        rows_html += f"""
        <tr>
            <td style="padding:8px 10px; font-weight:600; color:#E0E7FF; border-bottom:1px solid rgba(255,255,255,0.03);">{name}</td>
            <td style="padding:8px 10px; text-align:center; border-bottom:1px solid rgba(255,255,255,0.03);">
                <span style="padding:2px 8px; border-radius:8px; font-size:0.6rem; font-weight:700;
                    background:{sc}18; color:{sc}; border:1px solid {sc}33;">{stage}</span></td>
            <td style="padding:8px 10px; text-align:center; color:{rc}; font-weight:700; font-size:0.85rem;
                border-bottom:1px solid rgba(255,255,255,0.03);">{rul:.0f}h</td>
            <td style="padding:8px 10px; text-align:center; color:{fc}; font-weight:700; font-size:0.85rem;
                border-bottom:1px solid rgba(255,255,255,0.03);">${fail_cost:,.0f}</td>
            <td style="padding:8px 10px; text-align:center; color:{ic}; font-weight:700; font-size:0.85rem;
                border-bottom:1px solid rgba(255,255,255,0.03);">${inaction:,.0f}</td>
            <td style="padding:8px 10px; text-align:center; border-bottom:1px solid rgba(255,255,255,0.03);">
                <span style="padding:2px 8px; border-radius:8px; font-size:0.6rem; font-weight:700;
                    background:{pc}18; color:{pc}; border:1px solid {pc}33;">{parts}</span></td>
        </tr>"""

    st.html(f"""
    <div style="background:rgba(17,24,39,0.8); border:1px solid rgba(0,212,255,0.12); border-radius:8px; overflow:hidden;">
        <table style="width:100%; border-collapse:collapse; font-size:0.78rem;">
            <thead>
                <tr>
                    <th style="padding:10px; text-align:left; font-size:0.6rem; text-transform:uppercase;
                        letter-spacing:0.06em; color:#64748B; font-weight:600; border-bottom:1px solid rgba(0,212,255,0.12);">Asset</th>
                    <th style="padding:10px; text-align:center; font-size:0.6rem; text-transform:uppercase;
                        letter-spacing:0.06em; color:#64748B; font-weight:600; border-bottom:1px solid rgba(0,212,255,0.12);">Stage</th>
                    <th style="padding:10px; text-align:center; font-size:0.6rem; text-transform:uppercase;
                        letter-spacing:0.06em; color:#64748B; font-weight:600; border-bottom:1px solid rgba(0,212,255,0.12);">RUL</th>
                    <th style="padding:10px; text-align:center; font-size:0.6rem; text-transform:uppercase;
                        letter-spacing:0.06em; color:#64748B; font-weight:600; border-bottom:1px solid rgba(0,212,255,0.12);">Failure $</th>
                    <th style="padding:10px; text-align:center; font-size:0.6rem; text-transform:uppercase;
                        letter-spacing:0.06em; color:#64748B; font-weight:600; border-bottom:1px solid rgba(0,212,255,0.12);">At Stake</th>
                    <th style="padding:10px; text-align:center; font-size:0.6rem; text-transform:uppercase;
                        letter-spacing:0.06em; color:#64748B; font-weight:600; border-bottom:1px solid rgba(0,212,255,0.12);">Parts</th>
                </tr>
            </thead>
            <tbody>{rows_html}</tbody>
        </table>
    </div>
    """)
else:
    st.caption("No prediction data available.")


# ═══════════════════════════════════════════════════════════════
# SECTION 7: Supply Chain Exposure (compact, only when risks)
# ═══════════════════════════════════════════════════════════════
if proc_avail:
    try:
        proc = load_procurement_recs()
        pos = load_open_pos()
    except Exception:
        proc = pd.DataFrame()
        pos = pd.DataFrame()

    if len(proc) > 0 and "PROCUREMENT_RISK" in proc.columns:
        critical_parts = proc[proc["PROCUREMENT_RISK"] == "CRITICAL_SHORTAGE"]
        expedite_parts = proc[proc["PROCUREMENT_RISK"] == "EXPEDITE"]
        at_risk = proc[proc["PROCUREMENT_RISK"].isin(["CRITICAL_SHORTAGE", "EXPEDITE", "ORDER_NOW"])]

        if len(at_risk) > 0:
            _section_header("🔗", "Supply chain exposure", "#EF4444")

            total_at_risk_cost = 0
            if "UNIT_COST" in at_risk.columns and "REQUIRED_QUANTITY" in at_risk.columns:
                total_at_risk_cost = (at_risk["UNIT_COST"].fillna(0) * at_risk["REQUIRED_QUANTITY"].fillna(1)).sum()

            sc1, sc2, sc3, sc4 = st.columns(4)
            with sc1:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid #EF444433; border-radius:8px; padding:12px; text-align:center;">
                    <div style="font-size:0.55rem; color:#EF4444; text-transform:uppercase; font-weight:600;">Critical shortage</div>
                    <div style="font-size:1.5rem; font-weight:800; color:#EF4444;">{len(critical_parts)}</div>
                </div>""")
            with sc2:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid #F59E0B33; border-radius:8px; padding:12px; text-align:center;">
                    <div style="font-size:0.55rem; color:#F59E0B; text-transform:uppercase; font-weight:600;">Expedite needed</div>
                    <div style="font-size:1.5rem; font-weight:800; color:#F59E0B;">{len(expedite_parts)}</div>
                </div>""")
            with sc3:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid #00D4FF33; border-radius:8px; padding:12px; text-align:center;">
                    <div style="font-size:0.55rem; color:#00D4FF; text-transform:uppercase; font-weight:600;">At-risk cost</div>
                    <div style="font-size:1.5rem; font-weight:800; color:#00D4FF;">${total_at_risk_cost:,.0f}</div>
                </div>""")
            with sc4:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid #8B5CF633; border-radius:8px; padding:12px; text-align:center;">
                    <div style="font-size:0.55rem; color:#8B5CF6; text-transform:uppercase; font-weight:600;">Open POs</div>
                    <div style="font-size:1.5rem; font-weight:800; color:#8B5CF6;">{len(pos)}</div>
                </div>""")

            # Lead time gap chart for at-risk items
            if "LEAD_TIME_GAP_DAYS" in at_risk.columns:
                gap_data = at_risk[["ASSET_NAME", "LEAD_TIME_GAP_DAYS", "PROCUREMENT_RISK"]].copy()
                gap_data = gap_data.sort_values("LEAD_TIME_GAP_DAYS", ascending=False).head(8)
                if len(gap_data) > 0:
                    gap_chart = alt.Chart(gap_data).mark_bar(cornerRadiusTopRight=4, cornerRadiusBottomRight=4).encode(
                        y=alt.Y("ASSET_NAME:N", title="", sort="-x", axis=alt.Axis(labelColor="#94A3B8")),
                        x=alt.X("LEAD_TIME_GAP_DAYS:Q", title="Lead time gap (days)",
                                 axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                        color=alt.Color("PROCUREMENT_RISK:N", title="Risk", scale=alt.Scale(
                            domain=["CRITICAL_SHORTAGE", "EXPEDITE", "ORDER_NOW", "REPLENISH_NOW"],
                            range=["#EF4444", "#F59E0B", "#3B82F6", "#00D4FF"]
                        )),
                        tooltip=["ASSET_NAME:N", "LEAD_TIME_GAP_DAYS:Q", "PROCUREMENT_RISK:N"],
                    ).properties(height=180)
                    st.altair_chart(gap_chart.configure_view(strokeWidth=0).configure_axis(
                        gridColor="rgba(255,255,255,0.04)"), use_container_width=True)


# ═══════════════════════════════════════════════════════════════
# SECTION 8: Operational Detail (tabs — "Dig Deeper")
# ═══════════════════════════════════════════════════════════════
_section_header("🔍", "Operational detail", "#64748B")

tab_oee, tab_loss, tab_cost, tab_matrix, tab_wo, tab_raw = st.tabs([
    "OEE by line", "Loss attribution", "Maint. cost", "Full risk matrix", "WO breakdown", "Raw data"
])

with tab_oee:
    if len(oee) > 0:
        oee_long = oee.melt(id_vars=["LINE_ID"], value_vars=["AVAIL", "PERF", "QUAL", "OEE"],
                            var_name="Metric", value_name="Pct")
        chart = alt.Chart(oee_long).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
            x=alt.X("LINE_ID:N", title="Line"),
            y=alt.Y("Pct:Q", title="%", scale=alt.Scale(domain=[0, 100])),
            color=alt.Color("Metric:N", scale=alt.Scale(
                domain=["AVAIL", "PERF", "QUAL", "OEE"],
                range=["#3B82F6", "#F59E0B", "#8B5CF6", "#10B981"]
            )),
            xOffset="Metric:N",
            tooltip=["LINE_ID:N", "Metric:N", alt.Tooltip("Pct:Q", format=".1f")],
        ).properties(height=280)
        st.altair_chart(chart.configure_view(strokeWidth=0).configure_axis(
            gridColor="rgba(255,255,255,0.04)", labelColor="#64748B", titleColor="#94A3B8"),
            use_container_width=True)

        # Period comparison if available
        if len(oee_comparison) > 0:
            st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin:10px 0 6px 0;">Period-over-period change</div>')
            for _, r in oee_comparison.iterrows():
                d = r.get("OEE_DELTA", 0)
                dc = "#10B981" if d > 0 else "#EF4444" if d < -2 else "#F59E0B"
                arrow = "▲" if d > 0 else "▼"
                st.html(f'<div style="font-size:0.75rem; color:#94A3B8; margin:2px 0;">{r["LINE_ID"]}: <span style="color:{dc}; font-weight:700;">{arrow} {abs(d):.1f}%</span> (Current: {r.get("CURRENT_OEE", 0):.1f}%)</div>')
    else:
        st.info("No OEE data available.")

with tab_loss:
    if len(loss) > 0:
        loss_long = loss.melt(id_vars=["ASSET_NAME"], value_vars=["AVAIL_LOSS", "PERF_LOSS", "QUAL_LOSS"],
                              var_name="Loss type", value_name="Pct")
        chart2 = alt.Chart(loss_long).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
            x=alt.X("ASSET_NAME:N", title="Asset"),
            y=alt.Y("Pct:Q", title="Loss %", scale=alt.Scale(domain=[0, 100])),
            color=alt.Color("Loss type:N", scale=alt.Scale(
                domain=["AVAIL_LOSS", "PERF_LOSS", "QUAL_LOSS"],
                range=["#EF4444", "#F59E0B", "#6B7280"]
            )),
            xOffset="Loss type:N",
            tooltip=["ASSET_NAME:N", "Loss type:N", alt.Tooltip("Pct:Q", format=".1f")],
        ).properties(height=280)
        st.altair_chart(chart2.configure_view(strokeWidth=0).configure_axis(
            gridColor="rgba(255,255,255,0.04)", labelColor="#64748B", titleColor="#94A3B8"),
            use_container_width=True)
    else:
        st.info("No loss data.")

with tab_cost:
    if len(cost_asset) > 0:
        chart3 = alt.Chart(cost_asset).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
            x=alt.X("ASSET_NAME:N", title="Asset", sort="-y"),
            y=alt.Y("TOTAL_COST:Q", title="Total cost ($)"),
            color=alt.when(alt.datum.STAGE_PRED == "Critical").then(alt.value("#EF4444"))
                .when(alt.datum.STAGE_PRED == "Warning").then(alt.value("#F59E0B"))
                .otherwise(alt.value("#10B981")),
            tooltip=["ASSET_NAME", "TOTAL_COST", "EMERGENCY_COST", "CORRECTIVE_COST", "PREVENTIVE_COST",
                      "STAGE_PRED", "RUL_HOURS"],
        ).properties(height=280)
        st.altair_chart(chart3.configure_view(strokeWidth=0).configure_axis(
            gridColor="rgba(255,255,255,0.04)", labelColor="#64748B", titleColor="#94A3B8"),
            use_container_width=True)
    else:
        st.info("No cost data.")

with tab_matrix:
    if len(preds) > 0:
        st.dataframe(
            preds[["ASSET_NAME", "STAGE_PRED", "FAILURE_MODE_PRED", "RUL_HOURS", "ACTION_WINDOW",
                   "ESTIMATED_FAILURE_COST", "PLANNED_REPAIR_COST", "COST_OF_INACTION", "RECOMMENDED_PART", "PARTS_STATUS"]],
            use_container_width=True, hide_index=True,
            column_config={
                "ASSET_NAME": "Asset", "STAGE_PRED": "Stage", "FAILURE_MODE_PRED": "Failure mode",
                "RUL_HOURS": st.column_config.NumberColumn("RUL (h)", format="%.1f"),
                "ACTION_WINDOW": "Action", "ESTIMATED_FAILURE_COST": st.column_config.NumberColumn("Failure $", format="$%d"),
                "PLANNED_REPAIR_COST": st.column_config.NumberColumn("Repair $", format="$%d"),
                "COST_OF_INACTION": st.column_config.NumberColumn("Inaction $", format="$%d"),
                "RECOMMENDED_PART": "Part", "PARTS_STATUS": "Parts",
            },
        )
    else:
        st.info("No prediction data.")

with tab_wo:
    if len(all_wo) > 0:
        with st.container(horizontal=True):
            open_count = len(all_wo[all_wo["STATUS"].isin(["open", "in_progress"])])
            emergency_count = len(all_wo[(all_wo["WO_TYPE"] == "emergency") & (all_wo["STATUS"].isin(["open", "in_progress"]))])
            wo_total = all_wo["TOTAL_COST"].sum()
            st.metric("Open WOs", f"{open_count}", border=True)
            st.metric("Emergency WOs", f"{emergency_count}", border=True)
            st.metric("Total WO spend", fmt_currency(wo_total), border=True)
    else:
        st.info("No work order data.")

with tab_raw:
    raw_tab = st.selectbox("Dataset", ["OEE by line", "OEE daily trend", "Loss attribution", "Predictions with cost", "Maintenance cost by asset", "Procurement recommendations"], key="raw_sel")
    if raw_tab == "OEE by line" and len(oee) > 0:
        st.dataframe(oee, use_container_width=True, hide_index=True)
    elif raw_tab == "OEE daily trend" and len(oee_trend) > 0:
        st.dataframe(oee_trend, use_container_width=True, hide_index=True)
    elif raw_tab == "Loss attribution" and len(loss) > 0:
        st.dataframe(loss, use_container_width=True, hide_index=True)
    elif raw_tab == "Predictions with cost" and len(preds) > 0:
        st.dataframe(preds, use_container_width=True, hide_index=True)
    elif raw_tab == "Maintenance cost by asset" and len(cost_asset) > 0:
        st.dataframe(cost_asset, use_container_width=True, hide_index=True)
    elif raw_tab == "Procurement recommendations" and proc_avail:
        p = load_procurement_recs()
        if len(p) > 0:
            st.dataframe(p, use_container_width=True, hide_index=True)
        else:
            st.info("No data.")
    else:
        st.info("No data available for this dataset.")
