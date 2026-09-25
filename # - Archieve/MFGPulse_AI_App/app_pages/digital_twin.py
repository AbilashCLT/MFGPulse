import streamlit as st
import json
import pandas as pd
import altair as alt
from app_pages._shared import (
    load_live_predictions, load_procurement_recs, procurement_available,
    load_latest_sensor_readings, load_all_work_orders, load_parts_atp,
    load_open_pos, load_notification_settings, load_active_reservations,
    fmt_hours, fmt_currency, C, DB, get_conn, generate_executive_summary,
    PERSONA_CONFIG,
)

alt.renderers.enable("mimetype")

conn = get_conn()
preds = load_live_predictions()

# ─── Helper: HTML card renderer ───
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


def _sensor_bar(label, value, unit, pct, color="#00D4FF"):
    bar_w = max(5, min(100, int(pct)))
    return f"""
    <div style="display:flex; align-items:center; margin: 4px 0; font-size: 0.78rem;">
        <span style="width:110px; color:#94A3B8;">{label}</span>
        <div style="flex:1; background:rgba(255,255,255,0.05); border-radius:3px; height:6px; margin:0 10px;">
            <div style="width:{bar_w}%; background:{color}; height:100%; border-radius:3px;
                        box-shadow: 0 0 6px {color}66;"></div>
        </div>
        <span style="width:70px; text-align:right; color:#E0E7FF; font-weight:600;">{value:.1f}</span>
        <span style="width:35px; color:#64748B; font-size:0.7rem;"> {unit}</span>
    </div>
    """


def _scenario_mini_chart_html(label, prob_3, prob_7, prob_14, color, prob_label, days_label, cost_label, risk_label, risk_color):
    h3 = max(2, int(prob_3 * 60))
    h7 = max(2, int(prob_7 * 60))
    h14 = max(2, int(prob_14 * 60))
    return f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-radius:8px; padding:14px;
                box-shadow: 0 0 12px {color}11;">
        <div style="color:{color}; font-size:0.7rem; text-transform:uppercase; letter-spacing:0.08em;
                    font-weight:600; margin-bottom:10px;">{label}</div>
        <div style="display:flex; align-items:flex-end; gap:8px; height:65px; margin-bottom:10px;">
            <div style="display:flex; flex-direction:column; align-items:center; flex:1;">
                <div style="width:100%; background:{color}; height:{h3}px; border-radius:3px 3px 0 0;
                            box-shadow: 0 0 8px {color}55;"></div>
                <span style="font-size:0.6rem; color:#64748B; margin-top:3px;">3d</span>
            </div>
            <div style="display:flex; flex-direction:column; align-items:center; flex:1;">
                <div style="width:100%; background:{color}; height:{h7}px; border-radius:3px 3px 0 0;
                            box-shadow: 0 0 8px {color}55;"></div>
                <span style="font-size:0.6rem; color:#64748B; margin-top:3px;">7d</span>
            </div>
            <div style="display:flex; flex-direction:column; align-items:center; flex:1;">
                <div style="width:100%; background:{color}; height:{h14}px; border-radius:3px 3px 0 0;
                            box-shadow: 0 0 8px {color}55;"></div>
                <span style="font-size:0.6rem; color:#64748B; margin-top:3px;">14d</span>
            </div>
        </div>
        <div style="display:flex; justify-content:space-between; align-items:baseline; margin-bottom:4px;">
            <span style="font-size:1.6rem; font-weight:800; color:{color};">{prob_label}</span>
            <span style="font-size:0.75rem; color:#94A3B8;">Prob @ 14 days</span>
        </div>
        <div style="font-size:0.75rem; color:#94A3B8; margin-bottom:2px;">
            RUL: <span style="color:#E0E7FF; font-weight:600;">{days_label}</span>
        </div>
        <div style="font-size:0.75rem; color:#94A3B8; margin-bottom:6px;">
            Expected cost: <span style="color:#E0E7FF; font-weight:600;">{cost_label}</span>
        </div>
        <div style="display:inline-block; padding:2px 10px; border-radius:10px; font-size:0.65rem;
                    font-weight:700; text-transform:uppercase; letter-spacing:0.05em;
                    background:{risk_color}22; color:{risk_color}; border:1px solid {risk_color}44;">
            {risk_label}
        </div>
    </div>
    """


# ─── Page header ───
st.html("""
<div style="display:flex; align-items:center; gap:12px; margin-bottom:4px;">
    <div style="font-size:1.4rem; font-weight:700; color:#E0E7FF;">
        ⚙ Digital twin
    </div>
    <div style="font-size:0.7rem; color:#00D4FF; text-transform:uppercase; letter-spacing:0.1em;
                padding:3px 12px; border:1px solid #00D4FF33; border-radius:12px;">
        Monte Carlo Simulation
    </div>
</div>
""")
st.caption("3-scenario comparison with procurement timing and intervention planning")

with st.expander("About this page", expanded=False, icon=":material/info:"):
    st.markdown("""
**Purpose**: Monte Carlo failure simulation — compare intervention scenarios to quantify risk, cost, and remaining useful life under different operating conditions.

**How it works**: The `SIMULATE_FAILURE_TWIN` SQL UDF runs 100 stochastic paths per scenario (300 total). Each path projects fatigue accumulation with random degradation rates and shock events. Failure = fatigue score exceeding 0.9.

