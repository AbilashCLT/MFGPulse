# MFGPulse AI — Submission Deck Content Guide

*What to present, what to say, and what evidence to cite.*

---

## 1. Problem Brief

### The Business Problem

**Unplanned downtime is the single largest controllable cost in manufacturing.**

Every manufacturing plant generates two streams of data that never meet: OT (Operational Technology) sensor data — vibration, temperature, RPM, pressure — sits in historians or PLCs, while IT (Information Technology) data — work orders, maintenance logs, parts inventory, supplier lead times — lives in ERP and CMMS systems. When these data streams remain siloed, failures are discovered reactively: a machine breaks, production stops, emergency repairs cost 4-5x more than planned maintenance, and OEE (Overall Equipment Effectiveness) drops below target.

The problem is not a lack of data. Modern plants instrument everything. The problem is **convergence** — the inability to correlate sensor signatures with maintenance context in real time, predict what will fail, understand why, and act before it happens.

### Target Users / Personas

MFGPulse AI serves 6 distinct manufacturing personas, each with different information needs and action authority:

| Persona | Role in the Plant | What They Need from the System |
|---|---|---|
| **Technician** | Executes repairs on the shop floor | "Which asset do I fix next? What parts do I need? What's the root cause?" |
| **Reliability Engineer** | Analyzes failure patterns, plans interventions | "Why is this asset degrading? What if we reduce load? Show me the failure DNA." |
| **Shift Supervisor** | Manages shift operations, dispatches technicians | "What happened last shift? What's critical right now? Who's assigned to what?" |
| **Plant Manager** | Owns plant KPIs, approves budgets | "What's our OEE? How much downtime did we prevent? What's the ROI on maintenance?" |
| **Procurement Admin** | Manages parts supply chain | "Which parts are short? Which POs need approval? Will parts arrive before failure?" |
| **Application Admin** | Manages platform configuration | "Are all pipelines running? What's the system health? Configure notification routing." |

### Current Pain Points → How MFGPulse AI Solves Them

| Current Pain Point | Impact | MFGPulse AI Solution |
|---|---|---|
| Sensor data and ERP data live in separate systems | Failures detected only after breakdown | 13 Dynamic Tables auto-converge OT sensors with IT records into unified predictions |
| Maintenance is reactive (fix-when-broken) | Emergency repairs cost 4.3x more than planned | 12 ML models predict failures with RUL, failure mode, degradation stage, and hidden fatigue detection |
| Root cause investigation is manual, slow | Engineers spend hours correlating logs with sensor trends | Cortex Agent performs natural-language root cause analysis using RAG search over 78 maintenance documents + 7-model diagnosis |
| Work order creation is disconnected from predictions | Delayed response to predicted failures | One-click WO generation from alerts, or natural-language creation via Copilot ("Create a preventive WO for Fan F1") |
| Parts availability unknown at time of WO creation | Technician arrives to repair but parts unavailable | ATP (Available-to-Promise) calculation + procurement risk classification (NO_RISK → CRITICAL_SHORTAGE) + PO auto-generation |
| Shift handover is verbal, informal | Context lost between shifts | Dedicated Shift Handover view with critical actions, plant OEE, procurement readiness, alert summary |
| No cost justification for preventive maintenance | Budget approval delayed | Every prediction includes failure cost, repair cost, and "cost of inaction" ($failure − $repair) |
| Different roles see same dashboard | Information overload or insufficient access | 6 persona-filtered navigation paths with action permissions gated by role |

### Industry / Domain Context

- **Industry**: Discrete and process manufacturing (applicable to automotive, pharma, food & beverage, metals, chemicals)
- **Domain**: Predictive Maintenance (PdM) and Overall Equipment Effectiveness (OEE)
- **Plant profile**: 10 industrial assets (compressors, pumps, motors, fans, gearboxes, conveyors, turbines) across 3 production lines
- **Sensor channels**: Vibration (X/Y/Z axes), temperature, RPM, current draw, acoustic emission, pressure — 6 channels per asset at 15-minute intervals
- **Data volume**: 560,743 sensor readings — representative of a mid-size manufacturing facility with continuous monitoring

---

## 2. Architecture Diagram

### System Design — Data Flow

