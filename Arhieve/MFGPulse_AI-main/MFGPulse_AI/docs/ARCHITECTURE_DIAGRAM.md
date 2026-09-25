# MFGPulse AI — Architecture Diagram

*Complete system architecture and data flow for the Predictive Maintenance & OEE Command Center.*

---

## 1. High-Level System Architecture

```
┌──────────────────────────────── DATA SOURCES ─────────────────────────────────┐
│                                                                               │
│  ┌── OT (Operational Technology) ─┐  ┌── IT (Enterprise Systems) ──────────┐ │
│  │  Vibration (X/Y/Z axes)        │  │  CMMS: Work Orders, Maint. Logs    │ │
│  │  Temperature, RPM, Pressure    │  │  ERP: Parts, Suppliers, POs        │ │
│  │  Current (Amps), Acoustic (dB) │  │  MES: Production Output, Shifts    │ │
│  │  10 Assets × 23 Sensors        │  │  HR: Users (9), Personas (6)       │ │
│  └────────────────────────────────┘  └────────────────────────────────────┘ │
│                                                                               │
│  ┌── Environmental ───────────────┐  ┌── Simulated Feeds ─────────────────┐ │
│  │  Ambient Conditions            │  │  Sensor Feed Task (720 min)        │ │
│  │  External temp, humidity       │  │  Production Task (720 min)         │ │
│  └────────────────────────────────┘  │  Configurable via Admin Panel      │ │
│                                       └────────────────────────────────────┘ │
└───────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌───────────────────── MFGPULSE_DB (Snowflake) ───────────────────────────┐
│                                                                               │
│  ┌─────────────────────── INGESTION LAYER ────────────────────────────────┐  │
│  │                                                                         │  │
│  │  RAW_OT (4 tables)              RAW_IT (13 tables)                     │  │
│  │  ├─ ASSET_MASTER                ├─ WORK_ORDERS                         │  │
│  │  ├─ SENSOR_METADATA             ├─ MAINTENANCE_LOGS                    │  │
│  │  ├─ SENSOR_READINGS (560K+)     ├─ PARTS_INVENTORY                    │  │
│  │  └─ AMBIENT_CONDITIONS          ├─ PRODUCTION_OUTPUT                   │  │
│  │                                  ├─ SHIFT_SCHEDULE                     │  │
│  │  3 CDC Streams:                  ├─ USERS                              │  │
│  │  ├─ SENSOR_READINGS_STREAM      ├─ SUPPLIERS                          │  │
│  │  ├─ MAINTENANCE_LOGS_STREAM     ├─ PART_SUPPLIERS                     │  │
│  │  └─ WORK_ORDERS_STREAM          ├─ PURCHASE_ORDERS                    │  │
│  │                                  ├─ PURCHASE_ORDER_LINES               │  │
│  │                                  ├─ PART_RESERVATIONS                  │  │
│  │                                  ├─ APP_NOTIFICATIONS                  │  │
│  │                                  ├─ NOTIFICATION_SETTINGS              │  │
│  │                                  └─ SIMULATION_CONFIG                  │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                    │                                          │
│                                    ▼                                          │
│  ┌─────────────────────── CURATION LAYER ─────────────────────────────────┐  │
│  │                                                                         │  │
│  │  CURATED (3 Dynamic Tables, TARGET_LAG = 1 hour)                       │  │
│  │  ├─ SENSOR_WITH_CONTEXT ─── OT sensors + asset metadata joined         │  │
│  │  ├─ ASSET_HEALTH_CURRENT ── Latest reading per asset + health score    │  │
│  │  └─ FAILURE_HISTORY ──────── Pre-failure sensor profiles for training  │  │
│  │                                                                         │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                    │                                          │
│                                    ▼                                          │
│  ┌─────────────────────── FEATURE ENGINEERING ────────────────────────────┐  │
│  │                                                                         │  │
│  │  ML_FEATURES (7 Dynamic Tables + 11 Views, TARGET_LAG = 1 hour)       │  │
│  │                                                                         │  │
│  │  Dynamic Tables:                                                        │  │
│  │  ├─ LABELED_DATA ──────── Failure mode labels + degradation stages     │  │
│  │  ├─ ROLLING_STATS ─────── 6h/24h rolling window statistics (40 cols)  │  │
│  │  ├─ SENSOR_INTERACTIONS ── Cross-channel correlations & ratios         │  │
│  │  ├─ TEMPORAL_MEMORY ───── Breach timing, degradation velocity, trends  │  │
│  │  ├─ PHYSICS_COMPOSITE ─── ISO 10816, stress index, health score       │  │
│  │  ├─ CROSS_DOMAIN ──────── Maintenance history + production intensity  │  │
│  │  └─ FLEET_COMPARISON ──── Z-scores vs fleet mean per asset type       │  │
│  │                                                                         │  │
│  │  Training Views:                                                        │  │
│  │  ├─ ALL_DERIVED_FEATURES / ALL_DERIVED_FEATURES_INFERENCE              │  │
│  │  ├─ HEALTHY_DERIVED_FEATURES / HEALTHY_DERIVED_FEATURES_TRAIN          │  │
│  │  ├─ TRAIN_FAILURE_MODE / TRAIN_RUL / TRAIN_TRAJECTORY*                │  │
│  │  ├─ TRAIN_ANOMALY / TRAIN_ANOMALY_SMALL                               │  │
│  │  └─ FEATURE_CATALOG                                                    │  │
│  │                                                                         │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                    │                                          │
│                                    ▼                                          │
│  ┌─────────────────────── ML & PREDICTION LAYER ──────────────────────────┐  │
│  │                                                                         │  │
│  │  ML_MODELS (1 DT + 5 tables + 6 UDFs + 8 procedures)                  │  │
│  │                                                                         │  │
│  │  ┌──── 6 SQL UDFs (Rule-Based ML) ─────────────────────────────────┐  │  │
│  │  │  PREDICT_FAILURE_MODE ─── 5-class classifier (28 features)      │  │  │
│  │  │  PREDICT_RUL ──────────── Hours-to-failure with CI bands        │  │  │
│  │  │  PREDICT_DEGRADATION_STAGE ── Healthy/Warning/Critical          │  │  │
│  │  │  COMPUTE_FATIGUE_SCORE ──── Hidden fatigue (0.0-1.0)           │  │  │
│  │  │  SIMULATE_FAILURE_TWIN ──── Monte Carlo (100 paths × 3 scen.)  │  │  │
│  │  │  ANOMALY_SCORER ──────────── Anomaly detection scoring          │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                         │  │
│  │  ┌──── 3 LLM Procedures (Cortex Complete) ─────────────────────────┐  │  │
│  │  │  ANALYZE_ROOT_CAUSE ──── llama3.1-70b + RAG (Cortex Search)     │  │  │
│  │  │  PRESCRIBE_MAINTENANCE ── llama3.1-70b prescriptive actions     │  │  │
│  │  │  PREDICT_ALL ──────────── Orchestrates full 7-model pipeline    │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                         │  │
│  │  ┌──── Central Prediction Hub ─────────────────────────────────────┐  │  │
│  │  │  LIVE_PREDICTIONS (Dynamic Table, TARGET_LAG = 1 hour)          │  │  │
│  │  │  10 assets × 1 row each. Columns:                               │  │  │
│  │  │  failure_mode_pred, rul_hours (+ CI), stage_pred,               │  │  │
│  │  │  degradation_score, transition_probability,                      │  │  │
│  │  │  fatigue_score, composite_health_score, stress_index            │  │  │
│  │  └─────────────────────────────────────────────────────────────────┘  │  │
│  │                                                                         │  │
│  │  Other: FATIGUE_SCORES, ANOMALY_SCORES, MODEL_REGISTRY (12 models)    │  │
│  │  FEEDBACK_LOG, DRIFT_COMPARISON (closed-loop + drift detection)       │  │
│  │  Cortex Search: MAINTENANCE_SEARCH (78 docs, RAG over maint. logs)    │  │
│  │                                                                         │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                    │                                          │
│                                    ▼                                          │
│  ┌─────────────────────── ANALYTICS & BUSINESS LAYER ─────────────────────┐  │
│  │                                                                         │  │
│  │  ANALYTICS (3 DTs + 17 views + 15 procedures)                          │  │
│  │                                                                         │  │
│  │  Dynamic Tables:                                                        │  │
│  │  ├─ ACTIVE_ALERTS ────── Severity-classified alerts from predictions   │  │
│  │  ├─ OEE_METRICS ──────── Availability × Performance × Quality          │  │
│  │  └─ SAFETY_STOCK_POLICY ── Safety stock levels per part                │  │
│  │                                                                         │  │
│  │  Business Views:                                                        │  │
│  │  ├─ EXECUTIVE_SUMMARY ──────── Plant-wide KPIs for leadership          │  │
│  │  ├─ ASSET_COST_PROFILES ────── Per-asset failure/repair base costs     │  │
│  │  ├─ PREDICTIONS_WITH_COST ──── Predictions + per-asset cost estimates │  │
│  │  ├─ COST_IMPACT ────────────── Early detection savings analysis        │  │
│  │  ├─ COST_IMPACT_BY_ASSET ───── Cost rollup per asset                   │  │
│  │  ├─ ALERT_SUMMARY ─────────── Alert counts by severity                 │  │
│  │  └─ SHIFT_HANDOVER_VIEW ───── Critical actions for shift transitions   │  │
│  │                                                                         │  │
│  │  Procurement Views:                                                     │  │
│  │  ├─ PARTS_AVAILABLE_TO_PROMISE ── ATP = on_hand - reserved             │  │
│  │  ├─ PROCUREMENT_RECOMMENDATIONS ── Risk + action per asset-part        │  │
│  │  │    (36 columns: competing assets, buffer, incoming POs, net pos.)   │  │
│  │  ├─ PARTS_LIFECYCLE_INSIGHTS, PROCUREMENT_PERFORMANCE, SUPPLIER_SCORECARD ──── Per-part stock consumption view      │  │
│  │  └─ PLANNED_PURCHASE_ORDERS ───── PPO engine (aggregated by part)      │  │
│  │       (priority scoring, auto-convert deadlines, dual timing)          │  │
│  │                                                                         │  │
│  │  Procedures:                                                            │  │
│  │  ├─ GENERATE_WORK_ORDER ──────── Creates WO from prediction            │  │
│  │  ├─ AUTO_GENERATE_WORK_ORDERS ── Batch WO creation for at-risk assets  │  │
│  │  ├─ GENERATE_PURCHASE_ORDER ──── Creates PO with supplier lookup       │  │
│  │  ├─ AUTO_GENERATE_PURCHASE_ORDERS ── Batch PO creation                 │  │
│  │  ├─ RESERVE_PART_FOR_WORK_ORDER ── ATP-aware part reservation          │  │
│  │  ├─ AUTO_CONVERT_PLANNED_POS ──── Converts overdue PPOs to POs        │  │
│  │  └─ GENERATE_SHIFT_HANDOVER_SUMMARY                                    │  │
│  │                                                                         │  │
│  │  Task:                                                                  │  │
│  │  └─ DAG_CONVERT_PPOS (child of DAG_GENERATE_POS)                       │  │
│  │                                                                         │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                    │                                          │
│                                    ▼                                          │
│  ┌─────────────────────── CORTEX AI LAYER ────────────────────────────────┐  │
│  │                                                                         │  │
│  │  AGENT Schema                                                           │  │
│  │  ├─ MAINTENANCE_SEMANTIC_VIEW ── 6 tables, 21 VQRs                     │  │
│  │  │    VQRs: fleet health, predictions, OEE, supply chain,              │  │
│  │  │    alerts, procurement recommendations, cost impact                  │  │
│  │  │                                                                      │  │
│  │  └─ MAINTENANCE_COPILOT ──────── 5-tool Cortex Agent                   │  │
│  │       ├─ Tool 1: text-to-SQL (via Semantic View)                       │  │
│  │       ├─ Tool 2: RAG search (Cortex Search, 78 docs)                  │  │
│  │       ├─ Tool 3: 7-model diagnosis (PREDICT_ALL procedure)            │  │
│  │       ├─ Tool 4: Monte Carlo simulation (SIMULATE_FAILURE_TWIN)       │  │
│  │       └─ Tool 5: Work order generation (GENERATE_WORK_ORDER)          │  │
│  │                                                                         │  │
│  │  LLM Models Used:                                                       │  │
│  │  ├─ llama3.1-8b ── Executive summaries (6 pages, cached by hash)      │  │
│  │  └─ llama3.1-70b ── Root cause analysis, prescriptive maintenance     │  │
│  │                                                                         │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌─────────────────────── AUTOMATION ─────────────────────────────────────┐  │
│  │  11-Task DAG (MFGPULSE_AUTOMATION_WH, 720 min):                        │  │
│  │  ├─ MFGPULSE_AUTOMATION_DAG (root) ── Auto-complete aged WOs          │  │
│  │  ├─ DAG_SIMULATE_FEEDS ─────── Sensor + production simulation         │  │
│  │  ├─ DAG_CHECK_FRESHNESS ────── Data freshness SLA monitoring          │  │
│  │  ├─ DAG_REFRESH_FATIGUE ──────── Batch fatigue score computation      │  │
│  │  ├─ DAG_REFRESH_DTS ─────────── Force all 14 DTs to refresh          │  │
│  │  ├─ DAG_CHECK_DRIFT ──────────── Model drift: rule-based vs native   │  │
│  │  ├─ DAG_ARCHIVE_ALERTS ──────── Archive alerts before overwrite      │  │
│  │  ├─ DAG_GENERATE_WOS ────────── Auto-create WOs + notifications      │  │
│  │  ├─ DAG_GENERATE_POS ────────── Auto-create POs for at-risk parts    │  │
│  │  ├─ DAG_CONVERT_PPOS ────────── Convert overdue PPOs to actual POs   │  │
│  │  └─ DAG_SNAPSHOT_KPIS ────────── Daily KPI snapshot for trending     │  │
│  │                                                                         │  │
│  │  Notification System:                                                   │  │
│  │  ├─ LOG_APP_NOTIFICATION ──── In-app + email per persona              │  │
│  │  ├─ SEND_MFGPULSE_EMAIL ──── Via MFGPULSE_EMAIL integration          │  │
│  │  └─ 16 event types with admin-configurable routing                     │  │
│  │     (WO: created/started/completed/cancelled/reassigned/followup)      │  │
│  │     (PO: created/approved/rejected/received)                           │  │
│  │     (System: DATA_STALE, MODEL_DRIFT, MODEL_RETRAIN)                  │  │
│  │     (Ops: PART_SHORTAGE_ALERT, SHORTAGE_SIM, SHORTAGE_REVERTED)       │  │
│  │                                                                         │  │
│  │  Closed-Loop ML Improvement:                                           │  │
│  │  ├─ FEEDBACK_LOG ──────────── WO root cause → prediction comparison   │  │
│  │  ├─ MODEL_ACCURACY_LIVE ───── Rolling 30-day prediction accuracy      │  │
│  │  └─ RETRAIN_IF_NEEDED ─────── Triggers retrain when accuracy < 80%   │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
│  ┌─────────────────────── INFRASTRUCTURE ─────────────────────────────────┐  │
│  │  Warehouse: COMPUTE_WH (X-SMALL) — interactive queries, DT refreshes   │  │
│  │  Warehouse: MFGPULSE_AUTOMATION_WH (X-SMALL) — DAG tasks              │  │
│  │  Resource Monitor: MFGPULSE_CREDIT_GUARD (COMPUTE_WH)                  │  │
│  │  Resource Monitor: MFGPULSE_AUTOMATION_GUARD (MFGPULSE_AUTOMATION_WH)  │  │
│  │  Notification Integration: MFGPULSE_EMAIL (TYPE=EMAIL)                 │  │
│  └─────────────────────────────────────────────────────────────────────────┘  │
│                                                                               │
└───────────────────────────────────────────────────────────────────────────────┘
                                    │
                                    ▼
┌──────────────────── STREAMLIT APP (8 Pages, 6 Personas) ──────────────────────┐
│                                                                                │
│  ┌─── Executive ──┐ ┌─── Operations ──┐ ┌─── WO/PO Console ──┐              │
│  │ Plant KPIs      │ │ Fleet status    │ │ Work order mgmt    │              │
│  │ OEE trend chart │ │ Alert triage    │ │ Purchase orders    │              │
│  │ Cost analysis   │ │ Shift handover  │ │ Parts/PO per WO    │              │
│  │ Supply chain    │ │ Sensor feed     │ │ Activity log       │              │
│  │ LLM summary    │ │ LLM summary     │ │ Auto-reserve       │              │
│  └────────────────┘ └─────────────────┘ └────────────────────┘              │
│                                                                                │
│  ┌─── Maintenance ──┐ ┌─── Procurement ──────┐ ┌─── Digital Twin ──┐        │
│  │ Asset deep-dive   │ │ Recommendations      │ │ Monte Carlo sim  │        │
│  │ Failure DNA       │ │ Planned POs (PPO)    │ │ 3 scenarios      │        │
│  │ Root cause (LLM)  │ │ Stock insights       │ │ 300 paths        │        │
│  │ Prescriptive (LLM)│ │ Parts inventory      │ │ LLM summary      │        │
│  │ WO/PO generation  │ │ Purchase orders      │ │ Part arrival     │        │
│  └───────────────────┘ │ Auto-convert engine  │ └──────────────────┘        │
│                         └─────────────────────┘                               │
│  ┌─── Admin Panel ────────────────┐ ┌─── Maintenance Copilot ──────┐        │
│  │ Tasks / DTs / Streams / Models │ │ 5-tool AI agent              │        │
│  │ Cortex services / Notifications│ │ Conversational interface     │        │
│  │ Test suite / FinOps / Simulation│ │ Context-aware fast path     │        │
│  │ User management                │ │ Smart truncation             │        │
│  └────────────────────────────────┘ └──────────────────────────────┘        │
│                                                                                │
│  Persona Access Matrix:                                                       │
│  ┌────────────────────┬──────┬──────┬──────┬──────┬──────┬──────┬──────┬───┐ │
│  │                     │ Exec │ Ops  │ WO/PO│ Maint│ Proc │ Twin │ Admin│Co │ │
│  ├────────────────────┼──────┼──────┼──────┼──────┼──────┼──────┼──────┼───┤ │
│  │ Technician          │      │  x   │  x   │  x   │  x   │      │      │ x │ │
│  │ Reliability Eng.    │      │  x   │  x   │  x   │  x   │  x   │      │ x │ │
│  │ Shift Supervisor    │  x   │  x   │  x   │  x   │  x   │      │      │ x │ │
│  │ Plant Manager       │  x   │  x   │  x   │  x   │  x   │      │  x   │ x │ │
│  │ Procurement Admin   │      │  x   │  x   │  x   │  x   │      │      │ x │ │
│  │ App Admin           │  x   │  x   │  x   │  x   │  x   │  x   │  x   │ x │ │
│  └────────────────────┴──────┴──────┴──────┴──────┴──────┴──────┴──────┴───┘ │
└────────────────────────────────────────────────────────────────────────────────┘
```