**Simulation velocity**: Derived from the ML model's RUL prediction — `velocity = (1 - current_fatigue) / RUL_days`. This grounds Monte Carlo projections in the same physics the predictive models use.

**3 scenarios**:
- **Do nothing** — Current trajectory with no intervention (load=0%, delay=14 days, RPM=0%)
- **Reduce load** — Configurable load reduction and maintenance delay to extend asset life
- **Plan maintenance** — Configurable load, delay, and RPM adjustment for optimal scheduling

**Sections**:
- **Live sensor readings** — Current vibration, temperature, pressure, RPM, current, and acoustic levels
- **Scenario configurators** — Sliders for load reduction, maintenance delay, and RPM adjustment
- **Scenario result cards** — Failure probability at 3/7/14 days, median RUL, expected cost, and risk level
- **RUL forecast** — P10/P50/P90 distribution for each scenario with fails-before-maintenance percentage
- **Scenario cost comparison** — Side-by-side cost bars with savings calculation and recommended tag
- **Intervention options** — Actionable summary of each scenario's operational impact
- **Failure probability timeline** — Altair line chart comparing all 3 scenarios across 3/7/14-day horizons
- **Procurement timing** — Parts availability, lead time, and intervention window feasibility
- **AI simulation summary** — LLM-generated narrative of the simulation results

**Data sources**: `ML_MODELS.LIVE_PREDICTIONS`, `ML_MODELS.SIMULATE_FAILURE_TWIN` (UDF), `RAW_OT.SENSOR_READINGS`, `ANALYTICS.PARTS_AVAILABLE_TO_PROMISE`
""")

# ─── Asset selector ───
asset_names = preds["ASSET_NAME"].tolist() if len(preds) > 0 else []
default_idx = 0
if len(preds) > 0:
    warning_idx = preds.index[preds["STAGE_PRED"] == "Warning"].tolist()
    if warning_idx:
        default_idx = asset_names.index(preds.loc[warning_idx[0], "ASSET_NAME"])
    elif len(asset_names) > 3:
        default_idx = len(asset_names) // 2
selected = st.selectbox("Select asset", asset_names, index=default_idx if asset_names else None,
                         label_visibility="collapsed")

if not selected or len(preds) == 0:
    st.info("No assets available for simulation.", icon=":material/info:")
    st.stop()

asset = preds[preds["ASSET_NAME"] == selected].iloc[0]
deg = asset["DEGRADATION_SCORE"]
fatigue = asset["FATIGUE_SCORE"]
health = asset["COMPOSITE_HEALTH_SCORE"]

# ─── Asset KPI Bar: Warning + RUL + Degradation + Fatigue (single row below dropdown) ───
stage = asset["STAGE_PRED"]
stage_pct = int(deg * 100)
if stage == "Critical":
    stage_color = "#EF4444"
elif stage == "Warning":
    stage_color = "#F59E0B"
else:
    stage_color = "#10B981"

st.html(f"""
<div style="background:rgba(17,24,39,0.9); border:1px solid {stage_color}33; border-radius:10px;
            padding:14px 20px; margin-bottom:16px; box-shadow: 0 0 15px {stage_color}10;
            display:flex; align-items:center; gap:24px; flex-wrap:wrap;">
    <!-- Warning badge + percentage -->
    <div style="display:flex; align-items:center; gap:12px; min-width:180px;">
        <div style="font-size:2rem; font-weight:800; color:{stage_color};
                    text-shadow: 0 0 12px {stage_color}55;">{stage_pct}%</div>
        <div>
            <div style="font-size:0.65rem; text-transform:uppercase; letter-spacing:0.1em;
                        color:{stage_color}; font-weight:700;">⚠ {stage.upper()}</div>
            <div style="font-size:0.7rem; color:#94A3B8;">
                {'Degradation detected' if deg > 0.3 else 'Asset nominal'}</div>
        </div>
    </div>
    <!-- Progress bar -->
    <div style="flex:1; min-width:120px; max-width:200px;">
        <div style="background:rgba(255,255,255,0.05); border-radius:4px; height:8px; overflow:hidden;">
            <div style="width:{stage_pct}%; background:linear-gradient(90deg, {stage_color}88, {stage_color});
                        height:100%; border-radius:4px; box-shadow: 0 0 10px {stage_color}66;"></div>
        </div>
    </div>
    <!-- Divider -->
    <div style="width:1px; height:36px; background:rgba(255,255,255,0.08);"></div>
    <!-- RUL -->
    <div style="text-align:center;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.08em; color:#64748B; font-weight:600;">RUL</div>
        <div style="font-size:1.2rem; font-weight:700; color:#00D4FF;">{fmt_hours(asset["RUL_HOURS"])}</div>
    </div>
    <!-- Divider -->
    <div style="width:1px; height:36px; background:rgba(255,255,255,0.08);"></div>
    <!-- Degradation -->
    <div style="text-align:center;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.08em; color:#64748B; font-weight:600;">Degradation</div>
        <div style="font-size:1.2rem; font-weight:700; color:{stage_color};">{deg:.2f}</div>
    </div>
    <!-- Divider -->
    <div style="width:1px; height:36px; background:rgba(255,255,255,0.08);"></div>
    <!-- Fatigue -->
    <div style="text-align:center;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.08em; color:#64748B; font-weight:600;">Fatigue</div>
        <div style="font-size:1.2rem; font-weight:700; color:#8B5CF6;">{fatigue:.3f}</div>
    </div>
    <!-- Divider -->
    <div style="width:1px; height:36px; background:rgba(255,255,255,0.08);"></div>
    <!-- Asset name -->
    <div style="text-align:center;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.08em; color:#64748B; font-weight:600;">Asset</div>
        <div style="font-size:1.2rem; font-weight:700; color:#E0E7FF;">{selected}</div>
    </div>