```
┌──────────────────────────── DATA SOURCES ──────────────────────────────┐
│                                                                        │
│   ┌─── OT (Shop Floor) ────┐    ┌─── IT (ERP / CMMS) ──────────────┐ │
│   │                         │    │                                    │ │
│   │  SENSOR_READINGS        │    │  WORK_ORDERS                      │ │
│   │  172K rows, 6 channels  │    │  MAINTENANCE_LOGS                 │ │
│   │  15-min intervals       │    │  PARTS_INVENTORY                  │ │
│   │                         │    │  SUPPLIERS / PART_SUPPLIERS        │ │
│   │  ASSET_MASTER (10)      │    │  PRODUCTION_OUTPUT                │ │
│   │  SENSOR_METADATA        │    │  SHIFT_SCHEDULE                   │ │
│   │  AMBIENT_CONDITIONS     │    │  USERS (9 users, 6 personas)      │ │
│   │                         │    │  PURCHASE_ORDERS / PO_LINES       │ │
│   └──────────┬──────────────┘    │  NOTIFICATION_SETTINGS            │ │
│              │                   └──────────────┬─────────────────────┘ │
└──────────────┼──────────────────────────────────┼──────────────────────┘
               │                                  │
               │    ┌─── CDC Streams ──────────┐  │
               │    │ SENSOR_READINGS_STREAM   │  │
               │    │ MAINTENANCE_LOGS_STREAM  │  │
               │    │ WORK_ORDERS_STREAM       │  │
               │    └──────────────────────────┘  │
               │                                  │
               ▼                                  ▼
┌─────────────────────── CONVERGENCE LAYER ─────────────────────────────┐
│                                                                        │
│  CURATED Schema (3 Dynamic Tables)                                     │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  SENSOR_WITH_CONTEXT ── OT sensors + IT asset metadata joined    │  │
│  │  ASSET_HEALTH_CURRENT ── Latest reading per asset + 24h stats    │  │
│  │  FAILURE_HISTORY ── Pre-failure sensor patterns (7-day windows)  │  │
│  └──────────────────────────────┬───────────────────────────────────┘  │
│                                 │                                      │
│                                 ▼                                      │
│  ML_FEATURES Schema (7 Dynamic Tables — auto-refreshing)               │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  LABELED_DATA ──► ROLLING_STATS (6h/24h mean, std, crest, RMS)  │  │
│  │               ──► SENSOR_INTERACTIONS (cross-sensor correlation) │  │
│  │               ──► TEMPORAL_MEMORY (trend slopes, breach history) │  │
│  │               ──► CROSS_DOMAIN (IT+OT: days since maint, hours) │  │
│  │               ──► PHYSICS_COMPOSITE (stress, health, ISO 10816) │  │
│  │               ──► FLEET_COMPARISON (z-scores vs fleet mean)     │  │
│  └──────────────────────────────┬───────────────────────────────────┘  │
└─────────────────────────────────┼─────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────── PREDICTION LAYER ──────────────────────────────┐
│                                                                        │
│  ML_MODELS Schema                                                      │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │                    LIVE_PREDICTIONS (DT)                         │  │
│  │                   The single source of truth                     │  │
│  │                                                                  │  │
│  │  Calls 3 UDFs per row:                                          │  │
│  │    M1 PREDICT_FAILURE_MODE()  → 5-class failure mode            │  │
│  │    M2 PREDICT_RUL()           → Hours to failure (P10/P50/P90)  │  │
│  │    M3 PREDICT_DEGRADATION()   → Healthy / Warning / Critical    │  │
│  │                                                                  │  │
│  │  Joins:                                                          │  │
│  │    M4 FATIGUE_SCORES          → Hidden fatigue (0-1)            │  │
│  │    PHYSICS_COMPOSITE          → Health score, stress index      │  │
│  │                                                                  │  │
│  │  On-demand (via Agent or UI):                                   │  │
│  │    M5 ANALYZE_ROOT_CAUSE()    → LLM + RAG root cause           │  │
│  │    M6 SIMULATE_FAILURE_TWIN() → 100-path Monte Carlo           │  │
│  │    M7 PRESCRIBE_MAINTENANCE() → LLM action recommendation      │  │
│  └──────────────────────────────┬───────────────────────────────────┘  │
│                                                                        │
│  + 3 Native Snowflake ML Models:                                       │
│    NATIVE_FAILURE_MODE_CLASSIFIER  (Classification, 142K rows)         │
│    NATIVE_DEGRADATION_STAGER       (Classification, 137K rows)         │
│    NATIVE_RUL_FORECASTER           (Forecast, 20K rows)                │
│                                                                        │
│  + Anomaly Detection: ANOMALY_SCORES table (50K+ scores)               │
│                                                                        │
│  + Cortex Search: MAINTENANCE_SEARCH (78 docs, RAG-ready)             │
│  + Model Registry: 12 models tracked                                   │
└─────────────────────────────────┬─────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────── ANALYTICS LAYER ───────────────────────────────┐
│                                                                        │
│  ANALYTICS Schema                                                      │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  ACTIVE_ALERTS (DT)     ── Multi-signal alert engine (4 levels) │  │
│  │  OEE_METRICS (DT)       ── Per-asset-per-shift OEE calculation  │  │
│  │  EXECUTIVE_SUMMARY      ── Plant-wide KPIs (OEE, ROI, costs)   │  │
│  │  PREDICTIONS_WITH_COST  ── Predictions + failure/repair costs   │  │
│  │  COST_IMPACT_BY_ASSET   ── Per-asset cost breakdown             │  │
│  │  SHIFT_HANDOVER_VIEW    ── Shift briefing data                  │  │
│  │  PROCUREMENT_RECOMMENDATIONS ── Risk-classified parts           │  │
│  │  PARTS_AVAILABLE_TO_PROMISE  ── ATP calculation                 │  │
│  └──────────────────────────────┬───────────────────────────────────┘  │
│                                                                        │
│  27 Procedures:                                                        │
│    GENERATE_WORK_ORDER, AUTO_GENERATE_WORK_ORDERS,                     │
│    GENERATE_SHIFT_HANDOVER_SUMMARY, GENERATE_PURCHASE_ORDER,           │
│    AUTO_GENERATE_PURCHASE_ORDERS, AUTO_CONVERT_PLANNED_POS,            │
│    COMPLETE_WORK_ORDER, PROCESS_INVENTORY_TRANSACTION,                  │
│    RESERVE_PART_FOR_WORK_ORDER, SEND_MFGPULSE_EMAIL,                  │
│    LOG_APP_NOTIFICATION, PREDICT_ALL, PREDICT_CORE, PREDICT_DEEP,     │
│    ANALYZE_ROOT_CAUSE, PRESCRIBE_MAINTENANCE, LOG_FEEDBACK,            │
│    COMPUTE_NATIVE_PREDICTIONS, RETRAIN_IF_NEEDED,                      │
│    REFRESH_FATIGUE_SCORES, REFRESH_ALL_DTS, CHECK_DATA_FRESHNESS,     │
│    SNAPSHOT_KPIS, ARCHIVE_ALERTS, AUTO_COMPLETE_AGED_WORK_ORDERS,     │
│    SIMULATE_SENSOR_FEED_CONFIGURABLE, SIMULATE_ALL_FEEDS_RANDOM       │
└─────────────────────────────────┬─────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────── AGENT LAYER ───────────────────────────────────┐
│                                                                        │
│  AGENT Schema                                                          │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  MAINTENANCE_SEMANTIC_VIEW (6 tables, 21 VQRs)                  │  │
│  │    → Text-to-SQL for structured analytics queries               │  │
│  │                                                                  │  │
│  │  MAINTENANCE_COPILOT (Cortex Agent, 5 tools)                    │  │
│  │    Tool 1: maintenance_analytics  → Semantic View text-to-SQL   │  │
│  │    Tool 2: maintenance_history    → Cortex Search RAG           │  │
│  │    Tool 3: predict_all            → Full 7-model diagnosis      │  │
│  │    Tool 4: simulate_scenario      → Monte Carlo simulation      │  │
│  │    Tool 5: generate_work_order    → Create + file a WO          │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└─────────────────────────────────┬─────────────────────────────────────┘
                                  │
                                  ▼
┌─────────────────────── PRESENTATION LAYER ────────────────────────────┐
│                                                                        │
│  Streamlit in Snowflake (8 Pages, 6 Personas)                          │
│                                                                        │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────┐ ┌────────────┐  │
│  │Executive │ │Operations│ │ WO / PO  │ │Maintenan.│ │Procurement │  │
│  │Dashboard │ │ Center   │ │ Console  │ │   Hub    │ │ Dashboard  │  │
│  └──────────┘ └──────────┘ └──────────┘ └──────────┘ └────────────┘  │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐                               │
│  │ Digital  │ │  Admin   │ │Maintenan.│                               │
│  │   Twin   │ │  Panel   │ │ Copilot  │                               │
│  └──────────┘ └──────────┘ └──────────┘                               │
│                                                                        │
│  Notification System:                                                  │
│  ┌──────────────────────────────────────────────────────────────────┐  │
│  │  7 Event Types → LOG_APP_NOTIFICATION → NOTIFICATION_SETTINGS   │  │
│  │    → In-app (per-persona bell icon, 15s refresh)                │  │
│  │    → Email (MFGPULSE_EMAIL integration, Snowflake-managed)      │  │
│  └──────────────────────────────────────────────────────────────────┘  │
└────────────────────────────────────────────────────────────────────────┘
```

