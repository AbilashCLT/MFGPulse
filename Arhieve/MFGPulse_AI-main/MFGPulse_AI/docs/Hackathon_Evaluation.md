# MFGPulse AI — Hackathon Evaluation

*Self-assessment against the challenge brief and judging criteria.*

---

## The Challenge

> Manufacturers lose value to unplanned downtime because OT sensor data sits apart from ERP and maintenance context. Build a solution that converges IT and OT data to predict failures, automate work orders, and lift Overall Equipment Effectiveness.

### Required Capabilities
1. Correlate real-time sensor streams (vibration, temperature, RPM) with ERP and maintenance records
2. Predict failures in advance and support root cause investigation in natural language
3. Deliver a command center experience for alert triage and action

### Judging Focus
- **Real-World Relevance**
- **Technical Execution**
- **Solution Completeness**

---

## Challenge Requirement Mapping

### Requirement 1: Correlate Real-Time Sensor Streams with ERP and Maintenance Records

| What Was Asked | What MFGPulse AI Delivers | Where to Find It |
|---|---|---|
| Real-time sensor streams (vibration, temperature, RPM) | 560K+ sensor readings across 10 assets, 6 sensor channels (vibration_x/y/z, temperature, RPM, current, acoustic emission, pressure), 15-minute intervals. 3 CDC streams (SENSOR_READINGS_STREAM, MAINTENANCE_LOGS_STREAM, WORK_ORDERS_STREAM) for change capture. Continuous data growth via 11-task automation DAG. | `sql/02_base_tables.sql`, `sql/03_streams.sql`, `sql/05_generate_sensor_data.sql` |
| Correlate with ERP records | SENSOR_WITH_CONTEXT dynamic table joins OT sensor readings with IT asset metadata, production records, shift schedules, and ambient conditions. Computes vibration magnitude, temperature/RPM ratios, hours since last maintenance — fusing OT and IT in a single curated layer. | `sql/07_curated_dynamic_tables.sql` (SENSOR_WITH_CONTEXT DT) |
| Correlate with maintenance records | CROSS_DOMAIN dynamic table fuses sensor features with maintenance history (days since last maintenance, cumulative operating hours, WO count). FAILURE_HISTORY DT captures pre-failure sensor statistics (7-day window before each work order) for pattern analysis. | `sql/08_ml_feature_dynamic_tables.sql` (CROSS_DOMAIN, FAILURE_HISTORY) |
| IT/OT convergence | 7-schema architecture explicitly separates OT (RAW_OT: sensors, assets, ambient) from IT (RAW_IT: work orders, maintenance logs, parts, suppliers, production, users, notifications), then converges them through CURATED and ML_FEATURES dynamic tables. The convergence is automatic and continuous — not a batch job. | Architecture diagram in `TECHNICAL_GUIDE.md` Section 2 |

**Key Technical Detail**: The convergence is not a simple join. It is a 14-stage dynamic table pipeline:

```
RAW_OT (sensors) ──┐
                    ├──► CURATED (3 DTs) ──► ML_FEATURES (7 DTs) ──► LIVE_PREDICTIONS
RAW_IT (ERP/CMMS) ─┘
```

Each stage enriches the data: sensor context → health scoring → rolling statistics → cross-sensor interactions → temporal memory → cross-domain IT/OT fusion → physics-based composites → fleet comparison → unified prediction output. All auto-refreshing via Snowflake Dynamic Tables.

---

### Requirement 2: Predict Failures in Advance and Support Root Cause Investigation in Natural Language