</div>
""")

# ─── SECTION 1: Digital Twin Simulation Timeline (new section) ───
st.html("""
<div style="display:flex; align-items:center; gap:12px; margin: 8px 0 14px 0;">
    <div style="color:#00D4FF; font-size:0.75rem; text-transform:uppercase; letter-spacing:0.1em;
                font-weight:700;">⚡ Digital twin simulation timeline</div>
    <div style="flex:1; height:1px; background:rgba(0,212,255,0.12);"></div>
</div>
""")

# ─── Sensor Readings (full width) ───
try:
    sensors = load_latest_sensor_readings()
    asset_sensors = sensors[sensors["ASSET_ID"] == asset["ASSET_ID"]]
    if len(asset_sensors) > 0:
        s = asset_sensors.iloc[0]
        vib_mag = s.get("VIB_MAG", 0) or 0
        temp = s.get("TEMPERATURE", 0) or 0
        pressure = s.get("PRESSURE", 0) or 0
        rpm = s.get("RPM", 0) or 0
        current = s.get("CURRENT_AMPS", 0) or 0
        acoustic = s.get("ACOUSTIC_DB", 0) or 0

        vib_color = "#EF4444" if vib_mag > 7 else "#F59E0B" if vib_mag > 4 else "#10B981"
        temp_color = "#EF4444" if temp > 85 else "#F59E0B" if temp > 70 else "#10B981"
        pres_color = "#EF4444" if pressure > 5 else "#F59E0B" if pressure > 3.5 else "#10B981"
        rpm_color = "#F59E0B" if rpm > 1600 or rpm < 1300 else "#10B981"
        curr_color = "#EF4444" if current > 25 else "#F59E0B" if current > 20 else "#10B981"
        acou_color = "#F59E0B" if acoustic > 80 else "#10B981"

        bars_html = (
            _sensor_bar("VIBRATION", vib_mag, "mm/s", min(100, vib_mag * 10), vib_color) +
            _sensor_bar("TEMPERATURE", temp, "°C", min(100, temp), temp_color) +
            _sensor_bar("PRESSURE", pressure, "bar", min(100, pressure * 15), pres_color) +
            _sensor_bar("RPM", rpm, "rpm", min(100, rpm / 20), rpm_color) +
            _sensor_bar("CURRENT", current, "A", min(100, current * 4), curr_color) +
            _sensor_bar("ACOUSTIC", acoustic, "dB", min(100, acoustic), acou_color)
        )
        _glow_card("Live sensor readings", bars_html, border_color="#00D4FF", icon="📡")
    else:
        st.caption("No recent sensor data")
except Exception:
    st.caption("Sensor data unavailable")

# ─── Scenario Configurators (full-width 3-column row below sensors) ───
if deg > 0.8:
    st.warning("Advanced degradation (>0.8) — all scenarios may show near-certain failure.", icon=":material/info:")

col_s1, col_s2, col_s3 = st.columns(3)
with col_s1:
    with st.container(border=True):
        st.html('<div style="color:#EF4444; font-size:0.7rem; font-weight:700; text-transform:uppercase; letter-spacing:0.08em;">1 · Do nothing</div>')
        st.caption("No intervention — current trajectory")
with col_s2:
    with st.container(border=True):
        st.html('<div style="color:#F59E0B; font-size:0.7rem; font-weight:700; text-transform:uppercase; letter-spacing:0.08em;">2 · Reduce load</div>')
        load_b = st.slider("Load reduction %", 0, 50, 20, key="load_b")
        delay_b = st.slider("Maint. delay (days)", 0, 14, 7, key="delay_b")
with col_s3:
    with st.container(border=True):
        st.html('<div style="color:#10B981; font-size:0.7rem; font-weight:700; text-transform:uppercase; letter-spacing:0.08em;">3 · Plan maintenance</div>')
        load_c = st.slider("Load reduction %", 0, 50, 0, key="load_c")
        delay_c = st.slider("Maint. delay (days)", 0, 14, 0, key="delay_c")
        rpm_c = st.slider("RPM adjustment %", -20, 20, 0, key="rpm_c")

# ─── Run simulations ───
@st.cache_data(ttl=60)
def run_sim(vib, vel, fat, load, delay, rpm):
    session = conn.session()
    r = session.sql(
        f"SELECT {DB}.ML_MODELS.SIMULATE_FAILURE_TWIN(?, ?, ?, ?, ?, ?) AS R",
        params=[float(vib), float(vel), float(fat), float(load), float(delay), float(rpm)],
    ).collect()
    return json.loads(str(r[0]["R"])) if r else {}

vib_val = max(0.5, deg * 8)
# Derive velocity from ML model's RUL estimate so simulations are grounded in predictions
rul_days = max(1, asset["RUL_HOURS"] / 24)
vel_val = max(0.01, (1.0 - fatigue) / rul_days)

with st.spinner("Running 300 Monte Carlo simulations..."):
    sim_a = run_sim(vib_val, vel_val, fatigue, 0, 14, 0)
    sim_b = run_sim(vib_val, vel_val, fatigue, load_b, delay_b, 0)
    sim_c = run_sim(vib_val, vel_val, fatigue, load_c, delay_c, rpm_c)

# ─── Scenario result cards ───
scenarios = {"Do nothing": sim_a, "Reduce load": sim_b, "Plan maintenance": sim_c}
colors = {"Do nothing": "#EF4444", "Reduce load": "#F59E0B", "Plan maintenance": "#10B981"}
risk_labels = {"Do nothing": "HIGH", "Reduce load": "MEDIUM", "Plan maintenance": "LOW"}
risk_colors = {"HIGH": "#EF4444", "MEDIUM": "#F59E0B", "LOW": "#10B981"}

sc1, sc2, sc3 = st.columns(3)
for col, (label, sim) in zip([sc1, sc2, sc3], scenarios.items()):
    with col:
        prob14 = sim.get("failure_prob_day_14", 0)
        rul_d = sim.get("rul_days_p50", 0)
        cost = sim.get("expected_cost", 0)
        risk = risk_labels[label]
        st.html(_scenario_mini_chart_html(
            f"Scenario · {label}",
            sim.get("failure_prob_day_3", 0),
            sim.get("failure_prob_day_7", 0),
            prob14,
            colors[label],
            f"{prob14:.0%}",
            f"{rul_d:.1f}d ({rul_d * 24:.0f}h)",
            f"${cost:,.0f}",
            risk,
            risk_colors[risk],
        ))

# ─── Predict RUL button + inline forecast ───
if st.button("Predict RUL", type="primary", icon=":material/query_stats:", use_container_width=True, key="predict_rul"):
    st.session_state._show_rul_forecast = True

if st.session_state.get("_show_rul_forecast", False):
    fc1, fc2, fc3 = st.columns(3)
    for col, (label, sim), color in zip(
        [fc1, fc2, fc3],
        scenarios.items(),
        ["#EF4444", "#F59E0B", "#10B981"],
    ):
        p3 = sim.get("failure_prob_day_3", 0)
        p7 = sim.get("failure_prob_day_7", 0)
        p14 = sim.get("failure_prob_day_14", 0)
        rul_p10 = sim.get("rul_days_p10", 0)
        rul_p50 = sim.get("rul_days_p50", 0)
        rul_p90 = sim.get("rul_days_p90", 0)
        fbm = sim.get("fails_before_maintenance_pct", 0)
        with col:
            st.html(f"""
            <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-radius:8px;
                        padding:14px; box-shadow: 0 0 10px {color}11;">
                <div style="color:{color}; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em;
                            font-weight:700; margin-bottom:10px;">📈 {label} — RUL forecast</div>
                <div style="display:flex; gap:12px; margin-bottom:8px;">
                    <div style="flex:1; text-align:center; padding:6px; background:rgba(255,255,255,0.03); border-radius:6px;">
                        <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">P10 (worst)</div>
                        <div style="font-size:1rem; font-weight:700; color:#EF4444;">{rul_p10:.1f}d</div>
                    </div>
                    <div style="flex:1; text-align:center; padding:6px; background:rgba(255,255,255,0.03); border-radius:6px;">
                        <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">P50 (median)</div>
                        <div style="font-size:1rem; font-weight:700; color:{color};">{rul_p50:.1f}d</div>
                    </div>
                    <div style="flex:1; text-align:center; padding:6px; background:rgba(255,255,255,0.03); border-radius:6px;">
                        <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">P90 (best)</div>
                        <div style="font-size:1rem; font-weight:700; color:#10B981;">{rul_p90:.1f}d</div>
                    </div>
                </div>
                <div style="font-size:0.72rem; color:#94A3B8; margin-bottom:3px;">
                    Failure probability: <span style="color:#E0E7FF;">3d={p3:.0%}</span> ·
                    <span style="color:#E0E7FF;">7d={p7:.0%}</span> ·
                    <span style="color:{color}; font-weight:700;">14d={p14:.0%}</span>
                </div>
                <div style="font-size:0.72rem; color:#94A3B8;">
                    Fails before maintenance: <span style="color:{color}; font-weight:700;">{fbm:.0f}%</span>
                </div>
            </div>
            """)

# ─── Side-by-side scenario cost comparison ───
st.html("""
<div style="display:flex; align-items:center; gap:12px; margin: 16px 0 10px 0;">
    <div style="color:#00D4FF; font-size:0.7rem; text-transform:uppercase; letter-spacing:0.1em;
                font-weight:700;">💰 Scenario cost comparison</div>
    <div style="flex:1; height:1px; background:rgba(0,212,255,0.12);"></div>