### CoCo CLI Skills Used and How They Connect

| CoCo Skill | How It Was Used | What It Produced |
|---|---|---|
| **sql-author** | Authored and validated all SQL DDL — 27 scripts covering infrastructure, tables, dynamic tables, UDFs, procedures, views, and notification system | 7 schemas, 30 tables, 14 DTs, 31 views, 6 UDFs, 27 procedures |
| **streamlit-in-workspaces** | Built the 8-page Streamlit app with multipage navigation, persona routing, st.cache_data patterns, st.navigation, st.segmented_control, st.pills, st.status | 8 Streamlit pages + router + shared module |
| **agent-studio** | Created and deployed Cortex Semantic View (6 tables, 21 VQRs) and Cortex Agent (5 tools with orchestration instructions) | MAINTENANCE_SEMANTIC_VIEW + MAINTENANCE_COPILOT agent |
| **machine-learning** | Designed ML model architecture (M1-M7), native Snowflake ML training (Classification, Forecast, AnomalyDetection), model registry | 12 ML models registered and operational |
| **snowflake-tasks** | Configured 11-task DAG for end-to-end automation: simulation → freshness check → fatigue → DT refresh → drift check → WO gen → PO gen → PPO conversion → KPI snapshot → alert archive | 11-task DAG (MFGPULSE_AUTOMATION_DAG + 10 children) on MFGPULSE_AUTOMATION_WH |
| **data-governance** | Parameterized SQL throughout, persona-gated write operations, resource monitor setup | Security model with no SQL injection vectors |
| **cost-intelligence** | Built FinOps dashboard using ACCOUNT_USAGE views for credit consumption, query costs, storage, and DT refresh monitoring | Admin Panel FinOps section with 6 panels |
| **skill-development** | Iterative refinement of copilot behavior — greeting detection, pill deduplication, session history, role-aware welcome messages | Production-quality copilot experience |