| What Was Asked | What MFGPulse AI Delivers | Where to Find It |
|---|---|---|
| Predict failures in advance | **12 ML models** (6 UDF-based + 3 native Snowflake ML + 3 on-demand procedures). M1: 5-class failure mode classifier (bearing_wear, thermal_degradation, imbalance, misalignment, normal). M2: RUL estimator with confidence intervals (P10/P50/P90). M3: 3-stage degradation stager (Healthy/Warning/Critical). M4: Hidden fatigue detector (cumulative damage model). M6: Monte Carlo digital twin (100 stochastic paths, failure probability at 3/7/14 days). | `sql/10_udfs_live_predictions.sql`, `sql/11_native_ml_models.sql` |
| Root cause investigation | M5: LLM root cause analyzer using Cortex Search RAG (26 indexed maintenance docs) + Cortex Complete (llama3.1-70b). Returns natural-language root cause, confidence level, and cited evidence from maintenance history. | `sql/10_udfs_live_predictions.sql` (ANALYZE_ROOT_CAUSE procedure) |
| Natural language support | **Cortex Agent** with 5 tools: (1) maintenance_analytics — text-to-SQL via Semantic View for structured queries, (2) maintenance_history — RAG search over maintenance logs for root cause investigation, (3) predict_all — full 7-model diagnosis, (4) simulate_scenario — Monte Carlo what-if, (5) generate_work_order — create and file a WO from conversation. | `cortex_project/MAINTENANCE_COPILOT_agent.yaml` |
| Natural language root cause | Ask the Copilot: "Why is Compressor A1 showing degradation? Give me the root cause." The agent searches maintenance history (RAG), runs the 7-model diagnosis, and responds with a physics-based explanation citing specific maintenance log entries. | Copilot page (`app_pages/copilot.py`) |

**Key Technical Detail**: The prediction pipeline is not a single model — it is a 7-model diagnostic chain orchestrated by the PREDICT_ALL procedure. Each model contributes a different signal:

| Model | Signal | Why It Matters |
|---|---|---|
| M1 Failure Mode | *What* will fail | Determines which parts and skills are needed |
| M2 RUL | *When* it will fail | Sets the urgency window (IMMEDIATE/URGENT/SCHEDULED) |
| M3 Degradation | *How bad* is it now | Drives alert severity |
| M4 Fatigue | *Hidden* damage | Catches failures invisible to simple thresholds |
| M5 Root Cause | *Why* it is failing | Enables targeted repair, not just replacement |
| M6 Digital Twin | *What-if* scenarios | Compares intervention strategies before committing resources |
| M7 Prescriptive | *What to do* about it | Generates work order with parts, cost, and priority |

The natural-language interface is not a wrapper around SQL. The Cortex Agent has genuine tool-use capabilities — it decides which tools to invoke based on the question, chains tool outputs, and synthesizes a persona-aware response (technician gets step-by-step repair actions; plant manager gets cost-impact summary).

---

### Requirement 3: Deliver a Command Center Experience for Alert Triage and Action

| What Was Asked | What MFGPulse AI Delivers | Where to Find It |
|---|---|---|
| Command center experience | 8-page Streamlit app with role-based navigation for 6 personas. Top-bar navigation, sidebar with notifications and user context. Consistent color coding (red/orange/blue/green) across all pages. | `streamlit_app.py`, `app_pages/` (8 pages) |
| Alert triage | ACTIVE_ALERTS dynamic table with multi-signal alert engine (4 severity levels: Critical/Warning/Watch/Info). Operations Center has dedicated "Alert triage" view sorted by severity. Each alert includes failure mode, RUL, fatigue, chronic flag, and context-rich message. | `sql/12_analytics_layer.sql` (ACTIVE_ALERTS DT), `app_pages/operations_dashboard.py` |
| Action | End-to-end action loop: Alert → Diagnose (Copilot or Maintenance Hub) → Create WO (from Copilot, Maintenance Hub, or WO/PO Console) → Assign technician (auto from shift schedule) → Check parts (ATP view) → Create PO if needed → Approve PO → Track to completion → Notification sent. All persona-gated. | `app_pages/wo_po_console.py`, `app_pages/maintenance_dashboard.py`, `sql/17_procurement_procedures.sql` |

**Key Technical Detail**: The command center is not a dashboard — it is an operational workflow system. The distinction:

- **Dashboards** show data. MFGPulse AI does this (Executive Dashboard, OEE charts, fleet matrices).
- **Command centers** enable action. MFGPulse AI also does this:
  - Create/start/complete work orders with persona-gated permissions
  - Create/approve/reject/receive purchase orders with full lifecycle tracking
  - Auto-assign technicians from shift schedules
  - One-click PO generation from procurement recommendations
  - AI-generated work orders from natural language ("Create a preventive WO for Fan F1")
  - Email + in-app notifications on every state transition (16 event types, admin-configurable)
  - Monte Carlo simulation for intervention planning before committing resources

---

## Judging Criteria Deep Dive

### 1. Real-World Relevance

**The problem is real.** Unplanned downtime costs manufacturers an estimated $50B annually (Deloitte). The root cause is consistently the same: OT sensor data (vibration, temperature, RPM) lives in historians or PLCs, while maintenance context (work orders, parts, supplier lead times) lives in ERP systems. Predictive maintenance initiatives fail not because the ML is wrong, but because the data never converges.

**MFGPulse AI addresses this directly:**

| Real-World Pain Point | How MFGPulse AI Solves It |
|---|---|
| Sensor data sits in silos | RAW_OT and RAW_IT schemas explicitly model the IT/OT divide, then CURATED DTs converge them automatically |
| Maintenance is reactive | 12 ML models predict failures with RUL confidence intervals, before symptoms become visible |
| Technicians get alerts without context | Failure DNA profile shows 5 risk signals; root cause analysis cites evidence from maintenance history |
| PMs don't know the cost of inaction | Every prediction includes failure cost, repair cost, and cost-of-inaction calculation |
| Procurement is disconnected from maintenance | ATP math, procurement risk classification (NO_RISK → CRITICAL_SHORTAGE), and PO auto-generation tie parts availability directly to predicted failures |
| Shift handover is informal | Dedicated Shift Handover view with critical actions, plant OEE, procurement readiness |
| Different roles need different views | 6 personas with persona-filtered navigation and action permissions |
| Work order creation is manual | Copilot agent creates WOs from natural language, or one-click from alert triage |

**Production-ready patterns used:**
- Parameterized SQL throughout (no string interpolation of user input)
- Resource monitor (MFGPULSE_CREDIT_GUARD, 250 credits/month) for cost governance
- 80+ automated test cases with 95% pass rate acceptance criteria
- Admin-configurable notification routing (no code changes needed to adjust)
- Dynamic table pipeline eliminates manual ETL scheduling

---

### 2. Technical Execution

**Snowflake-native throughout.** Every component runs on Snowflake — no external services, no ETL tools, no third-party ML platforms.

| Component | Snowflake Feature Used | Implementation |
|---|---|---|
| Data pipeline | Dynamic Tables (14) | Auto-refreshing feature engineering, TARGET_LAG = 1 hour, PHYSICS_COMPOSITE and SENSOR_INTERACTIONS use INCREMENTAL mode |
| Change capture | Streams (3) | CDC on sensor readings, maintenance logs, work orders |
| ML predictions | SQL UDFs (6) + Procedures (8) | M1-M4 and M6 as UDFs; M5, M7, PREDICT_ALL + PREDICT_CORE + PREDICT_DEEP as procedures |
| Native ML | Snowflake.ML (3 models) | Classification (×2), Forecast using native Snowflake ML |
| LLM reasoning | Cortex Complete (llama3.1-70b) | Root cause analysis (M5), prescriptive engine (M7), Copilot responses |
| RAG search | Cortex Search | 78 maintenance documents indexed, SEARCH_PREVIEW enabled for accuracy benchmarks |
| AI agent | Cortex Agent (DATA_AGENT_RUN) | 5 tools with persona-aware orchestration instructions |
| Semantic layer | Cortex Semantic View | 6 tables, 21 VQRs, text-to-SQL for analytics queries |
| Simulation | Monte Carlo UDF | 100 stochastic paths per scenario, physics-based degradation projection |
| Frontend | Streamlit in Snowflake | 8-page multipage app with st.navigation, st.segmented_control, st.pills, st.status, bulk WO/PO operations |
| Notifications | SYSTEM$SEND_SNOWFLAKE_NOTIFICATION | Snowflake-managed email delivery via MFGPULSE_EMAIL integration |
| Scheduling | Tasks (11-task DAG) | MFGPULSE_AUTOMATION_DAG → Simulate → Freshness → Fatigue → DTs → Drift → Archive → WOs → POs → PPOs → KPIs |
| Security | Parameterized SQL | All user-input paths use `session.sql("...", params=[])` |