</div>
""")

# Compute comparison values
best_cost = min(s.get("expected_cost", 0) for s in scenarios.values())
worst_cost = max(s.get("expected_cost", 0) for s in scenarios.values())
max_cost_for_bar = max(worst_cost, 1)

cc1, cc2, cc3 = st.columns(3)
for col, (label, sim), color in zip(
    [cc1, cc2, cc3],
    scenarios.items(),
    ["#EF4444", "#F59E0B", "#10B981"],
):
    cost = sim.get("expected_cost", 0)
    rul_d = sim.get("rul_days_p50", 0)
    prob14 = sim.get("failure_prob_day_14", 0)
    saving = worst_cost - cost
    bar_pct = max(5, int(cost / max_cost_for_bar * 100))
    is_best = cost == best_cost
    with col:
        border_style = f"border:2px solid {color};" if is_best else f"border:1px solid {color}33;"
        best_tag = f'<div style="display:inline-block; padding:2px 8px; border-radius:8px; font-size:0.58rem; font-weight:700; background:#10B98122; color:#10B981; border:1px solid #10B98144; margin-bottom:8px;">✦ RECOMMENDED</div>' if is_best else ""
        st.html(f"""
        <div style="background:rgba(17,24,39,0.9); {border_style} border-radius:8px; padding:16px;
                    box-shadow: 0 0 12px {color}11;">
            {best_tag}
            <div style="color:{color}; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em;
                        font-weight:700; margin-bottom:10px;">{label}</div>
            <!-- Expected Cost -->
            <div style="margin-bottom:10px;">
                <div style="display:flex; justify-content:space-between; align-items:baseline; margin-bottom:4px;">
                    <span style="font-size:0.6rem; color:#64748B; text-transform:uppercase;">Expected cost</span>
                    <span style="font-size:1.3rem; font-weight:800; color:{color};">${cost:,.0f}</span>
                </div>
                <div style="background:rgba(255,255,255,0.04); border-radius:3px; height:6px; overflow:hidden;">
                    <div style="width:{bar_pct}%; background:{color}; height:100%; border-radius:3px;
                                box-shadow: 0 0 6px {color}55;"></div>
                </div>
            </div>
            <!-- Metrics row -->
            <div style="display:flex; gap:8px;">
                <div style="flex:1; padding:8px; background:rgba(255,255,255,0.03); border-radius:6px; text-align:center;">
                    <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">Saving</div>
                    <div style="font-size:0.95rem; font-weight:700; color:#10B981;">${saving:,.0f}</div>
                </div>
                <div style="flex:1; padding:8px; background:rgba(255,255,255,0.03); border-radius:6px; text-align:center;">
                    <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">Fail 14d</div>
                    <div style="font-size:0.95rem; font-weight:700; color:{'#EF4444' if prob14 > 0.5 else '#F59E0B' if prob14 > 0.2 else '#10B981'};">{prob14:.0%}</div>
                </div>
                <div style="flex:1; padding:8px; background:rgba(255,255,255,0.03); border-radius:6px; text-align:center;">
                    <div style="font-size:0.55rem; color:#64748B; text-transform:uppercase;">RUL</div>
                    <div style="font-size:0.95rem; font-weight:700; color:#00D4FF;">{rul_d:.1f}d</div>
                </div>
            </div>
        </div>
        """)

# ─── SECTION 2: Intervention Options ───
st.html("""
<div style="color:#00D4FF; font-size:0.7rem; text-transform:uppercase; letter-spacing:0.1em;
            font-weight:600; margin: 20px 0 10px 0;">
    🎯 Intervention options
