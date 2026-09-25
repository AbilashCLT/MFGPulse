import streamlit as st
import pandas as pd
import altair as alt
from app_pages._shared import (
    load_procurement_recs, load_parts_atp, load_open_pos, load_parts_lifecycle,
    load_planned_pos, load_safety_stock_policy, load_data_freshness,
    fmt_currency, DB, get_conn, RISK_COLOR, generate_executive_summary, C,
)

conn = get_conn()
proc = load_procurement_recs()
atp = load_parts_atp()
pos = load_open_pos()
ssp = load_safety_stock_policy()
if len(proc) > 0 and len(ssp) > 0:
    proc = proc.merge(ssp[["PART_ID", "MIN_STOCK", "REORDER_POINT", "REORDER_QTY", "AT_RISK_ASSETS"]], on="PART_ID", how="left")

# ─── Helpers (matching exec/ops/digital_twin/maintenance) ───
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

# ─── Compute metrics ───
crit_s = len(proc[proc["PROCUREMENT_RISK"] == "CRITICAL_SHORTAGE"]) if len(proc) > 0 and "PROCUREMENT_RISK" in proc.columns else 0
exp_s = len(proc[proc["PROCUREMENT_RISK"] == "EXPEDITE"]) if len(proc) > 0 and "PROCUREMENT_RISK" in proc.columns else 0
ord_s = len(proc[proc["PROCUREMENT_RISK"] == "ORDER_NOW"]) if len(proc) > 0 and "PROCUREMENT_RISK" in proc.columns else 0
no_risk_s = len(proc[proc["PROCUREMENT_RISK"] == "NO_RISK"]) if len(proc) > 0 and "PROCUREMENT_RISK" in proc.columns else 0

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
if crit_s > 0:
    sc_status, sc_color, sc_icon = "AT RISK", "#EF4444", "🔴"
elif exp_s > 0 or ord_s > 0:
    sc_status, sc_color, sc_icon = "MONITORING", "#F59E0B", "🟡"
else:
    sc_status, sc_color, sc_icon = "ADEQUATE", "#10B981", "🟢"

st.html(f"""
<div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:4px; flex-wrap:wrap; gap:10px;">
    <div style="display:flex; align-items:center; gap:14px;">
        <div style="font-size:1.5rem; font-weight:800; color:#E0E7FF;">🔗 Procurement</div>
        <div style="padding:4px 14px; border-radius:12px; font-size:0.65rem; font-weight:700;
                    text-transform:uppercase; letter-spacing:0.08em;
                    background:{sc_color}18; color:{sc_color}; border:1px solid {sc_color}44;
                    box-shadow: 0 0 12px {sc_color}22;">
            {sc_icon} {sc_status}
        </div>
    </div>
    <div style="display:flex; align-items:center; gap:8px;">
        <div style="padding:2px 8px; border-radius:8px; font-size:0.6rem; font-weight:600;
                    background:#10B98118; color:#10B981; border:1px solid #10B98133;">● LIVE</div>
        <span style="font-size:0.65rem; color:#64748B;">Sensor data: {stale_min} min ago</span>
    </div>
</div>
""")
st.caption("Parts availability, purchase orders, and procurement risk")

with st.expander("About this page", expanded=False, icon=":material/info:"):
    st.markdown("""
**Purpose**: Parts supply chain management — monitor availability, manage purchase orders, and act on procurement recommendations powered by a 4-signal evaluation engine.

**4-signal risk evaluation**: 1. Urgency (RUL-based) · 2. Supply (ATP, reservations, competing demand) · 3. Fulfillment (lead time feasibility) · 4. Safety stock policy

**Risk classification** (APICS/ASCM): RESERVED · CRITICAL_SHORTAGE · EXPEDITE · REPLENISH_NOW · ORDER_NOW · NO_RISK

**Key metrics** (4 KPI cards):
- **Supply chain risk** — Count of critical shortage, expedite, and order-now parts with color-coded risk bar
- **Buffer health** — Deficit/tight/surplus part counts with stacked proportion bar
- **PO pipeline** — Open POs, Ordered, Shipped, and Planned counts for full pipeline visibility
- **Inventory** — Zero-ATP part count and total available-to-promise units

**Tabs**:
- **Recommendations** — Per-asset procurement cards with urgency classification, risk badges, recommended action, parts/supplier context, lead time vs RUL feasibility, and one-click PO generation
- **Planned POs** — Auto-generated planned purchase orders from safety stock policy with priority, estimated cost, and auto-convert countdown
- **Stock insights** — Buffer status cards (deficit/tight/surplus/demand/ATP/incoming), stock vs demand grouped bar chart by part, and part contention analysis for multi-asset demand conflicts with net position and days-to-stockout
- **Inventory & POs** — Parts inventory table (on-hand, reserved, ATP, lead time, cost, supplier) and purchase order table with color-coded status breakdown strip (Ordered/Shipped/Pending Approval counts). Auto-generate POs button for bulk order creation.

**Data sources**: `ANALYTICS.PROCUREMENT_RECOMMENDATIONS`, `ANALYTICS.PARTS_AVAILABLE_TO_PROMISE`, `ANALYTICS.PARTS_LIFECYCLE_INSIGHTS`, `ANALYTICS.PLANNED_PURCHASE_ORDERS`, `RAW_IT.PURCHASE_ORDERS`
""")

# ═══════════════════════════════════════════════════════════════
# AI SUMMARY
# ═══════════════════════════════════════════════════════════════
_section_header("🤖", "Procurement brief", "#8B5CF6")