### Data Sources

| Source Type | Schema | Objects | Nature |
|---|---|---|---|
| **Structured — OT** | RAW_OT | SENSOR_READINGS (560K+ rows), ASSET_MASTER (10), SENSOR_METADATA, AMBIENT_CONDITIONS | Time-series sensor data + asset registry |
| **Structured — IT** | RAW_IT | WORK_ORDERS, MAINTENANCE_LOGS, PARTS_INVENTORY, SUPPLIERS, PRODUCTION_OUTPUT, SHIFT_SCHEDULE, USERS, PURCHASE_ORDERS, NOTIFICATION_SETTINGS, APP_NOTIFICATIONS | ERP/CMMS transactional data |
| **Unstructured — Maintenance Logs** | ML_MODELS | MAINTENANCE_SEARCH (Cortex Search, 78 docs) | Free-text technician notes indexed for RAG retrieval |
| **Derived — Features** | ML_FEATURES | 7 Dynamic Tables (ROLLING_STATS, SENSOR_INTERACTIONS, TEMPORAL_MEMORY, CROSS_DOMAIN, PHYSICS_COMPOSITE, FLEET_COMPARISON, LABELED_DATA) | Auto-engineered ML features from converged IT/OT data |
| **System — FinOps** | SNOWFLAKE.ACCOUNT_USAGE | METERING_HISTORY, WAREHOUSE_METERING_HISTORY, QUERY_HISTORY, TASK_HISTORY + INFORMATION_SCHEMA.TABLES, DYNAMIC_TABLE_REFRESH_HISTORY() | Credit consumption, query costs, storage, DT refresh, task execution monitoring |
| **Simulation** | RAW_OT / RAW_IT | SIMULATE_SENSOR_FEED_CONFIGURABLE procedure + SIMULATION_CONFIG table | Parameterized sensor + production data generation with 5 scenarios and credit estimation |

### How Modular Components Plug Together

The architecture is designed as a **layered pipeline** where each layer has a single responsibility and connects to the next through well-defined interfaces:

