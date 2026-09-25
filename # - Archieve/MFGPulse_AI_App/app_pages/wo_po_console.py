import streamlit as st
import pandas as pd
import altair as alt
from app_pages._shared import (
    load_all_work_orders, load_all_purchase_orders, load_unread_notifications, load_users,
    load_parts_atp, load_wo_parts_info, load_wo_activity_log, load_open_work_orders,
    load_procurement_recs, load_open_pos, load_active_reservations, load_live_predictions,
    load_safety_stock_policy,
    fmt_currency, C, DB, get_conn, PERSONA_CONFIG,
    WO_TYPE_COLOR, WO_STATUS_COLOR, PO_STATUS_COLOR, RISK_COLOR, generate_executive_summary,
)

alt.renderers.enable("mimetype")

conn = get_conn()

# ─── Helpers (matching all other pages) ───
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

def _notify(event_type, title, message, entity_id):
    try:
        conn.session().sql(
            f"CALL {DB}.RAW_IT.LOG_APP_NOTIFICATION(:1, :2, :3, :4)",
            params=[event_type, title, message, entity_id],
        ).collect()
        load_unread_notifications.clear()
    except Exception:
        pass


def _log_bulk_operation(operation_type, entity_type, entity_ids, total_selected, total_succeeded, total_blocked, blocked_reason=None, details=None):
    try:
        import json as _json
        conn.session().sql(
            f"CALL {DB}.ANALYTICS.LOG_BULK_OPERATION(:1, :2, PARSE_JSON(:3), :4, :5, :6, :7, :8, :9, PARSE_JSON(:10))",
            params=[
                operation_type, entity_type, _json.dumps(entity_ids),
                total_selected, total_succeeded, total_blocked,
                blocked_reason, username, persona,
                _json.dumps(details) if details else "null",
            ],
        ).collect()
    except Exception:
        pass
persona = st.session_state.get("persona", "TECHNICIAN")
username = st.session_state.get("username", "")
all_wo = load_all_work_orders()
all_po = load_all_purchase_orders()
wo_parts = load_wo_parts_info()

# Clear stale status overrides once DB reflects the change
for key in [k for k in st.session_state if k.startswith("_wo_status_")]:
    wo_id = key.replace("_wo_status_", "")
    if len(all_wo) > 0 and wo_id in all_wo["WO_ID"].values:
        db_status = all_wo.loc[all_wo["WO_ID"] == wo_id, "STATUS"].iloc[0]
        if db_status == st.session_state[key]:
            del st.session_state[key]

for key in [k for k in st.session_state if k.startswith("_po_status_")]:
    po_id = key.replace("_po_status_", "")
    if len(all_po) > 0 and po_id in all_po["PO_ID"].values:
        db_status = all_po.loc[all_po["PO_ID"] == po_id, "STATUS"].iloc[0]
        if db_status == st.session_state[key]:
            del st.session_state[key]

CAN_MANAGE_WO = persona in ("SHIFT_SUPERVISOR", "PLANT_MANAGER", "APP_ADMIN")
CAN_MANAGE_PO = persona in ("PROCUREMENT_ADMIN", "PLANT_MANAGER", "APP_ADMIN")
CAN_VIEW_PO = persona not in ("TECHNICIAN",)

# Bulk selection state
if "_bulk_wo_selected" not in st.session_state:
    st.session_state["_bulk_wo_selected"] = set()
if "_bulk_po_selected" not in st.session_state:
    st.session_state["_bulk_po_selected"] = set()
if "_bulk_wo_mode" not in st.session_state:
    st.session_state["_bulk_wo_mode"] = False
if "_bulk_po_mode" not in st.session_state:
    st.session_state["_bulk_po_mode"] = False
if "_bulk_complete_mode" not in st.session_state:
    st.session_state["_bulk_complete_mode"] = False
if "_bulk_reject_mode" not in st.session_state:
    st.session_state["_bulk_reject_mode"] = False

st.markdown("#### WO / PO console")
st.caption("Work order and purchase order management — actions vary by persona")

with st.expander("About this page", expanded=False, icon=":material/info:"):
    persona_label = PERSONA_CONFIG.get(persona, {}).get('label', persona)
    wo_perm = 'Start / Complete' if CAN_MANAGE_WO else 'View only'
    po_perm = 'Approve / Reject / Receive' if CAN_MANAGE_PO else 'View only' if CAN_VIEW_PO else 'Hidden'
    st.markdown(f"""
**Purpose**: Unified management of Work Orders and Purchase Orders with persona-gated permissions.

**Work order lifecycle**: open → in_progress → completed (or cancelled).
- **Start Work** gated by part availability: disabled if ATP=0 and no open PO; shows "Alert Procurement" button to notify procurement team
- **Complete** (only on in_progress): prompts "Was the part used?" (consumed vs returned to stock) and root cause confirmation (bearing_wear, thermal, imbalance, misalignment, electrical, false_alarm, undetermined_degradation). Auto-releases part reservations.
- **Part badges**: RESERVED (green) for in_progress WOs with active reservation; procurement risk badge for others; hidden on completed/cancelled
- **Aging warnings**: Reservation >7 days on open WO; WO in_progress >48h (orange) or >72h (red escalation)

**Purchase order lifecycle**: pending_approval → approved → ordered → shipped → received (or cancelled).
- **Reject** requires a written reason (stored in REJECTION_REASON). Impact notification sent to Shift Supervisor with asset/part/RUL context.
- **Approve/Receive** clear all procurement caches for immediate dashboard refresh.
- Cancelled POs display rejection reason and rejected-by user.

**Procurement intelligence** (APICS/ASCM compliant):
- **Buffer status**: SURPLUS (net >= competing demand + 1), ADEQUATE (net >= required), TIGHT (net >= 0), DEFICIT (net < 0) — accounts for competing asset demand, not just absolute stock levels.
- **Gap types**: FULFILLMENT_GAP (can't serve demand from current stock), REPLENISHMENT_GAP (stock available but reorder won't arrive before buffer depletes), NO_GAP (lead time within RUL).
- **Procurement risk**: CRITICAL_SHORTAGE, EXPEDITE, REPLENISH_NOW, ORDER_NOW, RESERVED, NO_RISK — based on RUL urgency, effective ATP vs demand, and lead time feasibility.
- **ESCALATE_NO_WO**: Flags assets with RUL < 72h and no open work order — a work identification gap per SMRP 5.5.2.

**Your permissions** ({persona_label}):
- Work orders: {wo_perm}
- Purchase orders: {po_perm}

**Sections**:
- **WO/PO summary** — AI-generated narrative (Cortex Complete, llama3.1-8b) of work order stats, completion rate, emergency-to-preventive ratio, and PO pipeline status with regenerate option
- **KPI bar** — Total WOs, Open WOs, Emergency WOs (open/in-progress only), total WO spend, Open POs, Pending approval — all with color-coded severity
- **Work orders** — Filter by status/type/priority/asset; per-WO cards with stage badges, cost, assignee, parts info with reservation status, activity log with timestamps; Start/Complete actions with part-used + root cause prompts. Completed WOs grouped in a collapsible section.
- **Purchase orders** — Filter by status/risk/supplier; sorted by required date (most urgent first); grouped by status in workflow order (Pending Approval → Approved → Ordered → Shipped → Draft) with per-group counts; per-PO cards with Approve/Reject (with written reason)/Mark ordered/shipped/received actions (persona-gated); bulk select mode for batch approve/reject; completed/cancelled POs in collapsible expander
- **WO analytics** — Donut chart (count by type), horizontal bar chart (cost by type), bar chart (cost by asset), average costs and completion rate metrics
- **Shortage simulation** — What-if part shortage simulator: select a part, set simulated quantity, view before/after impact on dependent assets and at-risk WOs with color-coded severity change, Apply/Revert controls

**Notifications**: Every WO/PO action triggers email + in-app notifications. PO rejection includes impact context for Shift Supervisor. Part shortage alerts target Procurement Admin.
""")

_section_header("🤖", "WO/PO brief", "#8B5CF6")
if len(all_wo) > 0:
    open_count = len(all_wo[all_wo["STATUS"].isin(["open", "in_progress"])])
    emerg_count = len(all_wo[(all_wo["WO_TYPE"] == "emergency") & (all_wo["STATUS"].isin(["open", "in_progress"]))])
    prev_count = len(all_wo[all_wo["WO_TYPE"] == "preventive"])
    corr_count = len(all_wo[all_wo["WO_TYPE"] == "corrective"])
    total_cost = all_wo["TOTAL_COST"].sum() if "TOTAL_COST" in all_wo.columns else 0
    comp_count = len(all_wo[all_wo["STATUS"] == "completed"])
    comp_rate = round(comp_count / len(all_wo) * 100) if len(all_wo) > 0 else 0
    open_po_count = len(all_po[all_po["STATUS"].isin(["draft", "pending_approval", "approved", "ordered"])]) if len(all_po) > 0 else 0
    pending_po_count = len(all_po[all_po["STATUS"] == "pending_approval"]) if len(all_po) > 0 else 0

    data_block = f"""Total work orders: {len(all_wo)} — {open_count} open, {comp_count} completed ({comp_rate}% completion rate). By type: {emerg_count} emergency, {corr_count} corrective, {prev_count} preventive. Emergency-to-preventive ratio: {emerg_count/max(prev_count,1):.1f}x. Total WO spend: ${total_cost:,.0f}. Purchase orders: {len(all_po)} total, {open_po_count} open, {pending_po_count} pending approval."""

    summary = generate_executive_summary(data_block, "wo_po")
    _glow_card("Operations brief", f'<div style="color:#E0E7FF; font-size:0.82rem; line-height:1.7;">{summary}</div>', "#8B5CF6", "✦")
    if st.button("Regenerate", key="regen_wopo", icon=":material/refresh:"):
        st.session_state.pop("_llm_summary_wo_po", None)
        st.session_state.pop("_llm_hash_wo_po", None)
        st.rerun()