if len(proc) > 0 and "PROCUREMENT_RISK" in proc.columns:
    repl_s = len(proc[proc["PROCUREMENT_RISK"] == "REPLENISH_NOW"])
    res_s = len(proc[proc["PROCUREMENT_RISK"] == "RESERVED"])
    total = len(proc)
    crit_desc = ""
    if crit_s > 0:
        crit_items = proc[proc["PROCUREMENT_RISK"] == "CRITICAL_SHORTAGE"][["ASSET_NAME", "PART_NAME"]].values.tolist()
        crit_desc = f"Critical shortages: {'; '.join([f'{a} ({p})' for a, p in crit_items])}."
    zero_atp_count = len(atp[atp["AVAILABLE_TO_PROMISE"] <= 0]) if len(atp) > 0 else 0

    data_block = f"""{total} asset-part combinations evaluated — {crit_s} Critical Shortage, {exp_s} Expedite, {ord_s} Order Now, {repl_s} Replenish Now, {res_s} Reserved, {no_risk_s} No Risk. {crit_desc} Parts with zero ATP: {zero_atp_count}. Open purchase orders: {len(pos)}."""

    summary = generate_executive_summary(data_block, "procurement")
    _glow_card("Supply chain brief", f'<div style="color:#E0E7FF; font-size:0.82rem; line-height:1.7;">{summary}</div>', "#8B5CF6", "✦")
    if st.button("Regenerate", key="regen_proc", icon=":material/refresh:"):
        st.session_state.pop("_llm_summary_procurement", None)
        st.session_state.pop("_llm_hash_procurement", None)
        st.rerun()

# ═══════════════════════════════════════════════════════════════
# KPI STRIP
# ═══════════════════════════════════════════════════════════════
_section_header("📊", "Key metrics")

k1, k2, k3, k4 = st.columns(4)
with k1:
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid #EF444433; border-left:3px solid #EF4444;
                border-radius:10px; padding:16px; text-align:center; box-shadow: 0 0 15px #EF444411;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">⚠ Supply chain risk</div>
        <div style="display:flex; justify-content:center; gap:14px;">
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:#EF4444;">{crit_s}</div>
                <div style="font-size:0.5rem; color:#EF4444; text-transform:uppercase;">Critical</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:#F59E0B;">{exp_s}</div>
                <div style="font-size:0.5rem; color:#F59E0B; text-transform:uppercase;">Expedite</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:#3B82F6;">{ord_s}</div>
                <div style="font-size:0.5rem; color:#3B82F6; text-transform:uppercase;">Order now</div>
            </div>
        </div>
    </div>
    """)

with k2:
    lifecycle = load_parts_lifecycle()
    deficit_count = len(lifecycle[lifecycle["BUFFER_STATUS"] == "DEFICIT"]) if len(lifecycle) > 0 and "BUFFER_STATUS" in lifecycle.columns else 0
    tight_count = len(lifecycle[lifecycle["BUFFER_STATUS"] == "TIGHT"]) if len(lifecycle) > 0 and "BUFFER_STATUS" in lifecycle.columns else 0
    surplus_count = len(lifecycle[lifecycle["BUFFER_STATUS"] == "SURPLUS"]) if len(lifecycle) > 0 and "BUFFER_STATUS" in lifecycle.columns else 0
    total_buf = max(deficit_count + tight_count + surplus_count, 1)
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid #00D4FF33; border-radius:10px;
                padding:16px; text-align:center; box-shadow: 0 0 15px #00D4FF11;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">📊 Buffer health</div>
        <div style="display:flex; justify-content:center; gap:14px; margin-bottom:8px;">
            <div>
                <div style="font-size:1.3rem; font-weight:800; color:#EF4444;">{deficit_count}</div>
                <div style="font-size:0.5rem; color:#EF4444; text-transform:uppercase;">Deficit</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.3rem; font-weight:800; color:#F59E0B;">{tight_count}</div>
                <div style="font-size:0.5rem; color:#F59E0B; text-transform:uppercase;">Tight</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.3rem; font-weight:800; color:#10B981;">{surplus_count}</div>
                <div style="font-size:0.5rem; color:#10B981; text-transform:uppercase;">Surplus</div>
            </div>
        </div>
        <div style="background:rgba(255,255,255,0.04); border-radius:4px; height:6px; overflow:hidden; display:flex;">
            <div style="width:{deficit_count/total_buf*100:.0f}%; background:#EF4444; height:100%;"></div>
            <div style="width:{tight_count/total_buf*100:.0f}%; background:#F59E0B; height:100%;"></div>
            <div style="width:{surplus_count/total_buf*100:.0f}%; background:#10B981; height:100%;"></div>
        </div>
    </div>
    """)

