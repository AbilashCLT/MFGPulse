import streamlit as st
import pandas as pd
import altair as alt
from app_pages._shared import DB, get_conn, fmt_currency, load_notification_settings, PERSONA_CONFIG, load_all_users_admin, load_users, load_drift_metrics, load_drift_comparison, load_model_accuracy, load_feedback_log, C

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

# Placeholder for system status (computed after data loads in service command center)
st.html("""
<div style="display:flex; align-items:center; justify-content:space-between; margin-bottom:4px; flex-wrap:wrap; gap:10px;">
    <div style="display:flex; align-items:center; gap:14px;">
        <div style="font-size:1.5rem; font-weight:800; color:#E0E7FF;">⚙ Admin control panel</div>
        <div style="padding:4px 14px; border-radius:12px; font-size:0.65rem; font-weight:700;
                    text-transform:uppercase; letter-spacing:0.08em;
                    background:#00D4FF18; color:#00D4FF; border:1px solid #00D4FF33;">
            🛠 System admin
        </div>
    </div>
</div>
""")
st.caption("Monitor and manage tasks, streams, dynamic tables, ML models, Cortex services, agent performance, and notifications")

with st.expander("About this page", expanded=False, icon=":material/info:"):
    st.markdown("""
**Purpose**: Infrastructure monitoring, notification management, test execution, and cost governance — restricted to Plant Manager and App Admin.

**13 sections**:
- **Service command center** — Unified view of all MFGPulse AI services (Tasks, Dynamic Tables, Streams, Search) with real-time stats, last refresh, row counts, and bulk Start all / Shut down controls
- **Tasks** — Resume/suspend scheduled jobs. All automation runs as a Task DAG: MFGPULSE_AUTOMATION_DAG (root) → Fatigue refresh → DT refresh → WO gen → PO gen → PPO conversion
- **Dynamic tables** — Row counts, refresh timestamps, and scheduling state
- **Streams** — CDC stream health (stale/active status)
- **ML models** — Model registry with registered models and metrics
- **Cortex services** — Status of Cortex Agent, Semantic View, and Cortex Search services
- **Agent monitoring** — Copilot execution history, latency percentiles, token/credit usage, tool breakdown, daily performance summary and SLA tracking
- **Notifications** — Per-event toggle configuration for email and in-app notification channels
- **Simulation** — Configurable sensor + production feed simulator with 5 failure scenarios, severity control, and physics-based signatures. Scheduled task (SIMULATE_ALL_FEEDS) uses persistent degradation from LIVE_PREDICTIONS, partial WO recovery, and intermittent fault simulation for realistic plant lifecycle data.
- **Test suite** — 80+ validation tests runnable inline with pass/fail results
- **FinOps** — Credit consumption, warehouse costs, query costs, storage usage, ML model cost estimator, and resource monitor status
- **User management** — Add, edit (persona/email/line/active), and deactivate users with full CRUD
- **Object inventory** — Full Snowflake object counts: base tables, DTs, views, streams, tasks, Cortex Search, semantic views, agents, ML models, sensor readings, active users

**FinOps data sources**: All read-only from `SNOWFLAKE.ACCOUNT_USAGE` views — METERING_HISTORY, WAREHOUSE_METERING_HISTORY, QUERY_HISTORY, TASK_HISTORY.

**Resource monitors**: MFGPULSE_CREDIT_GUARD (COMPUTE_WH — Streamlit + Agent, 250 cr/mo), MFGPULSE_AUTOMATION_GUARD (MFGPULSE_AUTOMATION_WH — Tasks + DTs, 50 cr/mo), MFGPULSE_ML_TRAINING_GUARD (MFGPULSE_ML_TRAINING_WH — ML training, 30 cr/mo). Total budget: 330 cr/mo.
""")

section = st.segmented_control(
    "Section",
    ["Service command center", "Tasks", "Dynamic tables", "Streams", "ML models", "Cortex services", "Agent monitoring", "Notifications", "Simulation", "Test suite", "FinOps", "User management", "Object inventory"],
    default="Service command center",
)

def run_show(sql):
    try:
        session = conn.session()
        rows = session.sql(sql).collect()
        if rows:
            return pd.DataFrame([r.as_dict() if hasattr(r, 'as_dict') else r.asDict() for r in rows])
        return pd.DataFrame()
    except Exception:
        try:
            return conn.query(sql)
        except Exception as ex:
            st.error(f"Query failed: {ex}")
            return pd.DataFrame()


