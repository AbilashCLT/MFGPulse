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
| 4 | sql/04_seed_data.sql | 10 assets, 23 sensors, 15 parts, 8 users, 22 WOs, 26 maintenance logs, shifts, production |
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
- 26 maintenance logs in MAINTENANCE_LOGS
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

## Phase 4: Streamlit Command Center — Role-Based Architecture

### Objective
Deploy the role-based Streamlit dashboard with persona-driven navigation, 7 pages + Copilot.

### Deliverables

| File | Page | Primary Persona |
|---|---|---|
| streamlit_app.py | Router + persona selection | All |
| app_pages/_shared.py | Shared utilities | — |
| app_pages/executive_dashboard.py | Executive Dashboard | Plant Manager |
| app_pages/operations_dashboard.py | Operations Dashboard | Shift Supervisor |
| app_pages/maintenance_dashboard.py | Maintenance Dashboard | Technician / Reliability Engineer |
| app_pages/digital_twin.py | Digital Twin Simulator | Technician / Reliability Engineer |
| app_pages/copilot.py | Maintenance Copilot | All |
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

### Validation Criteria
- All 4 tasks visible with correct state
- All 3 streams visible
- All DTs visible with refresh state
- Job history shows recent runs
- ML models listed with training metrics
- Resource monitor shows credit usage

---

## Phase 7: Validation & Hardening

### Objective
End-to-end acceptance testing, security validation, performance validation.

### Deliverables
- sql/18_validation.sql — Full verification suite
- Security: CALLER rights on write procedures, parameterized calls, audit trail
- Performance: Views < 5s on XSMALL, pages < 3s with cache
- Rollback: Drop new objects in reverse order, revert YAML, no impact on existing pipeline

### Object Count Targets
- Base tables: ~19 (14 original + 5 procurement)
- Dynamic tables: ~12
- Views: ~8
- Procedures: ~9
- Functions/UDFs: ~5
- Tasks: ~5 (all suspended)
- Streams: ~3
- Cortex Search: 1
- Semantic View: 1
- Cortex Agent: 1
- Streamlit pages: 7 + Copilot

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