</div>
""")

iv1, iv2, iv3 = st.columns(3)
interventions = [
    ("DO NOTHING", ":material/block:", "Continue operations without changes",
     f"Fail prob: {sim_a.get('failure_prob_day_14',0):.0%}", "#EF4444"),
    ("REDUCE LOAD", ":material/speed:", f"Reduce operating load by {load_b}%",
     f"Extends RUL by ~{max(0, sim_b.get('rul_days_p50',0) - sim_a.get('rul_days_p50',0)):.1f} days", "#F59E0B"),
    ("PLAN MAINTENANCE", ":material/build:", "Schedule maintenance in 3–14 days",
     f"Lowest risk — cost ${sim_c.get('expected_cost',0):,.0f}", "#10B981"),
]
for col, (title, icon, desc, detail, color) in zip([iv1, iv2, iv3], interventions):
    with col:
        with st.container(border=True):
            st.html(f"""
            <div style="text-align:center;">
                <div style="font-size:0.65rem; color:{color}; font-weight:700; text-transform:uppercase;
                            letter-spacing:0.08em; margin-bottom:6px;">{title}</div>
                <div style="color:#94A3B8; font-size:0.78rem; margin-bottom:4px;">{desc}</div>
                <div style="color:{color}; font-size:0.72rem; font-weight:600;">{detail}</div>
            </div>
            """)

# ─── SECTION 3: Failure Probability Timeline (full width) ───
best_scenario = min(scenarios.items(), key=lambda x: x[1].get("expected_cost", 9999999))
worst_scenario = max(scenarios.items(), key=lambda x: x[1].get("failure_prob_day_14", 0))
best_label, best_sim = best_scenario
worst_label, worst_sim = worst_scenario
cost_saving = worst_sim.get("expected_cost", 0) - best_sim.get("expected_cost", 0)

st.html("""
<div style="color:#00D4FF; font-size:0.7rem; text-transform:uppercase; letter-spacing:0.1em;
            font-weight:600; margin-bottom:8px;">
    📈 Failure probability timeline