def _render_wo_card(wo, can_manage=False, idx=0):
    wo_type = wo.get("WO_TYPE", "unknown")
    status = st.session_state.get(f"_wo_status_{wo.get('WO_ID')}", wo.get("STATUS", "unknown"))
    priority = wo.get("PRIORITY", "")
    type_icon = ":material/warning:" if wo_type == "emergency" else ":material/build:" if wo_type == "corrective" else ":material/check_circle:"

    with st.container(border=True):
        h1, h2, h3, h4, h5 = st.columns([2, 1, 1, 1, 1])
        with h1:
            st.markdown(f"{type_icon} **{wo['WO_ID']}** — {wo.get('ASSET_NAME', wo['ASSET_ID'])}")
        with h2:
            st.badge(wo_type, color=WO_TYPE_COLOR.get(wo_type, "gray"))
        with h3:
            st.badge(status, color=WO_STATUS_COLOR.get(status, "gray"))
        with h4:
            st.badge(priority, color="red" if priority in ("CRITICAL", "HIGH") else "blue" if priority == "MEDIUM" else "gray")
        with h5:
            cost = wo.get("TOTAL_COST")
            st.caption(fmt_currency(cost) if cost and not pd.isna(cost) else "—")

        detail_cols = st.columns([2, 2, 2])
        with detail_cols[0]:
            st.caption(f"Assigned: {wo.get('ASSIGNED_TO', 'Unassigned')}")
        with detail_cols[1]:
            st.caption(f"Created: {str(wo.get('CREATED_DATE', ''))[:16]}")
        with detail_cols[2]:
            completed = wo.get("COMPLETED_DATE")
            st.caption(f"Completed: {str(completed)[:16]}" if completed and not pd.isna(completed) else "Completed: —")

        asset_id = wo.get("ASSET_ID", "")
        reservations = load_active_reservations()
        has_reservation = len(reservations[(reservations["WO_ID"] == wo.get("WO_ID")) & (reservations["ASSET_ID"] == asset_id)]) > 0 if len(reservations) > 0 else False
        part_atp = 0
        part_name = ""
        part_id = ""
        has_open_po = False

        if len(wo_parts) > 0 and asset_id:
            asset_part = wo_parts[wo_parts["ASSET_ID"] == asset_id]
            if len(asset_part) > 0:
                ap = asset_part.iloc[0]
                part_name = ap.get("PART_NAME", "N/A")
                part_id = ap.get("PART_ID", "")
                risk = ap.get("PROCUREMENT_RISK", "")
                part_atp = ap.get("AVAILABLE_TO_PROMISE", 0)
                po_id = ap.get("OPEN_PO_ID", None)
                has_open_po = po_id is not None and str(po_id) not in ("None", "", "nan")
                po_text = f" | PO: {po_id}" if has_open_po else ""
                pc1, pc2 = st.columns([3, 1])
                with pc1:
                    st.caption(f":material/inventory_2: Part: **{part_name}** | ATP: {part_atp}{po_text}")
                with pc2:
                    if status in ("completed", "cancelled"):
                        pass
                    elif has_reservation:
                        st.badge("RESERVED", color="green")
                    elif risk:
                        st.badge(risk, color=RISK_COLOR.get(risk, "gray"))

                # Reservation aging warning: active reservation > 7 days on open WO
                if has_reservation and status == "open":
                    wo_reservations = reservations[(reservations["WO_ID"] == wo.get("WO_ID")) & (reservations["ASSET_ID"] == asset_id)]
                    if len(wo_reservations) > 0:
                        res_created = pd.to_datetime(wo_reservations.iloc[0].get("CREATED_AT"))
                        if pd.notna(res_created):
                            res_age_days = (pd.Timestamp.now() - res_created).days
                            if res_age_days > 7:
                                st.warning(f"Reservation aging: {res_age_days} days — WO still open. Start work or release part.")

        # WO aging warning: in_progress > 48 hours
        if status == "in_progress":
            created = pd.to_datetime(wo.get("CREATED_DATE"))
            if pd.notna(created):
                wo_age_hours = (pd.Timestamp.now() - created).total_seconds() / 3600
                if wo_age_hours > 72:
                    st.error(f":material/warning: WO in progress for {int(wo_age_hours)}h — escalation recommended")
                elif wo_age_hours > 48:
                    st.warning(f":material/schedule: WO in progress for {int(wo_age_hours)}h — check with technician")

        wo_log = load_wo_activity_log(wo.get("WO_ID", ""))
        if len(wo_log) > 0:
            with st.expander(f"Activity log ({len(wo_log)})", expanded=False):
                for _, entry in wo_log.iterrows():
                    ev = entry.get("EVENT_TYPE", "")
                    icon = ":material/swap_horiz:" if ev == "WO_REASSIGNED" else ":material/mail:" if ev == "WO_FOLLOWUP" else ":material/play_arrow:" if ev == "WO_STARTED" else ":material/check_circle:"
                    ts = str(entry.get("CREATED_AT", ""))[:16]
                    st.caption(f"{icon} **{ts}** — {entry.get('MESSAGE', '')[:200]}")

        if can_manage:
            wo_id = wo["WO_ID"]
            asset_name = wo.get("ASSET_NAME", wo.get("ASSET_ID", ""))

            if status == "open":
                # Gate Start Work by part availability
                if part_id and part_atp <= 0 and not has_open_po:
                    st.caption(":material/block: **Parts unavailable** — cannot start work")
                    if st.button("Alert Procurement", key=f"alert_proc_{wo_id}_{idx}", icon=":material/notification_important:"):
                        _notify("PART_SHORTAGE_ALERT",
                            f"Parts needed for {wo_id}",
                            f"{asset_name} needs {part_name} (ATP=0, no open PO). WO {wo_id} is blocked. Please create a PO or expedite.",
                            wo_id)
                        st.success("Procurement team notified.")
                elif part_id and part_atp <= 0 and has_open_po:
                    st.caption(":material/local_shipping: Parts incoming — PO exists but stock not yet received")
                    if st.button("Start work", key=f"start_{wo_id}_{idx}", icon=":material/play_arrow:"):
                        conn.session().sql(
                            f"UPDATE {DB}.RAW_IT.WORK_ORDERS SET STATUS = 'in_progress' WHERE WO_ID = :1",
                            params=[wo_id],
                        ).collect()
                        _notify("WO_STARTED", f"WO started: {wo_id}", f"{asset_name} — work started by {username} (parts incoming)", wo_id)
                        st.session_state["_wo_action_msg"] = f"Started: {wo_id} — {asset_name} (parts incoming)"
                        st.session_state[f"_wo_status_{wo_id}"] = "in_progress"
                        load_all_work_orders.clear()
                        load_open_work_orders.clear()
                        load_wo_activity_log.clear()
                        st.rerun()
                else:
                    if st.button("Start work", key=f"start_{wo_id}_{idx}", icon=":material/play_arrow:"):
                        conn.session().sql(
                            f"UPDATE {DB}.RAW_IT.WORK_ORDERS SET STATUS = 'in_progress' WHERE WO_ID = :1",
                            params=[wo_id],
                        ).collect()
                        if part_id and part_atp > 0:
                            try:
                                conn.session().sql(
                                    f"CALL {DB}.ANALYTICS.RESERVE_PART_FOR_WORK_ORDER(:1, :2, :3, :4, :5)",
                                    params=[asset_id, wo_id, part_id, 1, str(wo.get("CREATED_DATE", ""))[:10]],
                                ).collect()
                            except Exception:
                                pass
                        _notify("WO_STARTED", f"WO started: {wo_id}", f"{asset_name} — work started by {username}", wo_id)
                        st.session_state["_wo_action_msg"] = f"Started: {wo_id} — {asset_name}"
                        st.session_state[f"_wo_status_{wo_id}"] = "in_progress"
                        load_all_work_orders.clear()
                        load_open_work_orders.clear()
                        load_wo_activity_log.clear()
                        load_wo_parts_info.clear()
                        load_active_reservations.clear()
                        load_procurement_recs.clear()
                        st.rerun()

            elif status == "in_progress":
                # Completion flow with part-used + root cause
                complete_key = f"_wo_completing_{wo_id}"
                if st.session_state.get(complete_key):
                    st.info(f"Completing **{wo_id}** — {asset_name}")
                    part_used = st.radio("Was the part used?", ["Yes — consumed", "No — returned to stock"], key=f"part_used_{wo_id}_{idx}", horizontal=True)
                    root_cause = st.selectbox("Root cause confirmed", [
                        "—", "bearing_wear", "thermal_degradation", "imbalance",
                        "misalignment", "electrical_fault", "false_alarm", "other"
                    ], key=f"root_cause_{wo_id}_{idx}")
                    cc1, cc2 = st.columns(2)
                    with cc1:
                        if st.button("Confirm complete", key=f"confirm_complete_{wo_id}_{idx}", type="primary", icon=":material/check:"):
                            is_part_used = part_used.startswith("Yes")
                            rc_val = root_cause if root_cause != "—" else None
                            conn.session().sql(
                                f"UPDATE {DB}.RAW_IT.WORK_ORDERS SET STATUS = 'completed', COMPLETED_DATE = CURRENT_TIMESTAMP(), ROOT_CAUSE_CONFIRMED = :1, PART_USED = :2 WHERE WO_ID = :3",
                                params=[rc_val, is_part_used, wo_id],
                            ).collect()
                            # Auto-release reservation
                            new_status = 'consumed' if is_part_used else 'released'
                            try:
                                conn.session().sql(
                                    f"UPDATE {DB}.RAW_IT.PART_RESERVATIONS SET STATUS = :1 WHERE WO_ID = :2 AND STATUS = 'active'",
                                    params=[new_status, wo_id],
                                ).collect()
                                # Decrement inventory if part was consumed
                                if is_part_used:
                                    conn.session().sql(
                                        f"UPDATE {DB}.RAW_IT.PARTS_INVENTORY pi SET QUANTITY_ON_HAND = GREATEST(0, pi.QUANTITY_ON_HAND - pr.QUANTITY_RESERVED) FROM {DB}.RAW_IT.PART_RESERVATIONS pr WHERE pr.WO_ID = :1 AND pr.PART_ID = pi.PART_ID AND pr.STATUS = 'consumed'",
                                        params=[wo_id],
                                    ).collect()
                            except Exception:
                                pass
                            _notify("WO_COMPLETED", f"WO completed: {wo_id}",
                                f"{asset_name} — completed by {username}. Part {'consumed' if is_part_used else 'returned to stock'}. Root cause: {rc_val or 'not specified'}.",
                                wo_id)
                            # Inject post-maintenance sensor readings to reset RUL
                            try:
                                conn.session().sql(f"""
                                    INSERT INTO {DB}.RAW_OT.SENSOR_READINGS
                                        (READING_ID, ASSET_ID, TIMESTAMP, VIBRATION_X, VIBRATION_Y, VIBRATION_Z,
                                         TEMPERATURE, RPM, PRESSURE, CURRENT_AMPS, ACOUSTIC_DB, INGESTION_TS)
                                    SELECT
                                        (SELECT COALESCE(MAX(READING_ID),0) FROM {DB}.RAW_OT.SENSOR_READINGS) + SEQ4(),
                                        :1,
                                        DATEADD('minute', -SEQ4(), CURRENT_TIMESTAMP()),
                                        b.AVG_VX * UNIFORM(0.90, 1.10, RANDOM()),
                                        b.AVG_VY * UNIFORM(0.90, 1.10, RANDOM()),
                                        b.AVG_VZ * UNIFORM(0.90, 1.10, RANDOM()),
                                        b.AVG_TEMP * UNIFORM(0.98, 1.02, RANDOM()),
                                        b.AVG_RPM * UNIFORM(0.99, 1.01, RANDOM()),
                                        b.AVG_PRESSURE * UNIFORM(0.98, 1.02, RANDOM()),
                                        b.AVG_AMPS * UNIFORM(0.95, 1.05, RANDOM()),
                                        b.AVG_ACOUSTIC * UNIFORM(0.98, 1.02, RANDOM()),
                                        CURRENT_TIMESTAMP()
                                    FROM TABLE(GENERATOR(ROWCOUNT => 50))
                                    CROSS JOIN (
                                        SELECT AVG(VIBRATION_X) AS AVG_VX, AVG(VIBRATION_Y) AS AVG_VY, AVG(VIBRATION_Z) AS AVG_VZ,
                                               AVG(TEMPERATURE) AS AVG_TEMP, AVG(RPM) AS AVG_RPM, AVG(PRESSURE) AS AVG_PRESSURE,
                                               AVG(CURRENT_AMPS) AS AVG_AMPS, AVG(ACOUSTIC_DB) AS AVG_ACOUSTIC
                                        FROM {DB}.RAW_OT.SENSOR_READINGS
                                        WHERE ASSET_ID = :2 AND TIMESTAMP < DATEADD('month', -3, CURRENT_TIMESTAMP())
                                    ) b
                                """, params=[asset_id, asset_id]).collect()
                            except Exception:
                                pass
                            # Log feedback for closed-loop model improvement
                            if rc_val:
                                try:
                                    conn.session().sql(
                                        f"CALL {DB}.ML_MODELS.LOG_FEEDBACK(:1, :2, :3, :4)",
                                        params=[wo_id, wo.get("ASSET_ID", ""), rc_val, username],
                                    ).collect()
                                except Exception:
                                    pass
                            st.session_state.pop(complete_key, None)
                            st.session_state["_wo_action_msg"] = f"Completed: {wo_id} — {asset_name}"
                            st.session_state[f"_wo_status_{wo_id}"] = "completed"
                            load_all_work_orders.clear()
                            load_open_work_orders.clear()
                            load_wo_activity_log.clear()
                            load_wo_parts_info.clear()
                            load_active_reservations.clear()
                            load_procurement_recs.clear()
                            load_live_predictions.clear()
                            st.rerun()
                    with cc2:
                        if st.button("Cancel", key=f"cancel_complete_{wo_id}_{idx}", icon=":material/undo:"):
                            st.session_state.pop(complete_key, None)
                            st.rerun()
                else:
                    if st.button("Complete", key=f"complete_{wo_id}_{idx}", type="primary", icon=":material/check:"):
                        st.session_state[complete_key] = True
                        st.rerun()



