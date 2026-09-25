# MFGPulse AI — Enterprise Implementation Plan

## Predictive Maintenance & OEE Command Center on Snowflake

---

## Solution Overview

MFGPulse AI is a Snowflake-native predictive maintenance and OEE command center for industrial operations. It combines OT sensor telemetry, production output, asset metadata, IT maintenance records, 7 ML models, and generative AI into one decision workflow: detect degradation, estimate time to failure, explain likely cause, quantify financial exposure, and recommend or create the next maintenance action.

The reference implementation monitors 10 industrial assets across 3 production lines with a role-based Streamlit dashboard, Cortex AI agent, and a full procurement-to-maintenance closed loop.

---

## Architecture

```
OT telemetry + production output       IT maintenance + inventory + shifts + users
                |                                      |
                +------------------+-------------------+
                                   v
                    MFGPULSE_DB in Snowflake
       RAW_OT / RAW_IT -> CURATED -> ML_FEATURES -> ML_MODELS -> ANALYTICS / AGENT
                                   |
       +---------------------------+----------------------------+
       |                           |                            |
  Streamlit command center   Cortex Agent + Search        Tasks / alerts / WOs / POs
  (role-based dashboards)    (5+1 tools)                  (automated orchestration)
```

### Snowflake Data Layers

| Layer | Schema | Purpose |
|---|---|---|
| Ingestion | RAW_OT, RAW_IT | Asset master, sensors, readings, production, WOs, logs, parts, users, suppliers, POs |
| Curation | CURATED | OT+IT joined, failure history, current health |
| Features | ML_FEATURES | 7 auto-refreshing dynamic tables + 11 training/inference views |
| Models | ML_MODELS | UDFs, native ML models, LIVE_PREDICTIONS, simulation, Cortex Search |
| Analytics | ANALYTICS | Alerts, OEE, cost views, procurement recommendations, procedures |
| Agent | AGENT | Semantic view + Cortex Agent |

### 7 ML Models

| # | Model | Type | Output |
|---|---|---|---|
| M1 | Failure Mode Classifier | Classification | 5-class failure mode (bearing_wear, thermal_degradation, imbalance, misalignment, normal) |
| M2 | RUL Estimator | Regression/Forecast | Hours to failure with P10/P50/P90 confidence intervals |
| M3 | Degradation Stager | Classification | Healthy / Warning / Critical |
| M4 | Hidden Fatigue Detector | Anomaly Detection | Fatigue score (0-1) + level |
| M5 | Root Cause Analyzer | LLM | Natural-language root cause with evidence |
| M6 | Digital Twin Simulator | Monte Carlo | Failure probability curves under scenarios |
| M7 | Prescriptive Engine | LLM | Work order recommendation with cost justification |

### Role-Based Dashboards

| Dashboard | Primary Persona | Key Content |
|---|---|---|
| Executive Dashboard | Plant Manager | OEE, Availability, Performance, Quality, Production Losses, Financial Impact, ROI |
| Operations Dashboard | Shift Supervisor | Live production, downtime monitoring, equipment performance, shift handover, alerts |
| Maintenance Dashboard | Technician / Reliability Engineer | Asset health, failure prediction, maintenance recommendations, WO management |
| Digital Twin | Technician / Reliability Engineer | Monte Carlo scenario comparison, failure probability curves |
| Procurement Dashboard | Procurement Admin | Procurement recommendations, ATP, open POs, unified action queue |
| Admin Control Panel | Admin | Tasks, streams, DTs, simulations, jobs, ML models, resource monitoring |
| Maintenance Copilot | All personas | AI Q&A with 5 agent tools, auto-persona from USERS table |

---

## Phase 1: Infrastructure & Data Foundation

### Objective
Create the database, all schemas, all base tables (including USERS), seed all reference data with dates within the last 6 months (March 2026 - September 2026), generate sensor readings, and populate fatigue scores.

### Deliverables