</div>
""")
prob_data = []
scenario_labels = {"Do nothing": "A: Do nothing", "Reduce load": "B: Reduce load", "Plan maintenance": "C: Plan maintenance"}
for label, s in scenarios.items():
    sl = scenario_labels[label]
    prob_data.append({"Scenario": sl, "Day": 3, "Probability": s.get("failure_prob_day_3", 0)})
    prob_data.append({"Scenario": sl, "Day": 7, "Probability": s.get("failure_prob_day_7", 0)})
    prob_data.append({"Scenario": sl, "Day": 14, "Probability": s.get("failure_prob_day_14", 0)})
df_prob = pd.DataFrame(prob_data)
chart = alt.Chart(df_prob).mark_line(point=True, strokeWidth=3).encode(
    x=alt.X("Day:Q", title="Days from now", scale=alt.Scale(domain=[0, 16])),
    y=alt.Y("Probability:Q", title="Failure probability", scale=alt.Scale(domain=[0, 1]),
             axis=alt.Axis(format="%")),
    color=alt.Color("Scenario:N", scale=alt.Scale(
        domain=["A: Do nothing", "B: Reduce load", "C: Plan maintenance"],
        range=["#EF4444", "#F59E0B", "#10B981"]
    )),
    tooltip=["Scenario", "Day", alt.Tooltip("Probability:Q", format=".0%")],
).properties(height=280).configure_view(
    strokeWidth=0
).configure_axis(
    gridColor="rgba(255,255,255,0.05)",
    labelColor="#64748B",
    titleColor="#94A3B8",
)
st.altair_chart(chart, use_container_width=True)

# ─── SECTION 4: Maintenance Impact & Business Outcome ───
st.html("""
<div style="color:#00D4FF; font-size:0.7rem; text-transform:uppercase; letter-spacing:0.1em;
            font-weight:600; margin: 16px 0 10px 0;">
    📊 Maintenance impact &amp; business outcome
</div>
""")
m1, m2, m3, m4, m5 = st.columns(5)
with m1:
    _glow_card("Avoided downtime", f'<div style="color:#00D4FF; font-size:1.3rem; font-weight:700;">{cost_saving / max(1, worst_sim.get("expected_cost", 1)) * 100:.0f}%</div><div style="color:#64748B; font-size:0.7rem;">Reduce unplanned stops</div>', "#00D4FF", "⏱")
with m2:
    _glow_card("Cost avoidance", f'<div style="color:#10B981; font-size:1.3rem; font-weight:700;">${cost_saving:,.0f}</div><div style="color:#64748B; font-size:0.7rem;">vs worst-case scenario</div>', "#10B981", "💰")
with m3:
    _glow_card("OEE uplift", f'<div style="color:#F59E0B; font-size:1.3rem; font-weight:700;">+{min(15, cost_saving / max(1, worst_sim.get("expected_cost",1)) * 15):.1f}%</div><div style="color:#64748B; font-size:0.7rem;">Availability & performance</div>', "#F59E0B", "📈")
with m4:
    _glow_card("Asset life extension", f'<div style="color:#8B5CF6; font-size:1.3rem; font-weight:700;">+{best_sim.get("rul_days_p50", 0):.0f}d</div><div style="color:#64748B; font-size:0.7rem;">Reduce time between issues</div>', "#8B5CF6", "🔧")
with m5:
    parts_ok = "YES" if procurement_available() else "N/A"
    _glow_card("Parts readiness", f'<div style="color:#00D4FF; font-size:1.3rem; font-weight:700;">{parts_ok}</div><div style="color:#64748B; font-size:0.7rem;">Parts availability in time</div>', "#00D4FF", "📦")

# ─── SECTION 5: Workflow — Create WO → Check Parts → Planned PO → Part Reserved ───
st.html("""
<div style="color:#00D4FF; font-size:0.7rem; text-transform:uppercase; letter-spacing:0.1em;
            font-weight:600; margin: 16px 0 10px 0;">
    🔄 Automated workflow pipeline
</div>
""")

# Fetch related data
all_wo = load_all_work_orders()
asset_wo = all_wo[all_wo["ASSET_ID"] == asset["ASSET_ID"]] if len(all_wo) > 0 and "ASSET_ID" in all_wo.columns else pd.DataFrame()
latest_wo = asset_wo.iloc[0] if len(asset_wo) > 0 else None

proc_avail = procurement_available()
parts_df = load_parts_atp() if proc_avail else pd.DataFrame()
proc_recs = load_procurement_recs() if proc_avail else pd.DataFrame()
asset_proc = proc_recs[proc_recs["ASSET_ID"] == asset["ASSET_ID"]] if len(proc_recs) > 0 and "ASSET_ID" in proc_recs.columns else pd.DataFrame()

open_pos = load_open_pos() if proc_avail else pd.DataFrame()
asset_po = open_pos[open_pos["ASSET_ID"] == asset["ASSET_ID"]] if len(open_pos) > 0 and "ASSET_ID" in open_pos.columns else pd.DataFrame()

reservations = load_active_reservations()
asset_res = reservations[reservations["ASSET_ID"] == asset["ASSET_ID"]] if len(reservations) > 0 and "ASSET_ID" in reservations.columns else pd.DataFrame()

wf1, wf2, wf3, wf4 = st.columns(4)

with wf1:
    wo_id = latest_wo["WO_ID"] if latest_wo is not None else "—"
    wo_pri = latest_wo["PRIORITY"] if latest_wo is not None else "—"
    wo_status = latest_wo["STATUS"] if latest_wo is not None else "—"
    wo_color = "#10B981" if wo_status == "completed" else "#F59E0B" if wo_status == "in_progress" else "#3B82F6"
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid #F59E0B33; border-radius:8px; padding:14px;
                text-align:center; box-shadow: 0 0 12px #F59E0B11;">
        <div style="font-size:1.5rem; margin-bottom:6px;">📋</div>
        <div style="color:#F59E0B; font-size:0.65rem; font-weight:700; text-transform:uppercase;
                    letter-spacing:0.08em; margin-bottom:8px;">Create work order</div>
        <div style="color:#E0E7FF; font-size:0.78rem; font-weight:600;">{wo_id}</div>
        <div style="color:#94A3B8; font-size:0.7rem;">Priority: {wo_pri}</div>
        <div style="display:inline-block; padding:2px 8px; border-radius:8px; font-size:0.6rem;
                    margin-top:4px; background:{wo_color}22; color:{wo_color}; border:1px solid {wo_color}44;">
            {wo_status}
        </div>
    </div>
    """)