def _get_wo_start_eligibility(wo_row):
    """Check if a WO can be started based on ATP and PO status. Returns (can_start, reason)."""
    asset_id = wo_row.get("ASSET_ID", "")
    part_id = ""
    part_atp = 0
    has_open_po = False
    if len(wo_parts) > 0 and asset_id:
        asset_part = wo_parts[wo_parts["ASSET_ID"] == asset_id]
        if len(asset_part) > 0:
            ap = asset_part.iloc[0]
            part_id = ap.get("PART_ID", "")
            part_atp = ap.get("AVAILABLE_TO_PROMISE", 0)
            po_id = ap.get("OPEN_PO_ID", None)
            has_open_po = po_id is not None and str(po_id) not in ("None", "", "nan")
    if part_id and part_atp <= 0 and not has_open_po:
        return False, "No parts (ATP=0, no open PO)"
    return True, ""


def _execute_wo_start(wo_row):
    """Execute the start-work logic for a single WO. Returns success message."""
    wo_id = wo_row["WO_ID"]
    asset_id = wo_row.get("ASSET_ID", "")
    asset_name = wo_row.get("ASSET_NAME", asset_id)
    conn.session().sql(
        f"UPDATE {DB}.RAW_IT.WORK_ORDERS SET STATUS = 'in_progress' WHERE WO_ID = :1",
        params=[wo_id],
    ).collect()
    # Reserve part if available
    if len(wo_parts) > 0 and asset_id:
        asset_part = wo_parts[wo_parts["ASSET_ID"] == asset_id]
        if len(asset_part) > 0:
            ap = asset_part.iloc[0]
            part_id = ap.get("PART_ID", "")
            part_atp = ap.get("AVAILABLE_TO_PROMISE", 0)
            if part_id and part_atp > 0:
                try:
                    conn.session().sql(
                        f"CALL {DB}.ANALYTICS.RESERVE_PART_FOR_WORK_ORDER(:1, :2, :3, :4, :5)",
                        params=[asset_id, wo_id, part_id, 1, str(wo_row.get("CREATED_DATE", ""))[:10]],
                    ).collect()
                except Exception:
                    pass
    _notify("WO_STARTED", f"WO started: {wo_id}", f"{asset_name} — work started by {username}", wo_id)
    st.session_state[f"_wo_status_{wo_id}"] = "in_progress"
    return wo_id


def _execute_wo_complete(wo_row, is_part_used, rc_val):
    """Execute the complete logic for a single WO. Returns WO ID."""
    wo_id = wo_row["WO_ID"]
    asset_id = wo_row.get("ASSET_ID", "")
    asset_name = wo_row.get("ASSET_NAME", asset_id)
    conn.session().sql(
        f"UPDATE {DB}.RAW_IT.WORK_ORDERS SET STATUS = 'completed', COMPLETED_DATE = CURRENT_TIMESTAMP(), ROOT_CAUSE_CONFIRMED = :1, PART_USED = :2 WHERE WO_ID = :3",
        params=[rc_val, is_part_used, wo_id],
    ).collect()
    new_status = 'consumed' if is_part_used else 'released'
    try:
        conn.session().sql(
            f"UPDATE {DB}.RAW_IT.PART_RESERVATIONS SET STATUS = :1 WHERE WO_ID = :2 AND STATUS = 'active'",
            params=[new_status, wo_id],
        ).collect()
        if is_part_used:
            conn.session().sql(
                f"UPDATE {DB}.RAW_IT.PARTS_INVENTORY pi SET QUANTITY_ON_HAND = GREATEST(0, pi.QUANTITY_ON_HAND - pr.QUANTITY_RESERVED) FROM {DB}.RAW_IT.PART_RESERVATIONS pr WHERE pr.WO_ID = :1 AND pr.PART_ID = pi.PART_ID AND pr.STATUS = 'consumed'",
                params=[wo_id],
            ).collect()
    except Exception:
        pass
    _notify("WO_COMPLETED", f"WO completed: {wo_id}",
        f"{asset_name} — completed by {username}. Part {'consumed' if is_part_used else 'returned to stock'}. Root cause: {rc_val or 'not specified'}.",
        wo_id)
    try:
        conn.session().sql(f"""
            INSERT INTO {DB}.RAW_OT.SENSOR_READINGS
                (READING_ID, ASSET_ID, TIMESTAMP, VIBRATION_X, VIBRATION_Y, VIBRATION_Z,
                 TEMPERATURE, RPM, PRESSURE, CURRENT_AMPS, ACOUSTIC_DB, INGESTION_TS)
            SELECT
                (SELECT COALESCE(MAX(READING_ID),0) FROM {DB}.RAW_OT.SENSOR_READINGS) + SEQ4(),
                :1,
                DATEADD('minute', -SEQ4(), CURRENT_TIMESTAMP()),
                b.AVG_VX * UNIFORM(0.90, 1.10, RANDOM()),
                b.AVG_VY * UNIFORM(0.90, 1.10, RANDOM()),
                b.AVG_VZ * UNIFORM(0.90, 1.10, RANDOM()),
                b.AVG_TEMP * UNIFORM(0.98, 1.02, RANDOM()),
                b.AVG_RPM * UNIFORM(0.99, 1.01, RANDOM()),
                b.AVG_PRESSURE * UNIFORM(0.98, 1.02, RANDOM()),
                b.AVG_AMPS * UNIFORM(0.95, 1.05, RANDOM()),
                b.AVG_ACOUSTIC * UNIFORM(0.98, 1.02, RANDOM()),
                CURRENT_TIMESTAMP()
            FROM TABLE(GENERATOR(ROWCOUNT => 50))
            CROSS JOIN (
                SELECT AVG(VIBRATION_X) AS AVG_VX, AVG(VIBRATION_Y) AS AVG_VY, AVG(VIBRATION_Z) AS AVG_VZ,
                       AVG(TEMPERATURE) AS AVG_TEMP, AVG(RPM) AS AVG_RPM, AVG(PRESSURE) AS AVG_PRESSURE,
                       AVG(CURRENT_AMPS) AS AVG_AMPS, AVG(ACOUSTIC_DB) AS AVG_ACOUSTIC
                FROM {DB}.RAW_OT.SENSOR_READINGS
                WHERE ASSET_ID = :2 AND TIMESTAMP < DATEADD('month', -3, CURRENT_TIMESTAMP())
            ) b
        """, params=[asset_id, asset_id]).collect()
    except Exception:
        pass
    if rc_val:
        try:
            conn.session().sql(
                f"CALL {DB}.ML_MODELS.LOG_FEEDBACK(:1, :2, :3, :4)",
                params=[wo_id, asset_id, rc_val, username],
            ).collect()
        except Exception:
            pass
    st.session_state[f"_wo_status_{wo_id}"] = "completed"
    return wo_id


def _clear_wo_caches():
    load_all_work_orders.clear()
    load_open_work_orders.clear()
    load_wo_activity_log.clear()
    load_wo_parts_info.clear()
    load_active_reservations.clear()
    load_procurement_recs.clear()
    load_live_predictions.clear()