with k3:
    ppo_count = 0
    try:
        ppos_kpi = load_planned_pos()
        ppo_count = len(ppos_kpi)
    except Exception:
        pass
    ordered_count = len(pos[pos["STATUS"] == "ordered"]) if len(pos) > 0 and "STATUS" in pos.columns else 0
    shipped_count = len(pos[pos["STATUS"] == "shipped"]) if len(pos) > 0 and "STATUS" in pos.columns else 0
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid #8B5CF633; border-radius:10px;
                padding:16px; text-align:center; box-shadow: 0 0 15px #8B5CF611;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">📋 PO pipeline</div>
        <div style="display:flex; justify-content:center; gap:14px;">
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:#8B5CF6;">{len(pos)}</div>
                <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase;">Open POs</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:#3B82F6;">{ordered_count}</div>
                <div style="font-size:0.5rem; color:#3B82F6; text-transform:uppercase;">Ordered</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:#A78BFA;">{shipped_count}</div>
                <div style="font-size:0.5rem; color:#A78BFA; text-transform:uppercase;">Shipped</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:#64748B;">{ppo_count}</div>
                <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase;">Planned</div>
            </div>
        </div>
    </div>
    """)

with k4:
    zero_atp = len(atp[atp["AVAILABLE_TO_PROMISE"] <= 0]) if len(atp) > 0 else 0
    total_atp_val = int(atp["AVAILABLE_TO_PROMISE"].sum()) if len(atp) > 0 else 0
    atp_color = "#EF4444" if zero_atp > 2 else "#F59E0B" if zero_atp > 0 else "#10B981"
    st.html(f"""
    <div style="background:rgba(17,24,39,0.9); border:1px solid {atp_color}33; border-radius:10px;
                padding:16px; text-align:center; box-shadow: 0 0 15px {atp_color}11;">
        <div style="font-size:0.6rem; text-transform:uppercase; letter-spacing:0.1em; color:#64748B;
                    font-weight:600; margin-bottom:10px;">📦 Inventory</div>
        <div style="display:flex; justify-content:center; gap:14px;">
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:{atp_color};">{zero_atp}</div>
                <div style="font-size:0.5rem; color:{atp_color}; text-transform:uppercase;">Zero ATP</div>
            </div>
            <div style="width:1px; background:rgba(255,255,255,0.08);"></div>
            <div>
                <div style="font-size:1.5rem; font-weight:800; color:#00D4FF;">{total_atp_val}</div>
                <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase;">Total ATP</div>
            </div>
        </div>
    </div>
    """)

# ═══════════════════════════════════════════════════════════════
# TABS
# ═══════════════════════════════════════════════════════════════
tab_recs, tab_ppos, tab_stock, tab_inv = st.tabs([
    "Recommendations", "Planned POs", "Stock insights", "Inventory & POs"
])

# ─── TAB 1: PROCUREMENT RECOMMENDATIONS ───
with tab_recs:
    if len(proc) > 0:
        # --- Urgency helpers (preserved from original) ---
        def _urgency(risk, action):
            if risk in ("CRITICAL_SHORTAGE", "EXPEDITE") or action == "ESCALATE_NO_WO":
                return "Procurement critical", "red"
            if action == "MONITOR_RESERVATION":
                return "Reserved for WO", "green"
            if action in ("MONITOR_EXISTING_PO",):
                return "PO in progress", "blue"
            if risk in ("ORDER_NOW", "REPLENISH_NOW"):
                return "Procurement recommended", "orange"
            return "Stock adequate", "green"

        def _context(r):
            risk = r.get("PROCUREMENT_RISK", "")
            action = r.get("RECOMMENDED_PROCUREMENT_ACTION", "")
            atp_val = r.get("AVAILABLE_TO_PROMISE", 0)
            eff_atp = r.get("EFFECTIVE_ATP", 0)
            lead = r.get("LEAD_TIME_DAYS", 0)
            competing = r.get("COMPETING_ASSETS", 1)
            rul = r.get("RUL_HOURS", 0)
            incoming = r.get("INCOMING_PO_QTY", 0)
            net_pos = r.get("NET_POSITION", 0)
            gap = r.get("LEAD_TIME_GAP_DAYS", 0)
            open_po = r.get("OPEN_PO_ID")
            has_po = open_po is not None and str(open_po) not in ("None", "", "nan")
            min_stk = r.get("MIN_STOCK", None)
            reorder_pt = r.get("REORDER_POINT", None)
            reorder_qty = r.get("REORDER_QTY", None)
            ssp_str = f" | Min stock: {int(min_stk)}, reorder pt: {int(reorder_pt)}" if min_stk is not None and pd.notna(min_stk) else ""

            if action == "ESCALATE_NO_WO":
                return f":material/warning: **No work order exists** — create WO first, then reorder (ATP: {atp_val}, eff. ATP: {eff_atp}, lead: {lead}d{ssp_str})"
            if action == "ESCALATE_CRITICAL_SHORTAGE":
                return f":material/error: **ATP: {atp_val}** below min stock ({int(min_stk) if min_stk is not None and pd.notna(min_stk) else '?'}) — escalate immediately. {competing} assets competing, incoming: {incoming}, lead: {lead}d"
            if risk == "EXPEDITE" and action == "EXPEDITE_PO":
                return f":material/bolt: Parts won't arrive in time — expedite shipping (lead: {lead}d, RUL: {rul:.0f}h, gap: {gap:.0f}d). ATP: {atp_val}, eff. ATP: {eff_atp}{ssp_str}"
            if risk == "EXPEDITE":
                return f":material/bolt: Parts won't arrive in time (lead: {lead}d, RUL: {rul:.0f}h, gap: {gap:.0f}d). ATP: {atp_val}, eff. ATP: {eff_atp}{ssp_str}"
            if action == "MONITOR_EXISTING_PO" and has_po:
                return f":material/local_shipping: PO **{open_po}** in progress — ATP: {atp_val}, incoming: {incoming}, ATP+incoming: {atp_val + incoming}{ssp_str}"
            if action == "MONITOR_RESERVATION":
                wo_id = r.get("WO_ID", "")
                res_qty = r.get("RESERVED_QTY", 0)
                wo_str = f" for WO **{wo_id}**" if wo_id and str(wo_id) not in ("None", "", "nan") else ""
                return f":material/bookmark_added: **{int(res_qty)} unit(s) reserved**{wo_str} — part allocated for this repair. ATP after reservation: {atp_val}{ssp_str}"
            if action == "CREATE_PO":
                qty_str = f", order qty: {int(reorder_qty)}" if reorder_qty is not None and pd.notna(reorder_qty) else ""
                return f":material/add_shopping_cart: ATP: {atp_val} at/below reorder point ({int(reorder_pt) if reorder_pt is not None and pd.notna(reorder_pt) else '?'}) — create PO{qty_str}. Net pos: {net_pos}, lead: {lead}d"
            if risk == "REPLENISH_NOW" and competing > 1:
                return f"Stock covers immediate need (ATP: {atp_val}, eff. ATP: {eff_atp}) but {competing} assets compete — reorder now, lead: {lead}d{ssp_str}"
            if risk == "REPLENISH_NOW":
                return f"Parts in stock (ATP: {atp_val}) — reorder now, lead: {lead}d{ssp_str}"
            if risk == "ORDER_NOW":
                return f"ATP: {atp_val} at/below reorder point ({int(reorder_pt) if reorder_pt is not None and pd.notna(reorder_pt) else '?'}) — place order now. Net pos: {net_pos}{ssp_str}"
            if risk == "NO_RISK":
                return f"Supply adequate (ATP: {atp_val}, lead: {lead}d fits within RUL{ssp_str})"
            return f"ATP: {atp_val} | Eff. ATP: {eff_atp} | Lead: {lead}d{ssp_str}"

        def _signal_explanation(r):
            risk = r.get("PROCUREMENT_RISK", "")
            action = r.get("RECOMMENDED_PROCUREMENT_ACTION", "")
            atp_v = r.get("AVAILABLE_TO_PROMISE", 0)
            eff_atp = r.get("EFFECTIVE_ATP", 0)
            rul = r.get("RUL_HOURS", 0)
            stage = r.get("STAGE_PRED", "")
            mode = r.get("FAILURE_MODE_PRED", "normal")
            lead = r.get("LEAD_TIME_DAYS", 0)
            gap = r.get("LEAD_TIME_GAP_DAYS", 0)
            feasible = r.get("LEAD_TIME_FEASIBLE", False)
            competing = r.get("COMPETING_ASSETS", 1)
            incoming = r.get("INCOMING_PO_QTY", 0)
            net = r.get("NET_POSITION", 0)
            buf = r.get("BUFFER_STATUS", "")
            min_stk = r.get("MIN_STOCK", None)
            rp = r.get("REORDER_POINT", None)
            rq = r.get("REORDER_QTY", None)
            ar = r.get("AT_RISK_ASSETS", None)
            open_po = r.get("OPEN_PO_ID")
            has_po = open_po is not None and str(open_po) not in ("None", "", "nan")
            rul_days = round(rul / 24, 1)
            has_ssp = min_stk is not None and pd.notna(min_stk)
            ar_val = int(ar) if ar is not None and pd.notna(ar) else 0

            if rul < 72:
                s1_icon, s1 = "🔴", f"Asset may fail within **{rul:.0f} hours ({rul_days} days)**. Stage: **{stage}**, predicted failure: **{mode}**."
            elif rul < 336:
                s1_icon, s1 = "🟠", f"Asset has **{rul:.0f} hours ({rul_days} days)** of remaining life. Stage: **{stage}**. Plan maintenance this week."
            else:
                s1_icon, s1 = "🟢", f"Asset has **{rul:.0f} hours ({rul_days} days)** of remaining life. Stage: **{stage}**. No immediate urgency."

            if has_ssp and atp_v <= min_stk:
                s2_icon = "🔴"
                s2 = f"Only **{atp_v} units** on hand — below safety minimum of **{int(min_stk)}**. Effective availability: {eff_atp}. Buffer: **{buf}**."
            elif has_ssp and atp_v <= rp:
                s2_icon, s2 = "🟠", f"**{atp_v} units** on hand — below reorder point of **{int(rp)}**. Buffer: **{buf}**."
            elif eff_atp < 1:
                s2_icon, s2 = "🔴", f"After {competing} competing assets, effective availability drops to **{eff_atp}** — depleted. Buffer: **{buf}**."
            else:
                s2_icon, s2 = "🟢", f"**{atp_v} units** on hand, effective availability **{eff_atp}**. Buffer: **{buf}**."

            if not feasible:
                s3_icon, s3 = "🔴", f"Lead time **{lead} days** exceeds {rul_days}-day window. **{abs(gap):.0f}-day gap**."
            elif gap is not None and gap > -3:
                s3_icon, s3 = "🟠", f"Lead time **{lead} days** fits with only **{abs(gap):.0f} day(s)** margin."
            else:
                s3_icon, s3 = "🟢", f"Lead time **{lead} days** fits with **{abs(gap):.0f} days** margin."

            if has_ssp:
                if atp_v <= min_stk:
                    s4_icon, s4 = "🔴", f"Stock ({atp_v}) at/below minimum **{int(min_stk)}**. Order qty: {int(rq)}."
                elif atp_v <= rp:
                    s4_icon, s4 = "🟠", f"Stock ({atp_v}) below reorder point **{int(rp)}**."
                else:
                    s4_icon, s4 = "🟢", f"Stock ({atp_v}) above minimum ({int(min_stk)}) and reorder ({int(rp)})."
            else:
                s4_icon, s4 = "⚪", "No safety stock policy for this part."

            urg_label, _ = _urgency(risk, action)
            action_plain = {
                "ESCALATE_CRITICAL_SHORTAGE": "Escalate immediately",
                "ESCALATE_NO_WO": "Escalate — no work order exists",
                "EXPEDITE_PO": "Request expedited shipping",
                "CREATE_PO": "Create a new purchase order",
                "RESERVE_AND_REORDER": "Reserve stock and place reorder",
                "MONITOR_EXISTING_PO": "Monitor open PO",
                "MONITOR_RESERVATION": "Parts reserved — no action needed",
                "NO_ACTION": "No action needed",
            }.get(action, action)

            return "\n".join([
                f"**Signal 1 — Urgency** {s1_icon}", s1, "",
                f"**Signal 2 — Supply** {s2_icon}", s2, "",
                f"**Signal 3 — Fulfillment** {s3_icon}", s3, "",
                f"**Signal 4 — Safety Stock** {s4_icon}", s4, "",
                "---",
                f"**Bottom line**: Classified as **{urg_label}** ({risk}). {action_plain}.",
            ])

        # KPI bar (styled HTML cards matching exec/ops)
        _section_header("🎯", "Procurement actions")
        act_now_count = len(proc[proc.apply(lambda r: _urgency(r.get("PROCUREMENT_RISK",""), r.get("RECOMMENDED_PROCUREMENT_ACTION",""))[0] == "Procurement critical", axis=1)])
        order_soon_count = len(proc[proc.apply(lambda r: _urgency(r.get("PROCUREMENT_RISK",""), r.get("RECOMMENDED_PROCUREMENT_ACTION",""))[0] == "Procurement recommended", axis=1)])
        monitoring_count = len(proc[proc.apply(lambda r: _urgency(r.get("PROCUREMENT_RISK",""), r.get("RECOMMENDED_PROCUREMENT_ACTION",""))[0] == "PO in progress", axis=1)])
        reserved_count = len(proc[proc.apply(lambda r: _urgency(r.get("PROCUREMENT_RISK",""), r.get("RECOMMENDED_PROCUREMENT_ACTION",""))[0] == "Reserved for WO", axis=1)])
        ok_count = len(proc[proc.apply(lambda r: _urgency(r.get("PROCUREMENT_RISK",""), r.get("RECOMMENDED_PROCUREMENT_ACTION",""))[0] == "Stock adequate", axis=1)])

        ak1, ak2, ak3, ak4, ak5 = st.columns(5)
        for col, label, val, color in [
            (ak1, "Procurement critical", act_now_count, "#EF4444"),
            (ak2, "Recommended", order_soon_count, "#F59E0B"),
            (ak3, "PO in progress", monitoring_count, "#3B82F6"),
            (ak4, "Reserved for WO", reserved_count, "#8B5CF6"),
            (ak5, "Stock adequate", ok_count, "#10B981"),
        ]:
            with col:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                            border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                    <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
                    <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                </div>
                """)

        # Group by asset, sorted by worst urgency
        urgency_order = {"Procurement critical": 0, "Procurement recommended": 1, "PO in progress": 2, "Reserved for WO": 3, "Stock adequate": 4}
        proc = proc.copy()
        proc["_urgency_label"] = proc.apply(lambda r: _urgency(r.get("PROCUREMENT_RISK",""), r.get("RECOMMENDED_PROCUREMENT_ACTION",""))[0], axis=1)
        proc["_urgency_rank"] = proc["_urgency_label"].map(urgency_order)
        asset_worst = proc.groupby("ASSET_ID")["_urgency_rank"].min().reset_index().rename(columns={"_urgency_rank": "_asset_rank"})
        proc = proc.merge(asset_worst, on="ASSET_ID")

        actionable = proc[proc["_urgency_label"] != "Stock adequate"].sort_values(["_asset_rank", "RUL_HOURS"])
        no_action = proc[proc["_urgency_label"] == "Stock adequate"].sort_values(["ASSET_NAME", "PART_NAME"])

        if len(actionable) > 0:
            for asset_id, asset_parts in actionable.groupby("ASSET_ID", sort=False):
                first = asset_parts.iloc[0]
                worst_label, worst_color = _urgency(first.get("PROCUREMENT_RISK",""), first.get("RECOMMENDED_PROCUREMENT_ACTION",""))
                for _, p in asset_parts.iterrows():
                    lbl, clr = _urgency(p.get("PROCUREMENT_RISK",""), p.get("RECOMMENDED_PROCUREMENT_ACTION",""))
                    if urgency_order.get(lbl, 3) < urgency_order.get(worst_label, 3):
                        worst_label, worst_color = lbl, clr

                with st.container(border=True):
                    hdr1, hdr2, hdr3 = st.columns([3, 1, 1])
                    with hdr1:
                        st.markdown(f"**{first['ASSET_NAME']}** — {len(asset_parts)} part(s)")
                    with hdr2:
                        st.badge(worst_label, color=worst_color)
                    with hdr3:
                        stage = first.get("STAGE_PRED", "")
                        stage_color = "red" if stage == "Critical" else "orange" if stage == "Warning" else "green"
                        st.badge(f"RUL: {first.get('RUL_HOURS', 0):.0f}h", color=stage_color)

                    for pidx, (_, r) in enumerate(asset_parts.iterrows()):
                        urg_label, urg_color = _urgency(r.get("PROCUREMENT_RISK",""), r.get("RECOMMENDED_PROCUREMENT_ACTION",""))
                        ctx = _context(r)
                        pc1, pc2, pc3 = st.columns([2, 2, 1])
                        with pc1:
                            st.caption(f":material/inventory_2: **{r.get('PART_NAME', 'N/A')}**")
                            st.caption(ctx)
                            with st.expander("Why this classification?", expanded=False):
                                st.markdown(_signal_explanation(r))
                        with pc2:
                            st.badge(urg_label, color=urg_color)
                            competing = r.get("COMPETING_ASSETS", 1)
                            if competing > 1:
                                st.caption(f":material/group: {competing} assets share this part")
                        with pc3:
                            action = r.get("RECOMMENDED_PROCUREMENT_ACTION", "")
                            open_po = r.get("OPEN_PO_ID")
                            has_open_po = open_po is not None and str(open_po) not in ("None", "", "nan")
                            is_escalate_with_po = action == "ESCALATE_CRITICAL_SHORTAGE" and has_open_po
                            if is_escalate_with_po:
                                show_create, btn_label, btn_icon = True, "Supplement PO", ":material/add_alert:"
                            elif has_open_po:
                                override = st.checkbox("Override", key=f"override_{r['ASSET_ID']}_{r['PART_ID']}")
                                show_create, btn_label, btn_icon = override, "Create PO", ":material/add_shopping_cart:"
                            elif action and action not in ("RESERVE_STOCK", "NO_ACTION", "USE_STOCK", "MONITOR_PO", "MONITOR_RESERVATION", "MONITOR_EXISTING_PO"):
                                show_create, btn_label, btn_icon = True, "Create PO", ":material/add_shopping_cart:"
                            else:
                                show_create, btn_label, btn_icon = False, "Create PO", ":material/add_shopping_cart:"
                            if show_create:
                                if st.button(btn_label, key=f"po_{r['ASSET_ID']}_{r['PART_ID']}", type="primary", icon=btn_icon):
                                    try:
                                        session = conn.session()
                                        priority = "EMERGENCY" if r.get("PROCUREMENT_RISK") == "CRITICAL_SHORTAGE" else "HIGH" if r.get("PROCUREMENT_RISK") == "EXPEDITE" else "NORMAL"
                                        session.sql(
                                            f"CALL {DB}.ANALYTICS.GENERATE_PURCHASE_ORDER(:1, :2, :3, :4, :5, :6)",
                                            params=[
                                                str(r["ASSET_ID"]), str(r.get("PART_ID", "")),
                                                int(r.get("REQUIRED_QUANTITY", 1)),
                                                str(r.get("REQUIRED_BY_DATE", ""))[:10],
                                                str(r.get("WO_ID") or ""), priority,
                                            ],
                                        ).collect()
                                        st.session_state["_ppo_action_msg"] = f"PO created for {r['ASSET_NAME']} — {r.get('PART_NAME','')}"
                                        load_procurement_recs.clear()
                                        st.rerun()
                                    except Exception as ex:
                                        st.error(f"Failed: {ex}")
                        if pidx < len(asset_parts) - 1:
                            st.divider()

        if len(no_action) > 0:
            with st.expander(f"No action needed ({len(no_action)} parts)", expanded=False):
                for asset_id, asset_parts in no_action.groupby("ASSET_ID", sort=False):
                    first = asset_parts.iloc[0]
                    st.markdown(f"**{first['ASSET_NAME']}** — RUL: {first.get('RUL_HOURS', 0):.0f}h")
                    for _, r in asset_parts.iterrows():
                        st.caption(f":material/check_circle: {r.get('PART_NAME', 'N/A')} — ATP: {r.get('AVAILABLE_TO_PROMISE', 0)}, lead: {r.get('LEAD_TIME_DAYS', 0)}d | Supply adequate")
    else:
        st.info("No procurement recommendations available.")