---

## 2. Dynamic Table Dependency Chain

All 14 DTs use `TARGET_LAG = '1 hour'` (except SAFETY_STOCK_POLICY at 2 days) and `WAREHOUSE = COMPUTE_WH`.

```
RAW_OT.SENSOR_READINGS  ──────────────────────────────────────────┐
RAW_OT.ASSET_MASTER  ─────────────────────────────────────────────┤
RAW_IT.WORK_ORDERS  ──────────────────────────────────────────────┤
RAW_IT.PRODUCTION_OUTPUT  ────────────────────────────────────────┤
                                                                   ▼
                                                          ┌── CURATED ──┐
                                                          │             │
                                               SENSOR_WITH_CONTEXT (560K+ rows)
                                               ASSET_HEALTH_CURRENT (10 rows)
                                               FAILURE_HISTORY (12 rows)
                                                          │
                                                          ▼
                                                 ┌── ML_FEATURES ──┐
                                                 │                  │
                                          ┌──────┴──────────────────┴──────┐
                                          │                                │
                                   LABELED_DATA            ROLLING_STATS
                                          │            SENSOR_INTERACTIONS
                                          │            TEMPORAL_MEMORY
                                          │            PHYSICS_COMPOSITE
                                          │            CROSS_DOMAIN
                                          │            FLEET_COMPARISON
                                          │                                
                                          └───────────┬────────────────────┘
                                                      │
                                                      ▼
                                              LIVE_PREDICTIONS (10 rows)
                                              [ML_MODELS schema]
                                                      │
                                          ┌───────────┴────────────┐
                                          │                        │
                                    ACTIVE_ALERTS           OEE_METRICS
                                    (10 rows)               (3,340 rows)
                                    [ANALYTICS]             [ANALYTICS]
```