| # | File | Objects Created |
|---|---|---|
| 1 | sql/01_infrastructure.sql | Database MFGPULSE_DB, 7 schemas, warehouse COMPUTE_WH, resource monitor |
| 2 | sql/02_base_tables.sql | 14 base tables across RAW_OT, RAW_IT, ML_MODELS, ANALYTICS (including USERS) |
| 3 | sql/03_streams.sql | 3 CDC streams |
| 4 | sql/04_seed_data.sql | 10 assets, 23 sensors, 15 parts, 8 users, 22 WOs, 78 maintenance logs, shifts, production |
| 5 | sql/05_generate_sensor_data.sql | GENERATE_SENSOR_DATA procedure + call (~172K readings) |
| 6 | sql/06_fatigue_scores.sql | Fatigue score population from sensor readings |

### Date Strategy
All seed data dates shifted to March 2026 - September 2026 window:
- Asset install dates: 2021-2025 (preserving relative age)
- Sensor calibration: Dec 2025 - Jul 2026
- Work orders: Mar 2026 - Aug 2026
- Maintenance logs: Mar 2026 - Aug 2026
- Shift schedule: Mar 2026 - Sep 2026 (190 days)
- Production output: Mar 2026 - Sep 2026 (185 days)

### USER Table Design

| Column | Type | Notes |
|---|---|---|
| USER_ID | VARCHAR(20) | PK, format USR-001 |
| USERNAME | VARCHAR(100) | Display name |
| EMAIL | VARCHAR(200) | Contact |
| PERSONA | VARCHAR(50) | TECHNICIAN, RELIABILITY_ENGINEER, SHIFT_SUPERVISOR, PLANT_MANAGER, PROCUREMENT_ADMIN |
| ROLE | VARCHAR(50) | Snowflake role mapping (future RBAC) |
| LINE_ID | VARCHAR(20) | Assigned line (nullable for plant-wide) |
| ACTIVE | BOOLEAN | Default TRUE |
| CREATED_AT | TIMESTAMP_NTZ | Default CURRENT_TIMESTAMP |

### Validation Criteria
- 10 assets in ASSET_MASTER
- 23 sensors in SENSOR_METADATA
- 15 parts in PARTS_INVENTORY
- 8 users in USERS
- 22 work orders in WORK_ORDERS
- 78 maintenance logs in MAINTENANCE_LOGS
- ~1620 shift schedule rows
- ~3330 production output rows
- ~172K sensor readings
- Fatigue scores populated for all assets

### Pre-Deployment Checks
- ACCOUNTADMIN role available
- COMPUTE_WH warehouse can be created
- Account has sufficient credits (~3-5 for full deployment)

### Post-Deployment Checks
- All tables exist with expected row counts
- All timestamps fall within Mar-Sep 2026
- Streams created and active
- No errors in deployment log

---

## Phase 2: Feature Engineering & ML Layer

### Objective
Build the feature engineering pipeline (curated + ML feature dynamic tables and views), prediction UDFs, LIVE_PREDICTIONS dynamic table, and train native ML models.

### Deliverables

| # | File | Objects Created |
|---|---|---|
| 7 | sql/07_curated_dynamic_tables.sql | SENSOR_WITH_CONTEXT, FAILURE_HISTORY, ASSET_HEALTH_CURRENT |
| 8 | sql/08_ml_feature_dynamic_tables.sql | LABELED_DATA, ROLLING_STATS, SENSOR_INTERACTIONS, TEMPORAL_MEMORY, CROSS_DOMAIN, PHYSICS_COMPOSITE, FLEET_COMPARISON |
| 9 | sql/09_ml_feature_views.sql | ALL_DERIVED_FEATURES + 10 training/inference views |
| 10 | sql/10_udfs_live_predictions.sql | 5 UDFs + LIVE_PREDICTIONS DT |
| 11 | sql/11_native_ml_models.sql | Native Classification, Forecast, Anomaly Detection models |