def _render_bulk_wo_bar(filtered_df):
    """Render the bulk action bar for work orders."""
    selected = st.session_state["_bulk_wo_selected"]
    if not selected:
        return

    sel_wos = filtered_df[filtered_df["WO_ID"].isin(selected)]
    if len(sel_wos) == 0:
        return

    with st.container(border=True):
        st.markdown(f":material/checklist: **{len(sel_wos)} work order{'s' if len(sel_wos) != 1 else ''} selected**")

        # Classify by effective status
        eff_statuses = sel_wos["WO_ID"].apply(lambda wid: st.session_state.get(f"_wo_status_{wid}", sel_wos.loc[sel_wos["WO_ID"] == wid, "STATUS"].iloc[0]))
        open_sel = sel_wos[eff_statuses == "open"]
        ip_sel = sel_wos[eff_statuses == "in_progress"]

        # ATP eligibility for open WOs
        startable = []
        blocked = []
        for _, wo in open_sel.iterrows():
            can_start, reason = _get_wo_start_eligibility(wo)
            if can_start:
                startable.append(wo)
            else:
                blocked.append((wo, reason))

        bcol1, bcol2, bcol3 = st.columns([1, 1, 1])

        with bcol1:
            if len(open_sel) > 0:
                label = f"Start {len(startable)} of {len(open_sel)}" if blocked else f"Start {len(startable)}"
                if st.button(label, key="bulk_start_wo", type="primary", icon=":material/play_arrow:", disabled=len(startable) == 0):
                    started = []
                    for wo in startable:
                        try:
                            started.append(_execute_wo_start(wo))
                        except Exception:
                            pass
                    _clear_wo_caches()
                    blocked_ids = [b[0]["WO_ID"] for b in blocked]
                    _log_bulk_operation("BULK_START", "WO", started + blocked_ids,
                        len(open_sel), len(started), len(blocked),
                        "ATP=0, no open PO" if blocked else None)
                    if blocked:
                        st.session_state["_wo_action_msg"] = f"Bulk started {len(started)} WO(s). {len(blocked)} blocked (no parts/no PO)."
                    else:
                        st.session_state["_wo_action_msg"] = f"Bulk started {len(started)} WO(s): {', '.join(started)}"
                    st.session_state["_bulk_wo_selected"] = set()
                    st.rerun()
                if blocked:
                    st.caption(f"{len(blocked)} blocked: no parts/no PO")
            else:
                st.caption("No open WOs selected")

        with bcol2:
            if len(ip_sel) > 0:
                if st.session_state.get("_bulk_complete_mode"):
                    pass  # handled below
                elif st.button(f"Complete {len(ip_sel)}", key="bulk_complete_wo", type="primary", icon=":material/check:"):
                    st.session_state["_bulk_complete_mode"] = True
                    st.rerun()
            else:
                st.caption("No in-progress WOs selected")

        with bcol3:
            if st.button("Deselect all", key="bulk_deselect_wo", icon=":material/deselect:"):
                st.session_state["_bulk_wo_selected"] = set()
                st.session_state["_bulk_complete_mode"] = False
                st.rerun()

        # Bulk complete confirmation flow
        if st.session_state.get("_bulk_complete_mode") and len(ip_sel) > 0:
            st.divider()
            st.info(f"Completing **{len(ip_sel)}** work order(s): {', '.join(ip_sel['WO_ID'].tolist())}")
            part_used = st.radio("Was the part used? (applies to all)", ["Yes — consumed", "No — returned to stock"], key="bulk_part_used", horizontal=True)
            root_cause = st.selectbox("Root cause confirmed (applies to all)", [
                "—", "bearing_wear", "thermal_degradation", "imbalance",
                "misalignment", "electrical_fault", "false_alarm", "other"
            ], key="bulk_root_cause")
            cc1, cc2 = st.columns(2)
            with cc1:
                if st.button("Confirm complete all", key="bulk_confirm_complete", type="primary", icon=":material/check:"):
                    is_part_used = part_used.startswith("Yes")
                    rc_val = root_cause if root_cause != "—" else None
                    completed = []
                    for _, wo in ip_sel.iterrows():
                        try:
                            completed.append(_execute_wo_complete(wo, is_part_used, rc_val))
                        except Exception:
                            pass
                    _clear_wo_caches()
                    _log_bulk_operation("BULK_COMPLETE", "WO", completed,
                        len(ip_sel), len(completed), 0,
                        details={"root_cause": rc_val, "part_used": is_part_used})
                    st.session_state["_wo_action_msg"] = f"Bulk completed {len(completed)} WO(s): {', '.join(completed)}"
                    st.session_state["_bulk_wo_selected"] = set()
                    st.session_state["_bulk_complete_mode"] = False
                    st.rerun()
            with cc2:
                if st.button("Cancel", key="bulk_cancel_complete", icon=":material/undo:"):
                    st.session_state["_bulk_complete_mode"] = False
                    st.rerun()


def _clear_po_caches():
    load_all_purchase_orders.clear()
    try:
        load_procurement_recs.clear()
    except Exception:
        pass
    try:
        load_open_pos.clear()
    except Exception:
        pass
    try:
        load_parts_atp.clear()
    except Exception:
        pass


def _render_po_card(po, can_manage=False, idx=0):
    status = st.session_state.get(f"_po_status_{po.get('PO_ID')}", po.get("STATUS", "unknown"))
    risk = po.get("PROCUREMENT_RISK", "")

    with st.container(border=True):
        h1, h2, h3, h4 = st.columns([2, 1, 1, 1])
        with h1:
            st.markdown(f":material/receipt_long: **{po['PO_ID']}**")
            st.caption(f"{po.get('PART_NAME', po.get('PART_ID', ''))} for {po.get('ASSET_NAME', po.get('ASSET_ID', ''))}")
        with h2:
            st.badge(status, color=PO_STATUS_COLOR.get(status, "gray"))
        with h3:
            if risk:
                from app_pages._shared import RISK_COLOR
                st.badge(risk, color=RISK_COLOR.get(risk, "gray"))
        with h4:
            cost = po.get("TOTAL_COST")
            st.caption(fmt_currency(cost) if cost and not pd.isna(cost) else "—")

        detail_cols = st.columns([2, 2, 2])
        with detail_cols[0]:
            st.caption(f"Supplier: {po.get('SUPPLIER_NAME', 'N/A')}")
        with detail_cols[1]:
            st.caption(f"Required by: {str(po.get('REQUIRED_BY_DATE', ''))[:10]}")
        with detail_cols[2]:
            st.caption(f"Expected: {str(po.get('EXPECTED_ARRIVAL_DATE', ''))[:10]}")

        # Show rejection reason on cancelled POs
        if status == "cancelled":
            reason = po.get("REJECTION_REASON", "")
            rejected_by = po.get("REJECTED_BY", "")
            rejected_at = po.get("REJECTED_AT", "")
            if reason and str(reason) not in ("None", "", "nan"):
                st.caption(f":material/block: Rejected by **{rejected_by}** — {reason}")

        if can_manage:
            po_part = po.get("PART_NAME", po.get("PART_ID", ""))
            po_asset = po.get("ASSET_NAME", po.get("ASSET_ID", ""))
            po_id = po["PO_ID"]
            if status == "pending_approval":
                # Check if this PO is pending rejection (user clicked Reject, needs comment)
                reject_key = f"_po_rejecting_{po_id}"
                if st.session_state.get(reject_key):
                    st.warning(f"Rejecting **{po_id}** — this will cancel the order for {po_part} ({po_asset}).")
                    reject_reason = st.text_area("Rejection reason (required)", key=f"reject_reason_{po_id}_{idx}", placeholder="e.g., Budget exceeded, alternative sourced, duplicate order...")
                    rc1, rc2 = st.columns(2)
                    with rc1:
                        if st.button("Confirm rejection", key=f"confirm_reject_{po_id}_{idx}", type="primary", icon=":material/block:"):
                            if not reject_reason or not reject_reason.strip():
                                st.error("Rejection reason is required.")
                            else:
                                conn.session().sql(
                                    f"UPDATE {DB}.RAW_IT.PURCHASE_ORDERS SET STATUS = 'cancelled', REJECTION_REASON = :1, REJECTED_BY = :2, REJECTED_AT = CURRENT_TIMESTAMP() WHERE PO_ID = :3",
                                    params=[reject_reason.strip(), username, po_id],
                                ).collect()
                                # Impact notification to Shift Supervisor
                                rul_info = f"RUL: {po.get('RUL_HOURS_AT_ORDER', 'N/A')}h" if po.get('RUL_HOURS_AT_ORDER') else ""
                                impact_msg = f"PO {po_id} REJECTED by {username}. Part: {po_part} for {po_asset}. {rul_info}. Reason: {reject_reason.strip()}. This asset may not receive parts before predicted failure — review procurement alternatives."
                                _notify("PO_REJECTED", f"PO rejected: {po_id} — action needed", impact_msg, po_id)
                                st.session_state.pop(reject_key, None)
                                st.session_state["_po_action_msg"] = f"Rejected: {po_id} — {po_part} for {po_asset}"
                                st.session_state[f"_po_status_{po_id}"] = "cancelled"
                                _clear_po_caches()
                                st.rerun()
                    with rc2:
                        if st.button("Cancel", key=f"cancel_reject_{po_id}_{idx}", icon=":material/undo:"):
                            st.session_state.pop(reject_key, None)
                            st.rerun()
                else:
                    bc1, bc2 = st.columns(2)
                    with bc1:
                        if st.button("Approve", key=f"approve_{po_id}_{idx}", type="primary", icon=":material/thumb_up:"):
                            conn.session().sql(
                                f"UPDATE {DB}.RAW_IT.PURCHASE_ORDERS SET STATUS = 'approved' WHERE PO_ID = :1",
                                params=[po_id],
                            ).collect()
                            _notify("PO_APPROVED", f"PO approved: {po_id}", f"{po_part} for {po_asset} — approved by {username}", po_id)
                            st.session_state["_po_action_msg"] = f"Approved: {po_id} — {po_part} for {po_asset}"
                            st.session_state[f"_po_status_{po_id}"] = "approved"
                            _clear_po_caches()
                            st.rerun()
                    with bc2:
                        if st.button("Reject", key=f"reject_{po_id}_{idx}", icon=":material/thumb_down:"):
                            st.session_state[reject_key] = True
                            st.rerun()
            elif status in ("approved", "ordered", "shipped"):
                po_cols = st.columns(3 if status == "approved" else 2)
                if status == "approved":
                    with po_cols[0]:
                        if st.button("Mark ordered", key=f"order_{po_id}_{idx}", icon=":material/shopping_cart:"):
                            conn.session().sql(
                                f"UPDATE {DB}.RAW_IT.PURCHASE_ORDERS SET STATUS = 'ordered' WHERE PO_ID = :1",
                                params=[po_id],
                            ).collect()
                            st.session_state["_po_action_msg"] = f"Ordered: {po_id}"
                            st.session_state[f"_po_status_{po_id}"] = "ordered"
                            _clear_po_caches()
                            st.rerun()
                if status in ("approved", "ordered"):
                    col_idx = 1 if status == "approved" else 0
                    with po_cols[col_idx]:
                        if st.button("Mark shipped", key=f"ship_{po_id}_{idx}", icon=":material/local_shipping:"):
                            conn.session().sql(
                                f"UPDATE {DB}.RAW_IT.PURCHASE_ORDERS SET STATUS = 'shipped' WHERE PO_ID = :1",
                                params=[po_id],
                            ).collect()
                            st.session_state["_po_action_msg"] = f"Shipped: {po_id}"
                            st.session_state[f"_po_status_{po_id}"] = "shipped"
                            _clear_po_caches()
                            st.rerun()
                recv_col_idx = 2 if status == "approved" else 1
                with po_cols[recv_col_idx]:
                    if st.button("Mark received", key=f"recv_{po_id}_{idx}", type="primary", icon=":material/inventory:"):
                        conn.session().sql(
                            f"UPDATE {DB}.RAW_IT.PURCHASE_ORDERS SET STATUS = 'received' WHERE PO_ID = :1",
                            params=[po_id],
                        ).collect()
                        # Increment inventory for received parts
                        try:
                            conn.session().sql(
                                f"UPDATE {DB}.RAW_IT.PARTS_INVENTORY pi SET QUANTITY_ON_HAND = pi.QUANTITY_ON_HAND + pol.QUANTITY_ORDERED FROM {DB}.RAW_IT.PURCHASE_ORDER_LINES pol WHERE pol.PO_ID = :1 AND pol.PART_ID = pi.PART_ID",
                                params=[po_id],
                            ).collect()
                        except Exception:
                            pass
                        _notify("PO_RECEIVED", f"PO received: {po_id}", f"{po_part} for {po_asset} — received by {username}", po_id)
                        st.session_state["_po_action_msg"] = f"Received: {po_id} — {po_part} for {po_asset}"
                        st.session_state[f"_po_status_{po_id}"] = "received"
                        _clear_po_caches()
                        st.rerun()