---

## 3. Procurement Closed Loop

```
LIVE_PREDICTIONS (failure mode, RUL, stage)
       │
       ▼
PARTS_AVAILABLE_TO_PROMISE ──── ATP = on_hand - reserved
       │
       ▼
PROCUREMENT_RECOMMENDATIONS ──── Risk + action per asset × part
       │                          (CRITICAL_SHORTAGE / EXPEDITE / ORDER_NOW / NO_RISK)
       ├────────────────────┐
       │                    │
       ▼                    ▼
PARTS_LIFECYCLE_INSIGHTS, PROCUREMENT_PERFORMANCE, SUPPLIER_SCORECARD   PLANNED_PURCHASE_ORDERS (PPO)
(per-part stock health)    │ Aggregated by part
                           │ Priority score: RUL 40% + deficit 30% + competition 20% + critical 10%
                           │ Order-by deadline + expedite deadline
                           │
                     ┌─────┴──────────────────────┐
                     │                             │
              Manual action:                Auto-conversion:
              User clicks                   DAG_CONVERT_PPOS
              "Expedite" or                 (runs every 12h, suspended)
              "Convert now"                 converts overdue PPOs
                     │                             │
                     └────────────┬────────────────┘
                                  ▼
                           PURCHASE_ORDERS + PURCHASE_ORDER_LINES
                                  │
                                  ▼
                           PART_RESERVATIONS
                           (auto-created on WO start via
                            RESERVE_PART_FOR_WORK_ORDER)
```

