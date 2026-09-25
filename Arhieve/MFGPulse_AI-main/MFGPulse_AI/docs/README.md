# MFGPulse AI — Predictive Maintenance & OEE Command Center

*Built entirely on Snowflake. Co-authored with CoCo (Cortex Code).*

---

## What Is MFGPulse AI?

MFGPulse AI is an enterprise-grade **Predictive Maintenance and Overall Equipment Effectiveness (OEE) Command Center** for manufacturing plants. It monitors 10 industrial assets across 3 production lines, predicts failures before they happen, prescribes corrective actions with cost justification, and closes the loop with procurement, work orders, and notifications — all running natively on Snowflake.

The platform name combines "MFG" (manufacturing) with "Pulse" (continuous monitoring heartbeat), while the internal codename **Failure Genome** reflects the philosophy that every machine failure has a unique DNA — a combination of sensor signatures, degradation trajectories, fatigue patterns, and operational context that can be decoded to prevent breakdowns.

---

## Key Capabilities

| Capability | Description |
|---|---|
| **12 ML models** | 7 UDF-based models (classifier, RUL estimator, degradation stager, fatigue detector, root cause analyzer, digital twin simulator, prescriptive engine) + 4 native Snowflake ML models |
| **13 Dynamic Tables** | Auto-refreshing feature engineering pipeline from raw sensors through curated features to live predictions — no manual ETL |
| **Monte Carlo Digital Twin** | 100 stochastic simulation paths per scenario (3 scenarios = 300 paths) projecting failure probability at 3, 7, and 14 days |
| **Cortex AI Agent** | 5-tool conversational assistant: text-to-SQL analytics, RAG search over maintenance logs, full 7-model diagnosis, Monte Carlo simulation, and work order generation |
| **Semantic View** | 6 tables with 4 many-to-one relationships, 19 verified queries, module custom instructions (sql_generation for score conventions, severity ordering, OEE formula, table routing; question_categorization for scope definition and out-of-scope rejection) |
| **Procurement Closed Loop** | ATP calculation, 4-level risk classification (NO_RISK → CRITICAL_SHORTAGE), automated PO generation, planned purchase orders with auto-conversion, supplier management |
| **Email & In-App Notifications** | Admin-configurable per event type with persona targeting, priority levels, and Snowflake-managed email delivery |
| **Role-Based Access** | 6 personas with persona-filtered navigation — each user sees only the pages and actions relevant to their role |
| **80+ Automated Tests** | 8 test categories runnable from the Admin Panel with pass/fail tracking and acceptance criteria |
| **OEE Trend Analysis** | Daily OEE trend line chart per production line with plant-wide average, 85% target reference line, and switchable metric view (OEE, Availability, Performance, Quality) — 185 days of trend data across 6 assets |
| **Supply Chain Risk Visualizations** | Risk distribution donut chart, lead time gap bar chart by asset, at-risk cost metric, and detailed at-risk parts table — all derived from existing procurement recommendations |
| **Live Sensor Data Feed** | 24-hour sensor time-series with asset/time-range filtering, latest reading KPIs, channel selector (vibration, temperature, RPM, current), and raw data export in the Operations Center |
| **Data-Driven Summaries** | LLM-generated executive summaries on each dashboard page via Cortex Complete (llama3.1-8b) — boardroom-ready narratives synthesizing KPIs, risks, and recommended actions from live data. Cached per session with regenerate button. |
| **FinOps Dashboard** | Built-in infrastructure cost monitor — credit consumption by service type, daily trends, query cost breakdown, storage analysis, DT refresh history, and resource monitor status |
| **Configurable Simulation** | Admin-controlled sensor feed generator — clean or fault scenarios (bearing wear, thermal degradation, imbalance, misalignment) with configurable severity, asset targeting, credit estimation, and production-linked output |
| **User Access Management** | Add, edit, deactivate users and change personas from the Admin Panel — all changes take effect immediately on the login screen |