with wf2:
    if len(asset_proc) > 0:
        p = asset_proc.iloc[0]
        atp_status = p.get("PROCUREMENT_RISK", "UNKNOWN")
        lead = p.get("LEAD_TIME_DAYS", "—")
        atp_color = "#EF4444" if "SHORTAGE" in str(atp_status) else "#F59E0B" if "EXPEDITE" in str(atp_status) else "#10B981"
    else:
        atp_status, lead, atp_color = "N/A", "—", "#64748B"
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid #00D4FF33; border-radius:8px; padding:14px;
                text-align:center; box-shadow: 0 0 12px #00D4FF11;">
        <div style="font-size:1.5rem; margin-bottom:6px;">⚙️</div>
        <div style="color:#00D4FF; font-size:0.65rem; font-weight:700; text-transform:uppercase;
                    letter-spacing:0.08em; margin-bottom:8px;">Check parts availability</div>
        <div style="color:#E0E7FF; font-size:0.78rem; font-weight:600;">ATP status</div>
        <div style="display:inline-block; padding:2px 8px; border-radius:8px; font-size:0.65rem;
                    margin-top:4px; background:{atp_color}22; color:{atp_color}; border:1px solid {atp_color}44;
                    font-weight:700;">
            {atp_status}
        </div>
        <div style="color:#94A3B8; font-size:0.7rem; margin-top:6px;">Lead time: {lead} days</div>
    </div>
    """)

with wf3:
    if len(asset_po) > 0:
        po = asset_po.iloc[0]
        po_id = po.get("PO_ID", "—")
        po_status = po.get("STATUS", "—")
        eta = str(po.get("EXPECTED_ARRIVAL_DATE", "—"))[:10]
        po_color = "#10B981" if po_status == "received" else "#3B82F6" if po_status in ("ordered", "approved") else "#F59E0B"
    else:
        po_id, po_status, eta, po_color = "—", "None", "—", "#64748B"
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid #8B5CF633; border-radius:8px; padding:14px;
                text-align:center; box-shadow: 0 0 12px #8B5CF611;">
        <div style="font-size:1.5rem; margin-bottom:6px;">📦</div>
        <div style="color:#8B5CF6; font-size:0.65rem; font-weight:700; text-transform:uppercase;
                    letter-spacing:0.08em; margin-bottom:8px;">Planned purchase order</div>
        <div style="color:#E0E7FF; font-size:0.78rem; font-weight:600;">{po_id}</div>
        <div style="color:#94A3B8; font-size:0.7rem;">ETA: {eta}</div>
        <div style="display:inline-block; padding:2px 8px; border-radius:8px; font-size:0.6rem;
                    margin-top:4px; background:{po_color}22; color:{po_color}; border:1px solid {po_color}44;">
            {po_status}
        </div>
    </div>
    """)

with wf4:
    if len(asset_res) > 0:
        res = asset_res.iloc[0]
        res_qty = res.get("QUANTITY_RESERVED", 0)
        res_status = res.get("STATUS", "—")
        res_color = "#10B981"
    else:
        res_qty, res_status, res_color = 0, "None", "#64748B"
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid #10B98133; border-radius:8px; padding:14px;
                text-align:center; box-shadow: 0 0 12px #10B98111;">
        <div style="font-size:1.5rem; margin-bottom:6px;">✅</div>
        <div style="color:#10B981; font-size:0.65rem; font-weight:700; text-transform:uppercase;
                    letter-spacing:0.08em; margin-bottom:8px;">Part reserved</div>
        <div style="color:#E0E7FF; font-size:0.78rem; font-weight:600;">Qty: {res_qty}</div>
        <div style="display:inline-block; padding:2px 8px; border-radius:8px; font-size:0.6rem;
                    margin-top:4px; background:{res_color}22; color:{res_color}; border:1px solid {res_color}44;">
            {res_status}
        </div>
    </div>
    """)

# ─── Workflow connector arrows ───
st.html("""
<div style="display:flex; justify-content:center; align-items:center; margin: -6px 0 10px 0; gap: 60px;">
    <div style="color:#F59E0B; font-size:1.2rem;">→</div>
    <div style="color:#00D4FF; font-size:1.2rem;">→</div>
    <div style="color:#8B5CF6; font-size:1.2rem;">→</div>