```
Layer 1: INGESTION      → Raw data lands in RAW_OT / RAW_IT (append-only)
Layer 2: CHANGE CAPTURE → 3 Streams detect new/changed rows
Layer 3: CONVERGENCE    → CURATED DTs join OT + IT (auto-refresh)
Layer 4: FEATURES       → ML_FEATURES DTs compute 50+ engineered features (auto-refresh)
Layer 5: PREDICTION     → LIVE_PREDICTIONS DT calls UDFs on every refresh
Layer 6: ANALYTICS      → Views and DTs expose business metrics, alerts, costs
Layer 7: AGENT          → Semantic View + Agent provide natural-language access
Layer 8: PRESENTATION   → Streamlit pages consume analytics + agent layers
Layer 9: ACTION         → Procedures (WO, PO, notifications) write back to RAW_IT
```

**No circular dependencies.** Data flows strictly downward from ingestion to presentation. Action procedures write back to RAW_IT (the ingestion layer), which triggers the pipeline to re-process — creating a feedback loop through the standard data flow, not a shortcut.

---

## 3. Impact Statement

### Measurable Outcomes (from Live System)

These metrics are pulled from the running MFGPulse AI deployment on MFGPULSE_DB:

| Metric | Value | Source |
|---|---|---|
| **Total cost avoided** | $47,400 | EXECUTIVE_SUMMARY view — aggregate value of predicted failures that were or could be addressed preventively |
| **Maintenance ROI** | 3.3x | Cost avoided / total maintenance spend ($59,515) |
| **Emergency cost multiplier** | 4.3x | Average emergency failure cost ($10,317) vs planned repair cost ($2,417) — the financial penalty of reactive maintenance |
| **Assets monitored** | 10 across 3 lines | ASSET_MASTER — compressors, pumps, motors, fans, gearboxes, conveyors, turbines |
| **Sensor readings processed** | 172,326 initially, now 560K+ | Continuous generation via simulation DAG, 6 channels per asset, 15-minute intervals |
| **Active alerts** | 8 (2 Critical, 4 Warning, 2 Info) | ACTIVE_ALERTS dynamic table — multi-signal alert engine |
| **ML models operational** | 12 | 6 UDF-based + 3 native Snowflake ML + 3 on-demand procedures |
| **Prediction dimensions** | 7 per asset | Failure mode, RUL, degradation stage, fatigue, root cause, simulation, prescription |
| **Monte Carlo paths per simulation** | 300 (3 scenarios x 100) | SIMULATE_FAILURE_TWIN UDF |
| **Cortex Search documents** | 78 | Maintenance logs indexed for RAG-based root cause investigation |
| **Semantic View VQRs** | 21 | Verified query representations ensuring text-to-SQL accuracy |
| **Automated test cases** | 80+ | 8 test files, runnable from Admin Panel |

### Time Saved (Estimated)

| Task | Without MFGPulse AI | With MFGPulse AI | Improvement |
|---|---|---|---|
| **Root cause investigation** | 2-4 hours (manual log review + sensor correlation) | 30 seconds (Copilot: "Why is Compressor A1 degrading?") | ~99% reduction |
| **OEE trend identification** | Manual spreadsheet analysis across months of production data | Instant (Executive Dashboard: OEE Trend Analysis with 185-day history, per-line breakdown) | Manual → instant |
| **Supply chain risk assessment** | 1-2 hours (cross-reference RUL with parts ATP and supplier lead times) | Instant (Executive Dashboard: risk donut + lead time gap chart + at-risk cost; Procurement page for details) | ~95% reduction |
| **Sensor data monitoring** | Manual historian checks across multiple OT systems | Instant (Operations Center: Sensor feed with 24h time-series, asset filter, channel selector, raw data export) | Manual → instant |
| **Status reporting** | Manual compilation of KPI summaries from multiple systems | Instant (auto-generated executive summaries on every dashboard page — Executive, Operations, WO/PO, Maintenance, Procurement) | Manual → instant |
| **Shift handover preparation** | 30-45 min (compile notes, check systems) | Instant (Shift Handover view, or Copilot: "Give me the handover summary") | ~98% reduction |
| **Work order creation** | 15-20 min (lookup asset, check parts, find technician, fill form) | 1 click from alert or 1 sentence to Copilot | ~95% reduction |
| **Procurement risk assessment** | 1-2 hours (cross-reference RUL with parts ATP and supplier lead times) | Automatic (PROCUREMENT_RECOMMENDATIONS view + Digital Twin part-arrival analysis) | ~95% reduction |
| **Failure prediction** | Reactive (after breakdown) | Proactive (RUL with P10/P50/P90 confidence intervals) | Reactive → predictive |
| **Intervention planning** | Gut feel or simple thresholds | Monte Carlo simulation comparing 3 strategies with cost analysis | Qualitative → quantitative |