if section == "Service command center":
    _section_header("🏗", "Service command center")

    # Gather real-time stats
    tasks_df = run_show(f"SHOW TASKS IN DATABASE {DB}")
    dt_df = run_show(f"SHOW DYNAMIC TABLES IN DATABASE {DB}")
    streams_df = run_show(f"SHOW STREAMS IN DATABASE {DB}")
    search_df = run_show(f"SHOW CORTEX SEARCH SERVICES IN DATABASE {DB}")

    tasks_total = len(tasks_df)
    tasks_running = len(tasks_df[tasks_df["state"] == "started"]) if tasks_total > 0 and "state" in tasks_df.columns else 0
    dts_total = len(dt_df)
    dts_active = len(dt_df[dt_df["scheduling_state"] == "ACTIVE"]) if dts_total > 0 and "scheduling_state" in dt_df.columns else 0
    streams_total = len(streams_df)
    streams_healthy = len(streams_df[streams_df["stale"] == "false"]) if streams_total > 0 and "stale" in streams_df.columns else streams_total
    search_total = len(search_df)
    search_active = len(search_df[search_df["serving_state"] == "ACTIVE"]) if search_total > 0 and "serving_state" in search_df.columns else 0

    # Styled KPI cards
    sk1, sk2, sk3, sk4 = st.columns(4)
    for col, label, running, total, color in [
        (sk1, "Tasks", tasks_running, tasks_total, "#10B981"),
        (sk2, "Dynamic tables", dts_active, dts_total, "#00D4FF"),
        (sk3, "Streams", streams_healthy, streams_total, "#3B82F6"),
        (sk4, "Cortex Search", search_active, search_total, "#8B5CF6"),
    ]:
        pct = running / max(total, 1) * 100
        bar_color = "#10B981" if pct >= 80 else "#F59E0B" if pct >= 50 else "#EF4444"
        with col:
            st.html(f"""
            <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                        border-radius:8px; padding:14px; text-align:center; box-shadow: 0 0 10px {color}11;">
                <div style="font-size:1.6rem; font-weight:800; color:{color};">{running}/{total}</div>
                <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                <div style="background:rgba(255,255,255,0.04); border-radius:3px; height:4px; overflow:hidden; margin-top:8px;">
                    <div style="width:{pct:.0f}%; background:{bar_color}; height:100%;"></div>
                </div>
            </div>
            """)

    # Freshness and cost
    if dts_total > 0 and "data_timestamp" in dt_df.columns:
        latest_refresh = dt_df["data_timestamp"].max()
        dt_rows = int(dt_df["rows"].sum()) if "rows" in dt_df.columns else 0
        daily_cost = 1.5 if tasks_running > 0 else 0.12
        st.html(f"""
        <div style="display:flex; gap:16px; margin:8px 0; flex-wrap:wrap;">
            <div style="font-size:0.68rem; color:#94A3B8;">Last DT refresh: <span style="color:#E0E7FF; font-weight:600;">{str(latest_refresh)[:19] if latest_refresh else 'N/A'}</span></div>
            <div style="font-size:0.68rem; color:#94A3B8;">Total DT rows: <span style="color:#E0E7FF; font-weight:600;">{dt_rows:,}</span></div>
            <div style="font-size:0.68rem; color:#94A3B8;">Est. daily cost: <span style="color:#F59E0B; font-weight:600;">~{daily_cost:.1f} credits</span></div>
        </div>
        """)

    # Service type distribution chart
    svc_data = pd.DataFrame({
        "Type": ["Tasks", "Dynamic Tables", "Streams", "Cortex Search"],
        "Total": [tasks_total, dts_total, streams_total, search_total],
        "Active": [tasks_running, dts_active, streams_healthy, search_active],
    })
    if svc_data["Total"].sum() > 0:
        with st.container(border=True):
            st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Service health overview</div>')
            svc_melted = svc_data.melt(id_vars=["Type"], var_name="Status", value_name="Count")
            svc_chart = alt.Chart(svc_melted).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
                x=alt.X("Type:N", title="", axis=alt.Axis(labelColor="#64748B")),
                y=alt.Y("Count:Q", title="Count", axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                color=alt.Color("Status:N", scale=alt.Scale(
                    domain=["Total", "Active"],
                    range=["#64748B", "#10B981"])),
                xOffset="Status:N",
                tooltip=["Type:N", "Status:N", "Count:Q"],
            ).properties(height=200)
            st.altair_chart(svc_chart.configure_view(strokeWidth=0).configure_axis(
                gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

    # Consolidated service status table
    with st.container(border=True):
        st.markdown("**Service status**")
        status_rows = []
        if tasks_total > 0:
            for _, t in tasks_df.iterrows():
                status_rows.append({
                    "Service": t.get("name", ""),
                    "Type": "Task",
                    "Schema": t.get("schema_name", ""),
                    "Status": t.get("state", "unknown").upper(),
                    "Schedule / Lag": t.get("schedule", ""),
                })
        if dts_total > 0:
            for _, d in dt_df.iterrows():
                status_rows.append({
                    "Service": d.get("name", ""),
                    "Type": "Dynamic Table",
                    "Schema": d.get("schema_name", ""),
                    "Status": d.get("scheduling_state", "UNKNOWN"),
                    "Schedule / Lag": d.get("target_lag", ""),
                })
        if streams_total > 0:
            for _, s in streams_df.iterrows():
                status_rows.append({
                    "Service": s.get("name", ""),
                    "Type": "Stream",
                    "Schema": s.get("schema_name", ""),
                    "Status": "STALE" if s.get("stale") == "true" else "ACTIVE",
                    "Schedule / Lag": s.get("mode", ""),
                })
        if search_total > 0:
            for _, x in search_df.iterrows():
                status_rows.append({
                    "Service": x.get("name", ""),
                    "Type": "Cortex Search",
                    "Schema": x.get("schema_name", ""),
                    "Status": x.get("serving_state", "UNKNOWN"),
                    "Schedule / Lag": x.get("target_lag", ""),
                })
        if status_rows:
            status_df = pd.DataFrame(status_rows)
            st.dataframe(status_df, use_container_width=True, hide_index=True)

    # Bulk action buttons
    st.markdown("**Bulk actions**")
    b1, b2, b3 = st.columns(3)
    with b1:
        if st.button("Start all services", type="primary", icon=":material/play_arrow:", use_container_width=True):
            if tasks_total > 0:
                progress = st.progress(0, text="Starting services...")
                succeeded = 0
                failed = 0
                for idx, (_, t) in enumerate(tasks_df.iterrows()):
                    name = t.get("name", "")
                    schema = t.get("schema_name", "")
                    state = t.get("state", "")
                    fqn = f"{DB}.{schema}.{name}"
                    progress.progress((idx) / tasks_total, text=f"Resuming {name}...")
                    if state == "suspended":
                        try:
                            conn.session().sql(f"ALTER TASK {fqn} RESUME").collect()
                            succeeded += 1
                        except Exception as ex:
                            st.error(f"Failed to resume {name}: {ex}")
                            failed += 1
                    else:
                        succeeded += 1
                progress.progress(1.0, text="Done")
                st.success(f"Started {succeeded} task(s)" + (f", {failed} failed" if failed else ""))
                st.rerun()
            else:
                st.warning("No tasks found.")

    with b2:
        if st.button("Shutdown all services", icon=":material/stop:", use_container_width=True):
            if tasks_total > 0:
                progress = st.progress(0, text="Shutting down services...")
                succeeded = 0
                failed = 0
                for idx, (_, t) in enumerate(tasks_df.iterrows()):
                    name = t.get("name", "")
                    schema = t.get("schema_name", "")
                    state = t.get("state", "")
                    fqn = f"{DB}.{schema}.{name}"
                    progress.progress((idx) / tasks_total, text=f"Suspending {name}...")
                    if state == "started":
                        try:
                            conn.session().sql(f"ALTER TASK {fqn} SUSPEND").collect()
                            succeeded += 1
                        except Exception as ex:
                            st.error(f"Failed to suspend {name}: {ex}")
                            failed += 1
                    else:
                        succeeded += 1
                progress.progress(1.0, text="Done")
                st.success(f"Stopped {succeeded} task(s)" + (f", {failed} failed" if failed else ""))
                st.rerun()
            else:
                st.warning("No tasks found.")

    with b3:
        if st.button("Refresh all DTs", icon=":material/refresh:", use_container_width=True):
            if dts_total > 0:
                progress = st.progress(0, text="Refreshing dynamic tables...")
                succeeded = 0
                failed = 0
                for idx, (_, d) in enumerate(dt_df.iterrows()):
                    name = d.get("name", "")
                    schema = d.get("schema_name", "")
                    fqn = f"{DB}.{schema}.{name}"
                    progress.progress((idx) / dts_total, text=f"Refreshing {name}...")
                    try:
                        conn.session().sql(f"ALTER DYNAMIC TABLE {fqn} REFRESH").collect()
                        succeeded += 1
                    except Exception as ex:
                        st.error(f"Failed to refresh {name}: {ex}")
                        failed += 1
                progress.progress(1.0, text="Done")
                st.success(f"Refreshed {succeeded}/{dts_total} DTs" + (f", {failed} failed" if failed else ""))
            else:
                st.warning("No dynamic tables found.")


elif section == "Tasks":
    _section_header("⏱", "Task monitor")

    tasks_df = run_show(f"SHOW TASKS IN DATABASE {DB}")
    if len(tasks_df) > 0:
        # Task state distribution chart
        if "state" in tasks_df.columns:
            state_counts = tasks_df["state"].value_counts().reset_index()
            state_counts.columns = ["State", "Count"]
            with st.container(border=True):
                st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Task state distribution</div>')
                state_chart = alt.Chart(state_counts).mark_bar(cornerRadiusTopRight=4, cornerRadiusBottomRight=4).encode(
                    y=alt.Y("State:N", title="", axis=alt.Axis(labelColor="#64748B")),
                    x=alt.X("Count:Q", title="Count", axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                    color=alt.Color("State:N", scale=alt.Scale(
                        domain=["started", "suspended"],
                        range=["#10B981", "#F59E0B"]), legend=None),
                    tooltip=["State", "Count"],
                ).properties(height=100)
                st.altair_chart(state_chart.configure_view(strokeWidth=0).configure_axis(
                    gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

        for _, row in tasks_df.iterrows():
            name = row.get("name", "")
            schema = row.get("schema_name", "")
            state = row.get("state", "unknown")
            schedule = row.get("schedule", "")
            state_c = "green" if state == "started" else "orange" if state == "suspended" else "gray"

            with st.container(border=True):
                c1, c2, c3, c4 = st.columns([2, 1, 1, 2])
                with c1:
                    st.markdown(f"**{name}**")
                    st.caption(f"{schema} | {schedule}")
                with c2:
                    st.badge(state, color=state_c)
                with c3:
                    st.caption(f"WH: {row.get('warehouse', 'N/A')}")
                with c4:
                    fqn = f"{DB}.{schema}.{name}"
                    if state == "suspended":
                        if st.button("Resume", key=f"resume_{name}", type="primary", icon=":material/play_arrow:"):
                            try:
                                conn.session().sql(f"ALTER TASK {fqn} RESUME").collect()
                                st.success(f"Task {name} resumed")
                                st.rerun()
                            except Exception as ex:
                                st.error(f"Failed: {ex}")
                    elif state == "started":
                        if st.button("Suspend", key=f"suspend_{name}", icon=":material/pause:"):
                            try:
                                conn.session().sql(f"ALTER TASK {fqn} SUSPEND").collect()
                                st.success(f"Task {name} suspended")
                                st.rerun()
                            except Exception as ex:
                                st.error(f"Failed: {ex}")
    else:
        st.info("No tasks found.")


elif section == "Dynamic tables":
    _section_header("📊", "Dynamic table monitor")

    dt_df = run_show(f"SHOW DYNAMIC TABLES IN DATABASE {DB}")
    if len(dt_df) > 0:
        total = len(dt_df)
        active = len(dt_df[dt_df.get("scheduling_state", pd.Series(dtype=str)) == "ACTIVE"]) if "scheduling_state" in dt_df.columns else total
        total_rows = dt_df["rows"].sum() if "rows" in dt_df.columns else 0
        total_bytes = dt_df["bytes"].sum() if "bytes" in dt_df.columns else 0

        dk1, dk2, dk3, dk4 = st.columns(4)
        for col, label, val, color in [
            (dk1, "Total DTs", total, "#00D4FF"),
            (dk2, "Active", active, "#10B981"),
            (dk3, "Total rows", f"{int(total_rows):,}", "#3B82F6"),
            (dk4, "Storage", f"{total_bytes / 1024 / 1024:.1f} MB", "#8B5CF6"),
        ]:
            with col:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                            border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                    <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
                    <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                </div>
                """)

        # DT rows by table chart
        if "rows" in dt_df.columns and "name" in dt_df.columns:
            dt_chart_data = dt_df[["name", "rows"]].copy()
            dt_chart_data.columns = ["Table", "Rows"]
            dt_chart_data["Rows"] = pd.to_numeric(dt_chart_data["Rows"], errors="coerce").fillna(0).astype(int)
            if dt_chart_data["Rows"].sum() > 0:
                with st.container(border=True):
                    st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Rows by dynamic table</div>')
                    dt_bar = alt.Chart(dt_chart_data).mark_bar(cornerRadiusTopRight=4, cornerRadiusBottomRight=4).encode(
                        y=alt.Y("Table:N", title="", sort="-x", axis=alt.Axis(labelColor="#94A3B8")),
                        x=alt.X("Rows:Q", title="Row count", axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                        color=alt.value("#00D4FF"),
                        tooltip=["Table", alt.Tooltip("Rows:Q", format=",")],
                    ).properties(height=max(150, len(dt_chart_data) * 28))
                    st.altair_chart(dt_bar.configure_view(strokeWidth=0).configure_axis(
                        gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

        for _, row in dt_df.iterrows():
            name = row.get("name", "")
            schema = row.get("schema_name", "")
            rows_count = int(row.get("rows", 0) or 0)
            lag = row.get("target_lag", "")
            mode = row.get("refresh_mode", "")
            sched = row.get("scheduling_state", "")
            data_ts = row.get("data_timestamp", "")
            sched_c = "green" if sched == "ACTIVE" else "orange" if sched == "SUSPENDED" else "gray"

            with st.container(border=True):
                c1, c2, c3, c4 = st.columns([2, 1, 1, 2])
                with c1:
                    st.markdown(f"**{name}**")
                    st.caption(f"{schema} | {mode} refresh")
                with c2:
                    st.badge(sched, color=sched_c)
                with c3:
                    st.metric("Rows", f"{rows_count:,}")
                with c4:
                    st.caption(f"Lag: {lag} | Data: {str(data_ts)[:19]}")
                    fqn = f"{DB}.{schema}.{name}"
                    if st.button("Refresh", key=f"refresh_dt_{name}", icon=":material/refresh:"):
                        with st.spinner(f"Refreshing {name}..."):
                            try:
                                conn.session().sql(f"ALTER DYNAMIC TABLE {fqn} REFRESH").collect()
                                st.success(f"{name} refresh triggered")
                            except Exception as ex:
                                st.error(f"Failed: {ex}")
    else:
        st.info("No dynamic tables found.")


elif section == "Streams":
    st.markdown("**Stream monitor**")

    streams_df = run_show(f"SHOW STREAMS IN DATABASE {DB}")
    if len(streams_df) > 0:
        for _, row in streams_df.iterrows():
            name = row.get("name", "")
            schema = row.get("schema_name", "")
            table_name = row.get("table_name", "")
            mode = row.get("mode", "")
            stale = str(row.get("stale", "false")).lower() == "true"
            stale_after = row.get("stale_after", "")
            stale_c = "red" if stale else "green"

            with st.container(border=True):
                c1, c2, c3 = st.columns([2, 1, 2])
                with c1:
                    st.markdown(f"**{name}**")
                    st.caption(f"{schema} | {mode}")
                with c2:
                    st.badge("STALE" if stale else "ACTIVE", color=stale_c)
                with c3:
                    st.caption(f"Source: {table_name}")
                    st.caption(f"Stale after: {str(stale_after)[:19]}")
    else:
        st.info("No streams found.")


elif section == "ML models":
    st.markdown("**ML model registry**")

    models_df = conn.query(f"SELECT MODEL_NAME, MODEL_TYPE, TRAINING_DATA, PRECISION_SCORE, RECALL_SCORE, F1_SCORE, TOP_FEATURES, TRAINED_AT FROM {DB}.ML_MODELS.MODEL_REGISTRY ORDER BY TRAINED_AT DESC")
    if len(models_df) > 0:
        for _, row in models_df.iterrows():
            name = row.get("MODEL_NAME", "")
            mtype = row.get("MODEL_TYPE", "")
            trained_at = row.get("TRAINED_AT", "")
            f1 = row.get("F1_SCORE")
            prec = row.get("PRECISION_SCORE")
            recall = row.get("RECALL_SCORE")
            features = row.get("TOP_FEATURES", "")
            training = row.get("TRAINING_DATA", "")

            with st.container(border=True):
                c1, c2 = st.columns([2, 3])
                with c1:
                    st.markdown(f"**{name}**")
                    st.caption(f"{mtype}")
                    if f1 is not None and not pd.isna(f1):
                        st.metric("F1 score", f"{f1:.3f}")
                    else:
                        st.caption("Unsupervised / regression model")
                with c2:
                    st.caption(f"Training data: {training}")
                    st.caption(f"Top features: {features}")
                    if prec is not None and not pd.isna(prec):
                        st.caption(f"Precision: {prec:.3f} | Recall: {recall:.3f}")
                    st.caption(f"Trained: {str(trained_at)[:19]}")

        cortex_search = run_show(f"SHOW CORTEX SEARCH SERVICES IN DATABASE {DB}")
        if len(cortex_search) > 0:
            st.markdown("**Cortex Search services**")
            for _, row in cortex_search.iterrows():
                with st.container(border=True):
                    c1, c2 = st.columns([1, 2])
                    with c1:
                        st.markdown(f"**{row.get('name', '')}**")
                        st.badge("ACTIVE" if row.get("serving_state") == "ACTIVE" else "INACTIVE",
                                 color="green" if row.get("serving_state") == "ACTIVE" else "red")
                    with c2:
                        st.caption(f"Docs: {row.get('source_data_num_rows', 0)} | Column: {row.get('search_column', '')} | Lag: {row.get('target_lag', '')}")

        # --- Model Drift Detection ---
        st.divider()
        st.markdown("**Model drift detection**")
        st.caption("Compares rule-based (LIVE_PREDICTIONS) vs native Snowflake ML predictions. Alert threshold: 80%.")

        drift = load_drift_metrics()
        if len(drift) > 0:
            latest = drift.iloc[0]
            fm_pct = latest.get("FM_AGREEMENT_PCT", 0) or 0
            stage_pct = latest.get("STAGE_AGREEMENT_PCT", 0) or 0
            comp_date = str(latest.get("COMPARISON_DATE", ""))[:10]

            with st.container(horizontal=True):
                fm_color = "inverse" if fm_pct < 80 else "off"
                stage_color = "inverse" if stage_pct < 80 else "off"
                st.metric("Failure mode agreement", f"{fm_pct:.0f}%",
                           delta="Below threshold" if fm_pct < 80 else "OK",
                           delta_color=fm_color, border=True)
                st.metric("Stage agreement", f"{stage_pct:.0f}%",
                           delta="Below threshold" if stage_pct < 80 else "OK",
                           delta_color=stage_color, border=True)
                st.metric("Comparison date", comp_date, border=True)
                st.metric("Assets compared", str(int(latest.get("TOTAL_ASSETS", 0))), border=True)

            if fm_pct < 80 or stage_pct < 80:
                st.warning("Model drift detected — rule-based and native ML models disagree on predictions.", icon=":material/warning:")

            with st.container(horizontal=True):
                if st.button("Refresh drift comparison", icon=":material/compare_arrows:", key="btn_refresh_drift"):
                    try:
                        session = conn.session()
                        result = session.sql("CALL MFGPULSE_DB.ML_MODELS.COMPUTE_NATIVE_PREDICTIONS()").collect()
                        msg = result[0][0] if result else "Done"
                        st.success(msg)
                        load_drift_metrics.clear()
                        load_drift_comparison.clear()
                        st.rerun()
                    except Exception as ex:
                        st.error(f"Drift refresh failed: {ex}")
                if st.button("Retrain native models", icon=":material/model_training:", type="primary" if (fm_pct < 80 or stage_pct < 80) else "secondary", key="btn_retrain"):
                    try:
                        session = conn.session()
                        with st.status("Retraining native models...", expanded=True) as status:
                            status.update(label="Checking drift metrics...", state="running")
                            result = session.sql("CALL MFGPULSE_DB.ML_MODELS.RETRAIN_IF_NEEDED()").collect()
                            msg = result[0][0] if result else "Done"
                            if "No retraining" in msg:
                                status.update(label=msg, state="complete", expanded=False)
                            else:
                                status.update(label=msg, state="complete", expanded=False)
                                load_drift_metrics.clear()
                                load_drift_comparison.clear()
                                st.rerun()
                    except Exception as ex:
                        status.update(label=f"Retrain failed: {ex}", state="error", expanded=True)

            drift_detail = load_drift_comparison()
            if len(drift_detail) > 0:
                latest_date = drift_detail["COMPARISON_DATE"].max()
                today_detail = drift_detail[drift_detail["COMPARISON_DATE"] == latest_date]
                if len(today_detail) > 0:
                    with st.expander(f"Per-asset detail ({str(latest_date)[:10]})", expanded=False):
                        display_cols = ["ASSET_NAME", "RULE_FAILURE_MODE", "NATIVE_FAILURE_MODE",
                                        "FAILURE_MODE_AGREES", "RULE_STAGE", "NATIVE_STAGE", "STAGE_AGREES"]
                        available_cols = [c for c in display_cols if c in today_detail.columns]
                        detail_df = today_detail[available_cols].reset_index(drop=True)
                        if "NATIVE_STAGE" in detail_df.columns:
                            stage_label_map = {"0": "Healthy", "1": "Warning", "2": "Critical", "None": "N/A"}
                            detail_df["NATIVE_STAGE"] = detail_df["NATIVE_STAGE"].astype(str).map(
                                lambda v: stage_label_map.get(v, v)
                            )
                        st.dataframe(detail_df, use_container_width=True,
                                     column_config={
                                         "FAILURE_MODE_AGREES": st.column_config.CheckboxColumn("FM Agrees"),
                                         "STAGE_AGREES": st.column_config.CheckboxColumn("Stage Agrees"),
                                         "NATIVE_STAGE": st.column_config.TextColumn(
                                             "Native Stage",
                                             help="Degradation stage predicted by the native ML classification model (Healthy / Warning / Critical)."
                                         ),
                                     })
        else:
            st.info("No drift data available. Run `CALL ML_MODELS.COMPUTE_NATIVE_PREDICTIONS()` after training native models.")

        # --- Model Accuracy (Closed-Loop Feedback) ---
        st.divider()
        st.markdown("**Model accuracy (closed-loop feedback)**")
        st.caption("Rolling 30-day accuracy from technician-confirmed root causes on completed work orders.")

        accuracy = load_model_accuracy()
        if len(accuracy) > 0 and accuracy.iloc[0].get("TOTAL_FEEDBACK", 0) > 0:
            acc = accuracy.iloc[0]
            with st.container(horizontal=True):
                st.metric("Failure mode accuracy", f"{acc.get('FAILURE_MODE_ACCURACY_PCT', 0):.0f}%",
                           help="% of predictions where confirmed root cause matched predicted failure mode", border=True)
                st.metric("Stage accuracy", f"{acc.get('STAGE_ACCURACY_PCT', 0):.0f}%", border=True)
                st.metric("False alarm rate", f"{acc.get('FALSE_ALARM_RATE_PCT', 0):.0f}%",
                           delta="High" if (acc.get("FALSE_ALARM_RATE_PCT", 0) or 0) > 20 else "Normal",
                           delta_color="inverse" if (acc.get("FALSE_ALARM_RATE_PCT", 0) or 0) > 20 else "off", border=True)
                st.metric("Total feedback", str(int(acc.get("TOTAL_FEEDBACK", 0))), border=True)

            feedback = load_feedback_log()
            if len(feedback) > 0:
                with st.expander("Recent feedback entries", expanded=False):
                    fb_cols = ["WO_ID", "ASSET_ID", "PREDICTED_FAILURE_MODE", "CONFIRMED_ROOT_CAUSE",
                               "WAS_CORRECT", "CONFIRMED_AT", "CONFIRMED_BY"]
                    available_fb = [c for c in fb_cols if c in feedback.columns]
                    st.dataframe(feedback[available_fb].head(10).reset_index(drop=True), use_container_width=True,
                                 column_config={
                                     "WAS_CORRECT": st.column_config.CheckboxColumn("Correct?"),
                                 })
        else:
            st.info("No feedback data yet. Feedback is logged automatically when work orders are completed with a confirmed root cause.")
    else:
        st.info("No models in registry.")


elif section == "Cortex services":
    st.markdown("**Cortex Agent and Semantic View**")

    agents_df = run_show(f"SHOW AGENTS IN DATABASE {DB}")
    if len(agents_df) > 0:
        for _, row in agents_df.iterrows():
            with st.container(border=True):
                st.markdown(f":material/smart_toy: **{row.get('name', '')}**")
                st.caption(f"Schema: {row.get('schema_name', '')} | Owner: {row.get('owner', '')}")
                st.caption(f"Created: {str(row.get('created_on', ''))[:19]}")

    sv_df = run_show(f"SHOW SEMANTIC VIEWS IN SCHEMA {DB}.AGENT")
    if len(sv_df) > 0:
        for _, row in sv_df.iterrows():
            with st.container(border=True):
                st.markdown(f":material/schema: **{row.get('name', '')}**")
                st.caption(f"Schema: {row.get('schema_name', '')} | Owner: {row.get('owner', '')}")

    search_df = run_show(f"SHOW CORTEX SEARCH SERVICES IN DATABASE {DB}")
    if len(search_df) > 0:
        for _, row in search_df.iterrows():
            with st.container(border=True):
                st.markdown(f":material/search: **{row.get('name', '')}**")
                serving = row.get("serving_state", "UNKNOWN")
                st.badge(serving, color="green" if serving == "ACTIVE" else "red")
                st.caption(f"Docs: {row.get('source_data_num_rows', 0)} | Refresh: {row.get('refresh_mode', '')} | Lag: {row.get('target_lag', '')}")


elif section == "Agent monitoring":
    _section_header("🤖", "Copilot agent monitoring", "#8B5CF6")

    try:
        daily = conn.query(f"SELECT * FROM {DB}.ANALYTICS.AGENT_DAILY_SUMMARY LIMIT 30")

        if len(daily) == 0:
            st.info("No agent usage data yet. Data appears after the first Copilot interaction.")
        else:
            for col in daily.columns:
                if col != "DAY":
                    daily[col] = pd.to_numeric(daily[col], errors="coerce").fillna(0)

            latest = daily.iloc[0]
            yesterday = daily.iloc[1] if len(daily) > 1 else None

            # Health badge
            sla = float(latest.get("SLA_PCT", 0) or 0)
            total_req = int(latest.get("TOTAL_REQUESTS", 0) or 0)
            if total_req == 0:
                h_label, h_color = "NO REQUESTS TODAY", "#64748B"
            elif sla >= 90:
                h_label, h_color = "HEALTHY", "#10B981"
            elif sla >= 70:
                h_label, h_color = "DEGRADED", "#F59E0B"
            else:
                h_label, h_color = "UNHEALTHY", "#EF4444"

            st.html(f'<div style="display:inline-block; padding:3px 12px; border-radius:10px; font-size:0.62rem; font-weight:700; background:{h_color}18; color:{h_color}; border:1px solid {h_color}33; margin-bottom:8px;">{h_label}</div>')

            # Styled KPIs
            def delta_val(curr, prev_row, key):
                if prev_row is None:
                    return None
                prev = prev_row.get(key, 0) or 0
                diff = (curr or 0) - prev
                return int(diff) if diff != 0 else None

            avg_lat = int(latest.get("AVG_LATENCY_MS", 0) or 0)
            p95_lat = int(latest.get("P95_LATENCY_MS", 0) or 0)
            tokens_today = int(latest.get("TOTAL_TOKENS", 0) or 0)
            credits_today = float(latest.get("TOTAL_CREDITS", 0) or 0)
            tools_avg = float(latest.get("AVG_TOOL_CALLS", 0) or 0)

            am1, am2, am3, am4 = st.columns(4)
            for col, label, val, color in [
                (am1, "Requests today", str(total_req), "#00D4FF"),
                (am2, "Avg latency", f"{avg_lat:,}ms", "#F59E0B" if avg_lat > 10000 else "#10B981"),
                (am3, "P95 latency", f"{p95_lat:,}ms", "#EF4444" if p95_lat > 15000 else "#F59E0B" if p95_lat > 10000 else "#10B981"),
                (am4, "SLA (<15s)", f"{sla}%", "#10B981" if sla >= 90 else "#F59E0B" if sla >= 70 else "#EF4444"),
            ]:
                with col:
                    st.html(f"""
                    <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                                border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                        <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
                        <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                    </div>
                    """)

            am5, am6, am7, am8 = st.columns(4)
            for col, label, val, color in [
                (am5, "Total tokens", f"{tokens_today:,}", "#3B82F6"),
                (am6, "Total credits", f"{credits_today:.4f}", "#8B5CF6"),
                (am7, "Avg tool calls", f"{tools_avg:.1f}", "#00D4FF"),
                (am8, "Unique users", str(int(latest.get("UNIQUE_USERS", 0) or 0)), "#10B981"),
            ]:
                with col:
                    st.html(f"""
                    <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                                border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                        <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
                        <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                    </div>
                    """)

            # Performance tiers chart
            _section_header("⚡", "Performance tiers (today)")
            fast = int(latest.get("FAST_REQUESTS", 0) or 0)
            normal = int(latest.get("NORMAL_REQUESTS", 0) or 0)
            slow = int(latest.get("SLOW_REQUESTS", 0) or 0)
            very_slow = int(latest.get("VERY_SLOW_REQUESTS", 0) or 0)
            tier_df = pd.DataFrame({
                "Tier": ["FAST (<5s)", "NORMAL (5-15s)", "SLOW (15-60s)", "VERY SLOW (>60s)"],
                "Requests": [fast, normal, slow, very_slow],
            })
            with st.container(border=True):
                st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Request latency distribution</div>')
                tier_chart = alt.Chart(tier_df).mark_bar(cornerRadiusTopRight=4, cornerRadiusBottomRight=4).encode(
                    y=alt.Y("Tier:N", title="", sort=None, axis=alt.Axis(labelColor="#94A3B8")),
                    x=alt.X("Requests:Q", title="Count", axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                    color=alt.Color("Tier:N", scale=alt.Scale(
                        domain=["FAST (<5s)", "NORMAL (5-15s)", "SLOW (15-60s)", "VERY SLOW (>60s)"],
                        range=["#10B981", "#3B82F6", "#F59E0B", "#EF4444"]), legend=None),
                    tooltip=["Tier", "Requests"],
                ).properties(height=140)
                st.altair_chart(tier_chart.configure_view(strokeWidth=0).configure_axis(
                    gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

            # Tool usage + cost breakdown
            detail_all = conn.query(f"""
                SELECT REQUEST_ID, START_TIME, LATENCY_SECS, LATENCY_MS, USER_NAME,
                       TOTAL_TOKENS, TOTAL_CREDITS, TOKEN_CREDITS, AI_FUNCTIONS_CREDITS,
                       SQL_QUERY_CREDITS, TOOL_CALL_COUNT, SERVICES_USED, MODELS_USED,
                       SERVICE_TYPE, PERFORMANCE_TIER, REQUEST_DATE
                FROM {DB}.ANALYTICS.AGENT_EXECUTION_METRICS
                WHERE REQUEST_DATE >= DATEADD('day', -7, CURRENT_DATE())
                ORDER BY START_TIME DESC
            """)

            if len(detail_all) > 0:
                for col_name in ["LATENCY_SECS", "LATENCY_MS", "TOTAL_TOKENS", "TOTAL_CREDITS",
                            "TOKEN_CREDITS", "AI_FUNCTIONS_CREDITS", "SQL_QUERY_CREDITS", "TOOL_CALL_COUNT"]:
                    if col_name in detail_all.columns:
                        detail_all[col_name] = pd.to_numeric(detail_all[col_name], errors="coerce").fillna(0)

                col_left, col_right = st.columns(2)

                with col_left:
                    _section_header("🔧", "Tool usage (7 days)")
                    svc_col = detail_all["SERVICE_TYPE"].dropna()
                    if len(svc_col) > 0:
                        tool_counts = svc_col.value_counts().reset_index()
                        tool_counts.columns = ["Tool", "Calls"]
                        with st.container(border=True):
                            st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Service type calls</div>')
                            tool_chart = alt.Chart(tool_counts).mark_bar(cornerRadiusTopRight=4, cornerRadiusBottomRight=4).encode(
                                y=alt.Y("Tool:N", title="", sort="-x", axis=alt.Axis(labelColor="#94A3B8")),
                                x=alt.X("Calls:Q", title="", axis=alt.Axis(labelColor="#64748B")),
                                color=alt.value("#00D4FF"),
                                tooltip=["Tool", "Calls"],
                            ).properties(height=max(100, len(tool_counts) * 28))
                            st.altair_chart(tool_chart.configure_view(strokeWidth=0).configure_axis(
                                gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

                with col_right:
                    _section_header("💰", "Credit breakdown (7 days)")
                    per_req = detail_all.drop_duplicates(subset=["REQUEST_ID"])
                    token_c = per_req["TOKEN_CREDITS"].sum() or 0
                    ai_c = per_req["AI_FUNCTIONS_CREDITS"].sum() or 0
                    sql_c = per_req["SQL_QUERY_CREDITS"].sum() or 0
                    cost_df = pd.DataFrame({
                        "Category": ["Token (LLM)", "AI Functions", "SQL Queries"],
                        "Credits": [round(token_c, 4), round(ai_c, 4), round(sql_c, 4)],
                    })
                    cost_df = cost_df[cost_df["Credits"] > 0]
                    if len(cost_df) > 0:
                        with st.container(border=True):
                            st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Credits by category</div>')
                            cost_chart = alt.Chart(cost_df).mark_bar(cornerRadiusTopRight=4, cornerRadiusBottomRight=4).encode(
                                y=alt.Y("Category:N", title="", sort="-x", axis=alt.Axis(labelColor="#94A3B8")),
                                x=alt.X("Credits:Q", title="", axis=alt.Axis(labelColor="#64748B")),
                                color=alt.value("#8B5CF6"),
                                tooltip=["Category", alt.Tooltip("Credits:Q", format=".4f")],
                            ).properties(height=100)
                            st.altair_chart(cost_chart.configure_view(strokeWidth=0).configure_axis(
                                gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

                # Top users
                _section_header("👥", "Top users (7 days)")
                per_req2 = detail_all.drop_duplicates(subset=["REQUEST_ID"])
                if len(per_req2) > 0:
                    top_users = per_req2.groupby("USER_NAME").agg(
                        Requests=("REQUEST_ID", "count"),
                        Avg_Latency_s=("LATENCY_SECS", "mean"),
                        Total_Credits=("TOTAL_CREDITS", "sum"),
                    ).sort_values("Requests", ascending=False).head(5).reset_index()
                    top_users.columns = ["User", "Requests", "Avg Latency (s)", "Total Credits"]
                    top_users["Avg Latency (s)"] = top_users["Avg Latency (s)"].round(1)
                    top_users["Total Credits"] = top_users["Total Credits"].round(4)
                    st.dataframe(top_users, use_container_width=True, hide_index=True)

                # Slowest requests
                per_req3 = detail_all.drop_duplicates(subset=["REQUEST_ID"])
                slowest = per_req3.nlargest(3, "LATENCY_MS")
                if len(slowest) > 0 and float(slowest.iloc[0].get("LATENCY_SECS", 0) or 0) > 15:
                    _section_header("🐌", "Slowest requests (7 days)", "#EF4444")
                    for _, row in slowest.iterrows():
                        lat = float(row.get("LATENCY_SECS", 0) or 0)
                        lat_c = "#EF4444" if lat > 60 else "#F59E0B" if lat > 15 else "#10B981"
                        _glow_card(f"{row.get('USER_NAME', '')} — {str(row.get('START_TIME', ''))[:19]}",
                            f'<div style="display:inline-block; padding:2px 8px; border-radius:8px; font-size:0.65rem; font-weight:700; background:{lat_c}18; color:{lat_c}; border:1px solid {lat_c}33;">{lat:.1f}s</div>'
                            f'<div style="color:#94A3B8; font-size:0.72rem; margin-top:6px;">Tools: {row.get("SERVICES_USED", "")} · Tokens: {int(row.get("TOTAL_TOKENS", 0) or 0):,}</div>',
                            lat_c, "⏱")

            # Daily trend
            if len(daily) > 1:
                _section_header("📈", "Daily trend")
                trend_df = daily[["DAY", "TOTAL_REQUESTS", "AVG_LATENCY_MS", "TOTAL_CREDITS"]].copy()
                trend_df = trend_df.sort_values("DAY")
                with st.container(border=True):
                    st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Requests · Latency · Credits (7-day)</div>')
                    trend_melted = trend_df.melt(id_vars=["DAY"], var_name="Metric", value_name="Value")
                    trend_chart = alt.Chart(trend_melted).mark_line(strokeWidth=2).encode(
                        x=alt.X("DAY:T", title="", axis=alt.Axis(labelColor="#64748B", format="%b %d")),
                        y=alt.Y("Value:Q", title="", axis=alt.Axis(labelColor="#64748B")),
                        color=alt.Color("Metric:N", scale=alt.Scale(
                            domain=["TOTAL_REQUESTS", "AVG_LATENCY_MS", "TOTAL_CREDITS"],
                            range=["#00D4FF", "#F59E0B", "#8B5CF6"])),
                        tooltip=["DAY:T", "Metric:N", alt.Tooltip("Value:Q", format=",.1f")],
                    ).properties(height=200)
                    st.altair_chart(trend_chart.configure_view(strokeWidth=0).configure_axis(
                        gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

            with st.expander("Recent requests (detail)", expanded=False):
                if len(detail_all) > 0:
                    display_cols = ["REQUEST_ID", "START_TIME", "LATENCY_SECS", "USER_NAME",
                                    "TOTAL_TOKENS", "TOTAL_CREDITS", "TOOL_CALL_COUNT",
                                    "SERVICES_USED", "MODELS_USED", "PERFORMANCE_TIER"]
                    avail_cols = [c for c in display_cols if c in detail_all.columns]
                    show_df = detail_all.drop_duplicates(subset=["REQUEST_ID"])[avail_cols].head(50)
                    show_df["TOTAL_CREDITS"] = show_df["TOTAL_CREDITS"].round(6)
                    st.dataframe(show_df, use_container_width=True, hide_index=True,
                                 column_config={
                                     "REQUEST_ID": st.column_config.TextColumn("Request ID", width="small"),
                                     "LATENCY_SECS": st.column_config.NumberColumn("Latency (s)", format="%.1f"),
                                     "TOTAL_CREDITS": st.column_config.NumberColumn("Credits", format="%.6f"),
                                     "PERFORMANCE_TIER": st.column_config.TextColumn("Tier"),
                                 })

            st.caption("For full conversation traces, use **AI & ML > Agents > MAINTENANCE_COPILOT > Observability** in Snowsight.")

    except Exception as ex:
        st.warning(f"Agent monitoring unavailable: {ex}")


elif section == "Notifications":
    st.markdown("**Notification settings**")
    st.caption("Configure email and in-app notifications per event type")

    settings = load_notification_settings()
    if len(settings) == 0:
        st.info("No notification settings found. Run sql/19_notifications.sql to seed defaults.")
    else:
        ALL_PERSONAS = ["TECHNICIAN", "RELIABILITY_ENGINEER", "SHIFT_SUPERVISOR", "PLANT_MANAGER", "PROCUREMENT_ADMIN", "APP_ADMIN"]

        for _, row in settings.iterrows():
            evt = row["EVENT_TYPE"]
            with st.container(border=True):
                h1, h2, h3 = st.columns([2, 1, 1])
                with h1:
                    st.markdown(f"**{row.get('EVENT_LABEL', evt)}**")
                    st.caption(evt)
                with h2:
                    in_app = st.toggle("In-app", value=bool(row["IN_APP_ENABLED"]), key=f"inapp_{evt}")
                with h3:
                    email = st.toggle("Email", value=bool(row["EMAIL_ENABLED"]), key=f"email_{evt}")

                current_personas = [p.strip() for p in (row.get("NOTIFY_PERSONAS", "") or "").split(",") if p.strip()]
                selected_personas = st.multiselect(
                    "Notify personas", ALL_PERSONAS, default=current_personas, key=f"personas_{evt}",
                )

                current_recipients = row.get("EMAIL_RECIPIENTS", "") or ""
                recipients = st.text_input("Email recipients", value=current_recipients, key=f"recip_{evt}",
                                           placeholder="user@example.com, user2@example.com")

                priority = st.selectbox("Priority", ["NORMAL", "HIGH"], index=0 if row.get("PRIORITY") == "NORMAL" else 1, key=f"pri_{evt}")

                if st.button("Save", key=f"save_{evt}", type="primary", icon=":material/save:"):
                    personas_str = ",".join(selected_personas)
                    conn.session().sql(
                        f"""UPDATE {DB}.RAW_IT.NOTIFICATION_SETTINGS
                            SET EMAIL_ENABLED = :1, IN_APP_ENABLED = :2, EMAIL_RECIPIENTS = :3,
                                NOTIFY_PERSONAS = :4, PRIORITY = :5,
                                UPDATED_AT = CURRENT_TIMESTAMP(), UPDATED_BY = CURRENT_USER()
                            WHERE EVENT_TYPE = :6""",
                        params=[email, in_app, recipients, personas_str, priority, evt],
                    ).collect()
                    load_notification_settings.clear()
                    st.success(f"Settings saved for {evt}")

        st.divider()
        st.markdown("**Test notification**")
        test_evt = st.selectbox("Event type", settings["EVENT_TYPE"].tolist(), key="test_evt_sel")
        if st.button("Send test", icon=":material/send:", type="primary"):
            try:
                result = conn.session().sql(
                    f"CALL {DB}.RAW_IT.LOG_APP_NOTIFICATION(:1, :2, :3, :4)",
                    params=[test_evt, f"Test: {test_evt}", "This is a test notification from admin panel.", "TEST-001"],
                ).collect()
                st.success(f"Test sent: {result[0][0] if result else 'OK'}")
                from app_pages._shared import load_unread_notifications
                load_unread_notifications.clear()
            except Exception as ex:
                st.error(f"Failed: {ex}")

        st.divider()
        st.markdown("**Recent notifications**")
        recent = conn.query(f"""
            SELECT NOTIF_ID, CREATED_AT, EVENT_TYPE, PERSONA_TARGET, TITLE, ENTITY_ID, PRIORITY, IS_READ
            FROM {DB}.RAW_IT.APP_NOTIFICATIONS
            ORDER BY CREATED_AT DESC LIMIT 20
        """)
        if len(recent) > 0:
            st.dataframe(recent, use_container_width=True, hide_index=True,
                         column_config={
                             "NOTIF_ID": "ID", "CREATED_AT": "Time", "EVENT_TYPE": "Event",
                             "PERSONA_TARGET": "Persona", "TITLE": "Title", "ENTITY_ID": "Entity",
                             "PRIORITY": "Priority", "IS_READ": "Read",
                         })
        else:
            st.info("No notifications logged yet.")

elif section == "Simulation":
    st.markdown("**Simulation console**")
    st.caption("Generate configurable sensor feed + production data for clean or fault scenarios")

    ALL_SCENARIOS = {"Clean operation": "CLEAN", "Bearing wear": "BEARING_WEAR", "Thermal degradation": "THERMAL_DEGRADATION", "Imbalance": "IMBALANCE", "Misalignment": "MISALIGNMENT"}

    assets_df = conn.query(f"SELECT ASSET_ID, ASSET_NAME FROM {DB}.RAW_OT.ASSET_MASTER ORDER BY ASSET_ID")
    asset_options = ["ALL — all 10 assets"] + [f"{r['ASSET_ID']} — {r['ASSET_NAME']}" for _, r in assets_df.iterrows()]

    with st.expander("Scenario reference — sensor signatures", expanded=False, icon=":material/science:"):
        st.markdown("""
| Scenario | Vibration | Temperature | RPM | Current | Acoustic | Production |
|---|---|---|---|---|---|---|
| **Clean** | Low baseline | Normal | Stable | Normal | Quiet | Full |
| **Bearing wear** | High + spikes | Slight rise | Stable | Slight rise | Loud + spikes | Moderate drop |
| **Thermal degradation** | Normal | Ramp to rated max | Stable | Normal | Normal | Moderate drop |
| **Imbalance** | Moderate rise | Normal | Fluctuating | Normal | Slight rise | Significant drop |
| **Misalignment** | Oscillating + rise | Slight rise | Stable | High + progressive | Moderate rise | Moderate drop |
""")

    sim_c1, sim_c2 = st.columns(2)
    with sim_c1:
        sel_asset_raw = st.selectbox("Target asset", asset_options, key="sim_asset")
        sel_scenario_label = st.selectbox("Scenario", list(ALL_SCENARIOS.keys()), key="sim_scenario")
    with sim_c2:
        sel_severity = 0.0
        if sel_scenario_label != "Clean operation":
            sel_severity = st.slider("Severity", 0.0, 1.0, 0.5, 0.05, key="sim_severity", help="0 = onset, 1 = critical failure")
        else:
            st.caption("Severity: N/A for clean operation")
        sel_hours = st.number_input("Hours of data", min_value=1, max_value=168, value=12, key="sim_hours")

    sel_asset_id = "ALL" if sel_asset_raw.startswith("ALL") else sel_asset_raw.split(" — ")[0]
    sel_scenario = ALL_SCENARIOS[sel_scenario_label]
    asset_count = 10 if sel_asset_id == "ALL" else 1
    est_rows = sel_hours * 4 * asset_count
    est_prod = asset_count
    est_seconds = est_rows / 172000 * 60
    est_credits = est_seconds / 3600

    with st.container(border=True):
        st.markdown(f":material/calculate: **Estimated impact**: {est_rows:,} sensor rows + {est_prod} production records → ~{est_credits:.4f} credits (COMPUTE_WH X-SMALL)")

    if st.button("Run simulation", type="primary", icon=":material/play_arrow:", key="run_sim_btn"):
        with st.status(f"Running {sel_scenario_label} simulation on {sel_asset_id}...", expanded=True) as status:
            try:
                st.write("Logging simulation config...")
                conn.session().sql(
                    f"INSERT INTO {DB}.RAW_IT.SIMULATION_CONFIG (ASSET_ID, SCENARIO, SEVERITY, HOURS, STATUS, ESTIMATED_CREDITS, CREATED_BY) VALUES (:1, :2, :3, :4, 'RUNNING', :5, CURRENT_USER())",
                    params=[sel_asset_id, sel_scenario, sel_severity, sel_hours, est_credits],
                ).collect()

                st.write("Generating sensor readings + production data...")
                result = conn.session().sql(
                    f"CALL {DB}.RAW_OT.SIMULATE_SENSOR_FEED_CONFIGURABLE(:1, :2, :3, :4)",
                    params=[sel_asset_id, sel_scenario, sel_severity, sel_hours],
                ).collect()
                result_msg = result[0][0] if result else "Done"

                st.write("Updating simulation log...")
                conn.session().sql(
                    f"UPDATE {DB}.RAW_IT.SIMULATION_CONFIG SET STATUS = 'COMPLETED', ROWS_GENERATED = :1, COMPLETED_AT = CURRENT_TIMESTAMP() WHERE STATUS = 'RUNNING' AND ASSET_ID = :2 AND SCENARIO = :3",
                    params=[est_rows, sel_asset_id, sel_scenario],
                ).collect()

                status.update(label=f"Simulation complete: {result_msg}", state="complete")
            except Exception as ex:
                status.update(label="Simulation failed", state="error")
                st.error(f"Error: {ex}")

    st.divider()
    st.markdown("**Simulation history**")
    try:
        sim_hist = conn.query(f"""
            SELECT CONFIG_ID, ASSET_ID, SCENARIO, SEVERITY, HOURS, STATUS, ROWS_GENERATED,
                ROUND(ESTIMATED_CREDITS, 6) AS EST_CREDITS, CREATED_BY, CREATED_AT, COMPLETED_AT
            FROM {DB}.RAW_IT.SIMULATION_CONFIG ORDER BY CREATED_AT DESC LIMIT 20
        """)
        if len(sim_hist) > 0:
            st.dataframe(sim_hist, use_container_width=True, hide_index=True,
                         column_config={
                             "CONFIG_ID": "ID", "ASSET_ID": "Asset", "SCENARIO": "Scenario",
                             "SEVERITY": st.column_config.NumberColumn("Severity", format="%.2f"),
                             "HOURS": "Hours", "STATUS": "Status",
                             "ROWS_GENERATED": st.column_config.NumberColumn("Rows", format="%d"),
                             "EST_CREDITS": st.column_config.NumberColumn("Est. credits", format="%.6f"),
                             "CREATED_BY": "User", "CREATED_AT": "Started", "COMPLETED_AT": "Completed",
                         })
        else:
            st.info("No simulations run yet.")
    except Exception:
        st.info("No simulation history available.")

elif section == "Test suite":
    st.markdown("**Test suite**")
    st.caption("Run validation tests against the deployed Snowflake objects")

    TEST_CATEGORIES = {
        "Data integrity": {
            "file": "test_data_integrity.sql",
            "queries": {
                "TC-01-01 Schema existence": "SELECT 7 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME IN ('RAW_OT','RAW_IT','CURATED','ML_FEATURES','ML_MODELS','ANALYTICS','AGENT')) AS ACTUAL",
                "TC-01-02 Asset master": "SELECT 10 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_OT.ASSET_MASTER) AS ACTUAL",
                "TC-01-03 Sensor readings": "SELECT 170000 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS) AS ACTUAL",
                "TC-01-04 Active users": "SELECT 9 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_IT.USERS WHERE ACTIVE=TRUE) AS ACTUAL",
                "TC-01-05 Persona coverage": "SELECT 6 AS EXPECTED, (SELECT COUNT(DISTINCT PERSONA) FROM MFGPULSE_DB.RAW_IT.USERS WHERE ACTIVE=TRUE) AS ACTUAL",
                "TC-01-06 Sensor FK integrity": "SELECT 0 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_OT.SENSOR_READINGS sr LEFT JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON sr.ASSET_ID=am.ASSET_ID WHERE am.ASSET_ID IS NULL) AS ACTUAL",
                "TC-01-07 WO FK integrity": "SELECT 0 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS wo LEFT JOIN MFGPULSE_DB.RAW_OT.ASSET_MASTER am ON wo.ASSET_ID=am.ASSET_ID WHERE am.ASSET_ID IS NULL) AS ACTUAL",
                "TC-01-11 Model registry": "SELECT 12 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.ML_MODELS.MODEL_REGISTRY) AS ACTUAL",
                "TC-01-12 Notification settings": "SELECT 7 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_IT.NOTIFICATION_SETTINGS) AS ACTUAL",
            },
        },
        "ML pipeline": {
            "file": "test_ml_pipeline.sql",
            "queries": {
                "TC-02-01 Predictions count": "SELECT 10 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS) AS ACTUAL",
                "TC-02-02 RUL >= 0": "SELECT 0 AS EXPECTED, (SELECT COUNT_IF(RUL_HOURS<0) FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS) AS ACTUAL",
                "TC-02-03 Degradation 0-1": "SELECT 0 AS EXPECTED, (SELECT COUNT_IF(DEGRADATION_SCORE<0 OR DEGRADATION_SCORE>1) FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS) AS ACTUAL",
                "TC-02-04 Fatigue 0-1": "SELECT 0 AS EXPECTED, (SELECT COUNT_IF(FATIGUE_SCORE<0 OR FATIGUE_SCORE>1) FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS) AS ACTUAL",
                "TC-02-05 Health 0-100": "SELECT 0 AS EXPECTED, (SELECT COUNT_IF(COMPOSITE_HEALTH_SCORE<0 OR COMPOSITE_HEALTH_SCORE>100) FROM MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS) AS ACTUAL",
                "TC-02-11 Fatigue all assets": "SELECT 10 AS EXPECTED, (SELECT COUNT(DISTINCT ASSET_ID) FROM MFGPULSE_DB.ML_MODELS.FATIGUE_SCORES) AS ACTUAL",
                "TC-02-12 Anomaly scores": "SELECT 1800 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.ML_MODELS.ANOMALY_SCORES) AS ACTUAL",
                "TC-02-13 M1-M7 registry": "SELECT 7 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.ML_MODELS.MODEL_REGISTRY WHERE MODEL_NAME LIKE 'M%') AS ACTUAL",
            },
        },
        "Procurement": {
            "file": "test_procurement.sql",
            "queries": {
                "TC-03-02 All parts in ATP": "SELECT 15 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.ANALYTICS.PARTS_AVAILABLE_TO_PROMISE) AS ACTUAL",
                "TC-03-07 Suppliers active": "SELECT 5 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_IT.SUPPLIERS WHERE ACTIVE=TRUE) AS ACTUAL",
                "TC-03-08 Part-supplier maps": "SELECT 16 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_IT.PART_SUPPLIERS) AS ACTUAL",
            },
        },
        "Notifications": {
            "file": "test_notifications.sql",
            "queries": {
                "TC-04-01 Event types seeded": "SELECT 7 AS EXPECTED, (SELECT COUNT(*) FROM MFGPULSE_DB.RAW_IT.NOTIFICATION_SETTINGS) AS ACTUAL",
                "TC-04-02 Personas configured": "SELECT 0 AS EXPECTED, (SELECT COUNT_IF(NOTIFY_PERSONAS IS NULL OR LENGTH(TRIM(NOTIFY_PERSONAS))=0) FROM MFGPULSE_DB.RAW_IT.NOTIFICATION_SETTINGS) AS ACTUAL",
                "TC-04-03 In-app default ON": "SELECT 7 AS EXPECTED, (SELECT COUNT_IF(IN_APP_ENABLED=TRUE) FROM MFGPULSE_DB.RAW_IT.NOTIFICATION_SETTINGS) AS ACTUAL",
            },
        },
        "WO/PO lifecycle": {
            "file": "test_wo_po_lifecycle.sql",
            "queries": {
                "TC-05-01 Valid WO types": "SELECT 0 AS EXPECTED, (SELECT COUNT_IF(WO_TYPE NOT IN ('emergency','corrective','preventive')) FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS) AS ACTUAL",
                "TC-05-02 Valid WO statuses": "SELECT 0 AS EXPECTED, (SELECT COUNT_IF(STATUS NOT IN ('open','in_progress','completed','cancelled')) FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS) AS ACTUAL",
                "TC-05-03 Completed have date": "SELECT 0 AS EXPECTED, (SELECT COUNT_IF(STATUS='completed' AND COMPLETED_DATE IS NULL) FROM MFGPULSE_DB.RAW_IT.WORK_ORDERS) AS ACTUAL",
                "TC-05-07 Alerts exist": "SELECT 'TRUE' AS EXPECTED, (SELECT CASE WHEN COUNT(*)>0 THEN 'TRUE' ELSE 'FALSE' END FROM MFGPULSE_DB.ANALYTICS.ACTIVE_ALERTS WHERE SEVERITY IN ('CRITICAL','WARNING')) AS ACTUAL",
                "TC-05-08 OEE all assets": "SELECT 10 AS EXPECTED, (SELECT COUNT(DISTINCT ASSET_ID) FROM MFGPULSE_DB.ANALYTICS.OEE_METRICS) AS ACTUAL",
            },
        },
        "Simulation scenarios": {
            "file": "test_simulation_scenarios.sql",
            "queries": {
                "TC-06-01 Healthy 0% failure": "SELECT 0 AS EXPECTED, MFGPULSE_DB.ML_MODELS.SIMULATE_FAILURE_TWIN(0.56,0.0007,0.01,0,14,0):failure_prob_day_14::FLOAT AS ACTUAL",
                "TC-06-08 Always 100 sims": "SELECT 100 AS EXPECTED, MFGPULSE_DB.ML_MODELS.SIMULATE_FAILURE_TWIN(3.6,0.03,0.35,20,7,0):num_simulations::INT AS ACTUAL",
                "TC-06-09 Healthy → MONITOR": "SELECT 'MONITOR' AS EXPECTED, CASE WHEN MFGPULSE_DB.ML_MODELS.SIMULATE_FAILURE_TWIN(0.56,0.0007,0.01,0,14,0):recommended_intervention::VARCHAR LIKE '%MONITOR%' THEN 'MONITOR' ELSE 'OTHER' END AS ACTUAL",
            },
        },
    }

    cat = st.selectbox("Test category", list(TEST_CATEGORIES.keys()), key="test_cat_sel")
    cat_info = TEST_CATEGORIES[cat]
    st.caption(f"Source: `test_cases/{cat_info['file']}`")

    if st.button("Run tests", type="primary", icon=":material/play_arrow:", key="run_tests_btn"):
        results = []
        progress = st.progress(0)
        queries = cat_info["queries"]
        for i, (name, sql) in enumerate(queries.items()):
            try:
                r = conn.query(sql)
                expected = str(r.iloc[0]["EXPECTED"])
                actual = str(r.iloc[0]["ACTUAL"])
                status = "PASS" if expected == actual else ("PASS" if expected.startswith(">") or expected.startswith("<") else "FAIL")
                # Handle numeric comparison
                try:
                    e_num = float(expected)
                    a_num = float(actual)
                    status = "PASS" if (e_num == 0 and a_num == 0) or (e_num > 0 and a_num >= e_num) or (e_num == a_num) else "FAIL"
                except (ValueError, TypeError):
                    status = "PASS" if expected == actual else "FAIL"
                results.append({"Test": name, "Expected": expected, "Actual": actual, "Status": status})
            except Exception as ex:
                results.append({"Test": name, "Expected": "—", "Actual": str(ex)[:80], "Status": "ERROR"})
            progress.progress((i + 1) / len(queries))

        df_results = pd.DataFrame(results)
        passed = len(df_results[df_results["Status"] == "PASS"])
        failed = len(df_results[df_results["Status"] == "FAIL"])
        errors = len(df_results[df_results["Status"] == "ERROR"])
        total = len(df_results)

        pass_rate = f"{passed/total*100:.0f}%" if total > 0 else "0%"
        pass_color = "#10B981" if failed == 0 and errors == 0 else "#F59E0B" if failed > 0 else "#EF4444"
        tk1, tk2, tk3, tk4 = st.columns(4)
        for col, label, val, color in [
            (tk1, "Total tests", total, "#00D4FF"),
            (tk2, "Passed", passed, "#10B981"),
            (tk3, "Failed", failed, "#EF4444" if failed > 0 else "#10B981"),
            (tk4, "Pass rate", pass_rate, pass_color),
        ]:
            with col:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                            border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                    <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
                    <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                </div>
                """)

        st.dataframe(df_results, use_container_width=True, hide_index=True,
                     column_config={"Test": "Test case", "Expected": "Expected", "Actual": "Actual", "Status": "Result"})

elif section == "FinOps":
    _section_header("💰", "FinOps — infrastructure cost monitor", "#F59E0B")

    # --- 1. Credit summary KPIs ---
    try:
        svc_df = conn.query("""
            SELECT SERVICE_TYPE, ROUND(SUM(CREDITS_USED), 4) AS CREDITS
            FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY
            WHERE START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
            GROUP BY SERVICE_TYPE ORDER BY CREDITS DESC
        """)
        svc_map = dict(zip(svc_df["SERVICE_TYPE"], svc_df["CREDITS"])) if len(svc_df) > 0 else {}
        wh_credits = svc_map.get("WAREHOUSE_METERING", 0)
        coco_credits = svc_map.get("SNOWFLAKE_COCO_SNOWSIGHT", 0)
        container_credits = svc_map.get("SNOWPARK_CONTAINER_SERVICES", 0)
        ai_credits = svc_map.get("AI_FUNCTIONS", 0)
        total_credits = sum(svc_map.values())

        rm_df = run_show("SHOW RESOURCE MONITORS LIKE 'MFGPULSE_CREDIT_GUARD'")
        rm_quota = float(rm_df.iloc[0].get("credit_quota", 250)) if len(rm_df) > 0 else 250
        rm_used = float(rm_df.iloc[0].get("used_credits", 0)) if len(rm_df) > 0 else 0
        rm_remaining = rm_quota - rm_used

        fk1, fk2, fk3, fk4, fk5 = st.columns(5)
        for col, label, val, color in [
            (fk1, "Warehouse (30d)", f"{wh_credits:.2f}", "#3B82F6"),
            (fk2, "CoCo (30d)", f"{coco_credits:.2f}", "#8B5CF6"),
            (fk3, "Container (30d)", f"{container_credits:.2f}", "#00D4FF"),
            (fk4, "AI functions (30d)", f"{ai_credits:.4f}", "#10B981"),
            (fk5, "Total (30d)", f"{total_credits:.2f}", "#F59E0B"),
        ]:
            with col:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                            border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                    <div style="font-size:1.2rem; font-weight:800; color:{color};">{val}</div>
                    <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                </div>
                """)
    except Exception as ex:
        st.warning(f"Credit summary unavailable: {ex}")
        rm_quota, rm_used, rm_remaining = 250, 0, 250
        svc_df = pd.DataFrame()

    # --- 2. Resource monitors ---
    def render_resource_monitor(name, label):
        rm_data = run_show(f"SHOW RESOURCE MONITORS LIKE '{name}'")
        quota = float(rm_data.iloc[0].get("credit_quota", 0)) if len(rm_data) > 0 else 0
        used = float(rm_data.iloc[0].get("used_credits", 0)) if len(rm_data) > 0 else 0
        remaining = quota - used
        pct = (used / quota * 100) if quota > 0 else 0
        with st.container(border=True):
            st.markdown(f"**Resource monitor — {label}**")
            mc1, mc2, mc3 = st.columns(3)
            with mc1:
                st.metric("Monthly quota", f"{quota:.0f} credits")
            with mc2:
                st.metric("Used this period", f"{used:.2f} credits")
            with mc3:
                st.metric("Remaining", f"{remaining:.2f} credits")
            st.progress(min(pct / 100, 1.0), text=f"{pct:.1f}% of quota consumed — alerts at 75%, suspend at 90%, hard stop at 100%")
        return quota, used

    rm_quota, rm_used = render_resource_monitor("MFGPULSE_CREDIT_GUARD", "MFGPULSE_CREDIT_GUARD (COMPUTE_WH — Streamlit + Agent)")
    rm_remaining = rm_quota - rm_used
    render_resource_monitor("MFGPULSE_AUTOMATION_GUARD", "MFGPULSE_AUTOMATION_GUARD (MFGPULSE_AUTOMATION_WH — Tasks + DTs)")
    render_resource_monitor("MFGPULSE_ML_TRAINING_GUARD", "MFGPULSE_ML_TRAINING_GUARD (MFGPULSE_ML_TRAINING_WH — ML model training)")

    # --- 3. Daily credit trend ---
    try:
        daily_df = conn.query("""
            SELECT DATE_TRUNC('day', START_TIME)::DATE AS DAY, WAREHOUSE_NAME,
                ROUND(SUM(CREDITS_USED_COMPUTE), 4) AS COMPUTE,
                ROUND(SUM(CREDITS_USED_CLOUD_SERVICES), 4) AS CLOUD_SERVICES
            FROM SNOWFLAKE.ACCOUNT_USAGE.WAREHOUSE_METERING_HISTORY
            WHERE WAREHOUSE_NAME IN ('COMPUTE_WH', 'MFGPULSE_AUTOMATION_WH', 'MFGPULSE_ML_TRAINING_WH')
                AND START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
            GROUP BY DAY, WAREHOUSE_NAME ORDER BY DAY
        """)
        if len(daily_df) > 0:
            _section_header("📈", "Daily warehouse credit trend")
            with st.container(border=True):
                st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Compute credits by warehouse</div>')
                trend_chart = alt.Chart(daily_df).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
                    x=alt.X("DAY:T", title="Date", axis=alt.Axis(labelColor="#64748B", format="%b %d")),
                    y=alt.Y("COMPUTE:Q", title="Compute credits", axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                    color=alt.Color("WAREHOUSE_NAME:N", title="Warehouse",
                        scale=alt.Scale(domain=["COMPUTE_WH", "MFGPULSE_AUTOMATION_WH", "MFGPULSE_ML_TRAINING_WH"], range=["#3B82F6", "#F59E0B", "#EF4444"])),
                    tooltip=["DAY:T", "WAREHOUSE_NAME:N", alt.Tooltip("COMPUTE:Q", format=".4f"), alt.Tooltip("CLOUD_SERVICES:Q", format=".4f")],
                ).properties(height=250)
                st.altair_chart(trend_chart.configure_view(strokeWidth=0).configure_axis(
                    gridColor="rgba(255,255,255,0.04)"), use_container_width=True)
    except Exception:
        pass

    # --- 4. Cost by service type ---
    if len(svc_df) > 0:
        _section_header("📊", "Credit breakdown by service type (30 days)")
        with st.container(border=True):
            st.html('<div style="color:#10B981; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Credits by billing category</div>')
            chart_df = svc_df[svc_df["CREDITS"] > 0].copy().sort_values("CREDITS", ascending=True)
            svc_chart = alt.Chart(chart_df).mark_bar(cornerRadiusTopRight=4, cornerRadiusBottomRight=4).encode(
                y=alt.Y("SERVICE_TYPE:N", title="", sort="-x", axis=alt.Axis(labelColor="#94A3B8")),
                x=alt.X("CREDITS:Q", title="Credits", axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                color=alt.value("#10B981"),
                tooltip=["SERVICE_TYPE", alt.Tooltip("CREDITS:Q", format=".4f")],
            ).properties(height=max(120, len(chart_df) * 28))
            st.altair_chart(svc_chart.configure_view(strokeWidth=0).configure_axis(
                gridColor="rgba(255,255,255,0.04)"), use_container_width=True)

    # --- 5. Query cost breakdown ---
    try:
        query_df = conn.query("""
            SELECT QUERY_TYPE,
                COUNT(*) AS QUERIES,
                ROUND(SUM(TOTAL_ELAPSED_TIME)/1000/60, 1) AS EXEC_MINUTES,
                ROUND(SUM(CREDITS_USED_CLOUD_SERVICES), 4) AS CLOUD_CREDITS
            FROM SNOWFLAKE.ACCOUNT_USAGE.QUERY_HISTORY
            WHERE WAREHOUSE_NAME = 'COMPUTE_WH'
                AND START_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
                AND EXECUTION_STATUS = 'SUCCESS'
            GROUP BY QUERY_TYPE ORDER BY EXEC_MINUTES DESC LIMIT 12
        """)
        if len(query_df) > 0:
            st.markdown("**Query cost breakdown (top 12 by execution time)**")
            st.dataframe(query_df, use_container_width=True, hide_index=True,
                         column_config={
                             "QUERY_TYPE": "Query type", "QUERIES": st.column_config.NumberColumn("Count", format="%d"),
                             "EXEC_MINUTES": st.column_config.NumberColumn("Exec (min)", format="%.1f"),
                             "CLOUD_CREDITS": st.column_config.NumberColumn("Cloud credits", format="%.4f"),
                         })
    except Exception:
        pass

    # --- 6. Storage + DT refresh (two columns) ---
    col_l, col_r = st.columns(2)

    with col_l:
        try:
            storage_df = conn.query(f"""
                SELECT TABLE_SCHEMA || '.' || TABLE_NAME AS OBJECT,
                    ROW_COUNT AS ROWS,
                    ROUND(BYTES / (1024*1024), 2) AS SIZE_MB
                FROM {DB}.INFORMATION_SCHEMA.TABLES
                WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','PUBLIC')
                    AND TABLE_TYPE = 'BASE TABLE' AND BYTES > 0
                ORDER BY BYTES DESC LIMIT 10
            """)
            if len(storage_df) > 0:
                st.markdown("**Top tables by storage**")
                st.dataframe(storage_df, use_container_width=True, hide_index=True,
                             column_config={
                                 "OBJECT": "Table", "ROWS": st.column_config.NumberColumn("Rows", format="%d"),
                                 "SIZE_MB": st.column_config.NumberColumn("Size (MB)", format="%.2f"),
                             })
        except Exception:
            pass

    with col_r:
        try:
            dt_refresh_df = conn.query(f"""
                SELECT REPLACE(QUALIFIED_NAME, 'MFGPULSE_DB.', '') AS DT_NAME,
                    COUNT(*) AS REFRESHES,
                    ROUND(SUM(STATISTICS:"numInsertedRows"::INT), 0) AS ROWS_INSERTED,
                    ROUND(AVG(TIMESTAMPDIFF('second', REFRESH_START_TIME, REFRESH_END_TIME)), 1) AS AVG_SEC
                FROM TABLE({DB}.INFORMATION_SCHEMA.DYNAMIC_TABLE_REFRESH_HISTORY(
                    NAME_PREFIX => '{DB}'
                ))
                WHERE REFRESH_ACTION != 'NO_DATA'
                GROUP BY QUALIFIED_NAME ORDER BY ROWS_INSERTED DESC
            """)
            if len(dt_refresh_df) > 0:
                st.markdown("**Dynamic table refresh history**")
                st.dataframe(dt_refresh_df, use_container_width=True, hide_index=True,
                             column_config={
                                 "DT_NAME": "Dynamic table", "REFRESHES": st.column_config.NumberColumn("Refreshes", format="%d"),
                                 "ROWS_INSERTED": st.column_config.NumberColumn("Rows inserted", format="%d"),
                                 "AVG_SEC": st.column_config.NumberColumn("Avg duration (s)", format="%.1f"),
                             })
        except Exception:
            pass

    # --- 7. Task execution history ---
    try:
        task_hist_df = conn.query("""
            SELECT NAME AS TASK_NAME,
                COUNT(*) AS RUNS,
                ROUND(SUM(CREDITS_USED), 4) AS TOTAL_CREDITS,
                ROUND(AVG(TIMESTAMPDIFF('second', QUERY_START_TIME, COMPLETED_TIME)), 1) AS AVG_DURATION_SEC,
                MAX(COMPLETED_TIME)::TIMESTAMP_NTZ AS LAST_RUN
            FROM SNOWFLAKE.ACCOUNT_USAGE.TASK_HISTORY
            WHERE DATABASE_NAME = 'MFGPULSE_DB'
                AND SCHEDULED_TIME >= DATEADD('day', -30, CURRENT_TIMESTAMP())
                AND STATE = 'SUCCEEDED'
            GROUP BY NAME ORDER BY TOTAL_CREDITS DESC
        """)
        st.markdown("**Task execution history (30 days)**")
        if len(task_hist_df) > 0:
            st.dataframe(task_hist_df, use_container_width=True, hide_index=True,
                         column_config={
                             "TASK_NAME": "Task", "RUNS": st.column_config.NumberColumn("Runs", format="%d"),
                             "TOTAL_CREDITS": st.column_config.NumberColumn("Credits", format="%.4f"),
                             "AVG_DURATION_SEC": st.column_config.NumberColumn("Avg duration (s)", format="%.1f"),
                             "LAST_RUN": "Last run",
                         })
        else:
            st.info("No task executions in the last 30 days. All 3 tasks are currently suspended — resume them from the Tasks section to start data simulation.")
    except Exception:
        st.info("Task history unavailable — requires SNOWFLAKE.ACCOUNT_USAGE access.")

    # --- 8. Running cost simulator ---
    st.divider()
    st.markdown("**Running cost simulator**")
    st.caption("Estimate ongoing credit consumption based on active services")

    try:
        # Gather current state
        sim_tasks = run_show(f"SHOW TASKS IN DATABASE {DB}")
        sim_dts = run_show(f"SHOW DYNAMIC TABLES IN DATABASE {DB}")
        sim_search = run_show(f"SHOW CORTEX SEARCH SERVICES IN DATABASE {DB}")

        tasks_active = len(sim_tasks[sim_tasks["state"] == "started"]) if len(sim_tasks) > 0 and "state" in sim_tasks.columns else 0
        dts_count = len(sim_dts)
        search_active = len(sim_search[sim_search["serving_state"] == "ACTIVE"]) if len(sim_search) > 0 and "serving_state" in sim_search.columns else 0

        # Account budget
        acct_total = 400.0
        acct_used_df = conn.query("SELECT ROUND(SUM(CREDITS_USED), 2) AS USED FROM SNOWFLAKE.ACCOUNT_USAGE.METERING_HISTORY WHERE START_TIME >= '2026-09-01'")
        acct_used = float(acct_used_df.iloc[0]["USED"]) if len(acct_used_df) > 0 else 0
        acct_remaining = acct_total - acct_used

        # Cost line items
        cost_items = []

        # Streamlit app (always on if app is running)
        cost_items.append({"Service": "Streamlit app (container)", "Type": "Container Services", "Daily": 0.12, "Active": True})

        # Dynamic tables
        dt_daily = dts_count * 0.115  # ~1.5 credits/day for 13 DTs
        cost_items.append({"Service": f"DT refreshes ({dts_count} DTs @ 1h lag)", "Type": "Warehouse", "Daily": round(dt_daily, 2), "Active": dts_count > 0})
        cost_items.append({"Service": "  └ includes UDF model inference (M1-M4, M6)", "Type": "— (embedded)", "Daily": 0.0, "Active": dts_count > 0})

        # Tasks
        task_costs = {
            "SIMULATE_ALL_FEEDS": 0.15,
            "SIMULATE_SENSOR_FEED": 0.10,
            "SIMULATE_PRODUCTION": 0.02,
            "AUTO_PROCUREMENT_REVIEW": 0.02,
            "AUTO_CONVERT_PLANNED_POS_TASK": 0.02,
        }
        if len(sim_tasks) > 0:
            for _, t in sim_tasks.iterrows():
                tname = t.get("name", "")
                tstate = t.get("state", "")
                daily = task_costs.get(tname, 0.02)
                cost_items.append({"Service": f"Task: {tname} (720 min)", "Type": "Warehouse", "Daily": daily, "Active": tstate == "started"})

        # Cortex Search
        cost_items.append({"Service": "Cortex Search (MAINTENANCE_SEARCH)", "Type": "Cortex Search", "Daily": 0.01, "Active": search_active > 0})

        # AI Functions (scheduled/cached)
        cost_items.append({"Service": "LLM summaries (llama3.1-8b, cached)", "Type": "AI Functions", "Daily": 0.005, "Active": True})

        # On-demand AI
        cost_items.append({"Service": "Root cause / prescriptive (llama3.1-70b)", "Type": "AI Functions", "Daily": 0.01, "Active": False})
        cost_items.append({"Service": "Monte Carlo simulation (per run)", "Type": "Warehouse", "Daily": 0.002, "Active": False})
        cost_items.append({"Service": "Cortex Agent queries (per query)", "Type": "AI Functions", "Daily": 0.005, "Active": False})

        # Build dataframe
        cost_df = pd.DataFrame(cost_items)
        active_daily = cost_df[cost_df["Active"] == True]["Daily"].sum()
        all_daily = cost_df["Daily"].sum()

        # KPIs
        with st.container(horizontal=True):
            st.metric("Current daily cost", f"~{active_daily:.2f} credits", border=True)
            st.metric("Current monthly cost", f"~{active_daily * 30:.0f} credits", border=True)
            st.metric("Account remaining", f"{acct_remaining:.0f} credits", border=True)
            runway_days = int(acct_remaining / active_daily) if active_daily > 0 else 9999
            st.metric("Runway", f"~{runway_days} days", border=True)

        # Cost table
        with st.container(border=True):
            st.markdown("**Cost breakdown by service**")
            display_df = cost_df.copy()
            display_df["Monthly"] = display_df["Daily"] * 30
            display_df["Status"] = display_df["Active"].map({True: "ACTIVE", False: "OFF / ON-DEMAND"})
            st.dataframe(display_df[["Service", "Type", "Status", "Daily", "Monthly"]], use_container_width=True, hide_index=True,
                column_config={
                    "Service": "Service",
                    "Type": "Billing category",
                    "Status": "Status",
                    "Daily": st.column_config.NumberColumn("Daily (credits)", format="%.3f"),
                    "Monthly": st.column_config.NumberColumn("Monthly (credits)", format="%.1f"),
                })

        # Scenario comparison
        with st.container(border=True):
            st.markdown("**Scenario comparison**")
            scenarios = []

            # All active
            all_on = cost_df["Daily"].sum()
            scenarios.append({"Scenario": "All services active (tasks resumed)", "Daily": round(all_on, 2), "Monthly": round(all_on * 30, 0), "Runway (days)": int(acct_remaining / all_on) if all_on > 0 else 9999})

            # Tasks off
            tasks_off = cost_df[(cost_df["Active"] == True) | (~cost_df["Service"].str.startswith("Task:"))]["Daily"].sum()
            baseline = cost_df[~cost_df["Service"].str.startswith("Task:") & ~cost_df["Service"].str.startswith("Root") & ~cost_df["Service"].str.startswith("Monte") & ~cost_df["Service"].str.startswith("Cortex Agent")]["Daily"].sum()
            scenarios.append({"Scenario": "Tasks suspended (app + DTs only)", "Daily": round(baseline, 2), "Monthly": round(baseline * 30, 0), "Runway (days)": int(acct_remaining / baseline) if baseline > 0 else 9999})

            # Minimal
            minimal = 0.12 + 0.01  # app + search only, no DTs
            scenarios.append({"Scenario": "Minimal (app only, no DT refresh)", "Daily": round(minimal, 2), "Monthly": round(minimal * 30, 0), "Runway (days)": int(acct_remaining / minimal) if minimal > 0 else 9999})

            sc_df = pd.DataFrame(scenarios)
            st.dataframe(sc_df, use_container_width=True, hide_index=True,
                column_config={
                    "Scenario": "Scenario",
                    "Daily": st.column_config.NumberColumn("Daily (credits)", format="%.2f"),
                    "Monthly": st.column_config.NumberColumn("Monthly (credits)", format="%.0f"),
                    "Runway (days)": st.column_config.NumberColumn("Runway (days)", format="%d"),
                })

        # ML model cost detail
        with st.expander("ML model cost detail", expanded=False, icon=":material/model_training:"):
            ml_rows = [
                {"Model": "M1 — Failure Mode Classifier", "Type": "SQL UDF (rule-based)", "Training": "0 credits", "Inference": "Included in DT refresh"},
                {"Model": "M2 — RUL Predictor", "Type": "SQL UDF (physics-informed)", "Training": "0 credits", "Inference": "Included in DT refresh"},
                {"Model": "M3 — Degradation Stager", "Type": "SQL UDF (weighted composite)", "Training": "0 credits", "Inference": "Included in DT refresh"},
                {"Model": "M4 — Fatigue Detector", "Type": "SQL UDF (cumulative damage)", "Training": "0 credits", "Inference": "Included in DT refresh"},
                {"Model": "M5 — Root Cause Analyzer", "Type": "Cortex Complete (llama3.1-70b)", "Training": "N/A", "Inference": "~0.01 credits/call"},
                {"Model": "M6 — Monte Carlo Simulator", "Type": "SQL UDF (stochastic)", "Training": "0 credits", "Inference": "~0.002 credits/run"},
                {"Model": "M7 — Prescriptive Engine", "Type": "Cortex Complete (llama3.1-70b)", "Training": "N/A", "Inference": "~0.01 credits/call"},
                {"Model": "Native Classifier", "Type": "Snowflake ML Classification", "Training": "~0.1 credits (one-time)", "Inference": "N/A (not in live pipeline)"},
                {"Model": "Native Forecaster", "Type": "Snowflake ML Forecast", "Training": "~0.1 credits (one-time)", "Inference": "N/A (not in live pipeline)"},
                {"Model": "Native Degradation", "Type": "Snowflake ML Classification", "Training": "~0.1 credits (one-time)", "Inference": "N/A (not in live pipeline)"},
                {"Model": "Anomaly Detector", "Type": "Snowflake ML AnomalyDetection", "Training": "~0.1 credits (one-time)", "Inference": "N/A (not in live pipeline)"},
                {"Model": "Hidden Fatigue Detector", "Type": "Snowflake ML AnomalyDetection", "Training": "~0.1 credits (one-time)", "Inference": "N/A (not in live pipeline)"},
            ]
            st.caption("UDF models (M1-M4, M6) execute inside the LIVE_PREDICTIONS DT refresh — no separate billing. LLM models (M5, M7) are on-demand only. Native Snowflake ML models were trained once during initial build.")
            st.dataframe(pd.DataFrame(ml_rows), use_container_width=True, hide_index=True)

    except Exception as ex:
        st.warning(f"Cost simulator unavailable: {ex}")


elif section == "User management":
    _section_header("👥", "User management")

    ALL_PERSONAS = list(PERSONA_CONFIG.keys())
    PERSONA_TO_ROLE = {"TECHNICIAN": "MAINTENANCE_TECH", "RELIABILITY_ENGINEER": "RELIABILITY_ENG", "SHIFT_SUPERVISOR": "SHIFT_SUPERVISOR", "PLANT_MANAGER": "PLANT_MANAGER", "PROCUREMENT_ADMIN": "PROCUREMENT_ADMIN", "APP_ADMIN": "APP_ADMIN"}

    all_users = load_all_users_admin()

    # Styled KPIs
    active_count = len(all_users[all_users["ACTIVE"] == True]) if len(all_users) > 0 else 0
    persona_count = all_users["PERSONA"].nunique() if len(all_users) > 0 else 0
    uk1, uk2, uk3 = st.columns(3)
    for col, label, val, color in [
        (uk1, "Total users", len(all_users), "#00D4FF"),
        (uk2, "Active", active_count, "#10B981"),
        (uk3, "Personas", persona_count, "#8B5CF6"),
    ]:
        with col:
            st.html(f"""
            <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                        border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
                <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
            </div>
            """)

    if len(all_users) > 0:
        for idx, row in all_users.iterrows():
            uid = row["USER_ID"]
            is_active = bool(row["ACTIVE"])
            status_color = "green" if is_active else "gray"

            with st.container(border=True):
                h1, h2, h3, h4 = st.columns([2, 1, 1, 1])
                with h1:
                    st.markdown(f"**{row['USERNAME']}**")
                    st.caption(f"{uid} | {row.get('EMAIL', '')}")
                with h2:
                    st.badge(row["PERSONA"].replace("_", " ").title(), color="blue")
                with h3:
                    st.badge("Active" if is_active else "Inactive", color=status_color)
                with h4:
                    st.caption(f"Line: {row.get('LINE_ID') or 'All'}")

                with st.expander("Edit user", expanded=False):
                    ec1, ec2 = st.columns(2)
                    with ec1:
                        new_persona = st.selectbox("Persona", ALL_PERSONAS, index=ALL_PERSONAS.index(row["PERSONA"]) if row["PERSONA"] in ALL_PERSONAS else 0, key=f"persona_{uid}")
                        new_email = st.text_input("Email", value=row.get("EMAIL") or "", key=f"email_{uid}")
                    with ec2:
                        new_line = st.text_input("Line ID", value=row.get("LINE_ID") or "", key=f"line_{uid}", placeholder="LINE_01, LINE_02, LINE_03, or blank")
                        new_active = st.toggle("Active", value=is_active, key=f"active_{uid}")

                    if st.button("Save changes", key=f"save_user_{uid}", type="primary", icon=":material/save:"):
                        new_role = PERSONA_TO_ROLE.get(new_persona, new_persona)
                        conn.session().sql(
                            f"UPDATE {DB}.RAW_IT.USERS SET PERSONA = :1, ROLE = :2, EMAIL = :3, LINE_ID = NULLIF(:4, ''), ACTIVE = :5 WHERE USER_ID = :6",
                            params=[new_persona, new_role, new_email, new_line, new_active, uid],
                        ).collect()
                        load_all_users_admin.clear()
                        load_users.clear()
                        st.success(f"User {row['USERNAME']} updated")
                        st.rerun()

    st.divider()
    st.markdown("**Add new user**")

    with st.container(border=True):
        nc1, nc2 = st.columns(2)
        with nc1:
            new_username = st.text_input("Username", key="new_username", placeholder="Jane Smith")
            new_user_email = st.text_input("Email", key="new_user_email", placeholder="jane.smith@mfgpulse.ai")
        with nc2:
            new_user_persona = st.selectbox("Persona", ALL_PERSONAS, key="new_user_persona")
            new_user_line = st.text_input("Line ID (optional)", key="new_user_line", placeholder="LINE_01")

        if st.button("Create user", type="primary", icon=":material/person_add:", key="create_user_btn"):
            if not new_username.strip():
                st.error("Username is required.")
            else:
                max_id_result = conn.session().sql(f"SELECT COALESCE(MAX(CAST(REPLACE(USER_ID, 'USR-', '') AS INT)), 0) + 1 AS NEXT_ID FROM {DB}.RAW_IT.USERS WHERE USER_ID LIKE 'USR-%'").collect()
                next_id = max_id_result[0]["NEXT_ID"] if max_id_result else len(all_users) + 1
                new_uid = f"USR-{next_id:03d}"
                new_role = PERSONA_TO_ROLE.get(new_user_persona, new_user_persona)
                try:
                    conn.session().sql(
                        f"INSERT INTO {DB}.RAW_IT.USERS (USER_ID, USERNAME, EMAIL, PERSONA, ROLE, LINE_ID, ACTIVE) VALUES (:1, :2, :3, :4, :5, NULLIF(:6, ''), TRUE)",
                        params=[new_uid, new_username.strip(), new_user_email.strip(), new_user_persona, new_role, new_user_line.strip()],
                    ).collect()
                    load_all_users_admin.clear()
                    load_users.clear()
                    st.success(f"User {new_username} created as {new_uid} ({new_user_persona})")
                    st.rerun()
                except Exception as ex:
                    st.error(f"Failed to create user: {ex}")


elif section == "Object inventory":
    _section_header("📦", "Solution object inventory")

    try:
        counts = conn.query(f"""
            SELECT 'Base tables' AS TYPE, COUNT(*) AS CNT FROM {DB}.INFORMATION_SCHEMA.TABLES
                WHERE TABLE_TYPE = 'BASE TABLE' AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','PUBLIC')
            UNION ALL SELECT 'Views', COUNT(*) FROM {DB}.INFORMATION_SCHEMA.TABLES
                WHERE TABLE_TYPE = 'VIEW' AND TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','PUBLIC')
        """)

        dt_count = run_show(f"SHOW DYNAMIC TABLES IN DATABASE {DB}")
        task_count = run_show(f"SHOW TASKS IN DATABASE {DB}")
        stream_count = run_show(f"SHOW STREAMS IN DATABASE {DB}")
        search_count = run_show(f"SHOW CORTEX SEARCH SERVICES IN DATABASE {DB}")
        agent_count = run_show(f"SHOW AGENTS IN DATABASE {DB}")
        sv_count = run_show(f"SHOW SEMANTIC VIEWS IN SCHEMA {DB}.AGENT")

        bt = int(counts[counts["TYPE"] == "Base tables"]["CNT"].iloc[0]) if len(counts) > 0 else 0
        vw = int(counts[counts["TYPE"] == "Views"]["CNT"].iloc[0]) if len(counts) > 0 else 0

        # First row of KPIs
        ok1, ok2, ok3, ok4 = st.columns(4)
        for col, label, val, color in [
            (ok1, "Base tables", bt, "#00D4FF"),
            (ok2, "Dynamic tables", len(dt_count), "#3B82F6"),
            (ok3, "Views", vw, "#8B5CF6"),
            (ok4, "Streams", len(stream_count), "#10B981"),
        ]:
            with col:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                            border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                    <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
                    <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                </div>
                """)

        ok5, ok6, ok7, ok8 = st.columns(4)
        for col, label, val, color in [
            (ok5, "Tasks", len(task_count), "#F59E0B"),
            (ok6, "Cortex Search", len(search_count), "#EF4444"),
            (ok7, "Semantic views", len(sv_count), "#8B5CF6"),
            (ok8, "Cortex Agents", len(agent_count), "#10B981"),
        ]:
            with col:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                            border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                    <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
                    <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                </div>
                """)

        model_count = conn.query(f"SELECT COUNT(*) AS CNT FROM {DB}.ML_MODELS.MODEL_REGISTRY")
        sensor_count = conn.query(f"SELECT COUNT(*) AS CNT FROM {DB}.RAW_OT.SENSOR_READINGS")
        user_count = conn.query(f"SELECT COUNT(*) AS CNT FROM {DB}.RAW_IT.USERS WHERE ACTIVE = TRUE")

        ok9, ok10, ok11 = st.columns(3)
        for col, label, val, color in [
            (ok9, "ML models", int(model_count.iloc[0]["CNT"]), "#F59E0B"),
            (ok10, "Sensor readings", f"{int(sensor_count.iloc[0]['CNT']):,}", "#00D4FF"),
            (ok11, "Active users", int(user_count.iloc[0]["CNT"]), "#10B981"),
        ]:
            with col:
                st.html(f"""
                <div style="background:rgba(17,24,39,0.9); border:1px solid {color}33; border-top:3px solid {color};
                            border-radius:8px; padding:12px; text-align:center; box-shadow: 0 0 10px {color}11;">
                    <div style="font-size:1.4rem; font-weight:800; color:{color};">{val}</div>
                    <div style="font-size:0.5rem; color:#64748B; text-transform:uppercase; letter-spacing:0.06em; font-weight:600; margin-top:4px;">{label}</div>
                </div>
                """)

        # Schema breakdown chart
        _section_header("📊", "Schema breakdown")
        schema_counts = conn.query(f"""
            SELECT TABLE_SCHEMA, TABLE_TYPE, COUNT(*) AS CNT
            FROM {DB}.INFORMATION_SCHEMA.TABLES
            WHERE TABLE_SCHEMA NOT IN ('INFORMATION_SCHEMA','PUBLIC')
            GROUP BY TABLE_SCHEMA, TABLE_TYPE ORDER BY TABLE_SCHEMA, TABLE_TYPE
        """)
        if len(schema_counts) > 0:
            with st.container(border=True):
                st.html('<div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600; margin-bottom:6px;">Objects by schema and type</div>')
                schema_chart = alt.Chart(schema_counts).mark_bar(cornerRadiusTopLeft=3, cornerRadiusTopRight=3).encode(
                    x=alt.X("TABLE_SCHEMA:N", title="Schema", axis=alt.Axis(labelColor="#64748B")),
                    y=alt.Y("CNT:Q", title="Count", axis=alt.Axis(labelColor="#64748B", titleColor="#94A3B8")),
                    color=alt.Color("TABLE_TYPE:N", title="Type", scale=alt.Scale(
                        domain=["BASE TABLE", "VIEW"],
                        range=["#00D4FF", "#8B5CF6"])),
                    xOffset="TABLE_TYPE:N",
                    tooltip=["TABLE_SCHEMA", "TABLE_TYPE", "CNT"],
                ).properties(height=250)
                st.altair_chart(schema_chart.configure_view(strokeWidth=0).configure_axis(
                    gridColor="rgba(255,255,255,0.04)"), use_container_width=True)
    except Exception:
        st.info("Object inventory unavailable — some tables or schemas may not exist yet.")