def _execute_po_approve(po_row):
    po_id = po_row["PO_ID"]
    po_part = po_row.get("PART_NAME", po_row.get("PART_ID", ""))
    po_asset = po_row.get("ASSET_NAME", po_row.get("ASSET_ID", ""))
    conn.session().sql(
        f"UPDATE {DB}.RAW_IT.PURCHASE_ORDERS SET STATUS = 'approved' WHERE PO_ID = :1",
        params=[po_id],
    ).collect()
    _notify("PO_APPROVED", f"PO approved: {po_id}", f"{po_part} for {po_asset} — approved by {username}", po_id)
    st.session_state[f"_po_status_{po_id}"] = "approved"
    return po_id


def _execute_po_reject(po_row, reject_reason):
    po_id = po_row["PO_ID"]
    po_part = po_row.get("PART_NAME", po_row.get("PART_ID", ""))
    po_asset = po_row.get("ASSET_NAME", po_row.get("ASSET_ID", ""))
    conn.session().sql(
        f"UPDATE {DB}.RAW_IT.PURCHASE_ORDERS SET STATUS = 'cancelled', REJECTION_REASON = :1, REJECTED_BY = :2, REJECTED_AT = CURRENT_TIMESTAMP() WHERE PO_ID = :3",
        params=[reject_reason, username, po_id],
    ).collect()
    rul_info = f"RUL: {po_row.get('RUL_HOURS_AT_ORDER', 'N/A')}h" if po_row.get('RUL_HOURS_AT_ORDER') else ""
    impact_msg = f"PO {po_id} REJECTED by {username}. Part: {po_part} for {po_asset}. {rul_info}. Reason: {reject_reason}. This asset may not receive parts before predicted failure — review procurement alternatives."
    _notify("PO_REJECTED", f"PO rejected: {po_id} — action needed", impact_msg, po_id)
    st.session_state[f"_po_status_{po_id}"] = "cancelled"
    return po_id


def _execute_po_status_change(po_row, new_status):
    po_id = po_row["PO_ID"]
    po_part = po_row.get("PART_NAME", po_row.get("PART_ID", ""))
    po_asset = po_row.get("ASSET_NAME", po_row.get("ASSET_ID", ""))
    conn.session().sql(
        f"UPDATE {DB}.RAW_IT.PURCHASE_ORDERS SET STATUS = :1 WHERE PO_ID = :2",
        params=[new_status, po_id],
    ).collect()
    if new_status == "received":
        try:
            conn.session().sql(
                f"UPDATE {DB}.RAW_IT.PARTS_INVENTORY pi SET QUANTITY_ON_HAND = pi.QUANTITY_ON_HAND + pol.QUANTITY_ORDERED FROM {DB}.RAW_IT.PURCHASE_ORDER_LINES pol WHERE pol.PO_ID = :1 AND pol.PART_ID = pi.PART_ID",
                params=[po_id],
            ).collect()
        except Exception:
            pass
        _notify("PO_RECEIVED", f"PO received: {po_id}", f"{po_part} for {po_asset} — received by {username}", po_id)
    st.session_state[f"_po_status_{po_id}"] = new_status
    return po_id


def _render_bulk_po_bar(filtered_df):
    """Render the bulk action bar for purchase orders."""
    selected = st.session_state["_bulk_po_selected"]
    if not selected:
        return

    sel_pos = filtered_df[filtered_df["PO_ID"].isin(selected)]
    if len(sel_pos) == 0:
        return

    with st.container(border=True):
        st.markdown(f":material/checklist: **{len(sel_pos)} purchase order{'s' if len(sel_pos) != 1 else ''} selected**")

        eff_statuses = sel_pos["PO_ID"].apply(lambda pid: st.session_state.get(f"_po_status_{pid}", sel_pos.loc[sel_pos["PO_ID"] == pid, "STATUS"].iloc[0]))
        pending_sel = sel_pos[eff_statuses == "pending_approval"]
        approved_sel = sel_pos[eff_statuses == "approved"]
        ordered_sel = sel_pos[eff_statuses == "ordered"]
        shipped_sel = sel_pos[eff_statuses == "shipped"]
        # Receivable = approved + ordered + shipped
        receivable_sel = sel_pos[eff_statuses.isin(["approved", "ordered", "shipped"])]

        bcol1, bcol2, bcol3, bcol4 = st.columns([1, 1, 1, 1])

        with bcol1:
            if len(pending_sel) > 0:
                if st.button(f"Approve {len(pending_sel)}", key="bulk_approve_po", type="primary", icon=":material/thumb_up:"):
                    approved = []
                    for _, po in pending_sel.iterrows():
                        try:
                            approved.append(_execute_po_approve(po))
                        except Exception:
                            pass
                    _clear_po_caches()
                    _log_bulk_operation("BULK_APPROVE", "PO", approved,
                        len(pending_sel), len(approved), 0)
                    st.session_state["_po_action_msg"] = f"Bulk approved {len(approved)} PO(s): {', '.join(approved)}"
                    st.session_state["_bulk_po_selected"] = set()
                    st.rerun()
            else:
                st.caption("No pending POs")

        with bcol2:
            if len(pending_sel) > 0:
                if st.session_state.get("_bulk_reject_mode"):
                    pass  # handled below
                elif st.button(f"Reject {len(pending_sel)}", key="bulk_reject_po", icon=":material/thumb_down:"):
                    st.session_state["_bulk_reject_mode"] = True
                    st.rerun()

        with bcol3:
            if len(receivable_sel) > 0:
                if st.button(f"Mark received {len(receivable_sel)}", key="bulk_receive_po", type="primary", icon=":material/inventory:"):
                    received = []
                    for _, po in receivable_sel.iterrows():
                        try:
                            received.append(_execute_po_status_change(po, "received"))
                        except Exception:
                            pass
                    _clear_po_caches()
                    _log_bulk_operation("BULK_RECEIVE", "PO", received,
                        len(receivable_sel), len(received), 0)
                    st.session_state["_po_action_msg"] = f"Bulk received {len(received)} PO(s): {', '.join(received)}"
                    st.session_state["_bulk_po_selected"] = set()
                    st.rerun()
            else:
                st.caption("No receivable POs")

        with bcol4:
            if st.button("Deselect all", key="bulk_deselect_po", icon=":material/deselect:"):
                st.session_state["_bulk_po_selected"] = set()
                st.session_state["_bulk_reject_mode"] = False
                st.rerun()

        # Additional status transitions row
        if len(approved_sel) > 0 or len(ordered_sel) > 0:
            sc1, sc2 = st.columns(2)
            with sc1:
                if len(approved_sel) > 0:
                    if st.button(f"Mark ordered {len(approved_sel)}", key="bulk_order_po", icon=":material/shopping_cart:"):
                        done = []
                        for _, po in approved_sel.iterrows():
                            try:
                                done.append(_execute_po_status_change(po, "ordered"))
                            except Exception:
                                pass
                        _clear_po_caches()
                        _log_bulk_operation("BULK_ORDER", "PO", done,
                            len(approved_sel), len(done), 0)
                        st.session_state["_po_action_msg"] = f"Bulk ordered {len(done)} PO(s)"
                        st.session_state["_bulk_po_selected"] = set()
                        st.rerun()
            with sc2:
                shippable = sel_pos[eff_statuses.isin(["approved", "ordered"])]
                if len(shippable) > 0:
                    if st.button(f"Mark shipped {len(shippable)}", key="bulk_ship_po", icon=":material/local_shipping:"):
                        done = []
                        for _, po in shippable.iterrows():
                            try:
                                done.append(_execute_po_status_change(po, "shipped"))
                            except Exception:
                                pass
                        _clear_po_caches()
                        _log_bulk_operation("BULK_SHIP", "PO", done,
                            len(shippable), len(done), 0)
                        st.session_state["_po_action_msg"] = f"Bulk shipped {len(done)} PO(s)"
                        st.session_state["_bulk_po_selected"] = set()
                        st.rerun()

        # Bulk reject confirmation flow
        if st.session_state.get("_bulk_reject_mode") and len(pending_sel) > 0:
            st.divider()
            st.warning(f"Rejecting **{len(pending_sel)}** PO(s): {', '.join(pending_sel['PO_ID'].tolist())}")
            reject_reason = st.text_area("Rejection reason (required, applies to all)", key="bulk_reject_reason", placeholder="e.g., Budget exceeded, alternative sourced, duplicate order...")
            rc1, rc2 = st.columns(2)
            with rc1:
                if st.button("Confirm reject all", key="bulk_confirm_reject", type="primary", icon=":material/block:"):
                    if not reject_reason or not reject_reason.strip():
                        st.error("Rejection reason is required.")
                    else:
                        rejected = []
                        for _, po in pending_sel.iterrows():
                            try:
                                rejected.append(_execute_po_reject(po, reject_reason.strip()))
                            except Exception:
                                pass
                        _clear_po_caches()
                        _log_bulk_operation("BULK_REJECT", "PO", rejected,
                            len(pending_sel), len(rejected), 0,
                            details={"rejection_reason": reject_reason.strip()})
                        st.session_state["_po_action_msg"] = f"Bulk rejected {len(rejected)} PO(s): {', '.join(rejected)}"
                        st.session_state["_bulk_po_selected"] = set()
                        st.session_state["_bulk_reject_mode"] = False
                        st.rerun()
            with rc2:
                if st.button("Cancel", key="bulk_cancel_reject", icon=":material/undo:"):
                    st.session_state["_bulk_reject_mode"] = False
                    st.rerun()