**Architecture quality indicators:**

- **7-schema separation** (RAW_OT → RAW_IT → CURATED → ML_FEATURES → ML_MODELS → ANALYTICS → AGENT) — clean data flow with no circular dependencies
- **Single source of truth**: LIVE_PREDICTIONS dynamic table is the sole prediction output; every downstream view, alert, and dashboard reads from it
- **INCREMENTAL refresh** on PHYSICS_COMPOSITE and SENSOR_INTERACTIONS for efficiency (only new/changed rows processed)
- **Cortex Agent orchestration**: Not just a chatbot wrapper — the agent has genuine tool-use with procedures and functions as backends, persona-aware response formatting, and multi-tool chaining
- **Semantic View with 21 VQRs**: Verified query representations ensure text-to-SQL accuracy, not just schema exposure
- **Notification system decoupled from actions**: LOG_APP_NOTIFICATION reads NOTIFICATION_SETTINGS at runtime — admins change behavior without code deploys

---

### 3. Solution Completeness

**Scope coverage**: The solution addresses every link in the predictive maintenance value chain.

```
Sense → Converge → Predict → Diagnose → Decide → Act → Track → Learn
  │        │          │          │          │       │       │       │
  │        │          │          │          │       │       │       └─ Failure history DT
  │        │          │          │          │       │       └─ WO lifecycle + notifications
  │        │          │          │          │       └─ WO/PO creation (console + copilot)
  │        │          │          │          └─ Digital twin simulation
  │        │          │          └─ Root cause analysis (M5, Cortex Search RAG)
  │          │        └─ 14 ML models (M1-M7 + 3 native)
  │        └─ CURATED + ML_FEATURES dynamic tables
  └─ 560K+ sensor readings + 6 channels + 3 streams
```

**Feature inventory:**

| Category | Count | Details |
|---|---|---|
| Database schemas | 7 | Full separation of concerns |
| Base tables | 30 | OT sensors + IT ERP + notifications + procurement |
| Dynamic tables | 14 | Auto-refreshing pipeline, no manual ETL |
| Views | 31 | Analytics + ML features + procurement |
| ML models | 12 | 6 UDF-based + 3 native Snowflake ML + 3 on-demand procedures |
| UDFs | 6 | Prediction + simulation + anomaly scoring |
| Procedures | 27 | WO/PO lifecycle, root cause, prescriptive, notifications, automation |
| Cortex Search | 1 | 78 maintenance docs, RAG-ready |
| Semantic View | 1 | 6 tables, 21 verified queries |
| Cortex Agent | 1 | 5 tools, persona-aware orchestration |
| Streamlit pages | 8 | Executive, Operations, WO/PO, Maintenance, Procurement, Digital Twin, Admin, Copilot |
| User personas | 6 | Technician, Reliability Engineer, Shift Supervisor, Plant Manager, Procurement Admin, App Admin |
| Notification events | 16 | WO, PO, system, and operational event types |
| Automated tests | 80+ | 8 test files, Admin Panel integration |
| Documentation | 12 docs | README, Technical Guide, User Guide, Deployment Guide, Architecture, Process Flow, Test Cases, Submission, Presentation, Evaluation, ML Validation, Review |