---

## 4. ML Pipeline Detail

```
SENSOR_READINGS (560K+ rows, 15-min intervals)
    │
    ▼
SENSOR_WITH_CONTEXT ── joins asset metadata (rated_rpm, rated_temp_max)
    │
    ├──► LABELED_DATA ─── failure mode labels, degradation stage (0-4), hours_to_failure
    ├──► ROLLING_STATS ── 40 columns: 6h/24h mean/std/min/max/crest/RMS/CoeffVar + rate of change
    ├──► SENSOR_INTERACTIONS ── vib_xy_correlation, vib_temp_coupling, axis_dominance, acoustic_vib_ratio
    ├──► TEMPORAL_MEMORY ── hours_since_breach, degradation_velocity_30d, above_normal_count_24h
    ├──► PHYSICS_COMPOSITE ── ISO 10816, stress_index, composite_health_score, energy_balance
    ├──► CROSS_DOMAIN ── days_since_maintenance, maintenance_effectiveness, workload_intensity
    └──► FLEET_COMPARISON ── z-scores vs fleet mean, percentile rank, is_worst_in_fleet
          │
          └── All features joined in ──►  LIVE_PREDICTIONS
                                            │
                   ┌────────────────────────┤
                   │                        │
           PREDICT_FAILURE_MODE      PREDICT_RUL
           (5 classes)               (hours + CI)
                   │                        │
           PREDICT_DEGRADATION_STAGE COMPUTE_FATIGUE_SCORE
           (H/W/C + score)          (0.0-1.0)
```