# ═══════════════════════════════════════════════════════════════
# HEADER
# ═══════════════════════════════════════════════════════════════
open_wo = all_wo[all_wo["STATUS"].isin(["open", "in_progress"])] if len(all_wo) > 0 else pd.DataFrame()
completed_wo = all_wo[all_wo["STATUS"] == "completed"] if len(all_wo) > 0 else pd.DataFrame()
emergency_wo = all_wo[(all_wo["WO_TYPE"] == "emergency") & (all_wo["STATUS"].isin(["open", "in_progress"]))] if len(all_wo) > 0 else pd.DataFrame()
total_wo_cost = all_wo["TOTAL_COST"].sum() if len(all_wo) > 0 and "TOTAL_COST" in all_wo.columns else 0
open_po = all_po[all_po["STATUS"].isin(["draft", "pending_approval", "approved", "ordered"])] if len(all_po) > 0 else pd.DataFrame()
pending_po = all_po[all_po["STATUS"] == "pending_approval"] if len(all_po) > 0 else pd.DataFrame()

if len(emergency_wo) > 0:
    wo_status, wo_color, wo_icon = "URGENT", "#EF4444", "🔴"
elif len(open_wo) > 0:
    wo_status, wo_color, wo_icon = "ACTIVE", "#F59E0B", "🟡"
else:
    wo_status, wo_color, wo_icon = "CLEAR", "#10B981", "🟢"

persona_label = PERSONA_CONFIG.get(persona, {}).get('label', persona)
st.html(f"""
<div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:4px; flex-wrap:wrap; gap:10px;">
    <div style="display:flex; align-items:center; gap:14px;">
        <div style="font-size:1.5rem; font-weight:800; color:#E0E7FF;">📋 WO / PO console</div>
        <div style="padding:4px 14px; border-radius:12px; font-size:0.65rem; font-weight:700;
                    text-transform:uppercase; letter-spacing:0.08em;
                    background:{wo_color}18; color:{wo_color}; border:1px solid {wo_color}44;
                    box-shadow: 0 0 12px {wo_color}22;">
            {wo_icon} {wo_status}
        </div>
    </div>
    <div style="display:flex; align-items:center; gap:8px;">
        <div style="padding:2px 10px; border-radius:8px; font-size:0.6rem; font-weight:600;
                    background:#8B5CF618; color:#8B5CF6; border:1px solid #8B5CF633;">{persona_label}</div>
    </div>
</div>
""")
st.caption(f"Manage WOs and POs — viewing as **{persona_label}**")

# ═══════════════════════════════════════════════════════════════
# KPI BAR (styled HTML cards)
# ═══════════════════════════════════════════════════════════════
_section_header("📊", "Key metrics")

kpi_items = [
    ("Total WOs", len(all_wo), "#00D4FF"),
    ("Open WOs", len(open_wo), "#3B82F6"),
    ("Emergency", len(emergency_wo), "#EF4444"),
    ("WO spend", fmt_currency(total_wo_cost), "#F59E0B"),
]
if CAN_VIEW_PO:
    kpi_items.append(("Open POs", len(open_po), "#8B5CF6"))
    kpi_items.append(("Pending approval", len(pending_po), "#F59E0B"))

kpi_cols = st.columns(len(kpi_items))
for col, (label, val, color) in zip(kpi_cols, kpi_items):
    with col:
        st.html(f"""
        <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                    border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
            <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
            <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
        </div>
        """)

# ═══════════════════════════════════════════════════════════════
# TABS
# ═══════════════════════════════════════════════════════════════
tabs = ["Work orders"]
if CAN_VIEW_PO:
    tabs.append("Purchase orders")
tabs.append("WO analytics")
if CAN_MANAGE_WO or CAN_MANAGE_PO:
    tabs.append("Shortage simulation")

section = st.segmented_control("View", tabs, default="Work orders")

# =============================================
# WORK ORDERS TAB
# =============================================
if section == "Work orders":
    if "_wo_action_msg" in st.session_state:
        st.success(st.session_state.pop("_wo_action_msg"), icon=":material/check_circle:")
    if len(all_wo) == 0:
        st.info("No work orders found.")
    else:
        # Filters
        fc1, fc2, fc3, fc4 = st.columns(4)
        with fc1:
            f_status = st.multiselect("Status", all_wo["STATUS"].unique().tolist(), default=all_wo["STATUS"].unique().tolist(), key="wo_f_status")
        with fc2:
            f_type = st.multiselect("Type", all_wo["WO_TYPE"].unique().tolist(), default=all_wo["WO_TYPE"].unique().tolist(), key="wo_f_type")
        with fc3:
            pri_options = all_wo["PRIORITY"].dropna().unique().tolist()
            f_priority = st.multiselect("Priority", pri_options, default=pri_options, key="wo_f_pri")
        with fc4:
            f_asset = st.multiselect("Asset", all_wo["ASSET_NAME"].unique().tolist(), default=all_wo["ASSET_NAME"].unique().tolist(), key="wo_f_asset")

        filtered = all_wo[
            all_wo["STATUS"].isin(f_status) &
            all_wo["WO_TYPE"].isin(f_type) &
            (all_wo["PRIORITY"].isin(f_priority) | all_wo["PRIORITY"].isna()) &
            all_wo["ASSET_NAME"].isin(f_asset)
        ]

        # Bulk select toggle (only for personas that can manage)
        bulk_wo_active = False
        if CAN_MANAGE_WO and len(filtered) > 0:
            active_for_bulk = filtered[~filtered["STATUS"].isin(["completed", "cancelled"])]
            if len(active_for_bulk) > 0:
                tc1, tc2 = st.columns([1, 3])
                with tc1:
                    bulk_wo_active = st.toggle("Select multiple", key="bulk_wo_toggle", value=st.session_state["_bulk_wo_mode"])
                    if bulk_wo_active != st.session_state["_bulk_wo_mode"]:
                        st.session_state["_bulk_wo_mode"] = bulk_wo_active
                        if not bulk_wo_active:
                            st.session_state["_bulk_wo_selected"] = set()
                            st.session_state["_bulk_complete_mode"] = False
                        st.rerun()
                if bulk_wo_active:
                    with tc2:
                        sa1, sa2 = st.columns(2)
                        with sa1:
                            if st.button("Select all visible", key="wo_select_all", icon=":material/select_all:"):
                                st.session_state["_bulk_wo_selected"] = set(active_for_bulk["WO_ID"].tolist())
                                st.rerun()
                        with sa2:
                            if st.button("Deselect all", key="wo_deselect_all", icon=":material/deselect:"):
                                st.session_state["_bulk_wo_selected"] = set()
                                st.session_state["_bulk_complete_mode"] = False
                                st.rerun()

        # Bulk action bar
        if bulk_wo_active and CAN_MANAGE_WO:
            _render_bulk_wo_bar(filtered)

        def _render_wo_with_checkbox(wo_row, can_manage, idx, show_checkbox=False):
            if show_checkbox:
                wo_id = wo_row["WO_ID"]
                cb_col, card_col = st.columns([0.05, 0.95])
                with cb_col:
                    is_selected = wo_id in st.session_state["_bulk_wo_selected"]
                    if st.checkbox("", value=is_selected, key=f"bulk_cb_wo_{wo_id}_{idx}", label_visibility="collapsed"):
                        st.session_state["_bulk_wo_selected"].add(wo_id)
                    else:
                        st.session_state["_bulk_wo_selected"].discard(wo_id)
                with card_col:
                    _render_wo_card(wo_row, can_manage=can_manage, idx=idx)
            else:
                _render_wo_card(wo_row, can_manage=can_manage, idx=idx)

        # Persona-specific filtering
        if persona == "TECHNICIAN":
            my_wo = filtered[filtered["ASSIGNED_TO"] == username]
            other_wo = filtered[filtered["ASSIGNED_TO"] != username]
            my_active = my_wo[~my_wo["STATUS"].isin(["completed"])]
            my_completed = my_wo[my_wo["STATUS"] == "completed"]
            other_active = other_wo[~other_wo["STATUS"].isin(["completed"])]
            other_completed = other_wo[other_wo["STATUS"] == "completed"]
            if len(my_active) > 0:
                st.markdown(f"**My work orders** ({len(my_active)})")
                for _idx, (_, wo) in enumerate(my_active.iterrows()):
                    _render_wo_with_checkbox(wo, can_manage=True, idx=_idx, show_checkbox=bulk_wo_active)
            if len(other_active) > 0:
                with st.expander(f"Other work orders ({len(other_active)})"):
                    for _idx, (_, wo) in enumerate(other_active.iterrows()):
                        _render_wo_card(wo, can_manage=False, idx=1000+_idx)
            all_completed = pd.concat([my_completed, other_completed])
            if len(all_completed) > 0:
                with st.expander(f"Completed work orders ({len(all_completed)})", expanded=False):
                    for _idx, (_, wo) in enumerate(all_completed.iterrows()):
                        _render_wo_card(wo, can_manage=False, idx=2000+_idx)
            if len(my_active) == 0 and len(other_active) == 0 and len(all_completed) == 0:
                st.success("No work orders matching filters.")
        else:
            active_wo = filtered[~filtered["STATUS"].isin(["completed"])]
            completed_wo_filtered = filtered[filtered["STATUS"] == "completed"]
            if len(active_wo) > 0:
                st.markdown(f"**Work orders** ({len(active_wo)})")
                for _idx, (_, wo) in enumerate(active_wo.iterrows()):
                    _render_wo_with_checkbox(wo, can_manage=CAN_MANAGE_WO, idx=_idx, show_checkbox=bulk_wo_active and CAN_MANAGE_WO)
            if len(completed_wo_filtered) > 0:
                with st.expander(f"Completed work orders ({len(completed_wo_filtered)})", expanded=False):
                    for _idx, (_, wo) in enumerate(completed_wo_filtered.iterrows()):
                        _render_wo_card(wo, can_manage=False, idx=3000+_idx)
            if len(active_wo) == 0 and len(completed_wo_filtered) == 0:
                st.success("No work orders matching filters.")