---

## Architecture

```
┌──────────────────────────── DATA SOURCES ─────────────────────────────┐
│  Sensors (OT)              ERP / CMMS (IT)            Weather         │
│  vibration, temperature,   work orders, maintenance   ambient         │
│  RPM, pressure, current,   logs, parts, production,   conditions      │
│  acoustic emission         suppliers, schedules                       │
└──────────┬─────────────────────┬──────────────────────┬───────────────┘
           │                     │                      │
           ▼                     ▼                      ▼
┌───────────────────── MFGPULSE_DB ───────────────────────────────┐
│                                                                       │
│  RAW_OT / RAW_IT  →  CURATED (3 DTs)  →  ML_FEATURES (7 DTs)        │
│         ↓                                        ↓                    │
│    3 Streams                            LIVE_PREDICTIONS (DT)         │
│    9-Task DAG                                    ↓                    │
│                                    ┌─────────────┴──────────────┐     │
│                                    ▼                            ▼     │
│                              ML_MODELS                    ANALYTICS   │
│                           12 models registered         9 views, 2 DTs │
│                           Cortex Search (78 docs)      Alert engine   │
│                           5 UDFs, 25 procedures       OEE + PPO eng. │
│                                    │                                  │
│                                    ▼                                  │
│                                  AGENT                                │
│                           Semantic View (6 tables, 19 VQRs)            │
│                           Cortex Agent (5 tools)                      │
│                                                                       │
└───────────────────────────────┬───────────────────────────────────────┘
                                │
                                ▼
┌──── Streamlit App (9 pages) ──────────────────────────────────────────┐
│  Executive  │  Operations  │  WO/PO Console  │  Maintenance Hub       │
│  Procurement  │  Digital Twin  │  Admin Panel  │  Copilot              │
│                                                                       │
│  6 Personas: Technician, Reliability Engineer, Shift Supervisor,      │
│              Plant Manager, Procurement Admin, Application Admin       │
│                                                                       │
│  Notifications: 16 event types  →  Email (MFGPULSE_EMAIL integration) │
│                                →  In-app (persona-targeted bell icon) │
└───────────────────────────────────────────────────────────────────────┘
```

---

## Personas & Page Access

| Persona | Icon | Pages |
|---|---|---|
| **Technician** | :wrench: | Maintenance Hub, WO/PO Console, Operations, Procurement, Copilot |
| **Reliability Engineer** | :mag: | Maintenance Hub, Digital Twin, WO/PO Console, Operations, Procurement, Copilot |
| **Shift Supervisor** | :arrows_counterclockwise: | Operations, WO/PO Console, Maintenance Hub, Procurement, Executive, Copilot |
| **Plant Manager** | :bar_chart: | Executive, Operations, WO/PO Console, Maintenance Hub, Procurement, Admin Panel, Copilot |
| **Procurement Admin** | :truck: | Procurement, WO/PO Console, Maintenance Hub, Operations, Copilot |
| **Application Admin** | :shield: | All 9 pages (super-admin access) |

---

## Quick Start

### Prerequisites

- Snowflake account with `ACCOUNTADMIN` role (or equivalent privileges)
- Warehouse: `COMPUTE_WH` (interactive) + `MFGPULSE_AUTOMATION_WH` (DAG tasks)
- Compute pool: `SYSTEM_COMPUTE_POOL_CPU` (for Streamlit)

### Deployment Steps

**Step 1 — Run SQL scripts in order**

Execute each script sequentially in a Snowflake SQL worksheet:

| Script | Purpose |
|---|---|
| `sql/01_infrastructure.sql` | Database, schemas, warehouse, resource monitor |
| `sql/02_base_tables.sql` | 19 base tables across RAW_OT and RAW_IT |
| `sql/03_streams.sql` | 3 CDC streams on sensor readings, maintenance logs, work orders |
| `sql/04_seed_data.sql` | Reference data: 10 assets, 3 lines, 15 parts, 5 suppliers, 9 users, shifts |
| `sql/05_generate_sensor_data.sql` | 172K+ synthetic sensor readings (30-day history) |
| `sql/06_fatigue_scores.sql` | Physics-based fatigue scoring |
| `sql/07_curated_dynamic_tables.sql` | 3 curated DTs: sensor context, asset health, failure history |
| `sql/08_ml_feature_dynamic_tables.sql` | 7 feature engineering DTs (rolling stats, interactions, temporal, physics, fleet) |
| `sql/09_ml_feature_views.sql` | 11 ML feature views |
| `sql/10_udfs_live_predictions.sql` | 5 UDFs + LIVE_PREDICTIONS dynamic table |
| `sql/11_native_ml_models.sql` | 4 native Snowflake ML models (classification, forecasting, anomaly detection) |
| `sql/12_analytics_layer.sql` | Analytics views + ACTIVE_ALERTS and OEE_METRICS DTs |
| `sql/13_cortex_search.sql` | Cortex Search service over maintenance logs (78 docs) |
| `sql/14_automation.sql` | 3 scheduled tasks (sensor feed, production, procurement) |
| `sql/15_procurement_tables.sql` | Procurement tables (suppliers, parts, POs, reservations) |
| `sql/16_procurement_views.sql` | ATP and procurement recommendation views |
| `sql/17_procurement_procedures.sql` | PO lifecycle + work order procedures |
| `sql/18_validation.sql` | Full infrastructure verification suite |
| `sql/19_notifications.sql` | Notification settings, app notifications, email integration |

**Step 2 — Deploy Cortex Semantic View and Agent**

From the `cortex_project/` directory, deploy the Semantic View (6 tables, 4 relationships, 19 VQRs, custom instructions) and the Maintenance Copilot Agent (5 tools) using Snowflake's Cortex project tooling.

**Step 3 — Launch the Streamlit app**

Open `MFGPulse_AI_App/streamlit_app.py` in Snowsight. The app auto-detects the persona from the selected user profile and filters navigation accordingly.

---

## Object Inventory

| Category | Count | Details |
|---|---|---|
| **Schemas** | 7 | RAW_OT, RAW_IT, CURATED, ML_FEATURES, ML_MODELS, ANALYTICS, AGENT |
| **Base Tables** | 32 | Including NOTIFICATION_SETTINGS, APP_NOTIFICATIONS, SIMULATION_CONFIG, PART_RESERVATIONS, PURCHASE_ORDERS (with rejection tracking), WORK_ORDERS (with root cause + part used) |
| **Dynamic Tables** | 13 | 3 curated + 7 features + LIVE_PREDICTIONS + ACTIVE_ALERTS + OEE_METRICS |
| **Views** | 26 | 12 analytics (incl. PROCUREMENT_PERFORMANCE, SUPPLIER_SCORECARD) + 14 ML feature/training views |
| **Procedures** | 17 | Including DAG support (REFRESH_FATIGUE_SCORES, REFRESH_ALL_DTS, SIMULATE_ALL_FEEDS_RANDOM), WO/PO lifecycle, notifications |
| **UDFs** | 5 | Failure mode, RUL, degradation, fatigue, digital twin simulator |
| **ML Models** | 12 | 8 UDF-based (M1-M7) + 4 native Snowflake ML |
| **Streams** | 3 | Sensor readings, maintenance logs, work orders |
| **Tasks (DAG)** | 6 | MFGPULSE_AUTOMATION_DAG → Fatigue → DTs → WOs → POs → PPOs (on MFGPULSE_AUTOMATION_WH) |
| **Warehouses** | 2 | COMPUTE_WH (interactive) + MFGPULSE_AUTOMATION_WH (DAG tasks) |
| **Resource Monitors** | 3 | HARDSTOP (account), MFGPULSE_CREDIT_GUARD (COMPUTE_WH), MFGPULSE_AUTOMATION_GUARD (automation WH) |
| **Cortex Search** | 1 | MAINTENANCE_SEARCH (78 indexed docs) |
| **Semantic View** | 1 | MAINTENANCE_SEMANTIC_VIEW (6 tables, 4 relationships, 19 VQRs, module custom instructions) |
| **Cortex Agent** | 1 | MAINTENANCE_COPILOT (5 tools) |
| **Notification Integration** | 1 | MFGPULSE_EMAIL (TYPE=EMAIL) |
| **Streamlit Pages** | 9 | Executive, Operations, WO/PO, Maintenance, Procurement, Digital Twin, Admin, Copilot |
| **Sensor Readings** | 172K+ | 30-day history, 15-min intervals, 10 assets |
| **Test Cases** | 80+ | 11 categories, runnable from Admin Panel |