---

## 5. Notification Flow

```
Trigger Event (WO created, PO approved, etc.)
       │
       ▼
LOG_APP_NOTIFICATION procedure
       │
       ├─── Check NOTIFICATION_SETTINGS for event type
       │    (email_enabled, in_app_enabled, personas, priority)
       │
       ├─── In-App Path:
       │    INSERT into APP_NOTIFICATIONS
       │    (1 row per target persona)
       │    └─── Displayed in notification bell (TTL=15s cache)
       │
       └─── Email Path:
            SEND_MFGPULSE_EMAIL procedure
            └─── SYSTEM$SEND_SNOWFLAKE_NOTIFICATION
                 via MFGPULSE_EMAIL integration
```

---

## 6. Complete Object Inventory

| Schema | Object Type | Count | Key Objects |
|---|---|---|---|
| RAW_OT | Tables | 4 | ASSET_MASTER, SENSOR_METADATA, SENSOR_READINGS, AMBIENT_CONDITIONS |
| RAW_OT | Streams | 1 | SENSOR_READINGS_STREAM |
| RAW_OT | Procedures | 2 | GENERATE_SENSOR_DATA, SIMULATE_SENSOR_FEED_CONFIGURABLE |
| RAW_IT | Tables | 13 | WORK_ORDERS, PARTS_INVENTORY, PURCHASE_ORDERS, USERS, SUPPLIERS, APP_NOTIFICATIONS, ... |
| RAW_IT | Streams | 2 | MAINTENANCE_LOGS_STREAM, WORK_ORDERS_STREAM |
| RAW_IT | Procedures | 2 | LOG_APP_NOTIFICATION, SEND_MFGPULSE_EMAIL |
| CURATED | Dynamic Tables | 3 | SENSOR_WITH_CONTEXT, ASSET_HEALTH_CURRENT, FAILURE_HISTORY |
| ML_FEATURES | Dynamic Tables | 7 | LABELED_DATA, ROLLING_STATS, SENSOR_INTERACTIONS, TEMPORAL_MEMORY, PHYSICS_COMPOSITE, CROSS_DOMAIN, FLEET_COMPARISON |
| ML_FEATURES | Views | 11 | ALL_DERIVED_FEATURES*, TRAIN_*, FEATURE_CATALOG |
| ML_MODELS | Dynamic Tables | 1 | LIVE_PREDICTIONS |
| ML_MODELS | Tables | 5 | FATIGUE_SCORES, ANOMALY_SCORES, MODEL_REGISTRY, FEEDBACK_LOG, DRIFT_COMPARISON |
| ML_MODELS | UDFs | 6 | PREDICT_FAILURE_MODE, PREDICT_RUL, PREDICT_DEGRADATION_STAGE, COMPUTE_FATIGUE_SCORE, SIMULATE_FAILURE_TWIN, ANOMALY_SCORER |
| ML_MODELS | Procedures | 8 | ANALYZE_ROOT_CAUSE (×2 overloads), PRESCRIBE_MAINTENANCE, PREDICT_ALL, PREDICT_CORE, PREDICT_DEEP, LOG_FEEDBACK, COMPUTE_NATIVE_PREDICTIONS, RETRAIN_IF_NEEDED, REFRESH_FATIGUE_SCORES |
| ML_MODELS | Views | 3 | DRIFT_METRICS, MODEL_ACCURACY_LIVE, LIVE_PREDICTIONS_WITH_ANOMALY |
| ML_MODELS | Cortex Search | 1 | MAINTENANCE_SEARCH (78 docs) |
| ANALYTICS | Dynamic Tables | 3 | ACTIVE_ALERTS, OEE_METRICS, SAFETY_STOCK_POLICY |
| ANALYTICS | Tables | 4 | SHIFT_HANDOVER_HISTORY, KPI_SNAPSHOTS, ALERT_HISTORY, ASSET_COST_PROFILES |
| ANALYTICS | Views | 17 | EXECUTIVE_SUMMARY, PREDICTIONS_WITH_COST, COST_IMPACT, COST_IMPACT_BY_ASSET, ALERT_SUMMARY, SHIFT_HANDOVER_VIEW, PROCUREMENT_RECOMMENDATIONS, PLANNED_PURCHASE_ORDERS, PARTS_AVAILABLE_TO_PROMISE, PARTS_LIFECYCLE_INSIGHTS, PROCUREMENT_PERFORMANCE, SUPPLIER_SCORECARD, DATA_FRESHNESS_SLA, OEE_PERIOD_COMPARISON, PROACTIVE_REORDER, AGENT_DAILY_SUMMARY, AGENT_EXECUTION_METRICS |
| ANALYTICS | Procedures | 15 | GENERATE_WORK_ORDER, AUTO_GENERATE_WORK_ORDERS, GENERATE_PURCHASE_ORDER, AUTO_GENERATE_PURCHASE_ORDERS, AUTO_CONVERT_PLANNED_POS, RESERVE_PART_FOR_WORK_ORDER, COMPLETE_WORK_ORDER, PROCESS_INVENTORY_TRANSACTION, CHECK_DATA_FRESHNESS, SNAPSHOT_KPIS, ARCHIVE_ALERTS, AUTO_COMPLETE_AGED_WORK_ORDERS, REFRESH_ALL_DTS, GENERATE_SHIFT_HANDOVER_SUMMARY, ... |
| ANALYTICS | Tasks | 11 | MFGPULSE_AUTOMATION_DAG (root) + 10 child tasks (simulate, freshness, fatigue, DT refresh, drift, archive, WO gen, PO gen, PPO convert, KPI snapshot) |
| AGENT | Semantic View | 1 | MAINTENANCE_SEMANTIC_VIEW (6 tables, 21 VQRs) |
| AGENT | Cortex Agent | 1 | MAINTENANCE_COPILOT (5 tools) |
| **TOTAL** | | **~145+** | 7 schemas, 30 base tables, 14 DTs, 31 views, 6 UDFs, 27 procedures, 11 DAG tasks, 3 streams, 2 warehouses, 3 resource monitors, 3 native ML models, 16 notification event types |