</div>
""")

# ─── SECTION 6: RUL Distribution + Part Arrival Timing ───
col_rul, col_part = st.columns(2)

with col_rul:
    with st.container(border=True):
        st.html('<div style="color:#00D4FF; font-size:0.7rem; text-transform:uppercase; letter-spacing:0.1em; font-weight:600; margin-bottom:6px;">📊 RUL distribution comparison</div>')
        rul_data = []
        for label, s in scenarios.items():
            rul_data.append({"Scenario": label, "Percentile": "P10 (worst)", "Days": s.get("rul_days_p10", 0)})
            rul_data.append({"Scenario": label, "Percentile": "P50 (median)", "Days": s.get("rul_days_p50", 0)})
            rul_data.append({"Scenario": label, "Percentile": "P90 (best)", "Days": s.get("rul_days_p90", 0)})
        df_rul = pd.DataFrame(rul_data)
        chart2 = alt.Chart(df_rul).mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4).encode(
            x=alt.X("Scenario:N"),
            y=alt.Y("Days:Q", title="Remaining useful life (days)"),
            color=alt.Color("Percentile:N", scale=alt.Scale(
                domain=["P10 (worst)", "P50 (median)", "P90 (best)"],
                range=["#EF4444", "#F59E0B", "#10B981"]
            )),
            xOffset="Percentile:N",
            tooltip=["Scenario", "Percentile", alt.Tooltip("Days:Q", format=".1f")],
        ).properties(height=220).configure_view(strokeWidth=0).configure_axis(
            gridColor="rgba(255,255,255,0.05)", labelColor="#64748B", titleColor="#94A3B8",
        )
        st.altair_chart(chart2, use_container_width=True)

with col_part:
    with st.container(border=True):
        st.html('<div style="color:#00D4FF; font-size:0.7rem; text-transform:uppercase; letter-spacing:0.1em; font-weight:600; margin-bottom:6px;">⏱ Part arrival vs failure timing</div>')
        if proc_avail and len(asset_proc) > 0:
            p = asset_proc.iloc[0]
            lead_days = p.get("LEAD_TIME_DAYS", 0)
            lead_hours = lead_days * 24
            median_rul_days = sim_a.get("rul_days_p50", 0)
            median_rul_hours = median_rul_days * 24
            margin = median_rul_hours - lead_hours

            margin_color = "#10B981" if margin > 48 else "#F59E0B" if margin > 0 else "#EF4444"
            margin_label = "SAFE" if margin > 48 else "TIGHT MARGIN" if margin > 0 else "ARRIVES AFTER FAILURE"

            c1, c2, c3 = st.columns(3)
            with c1:
                st.metric("Lead time", f"{lead_days}d")
            with c2:
                st.metric("Median RUL", f"{median_rul_days:.1f}d")
            with c3:
                st.metric("Margin", f"{margin:.0f}h")
            st.badge(margin_label, color="green" if margin > 48 else "orange" if margin > 0 else "red")
        else:
            st.caption("No procurement data for this asset")

# ─── SECTION 8: AI Summary ───
with st.container(border=True):
    st.html('<div style="color:#8B5CF6; font-size:0.7rem; text-transform:uppercase; letter-spacing:0.1em; font-weight:600; margin-bottom:6px;">🤖 AI simulation summary</div>')

    a_prob3 = sim_a.get("failure_prob_day_3", 0)
    a_prob7 = sim_a.get("failure_prob_day_7", 0)
    a_prob14 = sim_a.get("failure_prob_day_14", 0)
    b_prob14 = sim_b.get("failure_prob_day_14", 0)
    c_prob14 = sim_c.get("failure_prob_day_14", 0)

    data_block = f"""Asset: {selected}. Stage: {asset['STAGE_PRED']}. Degradation: {deg:.2f}. Fatigue: {fatigue:.3f}. 300 Monte Carlo paths (3x100).
Scenario A (Do nothing): RUL {sim_a.get('rul_days_p50',0):.1f}d, cost ${sim_a.get('expected_cost',0):,.0f}, fail 3d={a_prob3:.0%} 7d={a_prob7:.0%} 14d={a_prob14:.0%}.
Scenario B (Reduce load {load_b}%): RUL {sim_b.get('rul_days_p50',0):.1f}d, cost ${sim_b.get('expected_cost',0):,.0f}, fail 14d={b_prob14:.0%}.
Scenario C (Custom load={load_c}% delay={delay_c}d rpm={rpm_c}%): RUL {sim_c.get('rul_days_p50',0):.1f}d, cost ${sim_c.get('expected_cost',0):,.0f}, fail 14d={c_prob14:.0%}.
Best: {best_label} at ${best_sim.get('expected_cost',0):,.0f}. Saving: ${cost_saving:,.0f}."""

    sim_summary = generate_executive_summary(data_block, f"digital_twin_{asset['ASSET_ID']}")
    _glow_card("Simulation summary", f'<div style="color:#E0E7FF; font-size:0.82rem; line-height:1.7;">{sim_summary}</div>', "#8B5CF6", "✦")
    if st.button("Regenerate summary", key="regen_dt", icon=":material/refresh:"):
        st.session_state.pop(f"_llm_summary_digital_twin_{asset['ASSET_ID']}", None)
        st.session_state.pop(f"_llm_hash_digital_twin_{asset['ASSET_ID']}", None)
        st.rerun()