**What elevates completeness beyond a demo:**

1. **Closed-loop procurement** — Predictions connect to parts availability (ATP), which connects to PO generation, which connects to supplier lead times, which connects back to simulation (part arrival vs failure timing). The enhanced PROCUREMENT_RECOMMENDATIONS view now factors in competing asset demand, incoming PO arrivals, net stock position, and buffer status (SURPLUS/TIGHT/DEFICIT). WO start auto-reserves parts. Stock Insights tab shows contention maps and consumption timelines. This is not a prediction dashboard with a "create PO" button bolted on — it is an integrated operational loop with supply/demand visibility.

2. **Persona-gated actions** — Technicians see their assigned WOs. Supervisors can start/complete WOs but can't approve POs. Procurement admins manage POs but can't manage WOs. Plant managers see financials. App admins see everything. This models real-world RBAC, not a single-user demo.

3. **Notification system** — Admin-configurable per event type (email on/off, in-app on/off, recipients, target personas, priority). Uses Snowflake-native SYSTEM$SEND_SNOWFLAKE_NOTIFICATION. No external email service required.

4. **Digital Twin with intervention comparison** — Not just "here's the prediction" but "here's what happens under 3 different intervention strategies with cost analysis." 300 Monte Carlo simulations (100 per scenario) with P10/P50/P90 confidence bounds.

5. **Test suite in the Admin Panel** — 80+ tests runnable from the UI with progress tracking and pass/fail KPIs. Not just developer tests — operational validation that plant admins can run.

6. **FinOps cost dashboard** — Built-in infrastructure cost monitoring using SNOWFLAKE.ACCOUNT_USAGE views. Credit consumption by service type, daily warehouse trends, query cost breakdown, storage analysis, DT refresh history, and resource monitor progress bar. No new tables — purely read-only system views. This is production-grade cost governance, not an afterthought.

7. **Session history in Copilot** — Previous conversations persisted in sidebar, restorable with one click. Role-aware welcome greetings. Greeting detection to avoid irrelevant data dumps on "hi."

8. **Configurable simulation console** — Admin-controlled sensor feed generator with 5 scenarios (clean + 4 fault modes), severity slider, asset targeting, credit estimation before execution, and production-linked output. Not a fixed data dump — a parameterized physics-based data generator that aligns synthetic readings with the chosen failure mode signature.

9. **User access management** — Add, edit, and deactivate users from the Admin Panel. Change personas, email, line assignment. All parameterized SQL, changes take effect immediately.

10. **OEE trend analysis** — Daily OEE trend per production line over 185 days with plant-wide average and 85% target reference line. Switchable between OEE, Availability, Performance, and Quality — enabling Plant Managers to track long-term trends, identify seasonal patterns, and measure the impact of maintenance campaigns. Uses a single cached query on the existing OEE_METRICS view — zero additional Snowflake objects or credit overhead.

11. **Supply chain risk visualizations** — Risk distribution donut chart, lead time gap bar chart by at-risk asset, and at-risk cost metric — providing an at-a-glance supply chain exposure view on the Executive Dashboard. All derived from the existing PROCUREMENT_RECOMMENDATIONS view with no additional queries.

12. **Live sensor data feed** — 24-hour sensor time-series in the Operations Center with asset filter, time range selector (1h/6h/12h/24h), latest reading KPIs (vibration, temperature, RPM, pressure, current, acoustic), channel time-series chart, and raw data export. Single cached query with 60s TTL, partition-pruned on TIMESTAMP — near-real-time monitoring at negligible credit cost.

13. **WO parts and activity tracking** — Each work order card in the WO/PO Console shows the recommended part with ATP, procurement risk badge, and linked PO (if applicable). An expandable activity log displays reassignment and follow-up history pulled from APP_NOTIFICATIONS — providing full traceability per work order.