### Scalability Potential

**MFGPulse AI scales along 4 dimensions without architectural changes:**

| Dimension | Current Demo | Scale Path | What Changes |
|---|---|---|---|
| **Assets** | 10 assets, 3 lines | 1,000+ assets, 50+ lines | Add rows to ASSET_MASTER and SENSOR_METADATA. Dynamic Tables, UDFs, and views scale automatically — no code changes. |
| **Sensor volume** | 172K readings (30 days) | Millions of readings (years of history) | Snowflake's elastic compute handles the volume. PHYSICS_COMPOSITE already uses INCREMENTAL refresh for efficiency. |
| **Plants** | 1 plant | Multi-plant enterprise | Add a PLANT_ID dimension to ASSET_MASTER and filter in Streamlit. The 7-schema architecture supports this naturally. |
| **Models** | 12 models (8 UDF/Proc + 4 native) | Custom models per asset type | MODEL_REGISTRY supports unlimited model entries. UDFs can be versioned. Native Snowflake ML retrains on new data. |
| **Users** | 9 users, 6 personas | Enterprise-wide deployment | USERS table + PERSONA_CONFIG in Streamlit. Add personas by extending the config dictionary. |
| **Notifications** | 16 event types | Custom event types | NOTIFICATION_SETTINGS table — add rows for new events. LOG_APP_NOTIFICATION reads settings at runtime. |

**Snowflake features that enable scale:**
- **Dynamic Tables** eliminate ETL scheduling — Snowflake manages refresh automatically
- **INCREMENTAL refresh** on PHYSICS_COMPOSITE processes only changed rows
- **Elastic warehouses** scale compute independently of storage
- **Cortex Search** handles document-scale RAG without external vector databases
- **Cortex Agent** orchestrates tools without custom API infrastructure

### How This Extends Beyond the Demo

| Extension | Effort | What It Adds |
|---|---|---|
| **Real OT integration** | Connect Snowpipe or Kafka to ingest from OPC-UA/MQTT historians | Live sensor data instead of simulated — the entire pipeline downstream works unchanged |
| **ERP integration** | Connect to SAP PM / Oracle EAM / Maximo via Snowflake connectors | Real work orders and parts data — the closed-loop procurement system works as-is |
| **Advanced ML** | Replace UDF-based models with deep learning (LSTM, Transformer) via Snowpark ML | Better prediction accuracy while keeping the same LIVE_PREDICTIONS interface |
| **Multi-plant federation** | Add PLANT_ID dimension + plant selector in Streamlit | Enterprise-wide command center with plant-level drill-down |
| **Regulatory compliance** | Add audit trail views and compliance dashboards | FDA 21 CFR Part 11, ISO 55000 asset management evidence |
| **Energy optimization** | Correlate sensor data with energy meters | OEE + energy efficiency = sustainable manufacturing |
| **Marketplace distribution** | Package as a Snowflake Native App | Distribute to other Snowflake customers as a turnkey solution |

---

## Appendix: Quick Reference Numbers

For the submission deck, here are the key numbers at a glance:

```
Platform:       100% Snowflake-native (zero external services)
Schemas:        7
Tables:         30 base + 14 dynamic = 44 total
Views:          31
ML Models:      12 (6 UDF + 3 native Snowflake ML + 3 on-demand procedures)
UDFs:           6
Procedures:     27
Streams:        3
Tasks:          11 (DAG: root + 10 children on MFGPULSE_AUTOMATION_WH)
Warehouses:     2 (COMPUTE_WH + MFGPULSE_AUTOMATION_WH)
Resource Mon:   3 (HARDSTOP + CREDIT_GUARD + AUTOMATION_GUARD)
Cortex Search:  1 service, 78 docs
Semantic View:  1 view, 6 tables, 21 VQRs
Cortex Agent:   1 agent, 5 tools
Streamlit:      8 pages + 1 router + 1 shared module, 6 personas
Admin Panel:    12 sections (incl. FinOps, Simulation, User Mgmt)
Notifications:  16 event types, email + in-app
Sensor Data:    560K+ readings, 6 channels, 10 assets
Test Cases:     80+ across 8 test files
Documentation:  12 docs + DDL export
SQL Scripts:    27 (20 modular + deploy/utility scripts)
Total Files:    82
```