# ─── TAB 2: PLANNED POs ───
with tab_ppos:
    if "_ppo_action_msg" in st.session_state:
        st.success(st.session_state.pop("_ppo_action_msg"), icon=":material/check_circle:")
    ppos = load_planned_pos()
    if len(ppos) > 0:
        _section_header("📋", "Planned purchase orders")
        emergency = len(ppos[ppos["PRIORITY_CLASSIFICATION"] == "EMERGENCY"])
        high = len(ppos[ppos["PRIORITY_CLASSIFICATION"] == "HIGH"])
        auto_due = len(ppos[ppos["AUTO_CONVERT_DUE"] == True])
        total_cost = ppos["ESTIMATED_TOTAL_COST"].sum()

        pp1, pp2, pp3, pp4, pp5 = st.columns(5)
        for col, label, val, color in [
            (pp1, "Planned POs", len(ppos), "#00D4FF"),
            (pp2, "Emergency", emergency, "#EF4444"),
            (pp3, "High priority", high, "#F59E0B"),
            (pp4, "Auto-convert due", auto_due, "#8B5CF6"),
            (pp5, "Est. cost", fmt_currency(total_cost), "#10B981"),
        ]:
            with col:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                            border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                    <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
                    <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                </div>
                """)

        for _, r in ppos.iterrows():
            prio = r.get("PRIORITY_CLASSIFICATION", "NORMAL")
            status = r.get("PPO_STATUS", "PLANNED")
            days_left = r.get("DAYS_UNTIL_AUTO_CONVERT", 0)
            prio_color = {"EMERGENCY": "red", "HIGH": "orange", "NORMAL": "blue", "LOW": "gray"}.get(prio, "gray")
            status_color = {"EXPEDITE_IMMEDIATELY": "red", "AUTO_CONVERTING": "red", "ORDER_SOON": "orange", "REVIEW_AND_EXPEDITE": "orange", "PLANNED": "blue"}.get(status, "gray")

            with st.container(border=True):
                c1, c2, c3 = st.columns([2, 1, 2])
                with c1:
                    st.markdown(f"**{r['PART_NAME']}**")
                    st.caption(f"{r['ASSET_COUNT']} asset(s): {r['ASSET_LIST']}")
                    st.caption(f"Qty: {r['TOTAL_QTY_NEEDED']} | Cost: {fmt_currency(r['ESTIMATED_TOTAL_COST'])} | Supplier: {r.get('SUPPLIER_NAME', 'N/A')}")
                with c2:
                    st.badge(prio, color=prio_color)
                    st.badge(status, color=status_color)
                    if days_left is not None:
                        if days_left <= 0:
                            st.caption(":material/warning: **Overdue** — auto-converting")
                        elif days_left <= 3:
                            st.caption(f":material/schedule: **{days_left}d** until auto-convert")
                        else:
                            st.caption(f"Auto-convert in {days_left}d")
                with c3:
                    st.caption(f"RUL: {r.get('MIN_RUL_DAYS', 0):.0f}d | Lead: {r['LEAD_TIME_DAYS']}d")
                    st.caption(f"Required by: {str(r['EARLIEST_REQUIRED_BY'])[:10]}")
                    st.caption(f"Std arrival: {str(r['STANDARD_ARRIVAL_DATE'])[:10]} | Expedite: {str(r['EXPEDITE_ARRIVAL_DATE'])[:10]}")
                    bc1, bc2 = st.columns(2)
                    with bc1:
                        if st.button("Expedite", key=f"exp_{r['PPO_ID']}", type="primary", icon=":material/bolt:"):
                            try:
                                session = conn.session()
                                part_recs = proc[proc["PART_ID"] == r["PART_ID"]]
                                first_asset_id = part_recs.iloc[0]["ASSET_ID"] if len(part_recs) > 0 else ""
                                session.sql(
                                    f"CALL {DB}.ANALYTICS.GENERATE_PURCHASE_ORDER(:1, :2, :3, :4, :5, :6)",
                                    params=[str(first_asset_id), str(r["PART_ID"]), int(r["TOTAL_QTY_NEEDED"]),
                                            str(r["EARLIEST_REQUIRED_BY"])[:10], "", "EMERGENCY"],
                                ).collect()
                                st.session_state["_ppo_action_msg"] = f"Expedited: PO created for {r['PART_NAME']}"
                                load_planned_pos.clear()
                                load_procurement_recs.clear()
                                st.rerun()
                            except Exception as ex:
                                st.error(f"Failed: {ex}")
                    with bc2:
                        if st.button("Convert now", key=f"conv_{r['PPO_ID']}", icon=":material/check_circle:"):
                            try:
                                session = conn.session()
                                part_recs = proc[proc["PART_ID"] == r["PART_ID"]]
                                first_asset_id = part_recs.iloc[0]["ASSET_ID"] if len(part_recs) > 0 else ""
                                session.sql(
                                    f"CALL {DB}.ANALYTICS.GENERATE_PURCHASE_ORDER(:1, :2, :3, :4, :5, :6)",
                                    params=[str(first_asset_id), str(r["PART_ID"]), int(r["TOTAL_QTY_NEEDED"]),
                                            str(r["EARLIEST_REQUIRED_BY"])[:10], "", str(prio)],
                                ).collect()
                                st.session_state["_ppo_action_msg"] = f"Converted: PO created for {r['PART_NAME']}"
                                load_planned_pos.clear()
                                load_procurement_recs.clear()
                                st.rerun()
                            except Exception as ex:
                                st.error(f"Failed: {ex}")

        with st.container(border=True):
            st.markdown("**Auto-conversion schedule**")
            st.caption("Planned POs auto-convert when the order-by deadline passes. Task runs every 12 hours.")
            if st.button("Run auto-convert now", type="primary", icon=":material/auto_awesome:"):
                try:
                    session = conn.session()
                    result = session.sql(f"CALL {DB}.ANALYTICS.AUTO_CONVERT_PLANNED_POS()").collect()
                    st.session_state["_ppo_action_msg"] = f"Auto-convert complete: {result[0][0] if result else 'Done'}"
                    load_planned_pos.clear()
                    load_procurement_recs.clear()
                    st.rerun()
                except Exception as ex:
                    st.error(f"Failed: {ex}")

        with st.expander("Planned PO data", expanded=False, icon=":material/table_chart:"):
            st.dataframe(ppos, use_container_width=True, hide_index=True,
                column_config={
                    "PPO_ID": "PPO", "PART_NAME": "Part", "SUPPLIER_NAME": "Supplier",
                    "ASSET_COUNT": "Assets", "TOTAL_QTY_NEEDED": "Qty",
                    "ESTIMATED_TOTAL_COST": st.column_config.NumberColumn("Est. cost", format="$%.0f"),
                    "PRIORITY_SCORE": st.column_config.NumberColumn("Score", format="%.3f"),
                    "PRIORITY_CLASSIFICATION": "Priority", "PPO_STATUS": "Status",
                    "MIN_RUL_DAYS": st.column_config.NumberColumn("Min RUL (d)", format="%.1f"),
                    "DAYS_UNTIL_AUTO_CONVERT": "Auto-convert in (d)",
                })
    else:
        st.info("No planned purchase orders. All procurement needs are covered.")

# ─── TAB 3: STOCK INSIGHTS ───
with tab_stock:
    if len(lifecycle) > 0:
        _section_header("📊", "Buffer status")

        bs1, bs2, bs3, bs4, bs5, bs6 = st.columns(6)
        total_demand = lifecycle["AT_RISK_ASSET_COUNT"].sum()
        total_atp_lc = lifecycle["AVAILABLE_TO_PROMISE"].sum()
        total_incoming = int(lifecycle["INCOMING_QTY"].sum()) if "INCOMING_QTY" in lifecycle.columns else 0
        for col, label, val, color in [
            (bs1, "Deficit", deficit_count, "#EF4444"),
            (bs2, "Tight", tight_count, "#F59E0B"),
            (bs3, "Surplus", surplus_count, "#10B981"),
            (bs4, "Total demand", f"{int(total_demand)}", "#00D4FF"),
            (bs5, "Total ATP", f"{int(total_atp_lc)}", "#8B5CF6"),
            (bs6, "Incoming (POs)", f"{total_incoming}", "#A78BFA"),
        ]:
            with col:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                            border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                    <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
                    <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                </div>
                """)

        _section_header("📦", "Stock vs demand by part")
        with st.container(border=True):
            st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">ATP vs Demand vs Incoming POs</div>')
            chart_data = lifecycle[lifecycle["AT_RISK_ASSET_COUNT"] > 0][["PART_NAME", "AVAILABLE_TO_PROMISE", "AT_RISK_ASSET_COUNT", "INCOMING_QTY"]].copy()
            chart_data = chart_data.rename(columns={"AVAILABLE_TO_PROMISE": "ATP", "AT_RISK_ASSET_COUNT": "Demand", "INCOMING_QTY": "Incoming POs"})
            chart_melted = chart_data.melt(id_vars=["PART_NAME"], var_name="Type", value_name="Qty")
            bar_chart = alt.Chart(chart_melted).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
                x=alt.X("PART_NAME:N", title="Part", sort="-y", axis=alt.Axis(labelColor="#64748B")),
                y=alt.Y("Qty:Q", title="Units", axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                color=alt.Color("Type:N", scale=alt.Scale(
                    domain=["ATP", "Demand", "Incoming POs"],
                    range=[C["healthy"], C["critical"], C["watch"]]
                )),
                xOffset="Type:N",
                tooltip=["PART_NAME:N", "Type:N", "Qty:Q"],
            ).properties(height=300)
            st.altair_chart(bar_chart.configure_view(strokeWidth=0).configure_axis(
                gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

        contention = lifecycle[lifecycle["AT_RISK_ASSET_COUNT"] > 1]
        if len(contention) > 0:
            _section_header("⚠️", "Part contention", "#F59E0B")
            for _, p in contention.iterrows():
                buf_color = "#10B981" if p["BUFFER_STATUS"] == "SURPLUS" else "#F59E0B" if p["BUFFER_STATUS"] == "TIGHT" else "#EF4444"
                _glow_card(f"{p['PART_NAME']} — {p['AT_RISK_ASSET_COUNT']} assets competing", f"""
                    <div style="color:#94A3B8; font-size:0.75rem;">Assets: {p.get('AT_RISK_ASSETS', 'N/A')}</div>
                    <div style="color:#94A3B8; font-size:0.75rem;">ATP: {p['AVAILABLE_TO_PROMISE']} | Demand: {p['AT_RISK_ASSET_COUNT']} | Net: {p['NET_POSITION']} | Incoming: {p['INCOMING_QTY']}</div>
                    <div style="display:inline-block; margin-top:6px; padding:2px 8px; border-radius:8px; font-size:0.6rem; font-weight:700;
                        background:{buf_color}18; color:{buf_color}; border:1px solid {buf_color}33;">{p['BUFFER_STATUS']}</div>
                    {"<div style='color:#64748B; font-size:0.65rem; margin-top:4px;'>Stockout in " + str(p['EST_DAYS_UNTIL_STOCKOUT']) + "d (soonest failure: " + str(p['MIN_RUL_DAYS']) + "d)</div>" if p.get("EST_DAYS_UNTIL_STOCKOUT") is not None and p["EST_DAYS_UNTIL_STOCKOUT"] > 0 else ""}
                """, buf_color, "⚠️")

        with st.expander("Full lifecycle data", expanded=False, icon=":material/table_chart:"):
            st.dataframe(lifecycle, use_container_width=True, hide_index=True,
                column_config={
                    "PART_ID": "Part", "PART_NAME": "Name", "AVAILABLE_TO_PROMISE": "ATP",
                    "AT_RISK_ASSET_COUNT": "Demand", "INCOMING_QTY": "Incoming",
                    "NET_POSITION": "Net", "EST_DAYS_UNTIL_STOCKOUT": st.column_config.NumberColumn("Stockout (d)", format="%.1f"),
                    "BUFFER_STATUS": "Buffer", "MIN_RUL_DAYS": st.column_config.NumberColumn("Min RUL (d)", format="%.1f"),
                    "UNIT_COST": st.column_config.NumberColumn("Cost", format="$%.0f"),
                })
    else:
        st.info("No lifecycle data available.")

# ─── TAB 4: INVENTORY & POs ───
with tab_inv:
    _section_header("📦", "Parts inventory")
    if len(atp) > 0:
        st.dataframe(
            atp, use_container_width=True, hide_index=True,
            column_config={
                "PART_ID": "Part ID", "PART_NAME": "Part", "QUANTITY_ON_HAND": "On hand",
                "RESERVED_QUANTITY": "Reserved", "AVAILABLE_TO_PROMISE": "ATP",
                "LEAD_TIME_DAYS": "Lead time (d)",
                "UNIT_COST": st.column_config.NumberColumn("Unit cost", format="$%.0f"),
                "SUPPLIER_NAME": "Supplier",
            },
        )
    else:
        st.info("Parts inventory not available.")

    _section_header("📋", "Purchase orders")
    if len(pos) > 0:
        # Status breakdown strip
        po_status_counts = pos["STATUS"].value_counts().to_dict() if "STATUS" in pos.columns else {}
        status_color_map = {"draft": "#64748B", "pending_approval": "#F59E0B", "approved": "#3B82F6",
                            "ordered": "#3B82F6", "shipped": "#A78BFA"}
        status_chips = " · ".join([
            f'<span style="color:{status_color_map.get(s, "#64748B")}; font-weight:700;">{s.replace("_"," ").title()}: {c}</span>'
            for s, c in po_status_counts.items()
        ])
        st.html(f'<div style="font-size:0.72rem; margin-bottom:8px;">{status_chips}</div>')
        st.dataframe(
            pos, use_container_width=True, hide_index=True,
            column_config={
                "PO_ID": "PO", "SUPPLIER_NAME": "Supplier", "STATUS": "Status",
                "PRIORITY": "Priority", "REQUIRED_BY_DATE": "Required by",
                "EXPECTED_ARRIVAL_DATE": "Expected arrival",
                "TOTAL_COST": st.column_config.NumberColumn("Cost", format="$%.0f"),
                "PART_ID": "Part", "ASSET_ID": "Asset", "PROCUREMENT_RISK": "Risk",
            },
        )
    else:
        st.info("No open purchase orders.")

    with st.container(border=True):
        st.markdown("**Auto-generate purchase orders**")
        st.caption("Creates POs for all at-risk assets without existing orders.")
        if st.button("Auto-generate POs", type="primary", icon=":material/auto_awesome:"):
            try:
                session = conn.session()
                result = session.sql(f"CALL {DB}.ANALYTICS.AUTO_GENERATE_PURCHASE_ORDERS()").collect()
                st.success(f"Result: {result[0][0] if result else 'Done'}")
            except Exception as ex:
                st.error(f"Failed: {ex}")
