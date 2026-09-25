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
| **Cortex AI Agent** | 7-tool conversational assistant: text-to-SQL analytics, RAG search over maintenance logs, fast diagnosis (M1-M4), deep analysis (M5-M7), Monte Carlo simulation, work order generation, and purchase order generation |
| **Semantic View** | 6 tables with 4 many-to-one relationships, 19 verified queries, module custom instructions (sql_generation for score conventions, severity ordering, OEE formula, table routing; question_categorization for scope definition and out-of-scope rejection) |
| **Procurement Closed Loop** | ATP calculation, 4-level risk classification (NO_RISK → CRITICAL_SHORTAGE), automated PO generation, planned purchase orders with auto-conversion, supplier management |
| **Email & In-App Notifications** | Admin-configurable per event type with persona targeting, priority levels, and Snowflake-managed email delivery |
| **Role-Based Access** | 6 personas with persona-filtered navigation — each user sees only the pages and actions relevant to their role |
| **80+ Automated Tests** | 9 test files across 11 categories runnable from the Admin Panel with pass/fail tracking and acceptance criteria |
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
│    10-Task DAG                                   ↓                    │
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
│                           Cortex Agent (7 tools)                      │
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
- Cortex AI enabled: Cortex Complete, Cortex Search, Cortex Agent, Semantic Views
- Snowflake ML enabled: Classification, Forecast, AnomalyDetection (Enterprise edition+)
- Compute pool: `SYSTEM_COMPUTE_POOL_CPU` must exist (required for Streamlit)

### Deployment Steps

**Step 1 — Run the consolidated deployment script**

Open a SQL worksheet in Snowsight, set role to `ACCOUNTADMIN`, and run:

```
0 - Setup/scripts/deploy_one_time_consolidated.sql
```

This single script creates everything from zero: 1 database, 7 schemas, 2 warehouses, 23+ tables, 13 dynamic tables, 30+ views, 5 UDFs, 21+ procedures, 10 DAG tasks, 1 Cortex Search service, seed data (~175K+ rows), and a `DEPLOYMENT_LOG` table tracking each phase with timing and validation. Estimated: ~15-25 min, ~1-2 credits.

**Step 2 — Deploy Cortex Semantic View and Agent**

From the `cortex_project/` directory, deploy the Semantic View (6 tables, 4 relationships, 19 VQRs, custom instructions) and the Maintenance Copilot Agent (7 tools) using Snowflake's Cortex project tooling.

**Step 3 — Launch the Streamlit app**

Open `MFGPulse_AI_App/streamlit_app.py` in Snowsight. The app auto-detects the persona from the selected user profile and filters navigation accordingly.

### Helper Scripts

Additional scripts in `0 - Setup/scripts/` for operational scenarios:

| Script | Purpose |
|---|---|
| `Share_DB.sql` | Cross-account share and replication setup for MFGPULSE_DB |
| `Copy Share & Git.sql` | Copy shared database (MFGPULSE_DB_SHARED) into a local writable MFGPULSE_DB |
| `Truncate and Sync Share.sql` | Truncate local tables and reload from the shared database |
| `emergency_stop_all_credits.sql` | Emergency suspension of all warehouses, tasks, and compute pools |

See `0 - Setup/DEPLOYMENT_GUIDE.md` for the full deployment walkthrough, prerequisites, verification steps, cross-instance deployment, and teardown instructions.

---

## Object Inventory