14. **Raw data analysis tab** — Collapsible "Raw data for analysis" section at the bottom of the Executive Dashboard with a dataset selector (OEE by line, OEE daily trend, loss attribution, predictions, cost impact, procurement) for direct data inspection and ad-hoc analysis. Uses already-loaded data — zero additional queries.

15. **LLM-powered executive summaries** — Every dashboard page (Executive, Operations, WO/PO Console, Maintenance Hub, Procurement) includes a Cortex Complete (llama3.1-8b)-generated boardroom-ready executive summary. Live KPI data is assembled into a structured prompt following an executive communications template (outcomes, risks, next steps). Summaries are cached in session state keyed by data hash — regenerated only when underlying data changes or user clicks "Regenerate". Uses the smallest viable model (8b vs 70b) for ~10x credit efficiency while maintaining quality on structured KPI summarization.

16. **Bulk WO/PO operations** — WO/PO Console supports multi-select mode with checkboxes, "Select all visible" / "Deselect all" controls, and context-aware bulk action bars. Bulk Start validates ATP eligibility per WO and reports blocked items. Bulk Complete prompts for shared root cause and part-used status. Bulk Approve/Reject (with shared rejection reason) and status transitions (ordered/shipped/received) for POs. All actions use the same per-item SQL logic as single-card operations for consistency.

---

## What MFGPulse AI Does NOT Do (Honest Gaps)

| Gap | Why | Mitigation |
|---|---|---|
| No real-time streaming (sub-second) | Dynamic Tables use TARGET_LAG = 1 hour, not sub-second. Sensor feed is simulated via scheduled task. | Adequate for predictive maintenance (failures develop over hours/days, not milliseconds). 1-hour refresh cadence provides timely alerts. |
| Synthetic data, not real sensors | No physical OT integration (OPC-UA, MQTT). Sensor readings are generated by SQL procedures. | Data distribution models real-world patterns (bearing wear signatures, thermal degradation profiles, imbalance oscillations). |
| No mobile interface | Streamlit in Snowflake is desktop-optimized. | Responsive layout works on tablets. Mobile would require a separate native app. |
| ML models are rule-based/physics-informed, not deep learning | UDFs use weighted scoring and physics equations, not neural networks. | Matches real-world industrial practice — physics-informed models are more interpretable and trusted by reliability engineers than black-box DL. Native Snowflake ML models (3) add statistical rigor. |
| Single-plant scope | 10 assets, 3 lines, 1 plant. | Architecture scales — Dynamic Tables and UDFs work identically at 1000 assets. Schema design supports multi-plant extension. |

---

## Summary

| Judging Criterion | Self-Assessment | Evidence |
|---|---|---|
| **Real-World Relevance** | Directly addresses the IT/OT convergence problem that causes unplanned downtime. Models 6 real manufacturing personas, real procurement workflows (ATP, lead times, supplier management), real maintenance patterns (failure modes, RUL, fatigue). Cost-of-inaction analysis ties predictions to business impact. | 7-schema IT/OT architecture, 12 ML models, closed-loop procurement, persona-gated workflows, shift handover, notification system |
| **Technical Execution** | 100% Snowflake-native. Uses Dynamic Tables (14), Cortex AI (Complete, Search, Agent, Semantic Views), Snowflake ML (3 native models), Streams (3), 11-task DAG, Streamlit (8 pages), parameterized SQL, notification integration. No external services. | 27 SQL scripts, 6 UDFs, 27 procedures, 1 Cortex Agent with 5 tools, 1 Semantic View with 21 VQRs, Monte Carlo UDF, 2 warehouses with resource monitors |
| **Solution Completeness** | End-to-end: Sense → Converge → Predict → Diagnose → Decide → Act → Track → Learn. Includes procurement closed loop, WO/PO lifecycle with bulk operations, notification system, digital twin simulation, natural-language copilot, admin control panel, 80+ automated tests across 8 test files, and 12 documentation files. | 82 project files, 8 Streamlit pages, 6 personas, 16 event types, 80+ test cases, 12 docs |