### Dependencies
- Phase 1 complete (all base tables populated with seed data)
- Sensor readings must exist for feature computation
- Fatigue scores must exist for LIVE_PREDICTIONS join

### Dynamic Table Refresh Chain
```
SENSOR_READINGS (base)
  -> LABELED_DATA (DOWNSTREAM)
    -> ROLLING_STATS, SENSOR_INTERACTIONS, TEMPORAL_MEMORY,
       CROSS_DOMAIN, PHYSICS_COMPOSITE, FLEET_COMPARISON
      -> ALL_DERIVED_FEATURES (view)
        -> LIVE_PREDICTIONS (DT, calls 3 UDFs + joins FATIGUE_SCORES)
```

### Validation Criteria
- All 3 curated DTs refresh successfully
- All 7 ML feature DTs refresh successfully
- ALL_DERIVED_FEATURES view returns rows for all 10 assets
- LIVE_PREDICTIONS returns 10 rows with non-null predictions
- Native ML models train successfully (verify with SHOW SNOWFLAKE.ML.*)

---

## Phase 3: Analytics & AI Layer

### Objective
Build the business-facing analytics layer (alerts, OEE, cost views, work order procedures), Cortex Search for RAG, semantic view, Cortex Agent, and scheduled automation.

### Deliverables