# =============================================
# PURCHASE ORDERS TAB
# =============================================
elif section == "Purchase orders" and CAN_VIEW_PO:
    if "_po_action_msg" in st.session_state:
        st.success(st.session_state.pop("_po_action_msg"), icon=":material/check_circle:")
    if len(all_po) == 0:
        st.info("No purchase orders found.")
    else:
        fc1, fc2, fc3 = st.columns(3)
        with fc1:
            pf_status = st.multiselect("Status", all_po["STATUS"].unique().tolist(), default=all_po["STATUS"].unique().tolist(), key="po_f_status")
        with fc2:
            risk_opts = all_po["PROCUREMENT_RISK"].dropna().unique().tolist() if "PROCUREMENT_RISK" in all_po.columns else []
            pf_risk = st.multiselect("Risk", risk_opts, default=risk_opts, key="po_f_risk") if risk_opts else risk_opts
        with fc3:
            supplier_opts = all_po["SUPPLIER_NAME"].dropna().unique().tolist() if "SUPPLIER_NAME" in all_po.columns else []
            pf_supplier = st.multiselect("Supplier", supplier_opts, default=supplier_opts, key="po_f_sup") if supplier_opts else supplier_opts

        filtered_po = all_po[all_po["STATUS"].isin(pf_status)]
        if pf_risk and "PROCUREMENT_RISK" in filtered_po.columns:
            filtered_po = filtered_po[filtered_po["PROCUREMENT_RISK"].isin(pf_risk)]
        if pf_supplier and "SUPPLIER_NAME" in filtered_po.columns:
            filtered_po = filtered_po[filtered_po["SUPPLIER_NAME"].isin(pf_supplier)]

        active_po = filtered_po[~filtered_po["STATUS"].isin(["received", "cancelled"])]
        done_po = filtered_po[filtered_po["STATUS"].isin(["received", "cancelled"])]

        # Sort active POs by required date (earliest first)
        if len(active_po) > 0 and "REQUIRED_BY_DATE" in active_po.columns:
            active_po = active_po.sort_values("REQUIRED_BY_DATE", ascending=True, na_position="last")

        # Bulk select toggle (only for personas that can manage)
        bulk_po_active = False
        if CAN_MANAGE_PO and len(active_po) > 0:
            tc1, tc2 = st.columns([1, 3])
            with tc1:
                bulk_po_active = st.toggle("Select multiple", key="bulk_po_toggle", value=st.session_state["_bulk_po_mode"])
                if bulk_po_active != st.session_state["_bulk_po_mode"]:
                    st.session_state["_bulk_po_mode"] = bulk_po_active
                    if not bulk_po_active:
                        st.session_state["_bulk_po_selected"] = set()
                        st.session_state["_bulk_reject_mode"] = False
                    st.rerun()
            if bulk_po_active:
                with tc2:
                    sa1, sa2 = st.columns(2)
                    with sa1:
                        if st.button("Select all visible", key="po_select_all", icon=":material/select_all:"):
                            st.session_state["_bulk_po_selected"] = set(active_po["PO_ID"].tolist())
                            st.rerun()
                    with sa2:
                        if st.button("Deselect all", key="po_deselect_all", icon=":material/deselect:"):
                            st.session_state["_bulk_po_selected"] = set()
                            st.session_state["_bulk_reject_mode"] = False
                            st.rerun()

        # Bulk action bar
        if bulk_po_active and CAN_MANAGE_PO:
            _render_bulk_po_bar(filtered_po)

        def _render_po_with_checkbox(po_row, can_manage, idx, show_checkbox=False):
            if show_checkbox:
                po_id = po_row["PO_ID"]
                cb_col, card_col = st.columns([0.05, 0.95])
                with cb_col:
                    is_selected = po_id in st.session_state["_bulk_po_selected"]
                    if st.checkbox("", value=is_selected, key=f"bulk_cb_po_{po_id}_{idx}", label_visibility="collapsed"):
                        st.session_state["_bulk_po_selected"].add(po_id)
                    else:
                        st.session_state["_bulk_po_selected"].discard(po_id)
                with card_col:
                    _render_po_card(po_row, can_manage=can_manage, idx=idx)
            else:
                _render_po_card(po_row, can_manage=can_manage, idx=idx)

        if len(active_po) > 0:
            # Group active POs by status in workflow order
            status_order = ["pending_approval", "approved", "ordered", "shipped", "draft"]
            status_labels = {"pending_approval": "Pending Approval", "approved": "Approved",
                             "ordered": "Ordered", "shipped": "Shipped", "draft": "Draft"}
            card_idx = 0
            for status in status_order:
                group = active_po[active_po["STATUS"] == status]
                if len(group) == 0:
                    continue
                st.markdown(f"**{status_labels.get(status, status.title())}** ({len(group)})")
                for _, po in group.iterrows():
                    _render_po_with_checkbox(po, can_manage=CAN_MANAGE_PO, idx=card_idx, show_checkbox=bulk_po_active and CAN_MANAGE_PO)
                    card_idx += 1
        if len(done_po) > 0:
            with st.expander(f"Completed / cancelled POs ({len(done_po)})", expanded=False):
                for idx, (_, po) in enumerate(done_po.iterrows()):
                    _render_po_card(po, can_manage=False, idx=4000+idx)
        if len(active_po) == 0 and len(done_po) == 0:
            st.success("No purchase orders matching filters.")