---

## 7. File Structure

```
MFGPulse_AI/
├── MFGPulse_AI_App/           # Streamlit application
│   ├── streamlit_app.py                # Entry point: persona login, navigation, notifications
│   ├── app_pages/
│   │   ├── _shared.py                  # Centralized data layer (25 loaders, caching, LLM helper)
│   │   ├── executive_dashboard.py      # Plant KPIs, OEE charts, supply chain, LLM summary
│   │   ├── operations_dashboard.py     # Fleet status, alerts, shift handover, sensor feed
│   │   ├── wo_po_console.py            # Work order + PO management with bulk operations
│   │   ├── maintenance_dashboard.py    # Asset deep-dive, failure DNA, root cause, prescriptive
│   │   ├── procurement_dashboard.py    # Recommendations, planned POs, stock, inventory, POs
│   │   ├── digital_twin.py            # Monte Carlo simulation (3 scenarios × 100 paths)
│   │   ├── admin_control_panel.py      # 12-section admin: tasks, DTs, ML, notifications, FinOps
│   │   └── copilot.py                 # 5-tool Cortex Agent conversational interface
│   ├── snowflake.yml                   # Streamlit deployment config
│   └── pyproject.toml                  # Python dependencies
│
├── cortex_project/                     # Cortex Agent + Semantic View
│   ├── cortex_project.yaml             # Project manifest
│   ├── MAINTENANCE_SEMANTIC_VIEW.sv.yaml  # Semantic View (6 tables, 21 VQRs)
│   └── MAINTENANCE_COPILOT_agent.yaml  # Agent definition (5 tools)
│
├── sql/                                # Deployment scripts (execution-order numbered)
│   ├── 01_infrastructure.sql           # Database, schemas, warehouse, resource monitor
│   ├── 02_base_tables.sql              # 19 base tables
│   ├── 03_streams.sql                  # 3 CDC streams
│   ├── 04_seed_data.sql                # Reference data
│   ├── 05_generate_sensor_data.sql     # Initial sensor readings generation
│   ├── 06_fatigue_scores.sql           # Fatigue + anomaly scores
│   ├── 07_curated_dynamic_tables.sql   # 3 curated DTs
│   ├── 08_ml_feature_dynamic_tables.sql # 7 feature DTs
│   ├── 09_ml_feature_views.sql         # 11 ML feature views
│   ├── 10_udfs_live_predictions.sql    # 6 UDFs + LIVE_PREDICTIONS DT
│   ├── 11_native_ml_models.sql         # Native ML model training (optional)
│   ├── 12_analytics_layer.sql          # 2 DTs + views + procedures
│   ├── 13_cortex_search.sql            # MAINTENANCE_SEARCH service
│   ├── 14_automation.sql               # 11-task DAG (suspended)
│   ├── 15_procurement_tables.sql       # Procurement table structures
│   ├── 16_procurement_views.sql        # ATP + procurement views
│   ├── 17_procurement_procedures.sql   # PO lifecycle procedures
│   ├── 18_validation.sql               # Full verification suite
│   ├── 19_notifications.sql            # Notification settings + email integration
│   ├── 20_configurable_simulation.sql  # Configurable simulation
│   └── ddl_objects.sql                 # Cross-instance: all UDFs, procedures, PPO view, task
│
├── test_cases/                         # Validation scripts
│   └── test_ml_edge_cases.sql          # TC-11: UDF boundary tests
│
└── docs/                               # Documentation
    ├── README.md                       # Project overview + capabilities
    ├── TECHNICAL_GUIDE.md              # Deep technical reference (523 lines)
    ├── USER_GUIDE.md                   # Per-persona workflows (618 lines)
    ├── DEPLOYMENT_GUIDE.md             # One-shot deployment (583 lines)
    ├── ARCHITECTURE_DIAGRAM.md         # This file
    ├── review.md                       # Audit report (8.5/10)
    └── ...                             # Presentation, evaluation, submission guides
```