| # | File | Objects Created |
|---|---|---|
| 12 | sql/12_analytics_layer.sql | ACTIVE_ALERTS DT, OEE_METRICS DT, 6 views, 3+ procedures |
| 13 | sql/13_cortex_search.sql | MAINTENANCE_SEARCH Cortex Search service |
| 14 | sql/14_automation.sql | 4 tasks/alerts (all SUSPENDED) |
| — | cortex_project/*.yaml | Semantic view + Cortex Agent (updated with USERS table) |

### Analytics Objects

| Object | Type | Purpose |
|---|---|---|
| ACTIVE_ALERTS | Dynamic Table | Multi-signal alert engine (degradation + RUL + fatigue + chronic WO) |
| OEE_METRICS | Dynamic Table | Per-asset-per-shift OEE with loss attribution |
| ALERT_SUMMARY | View | Aggregated alert counts by severity |
| COST_IMPACT | View | Plant-wide cost metrics |
| COST_IMPACT_BY_ASSET | View | Per-asset cost breakdown |
| ASSET_COST_PROFILES | Table | Per-asset emergency failure and planned repair base costs (grounded in WO history) |
| EXECUTIVE_SUMMARY | View | Single-row plant KPI summary |
| PREDICTIONS_WITH_COST | View | Cost-enriched predictions using per-asset profiles + parts + WO status |
| SHIFT_HANDOVER_VIEW | View | Shift transition data |
| GENERATE_WORK_ORDER | Procedure | Create WO for specific asset |
| AUTO_GENERATE_WORK_ORDERS | Procedure | Create WOs for all at-risk assets |
| GENERATE_SHIFT_HANDOVER_SUMMARY | Procedure | AI-generated shift briefing |

### Cortex Agent Tools (5)

| Tool | Type | Purpose |
|---|---|---|
| maintenance_analytics | Text-to-SQL | Query via semantic view |
| maintenance_history | Cortex Search | RAG over maintenance logs |
| predict_all | Procedure | Full 7-model diagnosis |
| simulate_scenario | Function | Monte Carlo what-if |
| generate_work_order | Procedure | Create and file WO |

### Validation Criteria
- ACTIVE_ALERTS populated with severity-appropriate alerts
- OEE_METRICS returns per-asset-per-shift rows
- EXECUTIVE_SUMMARY returns 1 row with plant OEE
- PREDICTIONS_WITH_COST returns 10 rows with cost data
- Cortex Search service active (SHOW CORTEX SEARCH SERVICES)
- Cortex Agent responds to test question
- All tasks created in SUSPENDED state

---

## Phase 4: Streamlit Command Center — Role-Based Architecture [DEPLOYED]

### Objective
Deploy the role-based Streamlit dashboard with persona-driven navigation, 5 pages + Copilot.

### Architecture

The dashboard uses a persona-based router: users select their profile from the USERS table on first load, and the navigation dynamically filters pages based on their role. All pages share a centralized data loader module with TTL-based caching.

```
streamlit_app.py (persona router + st.navigation)
  -> app_pages/_shared.py (data loaders, colors, helpers)
  -> app_pages/executive_dashboard.py
  -> app_pages/operations_dashboard.py
  -> app_pages/maintenance_dashboard.py
  -> app_pages/digital_twin.py
  -> app_pages/copilot.py
```

### Deliverables

| File | Page | Primary Persona |
|---|---|---|
| streamlit_app.py | Persona router + navigation | All |
| app_pages/_shared.py | Shared utilities, data loaders, constants | — |
| app_pages/executive_dashboard.py | OEE, financial impact, cost analysis, WO breakdown | Plant Manager |
| app_pages/operations_dashboard.py | Fleet status, alert triage, shift handover, WO management | Shift Supervisor |
| app_pages/maintenance_dashboard.py | Asset health matrix, deep dive, failure DNA, parts/WO | Technician / Reliability Engineer |
| app_pages/digital_twin.py | Monte Carlo 3-scenario simulator | Technician / Reliability Engineer |
| app_pages/copilot.py | AI assistant with fast LLM + Cortex Agent dual path | All |
| snowflake.yml | Deployment manifest | — |
| pyproject.toml | Dependencies | — |
| .streamlit/config.toml | Theme config | — |

### Persona-to-Page Access Matrix

| Page | Technician | Reliability Eng | Supervisor | Plant Manager | Procurement | Admin |
|---|---|---|---|---|---|---|
| Executive Dashboard | — | — | View | Full | — | Full |
| Operations Dashboard | View | View | Full | Full | — | Full |
| Maintenance Dashboard | Full | Full | Full | View | View | Full |
| Digital Twin | Full | Full | View | — | — | Full |
| Procurement Dashboard | — | — | View | View | Full | Full |
| Admin Control Panel | — | — | — | — | — | Full |
| Maintenance Copilot | Full | Full | Full | Full | Full | Full |

### Design Principles
- Persona selection from USERS table on first load
- st.navigation with sections for grouping
- Native Streamlit components (st.metric, st.badge, st.container, st.dialog, st.pills)
- Material Symbols icons, sentence casing
- Cached reads with TTL, cache clear after writes
- Parameterized procedure calls (no string formatting for SQL)
- Graceful degradation when optional objects don't exist

### Validation Criteria
- All pages render without error
- Persona selection works and filters navigation
- Copilot responds via both fast LLM and agent paths
- Work order generation succeeds
- Charts render with Altair

---

## Phase 5: Procurement Extension

### Objective
Add the procurement layer: tables, views, procedures, Streamlit page, agent tool.

### Deliverables

| # | File | Objects Created |
|---|---|---|
| 15 | sql/15_procurement_tables.sql | SUPPLIERS, PART_SUPPLIERS, PART_RESERVATIONS, PURCHASE_ORDERS, PURCHASE_ORDER_LINES + seed data |
| 16 | sql/16_procurement_views.sql | PARTS_AVAILABLE_TO_PROMISE, PROCUREMENT_RECOMMENDATIONS |
| 17 | sql/17_procurement_procedures.sql | RESERVE_PART_FOR_WORK_ORDER, GENERATE_PURCHASE_ORDER, AUTO_GENERATE_PURCHASE_ORDERS + suspended task |
| — | app_pages/procurement_dashboard.py | Procurement dashboard page |
| — | cortex_project/*.yaml | Updated semantic view + agent with procurement |

### Business Rules
- Required-by date = predicted_failure_at - maintenance_buffer_days (1d normal, 2d HIGH, 0d EMERGENCY)
- Procurement risk: NO_RISK / ORDER_NOW / EXPEDITE / CRITICAL_SHORTAGE / UNKNOWN
- PO default status: pending_approval
- Duplicate PO prevention on same PART_ID + ASSET_ID + WO_ID

### Validation Criteria (8 acceptance criteria)
1. Low-RUL + no stock -> PO created with correct supplier/dates
2. Available stock -> reservation, no PO
3. Stock reserved by another WO -> ATP correct, PO when insufficient
4. Lead time exceeds required-by -> EXPEDITE or CRITICAL_SHORTAGE
5. Dashboard shows risk, PO, arrival for at-risk assets
6. Shift handover reports missing parts + pending POs
7. Agent answers procurement questions, creates POs only when asked
8. Duplicate PO prevention works

---

## Phase 6: Admin Control Panel

### Objective
Build the infrastructure monitoring and management page for administrators.

### Deliverables

| Section | Data Source | Actions |
|---|---|---|
| Task Monitor | SHOW TASKS, TASK_HISTORY() | Resume / Suspend / Execute Now |
| Stream Monitor | SHOW STREAMS | Read-only |
| Dynamic Table Monitor | SHOW DYNAMIC TABLES, DT refresh history | Manual Refresh / Alter Lag |
| Scenario Simulation Control | Task state for simulators | Run sensor feed / Run production now |
| Job History | TASK_HISTORY() | Filter by task, date, state |
| ML Model Registry | ML_MODELS.MODEL_REGISTRY | Read-only |
| Resource Monitor | RESOURCE_MONITORS | Read-only |
| Alert Manager | SHOW ALERTS | Resume / Suspend |

### Implementation (Completed)
- **File**: `app_pages/admin_control_panel.py` (283 lines)
- **6 sections** via `st.segmented_control`:
  1. **Tasks** — Resume/Suspend buttons per task, schedule and warehouse info
  2. **Dynamic tables** — KPI bar (count, rows, storage), per-DT refresh trigger, lag/mode/state
  3. **Streams** — Stale/Active badge, source table, mode, stale-after date
  4. **ML models** — Model registry cards (F1/precision/recall, features, training data), Cortex Search services
  5. **Cortex services** — Agent, Semantic View, Cortex Search listing
  6. **Object inventory** — Full count of all solution objects + schema breakdown
- Access restricted to **PLANT_MANAGER** persona only via `_shared.py` PERSONA_CONFIG
- Registered in `snowflake.yml` artifacts

### Validation Criteria
- All 6 DAG tasks visible with correct state
- All 3 streams visible
- All 13 DTs visible with refresh state
- ML models listed with training metrics
- Cortex Agent + Semantic View + Search visible
- Object inventory counts match deployed objects

---

## Phase 7: Validation & Hardening (Completed)

### Objective
End-to-end acceptance testing, security validation, performance validation.

### Deliverables
- `sql/18_validation.sql` (234 lines) — Full verification suite with 8 sections

### Implementation

**Section 1 — Object existence**: 7 schemas, 32 base tables (across RAW_OT/RAW_IT/ML_MODELS), 26 views verified.

**Section 2 — Data integrity**:
- Row counts: 10 assets, 23 sensors, 15 parts, 8 users, 172K+ readings, 22 WOs, 26 logs, 5 suppliers, 16 part-supplier mappings, 12 ML models — **ALL PASS**
- Date range: All seed data within Mar–Sep 2026 — **ALL PASS**
- Referential integrity: Zero orphaned sensor readings or work orders — **ALL PASS**
- Null PKs: Zero null primary keys across 5 key tables — **ALL PASS**

**Section 3 — Dynamic table health**: All 13 DTs in ACTIVE scheduling state.

**Section 4 — ML pipeline**: 10 LIVE_PREDICTIONS (one per asset), 6.7K fatigue scores, 2,520 anomaly scores (1,190 flagged anomalies), prediction ranges valid (RUL 13.5–2000h, degradation 0.07–0.85, fatigue 0.01–0.61, health 0–100).

**Section 5 — Analytics layer**: 8 active alerts across 3 severity levels, 3330 OEE records, 8 procurement recommendations, 15 ATP rows, zero negative ATP.

**Section 6 — UDF smoke tests**: PREDICT_FAILURE_MODE, PREDICT_RUL, COMPUTE_FATIGUE_SCORE, SIMULATE_FAILURE_TWIN all return valid results.

**Section 7 — Users/personas**: All 5 personas represented (TECHNICIAN x3, RELIABILITY_ENGINEER x2, SHIFT_SUPERVISOR x1, PLANT_MANAGER x1, PROCUREMENT_ADMIN x1). No duplicate usernames.

### Security Hardening (Completed)
- **2 SQL injection vulnerabilities fixed** in `copilot.py`:
  - `fast_llm_answer()`: manual `replace("'","''")` escaping → parameterized `session.sql(?, params=[])`
  - `call_agent()`: `$$` dollar-quoting of user input → parameterized `session.sql(?, params=[])`
- **1 advisory resolved** in `digital_twin.py`: slider values now parameterized for defense-in-depth
- **0 hardcoded secrets, 0 unsafe exec patterns** across all 9 Python files
- All write operations (`GENERATE_PURCHASE_ORDER`, `RESERVE_PART_FOR_WORK_ORDER`) use parameterized SQL

### Final Object Counts (Verified)
| Object Type | Count | Notes |
|---|---|---|
| Schemas | 7 | RAW_OT, RAW_IT, CURATED, ML_FEATURES, ML_MODELS, ANALYTICS, AGENT |
| Base tables | 19 | 4 RAW_OT + 11 RAW_IT + 4 ML_MODELS |
| Dynamic tables | 13 | All ACTIVE, TARGET_LAG = 1 hour |
| Views | 19 | 8 ANALYTICS + 11 ML_FEATURES |
| Procedures | 10 | User-defined (excludes built-in) |
| Functions/UDFs | 5 | PREDICT_FAILURE_MODE, PREDICT_RUL, SIMULATE_FAILURE_TWIN, COMPUTE_FATIGUE_SCORE, PREDICT_DEGRADATION_STAGE |
| Tasks | 3 | All SUSPENDED (SIMULATE_SENSOR_FEED, SIMULATE_PRODUCTION, AUTO_PROCUREMENT_REVIEW) |
| Streams | 3 | SENSOR_READINGS_STREAM, MAINTENANCE_LOGS_STREAM, WORK_ORDERS_STREAM |
| Cortex Search | 1 | MAINTENANCE_SEARCH (78 docs, ACTIVE) |
| Semantic View | 1 | MAINTENANCE_SEMANTIC_VIEW (6 tables, 21 VQRs) |
| Cortex Agent | 1 | MAINTENANCE_COPILOT (5 tools, published) |
| ML models registered | 10 | 4 native (Classification ×2 + Forecast) + 7 UDF-based (M1–M7) in MODEL_REGISTRY |
| Streamlit pages | 8 | Executive, Operations, Maintenance, Procurement, Digital Twin, Admin, Copilot + router |
| Sensor readings | 172,326 | Physics-based with failure signatures |

### Production Maturity Features (Added)
| Feature | Objects | Description |
|---|---|---|
| Data Freshness SLA | VIEW + PROC + TASK | DATA_FRESHNESS_SLA view, CHECK_DATA_FRESHNESS proc, DAG_CHECK_FRESHNESS task. Monitors sensor data staleness with configurable SLA (120 min), fires DATA_STALE notification on breach |
| Model Drift Detection | 2 TABLES + VIEW + PROC + TASK | DRIFT_COMPARISON, DRIFT_METRICS, COMPUTE_NATIVE_PREDICTIONS, DAG_CHECK_DRIFT. Compares rule-based vs native ML predictions per asset; alerts when agreement < 80% |
| Closed-Loop ML Improvement | TABLE + VIEW + 2 PROCS | FEEDBACK_LOG, MODEL_ACCURACY_LIVE, LOG_FEEDBACK (called on WO completion), RETRAIN_IF_NEEDED. WO root cause confirmation flows back as prediction labels |
| Time-Range Comparison | 2 TABLES + VIEW + 2 PROCS + 2 TASKS | KPI_SNAPSHOTS, ALERT_HISTORY, OEE_PERIOD_COMPARISON, SNAPSHOT_KPIS, ARCHIVE_ALERTS. Enables week-over-week KPI trending and delta badges |

### Workflow & Procurement Audit Fixes (23 items across 3 phases)
| Phase | Fixes | Key Changes |
|---|---|---|
| Phase 1 (Immediate) | 10 | Feedback log `w→wo` bug fix, WO_CREATED + PO_CREATED notifications added to procedures, 5 missing event types seeded, duplicate WO check expanded, PROCUREMENT_RECOMMENDATIONS redeployed with REPLENISH_NOW risk + LEAD_TIME_FEASIBLE wiring + ESCALATE_NO_WO action, SHIFT_SUPERVISOR added to PO_REJECTED |
| Phase 2 (Sprint) | 7 | Inventory +qty on PO receive, -qty on WO consumption, WO cancel button + WO_CANCELLED event, null-supplier guard, PROACTIVE_REORDER view for zero-stock parts |
| Phase 3 (Backlog) | 6 | PO ordered→shipped→received transitions, PO ID collision fix (timestamp added), TECHNICIAN added to WO_STARTED |

### Notification Coverage: 16 Event Types
- **WO lifecycle**: CREATED, STARTED, COMPLETED, CANCELLED, REASSIGNED, FOLLOWUP (6)
- **PO lifecycle**: CREATED, APPROVED, REJECTED, RECEIVED (4)
- **System**: DATA_STALE, MODEL_DRIFT, MODEL_RETRAIN (3)
- **Operations**: PART_SHORTAGE_ALERT, SHORTAGE_SIM, SHORTAGE_REVERTED (3)

---

## Dependencies

```
Phase 1 --> Phase 2 --> Phase 3 --> Phase 4 --> Phase 5 --> Phase 6 --> Phase 7
(infra +    (features   (analytics  (streamlit  (procure-   (admin     (validation)
 tables +    + ML)       + AI)       7 pages)    ment)       panel)
 seed data
 + USERS)
```

## Risks

| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Streamlit version doesn't support st.dialog/st.pills | Medium | High | Check pyproject.toml; fall back to st.expander |
| LIVE_PREDICTIONS DT stale data | Low | High | Validate refresh history before procurement depends on it |
| Native ML training fails on fresh data | Low | Medium | UDFs have fallback logic |
| Notification email placeholder not replaced | High | Low | Flag during pre-flight |
| No RBAC roles for PO approval | Medium | Medium | MVP uses ACCOUNTADMIN; add roles later |

## Open Questions

1. Should generated POs stay in Snowflake or push to external ERP? (Non-goal for MVP)
2. What role moves PO from pending_approval to approved? (ACCOUNTADMIN for MVP)
3. One part per failure mode, or multi-part BOM? (Default required_quantity=1 for now)
4. Should ATP account for safety stock? (Not for MVP)
5. Emergency purchases use expedite lead time ranking? (Yes, recommended)

---

*Source of truth: docs/ folder in the Predictive-Maintenance-OEE-Command-Center workspace.*
*All recommendations traceable to TECHNICAL_GUIDE.md, USER_GUIDE.md, PURCHASE_ORDER_WORKFLOW_SPEC.md, and STREAMLIT_PROCUREMENT_UX_SPEC.md.*