---

## Technology Stack

| Component | Technology |
|---|---|
| **Database** | Snowflake (MFGPULSE_DB) |
| **Feature Engineering** | Dynamic Tables (TARGET_LAG = 1 hour, auto-refresh) |
| **ML Models** | SQL UDFs + Snowflake.ML (Classification, Forecast, AnomalyDetection) |
| **LLM** | Snowflake Cortex Complete (llama3.1-70b) |
| **RAG** | Cortex Search (78 maintenance docs, SEARCH_PREVIEW enabled) |
| **AI Agent** | Cortex Agent (DATA_AGENT_RUN, 5 tools) |
| **Semantic Layer** | Cortex Semantic View (6 tables, 4 relationships, 19 VQRs, module custom instructions) |
| **Frontend** | Streamlit in Snowflake (multipage, st.navigation) |
| **Notifications** | SYSTEM$SEND_SNOWFLAKE_NOTIFICATION + APP_NOTIFICATIONS table |
| **Simulation** | Monte Carlo UDF (100 stochastic paths per scenario) |
| **Data Freshness SLA** | DATA_FRESHNESS_SLA view + CHECK_DATA_FRESHNESS proc (120-min SLA, auto-notification) |
| **Model Drift Detection** | DRIFT_COMPARISON + DRIFT_METRICS + COMPUTE_NATIVE_PREDICTIONS (rule-based vs native ML, 80% threshold, auto-retrain via RETRAIN_IF_NEEDED) |
| **Closed-Loop ML** | FEEDBACK_LOG + MODEL_ACCURACY_LIVE + LOG_FEEDBACK (WO root cause → prediction accuracy → retrain trigger) |
| **KPI Trending** | KPI_SNAPSHOTS + ALERT_HISTORY + OEE_PERIOD_COMPARISON (daily snapshots, week-over-week deltas) |
| **Security** | Parameterized SQL throughout, persona-gated write operations |
| **Monitoring** | Resource monitor (MFGPULSE_CREDIT_GUARD, 250 credits/month) |

---

## Project Structure