| Category | Count | Details |
|---|---|---|
| **Schemas** | 7 | RAW_OT, RAW_IT, CURATED, ML_FEATURES, ML_MODELS, ANALYTICS, AGENT |
| **Base Tables** | 32 | Including NOTIFICATION_SETTINGS, APP_NOTIFICATIONS, SIMULATION_CONFIG, PART_RESERVATIONS, PURCHASE_ORDERS (with rejection tracking), WORK_ORDERS (with root cause + part used) |
| **Dynamic Tables** | 13 | 3 curated + 7 features + LIVE_PREDICTIONS + ACTIVE_ALERTS + OEE_METRICS |
| **Views** | 26 | 12 analytics (incl. PROCUREMENT_PERFORMANCE, SUPPLIER_SCORECARD) + 14 ML feature/training views |
| **Procedures** | 25+ | Including DAG support (REFRESH_FATIGUE_SCORES, REFRESH_ALL_DTS, SIMULATE_ALL_FEEDS_RANDOM), WO/PO lifecycle, notifications, drift detection, KPI snapshots |
| **UDFs** | 5 | Failure mode, RUL, degradation, fatigue, digital twin simulator |
| **ML Models** | 12 | 8 UDF-based (M1-M7) + 4 native Snowflake ML |
| **Streams** | 3 | Sensor readings, maintenance logs, work orders |
| **Tasks (DAG)** | 10 | MFGPULSE_AUTOMATION_DAG (root) → CHECK_FRESHNESS ∥ REFRESH_FATIGUE → REFRESH_DTS → ARCHIVE_ALERTS ∥ CHECK_DRIFT ∥ GENERATE_WOS → GENERATE_POS → CONVERT_PPOS → SNAPSHOT_KPIS (on MFGPULSE_AUTOMATION_WH) |
| **Warehouses** | 2 | COMPUTE_WH (interactive) + MFGPULSE_AUTOMATION_WH (DAG tasks) |
| **Resource Monitors** | 3 | HARDSTOP (account), MFGPULSE_CREDIT_GUARD (COMPUTE_WH), MFGPULSE_AUTOMATION_GUARD (automation WH) |
| **Cortex Search** | 1 | MAINTENANCE_SEARCH (78 indexed docs) |
| **Semantic View** | 1 | MAINTENANCE_SEMANTIC_VIEW (6 tables, 4 relationships, 19 VQRs, module custom instructions) |
| **Cortex Agent** | 1 | MAINTENANCE_COPILOT (7 tools: maintenance_analytics, maintenance_history, diagnose_asset, deep_analysis, simulate_scenario, generate_work_order, generate_purchase_order) |
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
| **AI Agent** | Cortex Agent (DATA_AGENT_RUN, 7 tools) |
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
MFGPulse/                                 # Workspace root
├── README.md                             # This file
├── .gitignore
│
├── 0 - Setup/                            # Deployment & operations
│   ├── DEPLOYMENT_GUIDE.md               # Full deployment walkthrough + cross-instance instructions
│   └── scripts/
│       ├── deploy_one_time_consolidated.sql   # Master deployment (14 checkpoints, all DDL + seed data)
│       ├── Share_DB.sql                       # Cross-account share & replication setup
│       ├── Copy Share & Git.sql               # Copy shared DB into local writable MFGPULSE_DB
│       ├── Truncate and Sync Share.sql        # Reload local tables from shared database
│       └── emergency_stop_all_credits.sql     # Emergency suspension of all resources
│
├── 1 - docs/                             # Documentation
│   ├── TECHNICAL_GUIDE.md                # Architecture, data model, ML pipeline, security
│   ├── USER_GUIDE.md                     # Per-persona walkthrough with workflows
│   └── PROCESS_FLOW.md                   # 12 business/technical process flow diagrams with DAG details
│
├── MFGPulse_AI_App/                      # Streamlit application
│   ├── streamlit_app.py                  # Entry point — persona login, navigation, notifications
│   ├── snowflake.yml                     # Deployment manifest (MFGPULSE_DB.AGENT.MFGPULSE_AI_APP)
│   ├── pyproject.toml                    # Python dependencies
│   ├── .streamlit/config.toml            # Dark industrial theme configuration
│   └── app_pages/
│       ├── _shared.py                    # Centralized data loaders, constants, formatters
│       ├── executive_dashboard.py        # Plant-wide KPIs, OEE, cost analysis
│       ├── operations_dashboard.py       # Fleet status, alert triage, shift handover
│       ├── wo_po_console.py              # Work order / purchase order management
│       ├── maintenance_dashboard.py      # Asset-level diagnostics, failure DNA
│       ├── procurement_dashboard.py      # ATP, risk recommendations, PO management
│       ├── digital_twin.py              # Monte Carlo simulation comparisons
│       ├── admin_control_panel.py        # Infrastructure, notifications, test suite
│       └── copilot.py                    # Cortex Agent conversational interface
│
├── cortex_project/                       # Cortex AI definitions
│   ├── cortex_project.yaml              # Project manifest
│   ├── MAINTENANCE_SEMANTIC_VIEW.sv.yaml # Semantic View (6 tables, 4 relationships, 19 VQRs, custom instructions)
│   └── MAINTENANCE_COPILOT_agent.yaml   # Cortex Agent (7 tools)
│
└── test_cases/                           # 80+ test cases across 9 files
    ├── test_data_integrity.sql           # TC-01: Schema, row counts, FKs, DTs (12 tests)
    ├── test_ml_pipeline.sql              # TC-02: Predictions, value ranges, UDFs (11 tests)
    ├── test_procurement.sql              # TC-03: ATP math, risk enums (5 tests)
    ├── test_notifications.sql            # TC-04: Event types, persona targeting (3 tests)
    ├── test_wo_po_lifecycle.sql          # TC-05: Status transitions, completion (5 tests)
    ├── test_simulation_scenarios.sql     # TC-06: Probability bounds, load effects (4 tests)
    ├── test_copilot_scenarios.sql        # TC-07: Search coverage, accuracy benchmarks (2+ tests)
    ├── test_persona_access.py            # TC-08: Page access matrix (11 tests)
    └── test_ml_edge_cases.sql            # TC-11: ML UDF boundary, null, zero, extreme inputs (10+ tests)
```

---

## Documentation

| Document | Audience | Content |
|---|---|---|
| **[TECHNICAL_GUIDE.md](1%20-%20docs/TECHNICAL_GUIDE.md)** | Developers, DBAs | Architecture, data model, ML pipeline, dynamic table chain, notification system, security model |
| **[USER_GUIDE.md](1%20-%20docs/USER_GUIDE.md)** | End users, operators | Per-persona page walkthroughs, workflow guides, FAQ, tips |
| **[PROCESS_FLOW.md](1%20-%20docs/PROCESS_FLOW.md)** | Engineers, architects | 12 end-to-end process flow diagrams: data ingestion, feature engineering, prediction, alerts, WO/PO lifecycle, notifications, drift detection, shift handover, digital twin, copilot, DAG automation |
| **[DEPLOYMENT_GUIDE.md](0%20-%20Setup/DEPLOYMENT_GUIDE.md)** | DevOps, DBAs | Full deployment walkthrough, prerequisites, verification, cross-instance replication, teardown |

---