# =============================================
# WO ANALYTICS TAB
# =============================================
elif section == "WO analytics":
    if len(all_wo) == 0:
        st.info("No work order data for analytics.")
    else:
        _section_header("📊", "Work order analytics")

        col1, col2 = st.columns(2)
        with col1:
            with st.container(border=True):
                st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">WO count by type</div>')
                type_counts = all_wo.groupby("WO_TYPE").size().reset_index(name="Count")
                chart = alt.Chart(type_counts).mark_arc(innerRadius=50).encode(
                    theta=alt.Theta("Count:Q"),
                    color=alt.Color("WO_TYPE:N", scale=alt.Scale(
                        domain=["emergency", "corrective", "preventive"],
                        range=[C["critical"], C["warning"], C["healthy"]]
                    )),
                    tooltip=["WO_TYPE", "Count"],
                ).properties(height=250)
                st.altair_chart(chart.configure_view(strokeWidth=0), use_container_width=True)

        with col2:
            with st.container(border=True):
                st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">WO cost by type</div>')
                cost_by_type = all_wo.groupby("WO_TYPE")["TOTAL_COST"].sum().reset_index()
                cost_by_type.columns = ["WO_TYPE", "TOTAL_COST"]
                chart2 = alt.Chart(cost_by_type).mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4).encode(
                    x=alt.X("WO_TYPE:N", title="Type", axis=alt.Axis(labelColor="#64748B")),
                    y=alt.Y("TOTAL_COST:Q", title="Total cost ($)", axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                    color=alt.Color("WO_TYPE:N", scale=alt.Scale(
                        domain=["emergency", "corrective", "preventive"],
                        range=[C["critical"], C["warning"], C["healthy"]]
                    ), legend=None),
                    tooltip=["WO_TYPE", alt.Tooltip("TOTAL_COST:Q", format="$,.0f")],
                ).properties(height=250)
                st.altair_chart(chart2.configure_view(strokeWidth=0).configure_axis(
                    gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

        with st.container(border=True):
            st.html('<div style="color:#8B5CF6; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">WO cost by asset</div>')
            cost_by_asset = all_wo.groupby("ASSET_NAME")["TOTAL_COST"].sum().reset_index().sort_values("TOTAL_COST", ascending=False)
            chart3 = alt.Chart(cost_by_asset).mark_bar(cornerRadiusTopLeft=4, cornerRadiusTopRight=4).encode(
                x=alt.X("ASSET_NAME:N", sort="-y", title="Asset", axis=alt.Axis(labelColor="#64748B")),
                y=alt.Y("TOTAL_COST:Q", title="Total cost ($)", axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                color=alt.value(C["accent"]),
                tooltip=["ASSET_NAME", alt.Tooltip("TOTAL_COST:Q", format="$,.0f")],
            ).properties(height=250)
            st.altair_chart(chart3.configure_view(strokeWidth=0).configure_axis(
                gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

        # Cost KPIs
        _section_header("💰", "Cost breakdown")
        avg_emergency = all_wo[all_wo["WO_TYPE"] == "emergency"]["TOTAL_COST"].mean()
        avg_corrective = all_wo[all_wo["WO_TYPE"] == "corrective"]["TOTAL_COST"].mean()
        avg_preventive = all_wo[all_wo["WO_TYPE"] == "preventive"]["TOTAL_COST"].mean()
        completion_rate_val = len(completed_wo) / len(all_wo) * 100 if len(all_wo) > 0 else 0

        ck1, ck2, ck3, ck4 = st.columns(4)
        for col, label, val, color in [
            (ck1, "Avg emergency", fmt_currency(avg_emergency), "#EF4444"),
            (ck2, "Avg corrective", fmt_currency(avg_corrective), "#F59E0B"),
            (ck3, "Avg preventive", fmt_currency(avg_preventive), "#10B981"),
            (ck4, "Completion rate", f"{completion_rate_val:.0f}%", "#00D4FF"),
        ]:
            with col:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                            border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                    <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
                    <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                </div>
                """)

# =============================================
# SHORTAGE SIMULATION TAB
# =============================================
elif section == "Shortage simulation":
    import json as _json

    _section_header("🧪", "Part shortage simulation", "#F59E0B")
    st.caption("Reduce a part's on-hand quantity to see which assets and work orders would be impacted.")

    parts_atp = load_parts_atp()
    if len(parts_atp) == 0:
        st.info("No parts inventory data available.")
    else:
        inv_raw = conn.session().sql(
            f"SELECT PART_ID, PART_NAME, QUANTITY_ON_HAND, LEAD_TIME_DAYS, UNIT_COST, COMPATIBLE_ASSETS FROM {DB}.RAW_IT.PARTS_INVENTORY ORDER BY PART_ID"
        ).to_pandas()

        # Load safety stock thresholds
        ssp = load_safety_stock_policy()

        part_labels = (inv_raw["PART_ID"] + " — " + inv_raw["PART_NAME"]).tolist()
        sc1, sc2 = st.columns([2, 1])
        with sc1:
            selected_part_label = st.selectbox("Select part to simulate shortage", part_labels, index=None, placeholder="Pick a part…", key="sim_part")
        with sc2:
            if selected_part_label:
                sel_part_id = selected_part_label.split(" — ")[0]
                part_row = inv_raw[inv_raw["PART_ID"] == sel_part_id].iloc[0]
                current_qty = int(part_row["QUANTITY_ON_HAND"])
                sim_qty = st.number_input("Simulated on-hand quantity", min_value=0, max_value=current_qty, value=0, key="sim_qty")

        if selected_part_label:
            sel_part_id = selected_part_label.split(" — ")[0]
            part_row = inv_raw[inv_raw["PART_ID"] == sel_part_id].iloc[0]
            current_qty = int(part_row["QUANTITY_ON_HAND"])
            lead_time = int(part_row["LEAD_TIME_DAYS"])
            unit_cost = part_row["UNIT_COST"]
            sim_qty = st.session_state.get("sim_qty", 0)

            compatible_raw = part_row.get("COMPATIBLE_ASSETS", "[]")
            if isinstance(compatible_raw, str):
                try:
                    compatible_assets = _json.loads(compatible_raw)
                except Exception:
                    compatible_assets = []
            elif isinstance(compatible_raw, list):
                compatible_assets = compatible_raw
            else:
                compatible_assets = []

            # Safety stock thresholds for this part
            min_stock = 1
            reorder_point = 2
            if len(ssp) > 0:
                ssp_row = ssp[ssp["PART_ID"] == sel_part_id]
                if len(ssp_row) > 0:
                    min_stock = int(ssp_row.iloc[0].get("MIN_STOCK", 1))
                    reorder_point = int(ssp_row.iloc[0].get("REORDER_POINT", 2))

            # Before / After styled KPIs (with safety stock context)
            _section_header("📊", "Before / after comparison")
            bk1, bk2, bk3, bk4, bk5 = st.columns(5)
            curr_color = "#10B981" if current_qty > reorder_point else "#F59E0B" if current_qty > min_stock else "#EF4444"
            sim_color = "#10B981" if sim_qty > reorder_point else "#F59E0B" if sim_qty > min_stock else "#EF4444"
            for col, label, val, color in [
                (bk1, "Current on-hand", current_qty, curr_color),
                (bk2, "Simulated on-hand", sim_qty, sim_color),
                (bk3, "Safety stock", min_stock, "#8B5CF6"),
                (bk4, "Reorder point", reorder_point, "#6366F1"),
                (bk5, "Lead time", f"{lead_time}d", "#3B82F6"),
            ]:
                with col:
                    st.html(f"""
                    <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                                border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                        <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
                        <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                    </div>
                    """)

            # Find WOs at risk by PART linkage (reservations + PO lines), not by asset
            try:
                wo_by_part = conn.session().sql(f"""
                    SELECT DISTINCT wo.WO_ID, wo.ASSET_ID, am.ASSET_NAME, wo.WO_TYPE, wo.STATUS, 'reservation' AS LINK_TYPE
                    FROM {DB}.RAW_IT.PART_RESERVATIONS pr
                    JOIN {DB}.RAW_IT.WORK_ORDERS wo ON pr.WO_ID = wo.WO_ID
                    LEFT JOIN {DB}.RAW_OT.ASSET_MASTER am ON wo.ASSET_ID = am.ASSET_ID
                    WHERE pr.PART_ID = :1 AND pr.STATUS = 'active' AND wo.STATUS IN ('open','in_progress')
                    UNION
                    SELECT DISTINCT wo.WO_ID, wo.ASSET_ID, am.ASSET_NAME, wo.WO_TYPE, wo.STATUS, 'po_line' AS LINK_TYPE
                    FROM {DB}.RAW_IT.PURCHASE_ORDER_LINES pol
                    JOIN {DB}.RAW_IT.WORK_ORDERS wo ON pol.WO_ID = wo.WO_ID
                    LEFT JOIN {DB}.RAW_OT.ASSET_MASTER am ON wo.ASSET_ID = am.ASSET_ID
                    WHERE pol.PART_ID = :2 AND wo.STATUS IN ('open','in_progress')
                """, params=[sel_part_id, sel_part_id]).to_pandas()
            except Exception:
                wo_by_part = pd.DataFrame()
            affected_wo = wo_by_part

            _section_header("🎯", "Impact assessment")
            col_a, col_b = st.columns(2)
            with col_a:
                _glow_card(f"Dependent assets ({len(compatible_assets)})", "".join([
                    f'<div style="color:#E0E7FF; font-size:0.75rem; margin:2px 0;">{a_id}</div>' for a_id in compatible_assets
                ]) if compatible_assets else '<div style="color:#64748B; font-size:0.75rem;">No compatible assets listed.</div>', "#3B82F6", "🏭")

            with col_b:
                wo_html = ""
                if len(affected_wo) > 0:
                    for _, wo in affected_wo.iterrows():
                        wo_html += f'<div style="color:#E0E7FF; font-size:0.75rem; margin:4px 0;"><strong>{wo["WO_ID"]}</strong> — {wo.get("ASSET_NAME", wo["ASSET_ID"])} · {wo["WO_TYPE"]} · {wo["STATUS"]}</div>'
                else:
                    wo_html = '<div style="color:#64748B; font-size:0.75rem;">No open work orders need this part.</div>'
                _glow_card(f"Open WOs at risk ({len(affected_wo)})", wo_html, "#EF4444", "⚠")

            # Risk assessment using safety stock thresholds
            if sim_qty == 0:
                risk_label = "CRITICAL_SHORTAGE"
                risk_detail = "Zero stock — all dependent maintenance is blocked until resupply."
                risk_c = "#EF4444"
            elif sim_qty <= min_stock:
                risk_label = "CRITICAL_SHORTAGE"
                risk_detail = f"Below safety stock ({min_stock}) — insufficient buffer for at-risk assets."
                risk_c = "#EF4444"
            elif sim_qty <= reorder_point:
                risk_label = "EXPEDITE"
                risk_detail = f"At or below reorder point ({reorder_point}) — replenishment needed before lead time elapses."
                risk_c = "#F59E0B"
            elif sim_qty < current_qty:
                risk_label = "ORDER_NOW"
                risk_detail = f"Above reorder point but reduced from {current_qty} — schedule replenishment."
                risk_c = "#3B82F6"
            else:
                risk_label = "NO_RISK"
                risk_detail = "Stock level unchanged — no additional risk."
                risk_c = "#10B981"

            cost_html = ""
            if sim_qty < current_qty:
                est_delay = lead_time
                blocked_wo_count = len(affected_wo) if sim_qty <= min_stock else 0
                total_risk_cost = blocked_wo_count * float(unit_cost) if blocked_wo_count > 0 else 0
                parts_html = []
                if blocked_wo_count > 0:
                    parts_html.append(f'Blocked WOs: <span style="color:#EF4444; font-weight:600;">{blocked_wo_count}</span>')
                    parts_html.append(f'Cost exposure: <span style="color:#EF4444; font-weight:600;">{fmt_currency(total_risk_cost)}</span>')
                parts_html.append(f'Resupply delay: <span style="color:#F59E0B; font-weight:600;">{est_delay} days</span>')
                if sim_qty <= reorder_point and sim_qty > min_stock:
                    parts_html.append(f'Buffer remaining: <span style="color:#F59E0B; font-weight:600;">{sim_qty - min_stock} units above safety stock</span>')
                cost_html = f'<div style="color:#94A3B8; font-size:0.75rem; margin-top:8px;">{" · ".join(parts_html)}</div>'

            _glow_card("Projected risk", f"""
                <div style="display:inline-block; padding:3px 12px; border-radius:10px; font-size:0.65rem; font-weight:700;
                    background:{risk_c}18; color:{risk_c}; border:1px solid {risk_c}33;">{risk_label}</div>
                <div style="color:#E0E7FF; font-size:0.78rem; margin-top:8px;">{risk_detail}</div>
                {cost_html}
            """, risk_c, "📊")

            # Apply simulation
            if sim_qty < current_qty:
                _section_header("⚡", "Apply simulation", "#F59E0B")
                st.caption("This will UPDATE the PARTS_INVENTORY table. Downstream dynamic tables will refresh automatically.")

                ac1, ac2 = st.columns(2)
                with ac1:
                    if st.button("Apply shortage", type="primary", icon=":material/science:", key="apply_shortage"):
                        conn.session().sql(
                            f"UPDATE {DB}.RAW_IT.PARTS_INVENTORY SET QUANTITY_ON_HAND = :1 WHERE PART_ID = :2",
                            params=[sim_qty, sel_part_id],
                        ).collect()
                        _notify("SHORTAGE_SIM", f"Shortage simulated: {sel_part_id}",
                                f"{part_row['PART_NAME']} reduced from {current_qty} to {sim_qty} by {username}", sel_part_id)
                        load_parts_atp.clear()
                        load_all_purchase_orders.clear()
                        st.toast(f"Applied: {part_row['PART_NAME']} set to {sim_qty} units", icon=":material/science:")
                        st.rerun()
                with ac2:
                    if st.button("Revert to original", icon=":material/undo:", key="revert_shortage"):
                        conn.session().sql(
                            f"UPDATE {DB}.RAW_IT.PARTS_INVENTORY SET QUANTITY_ON_HAND = :1 WHERE PART_ID = :2",
                            params=[current_qty, sel_part_id],
                        ).collect()
                        _notify("SHORTAGE_REVERTED", f"Shortage reverted: {sel_part_id}",
                                f"{part_row['PART_NAME']} restored to {current_qty} by {username}", sel_part_id)
                        load_parts_atp.clear()
                        load_all_purchase_orders.clear()
                        st.toast(f"Reverted: {part_row['PART_NAME']} restored to {current_qty} units", icon=":material/undo:")
                        st.rerun()