```
MFGPulse_AI/
├── MFGPulse_AI_App/          # Streamlit application
│   ├── streamlit_app.py               # Entry point — persona login, navigation, notifications
│   ├── snowflake.yml                  # Deployment manifest
│   ├── pyproject.toml                 # Python dependencies
│   ├── .streamlit/config.toml         # Theme configuration
│   └── app_pages/
│       ├── _shared.py                 # Centralized data loaders, constants, formatters
│       ├── executive_dashboard.py     # Plant-wide KPIs, OEE, cost analysis
│       ├── operations_dashboard.py    # Fleet status, alert triage, shift handover
│       ├── wo_po_console.py           # Work order / purchase order management
│       ├── maintenance_dashboard.py   # Asset-level diagnostics, failure DNA
│       ├── procurement_dashboard.py   # ATP, risk recommendations, PO management
│       ├── digital_twin.py            # Monte Carlo simulation comparisons
│       ├── admin_control_panel.py     # Infrastructure, notifications, test suite
│       └── copilot.py                 # Cortex Agent conversational interface
│
├── sql/                               # DDL & seed data (run in order: 01 → 20)
│   ├── 01_infrastructure.sql          # Database, schemas, warehouse
│   ├── 02_base_tables.sql             # 19 base tables
│   ├── ...                            # (see Deployment Steps above)
│   ├── 16_procurement_views.sql       # 5 procurement views (ATP, Recs, Lifecycle, Performance, Scorecard)
│   ├── 19_notifications.sql           # Notification system
│   ├── 20_configurable_simulation.sql # Configurable simulation
│   ├── deploy_one_time_consolidated.sql # Master deployment script (4800+ lines, fully self-contained)
│   ├── deployment_report.sql          # Post-deployment verification report
│   ├── credit_consumption_report.sql  # Credit usage analysis and cost projections
│   └── ddl_objects.sql                # Executable UDF + procedure DDL for cross-instance deployment
│
├── cortex_project/                    # Cortex AI definitions
│   ├── cortex_project.yaml            # Project manifest
│   ├── MAINTENANCE_SEMANTIC_VIEW.sv.yaml   # Semantic View (6 tables, 4 relationships, 19 VQRs, custom instructions)
│   └── MAINTENANCE_COPILOT_agent.yaml      # Cortex Agent (5 tools)
│
├── test_cases/                        # 80+ test cases
│   ├── test_data_integrity.sql        # TC-01: Schema, row counts, FKs, DTs (12 tests)
│   ├── test_ml_pipeline.sql           # TC-02: Predictions, value ranges, UDFs (11 tests)
│   ├── test_procurement.sql           # TC-03: ATP math, risk enums (5 tests)
│   ├── test_notifications.sql         # TC-04: Event types, persona targeting (3 tests)
│   ├── test_wo_po_lifecycle.sql       # TC-05: Status transitions, completion (5 tests)
│   ├── test_simulation_scenarios.sql  # TC-06: Probability bounds, load effects (4 tests)
│   ├── test_copilot_scenarios.sql     # TC-07: Search coverage, accuracy benchmarks (2+ tests)
│   └── test_persona_access.py         # TC-08: Page access matrix (11 tests)
│
├── docs/                              # Documentation
│   ├── README.md                      # This file
│   ├── TECHNICAL_GUIDE.md             # Architecture, data model, ML pipeline, security
│   ├── USER_GUIDE.md                  # Per-persona walkthrough with workflows
│   ├── TEST_CASES_GUIDE.md            # Test catalog and acceptance criteria
│   └── full_ddl_export.sql            # Consolidated DDL for reference
│
├── PLAN.md                            # Implementation plan (7 phases)
└── PLAN_v1_original.md                # Original plan (pre-revision)
```

---

## Documentation

| Document | Audience | Content |
|---|---|---|
| **[TECHNICAL_GUIDE.md](TECHNICAL_GUIDE.md)** | Developers, DBAs | Architecture, data model, ML pipeline, dynamic table chain, notification system, security model |
| **[USER_GUIDE.md](USER_GUIDE.md)** | End users, operators | Per-persona page walkthroughs, workflow guides, FAQ, tips |
| **[DEPLOYMENT_GUIDE.md](DEPLOYMENT_GUIDE.md)** | DevOps, DBAs | Full deployment walkthrough + cross-instance deployment instructions |
| **[TEST_CASES_GUIDE.md](TEST_CASES_GUIDE.md)** | QA, developers | Test catalog with IDs, descriptions, acceptance criteria, how to run |
| **[full_ddl_export.sql](full_ddl_export.sql)** | DBAs | Consolidated DDL for all database objects |

---

## Credits

Built on **Snowflake** using Dynamic Tables, Cortex AI (Complete, Search, Agent, Semantic Views), Snowflake ML, and Streamlit in S