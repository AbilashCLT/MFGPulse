# MFGPulse AI Command Center — Technical Guide
*Co-authored with CoCo*

---

## 1. What Is This Solution?

The **MFGPulse AI Command Center** is a predictive maintenance and OEE (Overall Equipment Effectiveness) platform built entirely on Snowflake. It monitors 10 industrial assets across 3 production lines in a manufacturing plant, predicting failures before they happen and prescribing maintenance actions with cost justification.

The name "Failure Genome" reflects the idea that every machine failure has a unique DNA — a combination of sensor signatures, degradation trajectories, fatigue patterns, and operational context that can be decoded to predict and prevent breakdowns.

The platform includes role-based dashboards for 6 personas, a Cortex AI agent with 7 tools, a procurement-to-maintenance closed loop with PO lifecycle management, an email/in-app notification system, and an integrated test suite — all running natively on Snowflake.

---

## 2. Solution Architecture

```
┌─────────────────────────── DATA SOURCES ───────────────────────────┐
│  Sensors (OT)              ERP/CMMS (IT)           Weather         │
│  vibration, temp,          work orders,            ambient         │
│  RPM, pressure,            maintenance logs,       conditions      │
│  current, acoustic         parts, production                       │
└──────────┬─────────────────────┬──────────────────────┬────────────┘
           │                     │                      │
           ▼                     ▼                      ▼
┌──────────────────── MFGPULSE_DB ─────────────────────────────┐
│                                                                     │
│  ┌─── RAW_OT ───┐    ┌─── RAW_IT ──────────────────────────┐      │
│  │ ASSET_MASTER  │    │ WORK_ORDERS    USERS                │      │
│  │ SENSOR_META   │    │ MAINT_LOGS     SUPPLIERS            │      │
│  │ SENSOR_READS  │    │ PARTS_INV      PART_SUPPLIERS       │      │
│  │ AMBIENT_COND  │    │ PRODUCTION     PURCHASE_ORDERS      │      │
│  │   (stream) ───┼────│ SHIFT_SCHED    PURCHASE_ORDER_LINES │      │
│  └───────┬───────┘    │ PART_RESERVATIONS  SIMULATION_CFG   │      │
│          │            │ NOTIFICATION_SETTINGS                │      │
│          │            │ APP_NOTIFICATIONS                    │      │
│          │            └─────────────────────────────────────┘      │
│          ▼                                                         │
│  ┌─── CURATED (3 DTs) ─────────────┐                              │
│  │ SENSOR_WITH_CONTEXT             │  ← OT + IT joined            │
│  │ ASSET_HEALTH_CURRENT            │                               │
│  │ FAILURE_HISTORY                 │                               │
│  └───────┬─────────────────────────┘                               │
│          ▼                                                         │
│  ┌─── ML_FEATURES (7 DTs + 11 views) ──┐                          │
│  │ LABELED_DATA ──► ROLLING_STATS       │  ← Auto-refreshing      │
│  │              ──► SENSOR_INTERACT.    │    feature engineering   │
│  │              ──► TEMPORAL_MEMORY     │                          │
│  │              ──► CROSS_DOMAIN        │                          │
│  │              ──► PHYSICS_COMPOSITE   │                          │
│  │              ──► FLEET_COMPARISON    │                          │
│  └───────┬──────────────────────────────┘                          │
│          ▼                                                         │
│  ┌─── ML_MODELS ──────────────────────┐                            │
│  │ 5 UDFs + 3 Procs → LIVE_PRED. DT  │  ← Central prediction hub │
│  │ FATIGUE_SCORES, ANOMALY_SCORES     │                            │
│  │ MODEL_REGISTRY (12 models)         │                            │
│  │ MAINTENANCE_SEARCH (Cortex Search) │                            │
│  └───────┬────────────────────────────┘                            │
│          ▼                                                         │
│  ┌─── ANALYTICS (2 DTs + 9 views + 7 procs) ─┐                    │
│  │ ACTIVE_ALERTS (DT)  OEE_METRICS (DT)      │ ← Business layer  │
│  │ EXECUTIVE_SUMMARY   PREDICTIONS_WITH_COST  │                    │
│  │ COST_IMPACT         ASSET_COST_PROFILES                       │
│  │ PARTS_AVAILABLE_TO_PROMISE                │                    │
│  │ PROCUREMENT_RECOMMENDATIONS                │                    │
│  │ PARTS_LIFECYCLE_INSIGHTS                   │                    │
│  │ PLANNED_PURCHASE_ORDERS (PPO engine)       │                    │
│  │ DAG_CONVERT_PPOS (child task in DAG)          │                    │
│  └────────────────────────────────────────────┘                    │
│                                                                     │
│  ┌─── AGENT ──────────────────────────┐                            │
│  │ MAINTENANCE_SEMANTIC_VIEW (21 VQRs)│  ← Cortex Agent layer     │
│  │ MAINTENANCE_COPILOT (7-tool agent) │                            │
│  └────────────────────────────────────┘                            │
└─────────────────────────────────────────────────────────────────────┘
           │
           ▼
┌─── Streamlit App (9 pages, 6 personas) ────────────────────────────┐
│ Executive │ Operations │ WO/PO Console │ Maintenance │ Procurement │
│ Digital Twin │ Admin Panel │ Maintenance Copilot                   │
└────────────────────────────────────────────────────────────────────┘
```

---

## 3. Key Terminologies

| Term | Definition |
|---|---|
| **OEE** | Overall Equipment Effectiveness = Availability x Performance x Quality. Industry benchmark: 85%. |
| **RUL** | Remaining Useful Life — predicted hours until failure, with confidence intervals (P10/P50/P90). |
| **Degradation Stage** | 3-level classification: `Healthy` / `Warning` / `Critical`. |
| **Failure Mode** | The specific failure type: `bearing_wear`, `thermal_degradation`, `imbalance`, `misalignment`, or `normal`. |
| **Fatigue Score** | Hidden fatigue level (0.0-1.0) detected from physics-composite features. Levels: `healthy` / `accumul` / `high` / `critical`. |
| **Digital Twin** | A Monte Carlo simulation engine that runs 100 stochastic paths to project failure probability under different intervention strategies. |
| **Failure DNA Profile** | A visual fingerprint of 5 risk signals per asset: degradation, fatigue, transition probability, stress, and health loss. |
| **Cost of Inaction** | The estimated financial impact if a predicted failure is ignored: `failure_cost - planned_repair_cost`. |
| **Action Window** | Urgency classification based on RUL: `IMMEDIATE` (< 24h), `URGENT` (24-72h), `SCHEDULED` (> 72h). |
| **Composite Health Score** | A 0-100 score combining vibration magnitude, temperature ratio, current deviation, and acoustic deviation. |
| **ISO 10816 Severity** | Vibration severity per ISO 10816: `Good` (1) / `Acceptable` (2) / `Warning` (3) / `Unacceptable` (4). |
| **Stress Index** | Physics-based stress metric derived from vibration, temperature, current, and pressure readings. |
| **Transition Probability** | Likelihood that an asset will move to a worse degradation stage within the next maintenance window. |
| **Fleet Comparison** | Z-score of an asset's vibration relative to the fleet mean — identifies outliers ("worst in fleet"). |
| **ATP** | Available-to-Promise = `quantity_on_hand - reserved_quantity`. How many parts are actually available. |
| **Procurement Risk** | 4-level classification: `NO_RISK` / `ORDER_NOW` / `EXPEDITE` / `CRITICAL_SHORTAGE`. |
| **Cortex Agent** | An LLM-powered assistant with 7 tools: analytics (text-to-SQL), search (RAG), fast diagnosis (M1-M4), deep analysis (M5-M7), simulation, work order generation, and purchase order generation. |
| **Dynamic Table** | A Snowflake object that auto-refreshes its contents based on upstream changes — the backbone of the feature engineering pipeline. |
| **Cortex Search** | A RAG (Retrieval-Augmented Generation) service indexing maintenance logs for natural-language search. |
| **Persona** | A user role that determines page access: `TECHNICIAN`, `RELIABILITY_ENGINEER`, `SHIFT_SUPERVISOR`, `PLANT_MANAGER`, `PROCUREMENT_ADMIN`, `APP_ADMIN`. |

---

## 4. Database Schemas — Rules & Conventions

### Schema Hierarchy

| Layer | Schema | Convention | Example Objects |
|---|---|---|---|
| **Ingestion** | `RAW_OT`, `RAW_IT` | Raw data, append-only streams, simulation tasks, users, procurement, notifications | `SENSOR_READINGS`, `WORK_ORDERS`, `PURCHASE_ORDERS`, `NOTIFICATION_SETTINGS` |
| **Curation** | `CURATED` | Cleaned joins, context enrichment | `SENSOR_WITH_CONTEXT`, `ASSET_HEALTH_CURRENT` |
| **Features** | `ML_FEATURES` | Dynamic tables only, auto-refresh, no manual DML | `ROLLING_STATS`, `PHYSICS_COMPOSITE`, `FLEET_COMPARISON` |
| **Models** | `ML_MODELS` | Model outputs, UDFs, procedures, search services | `LIVE_PREDICTIONS`, `SIMULATE_FAILURE_TWIN`, `MAINTENANCE_SEARCH` |
| **Analytics** | `ANALYTICS` | Business views, alert DTs, KPI aggregations, WO/PO procedures, planned PO engine | `EXECUTIVE_SUMMARY`, `ACTIVE_ALERTS`, `PROCUREMENT_RECOMMENDATIONS`, `PLANNED_PURCHASE_ORDERS` |
| **Agent** | `AGENT` | Semantic views, Cortex Agent definitions | `MAINTENANCE_COPILOT`, `MAINTENANCE_SEMANTIC_VIEW` |

### Naming Rules

- **Tables**: `UPPER_SNAKE_CASE` — noun describing the entity (`SENSOR_READINGS`, `WORK_ORDERS`).
- **Dynamic Tables**: Same naming, in `CURATED`, `ML_FEATURES`, `ML_MODELS`, or `ANALYTICS` schemas.
- **Views**: Descriptive name of what they expose (`PREDICTIONS_WITH_COST`, `EXECUTIVE_SUMMARY`).
- **Procedures**: Verb-first (`GENERATE_WORK_ORDER`, `LOG_APP_NOTIFICATION`).
- **UDFs**: Verb-first (`SIMULATE_FAILURE_TWIN`, `COMPUTE_FATIGUE_SCORE`).
- **Streams**: `{TABLE_NAME}_STREAM` (e.g., `SENSOR_READINGS_STREAM`).
- **Assets**: `ASSET_001` through `ASSET_010`, each with a descriptive `asset_name`.

### Data Flow Rules

1. **No manual DML on dynamic tables** — they auto-refresh from upstream sources.
2. **Streams drive CDC** — 3 streams on SENSOR_READINGS, MAINTENANCE_LOGS, WORK_ORDERS.
3. **All DTs use TARGET_LAG = '1 hour'** and WAREHOUSE = COMPUTE_WH.
4. **LIVE_PREDICTIONS is the single source of truth** for all model outputs — every page reads from it or its derivative views.
5. **ANALYTICS views never store data** (except `ACTIVE_ALERTS` and `OEE_METRICS` which are dynamic tables).
6. **All user-facing SQL uses parameterized queries** — no string interpolation of user input.

---

## 5. The 12 ML models

### UDF-Based Pipeline (M1-M7)

| # | Model | Type | Input | Output | Method |
|---|---|---|---|---|---|
| M1 | **Failure Mode Classifier** | Classification | 28 sensor + engineered features | 6-class failure mode + confidence | Rule-based ensemble with undetermined_degradation catch-all (ISO 13379) |
| M2 | **RUL Estimator** | Regression | 8 core features | Hours to failure (P10/P50/P90 CI) | Physics-informed regression UDF |
| M3 | **Degradation Stager** | Classification | 7 sensor features + RUL | Healthy/Warning/Critical + score | Weighted composite with RUL override (ISO 13381-1) |
| M4 | **Hidden Fatigue Detector** | Anomaly Detection | 9 physics-composite features | Fatigue score (0-1) + level | Cumulative damage model UDF |
| M5 | **Root Cause Analyzer** | LLM | Sensor readings + Cortex Search RAG | Natural-language root cause + evidence | Cortex COMPLETE (llama3.1-70b) procedure |
| M6 | **Digital Twin Simulator** | Monte Carlo | Current state + scenario params | 100 paths, fail prob at 3/7/14d, RUL distribution | SQL UDF with stochastic projection |
| M7 | **Prescriptive Engine** | LLM | All model outputs + parts/cost data | Action, priority, parts, cost analysis | Cortex COMPLETE (llama3.1-70b) procedure |

### Native Snowflake ML Models (4)

| Model | Type | Training Data | Notes |
|---|---|---|---|
| NATIVE_FAILURE_MODE_CLASSIFIER | Snowflake.ML.Classification | ~14.5M rows, 5 classes | Rebalanced: normal class sampled at 50% (was 15%) |
| NATIVE_DEGRADATION_STAGER | Snowflake.ML.Classification | ~107M rows, 3 text-label classes | Labels: 'Healthy'/'Warning'/'Critical' (was numeric 0/1/2) |
| NATIVE_RUL_FORECASTER | Snowflake.ML.Forecast | 20K rows, 7 asset series | |
| NATIVE_ANOMALY_DETECTOR | Snowflake.ML.AnomalyDetection | 50K multivariate scores | |

### Drift Detection & Closed-Loop ML

The system compares rule-based (LIVE_PREDICTIONS) and native ML predictions to detect model drift:

- **COMPUTE_NATIVE_PREDICTIONS** procedure: Runs native classifiers on latest features, joins with rule-based output, and inserts into `DRIFT_COMPARISON`. Executed automatically by the `DAG_CHECK_DRIFT` task after each DT refresh. Features:
  - **Dedup-safe**: DELETEs existing rows for CURRENT_DATE() before inserting, so re-runs don't create duplicates.
  - **Exception-safe**: Each `!PREDICT` call is wrapped in BEGIN/EXCEPTION. If a native model is broken or unavailable, the procedure writes `'UNAVAILABLE'` for that model's predictions instead of crashing.
  - **Non-NULL booleans**: Uses `COALESCE(a = b, FALSE)` to guarantee FAILURE_MODE_AGREES and STAGE_AGREES are never NULL (NULL equality → FALSE).
- **DRIFT_METRICS** view: Aggregates per-day agreement rates. Alert threshold: < 80%.
- **RETRAIN_IF_NEEDED** procedure: Checks drift metrics; if agreement < 80%, retrains the native models with `CREATE OR REPLACE SNOWFLAKE.ML.CLASSIFICATION`.
- **FEEDBACK_LOG** + **MODEL_ACCURACY_LIVE**: Technicians confirm root cause on WO completion; `LOG_FEEDBACK` procedure captures whether the predicted failure mode was correct. Rolling 30-day accuracy view.

**Streamlit UI**: Both drift and accuracy are displayed in **Admin Panel → ML models** (scroll below model registry). Shows FM/stage agreement KPIs, per-asset disagreement detail, and 30-day feedback accuracy.

**2026-09-13 fix**: Prior to this date, TRAIN_TRAJECTORY_3CLASS used numeric labels (0/1/2) while the rule-based engine produced text labels ('Healthy'/'Warning'/'Critical'). This caused 100% false stage disagreement. Both training views and the COMPUTE_NATIVE_PREDICTIONS procedure have been corrected. TRAIN_FAILURE_MODE normal-class sampling was also increased from 15% to 50% to reduce failure-mode bias.

### How Models Feed LIVE_PREDICTIONS

The `LIVE_PREDICTIONS` dynamic table joins:
- Latest sensor features per asset (from `ML_FEATURES.ROLLING_STATS`, `SENSOR_INTERACTIONS`, `TEMPORAL_MEMORY`, `PHYSICS_COMPOSITE`)
- Inline failure mode classification → `FAILURE_MODE_PRED`, `FAILURE_MODE_CONFIDENCE`
- Inline RUL estimation → `RUL_HOURS`, `RUL_LOWER_CI`, `RUL_UPPER_CI`
- Inline degradation staging with RUL override → `STAGE_PRED`, `DEGRADATION_SCORE`, `TRANSITION_PROBABILITY`
- `FATIGUE_SCORES` table → `FATIGUE_SCORE`, `FATIGUE_LEVEL`
- `PHYSICS_COMPOSITE` DT → `COMPOSITE_HEALTH_SCORE`, `STRESS_INDEX`

### Stage Classification (ISO 13381-1 / P-F Curve)

RUL overrides the composite degradation score — per the P-F interval model, an asset near or at functional failure cannot be classified below Critical.

| Priority | Condition | Stage |
|---|---|---|
| 1 | RUL < 48h | **Critical** (P-F interval override) |
| 2 | Degradation score >= 0.65 | **Critical** |
| 3 | RUL < 168h OR degradation score >= 0.30 | **Warning** |
| 4 | All else | **Healthy** |

### Failure Mode Classification (ISO 13379)

| Mode | Trigger Conditions |
|---|---|
| bearing_wear | vib_crest_factor > 1.5 AND acoustic/vib ratio > 20 AND vib_rms > 5.0 |
| thermal_degradation | temp_mean > 70 AND vib_rms < 4.0 AND stress_index > 0.5 |
| misalignment | abs(xy_correlation) > 0.6 AND current/rpm ratio > 8.0 AND axis_dominance < 0.7 |
| imbalance | axis_dominance > 0.75 AND vib_rms > 4.0 AND current/rpm ratio < 7.0 |
| undetermined_degradation | degradation_score > 0.5 OR stress_index > 0.7 OR health_score < 30 (catch-all) |
| normal | No degradation signals detected |

---

## 6. Streamlit App — Page-by-Page Navigation Guide

### 6.1 Executive Dashboard

**Purpose**: Plant-wide KPIs and financial impact — the page a Plant Manager opens first.

**Executive summary**: LLM-generated boardroom-ready narrative via Cortex Complete (llama3.1-8b). Assembles plant OEE, critical assets, cost avoided, ROI, emergency WOs, early detection, and line performance into a structured prompt. Result cached in session state keyed by data hash — regenerates only when KPIs change or user clicks "Regenerate". Same pattern used on Operations, WO/PO, Maintenance, and Procurement pages.

**What you see**:
- **8 KPI cards**: Plant OEE, Critical Assets, Cost Avoided, Maintenance ROI, Early Detection Days, Emergency WOs, Total Spend, OEE Improvement Potential.
- **OEE by Production Line**: Grouped bar chart (Availability, Performance, Quality, OEE per line).
- **OEE Loss Attribution**: Which assets cause the most availability/performance/quality loss.
- **OEE Trend Analysis**: Daily multi-line chart (one line per production line + plant-wide average) with 85% target reference line. Switchable between OEE, Availability, Performance, and Quality metrics. Covers 185 days of trend data. Uses a single cached query on OEE_METRICS aggregated by date and line.
- **Maintenance Cost by Asset**: Vertical bars color-coded by degradation stage with tooltip detail.
- **Asset Risk Matrix**: Sortable table with stage, failure mode, RUL, action window, failure/repair/inaction costs, parts status.
- **Work Order Cost Breakdown**: Donut chart by WO type (emergency/corrective/preventive) with open WO count, emergency count, total spend.
- **Supply Chain Risk Overview**: Risk distribution donut chart (Critical Shortage / Expedite / Order Now / No Risk), lead time gap horizontal bar chart per at-risk asset, at-risk cost metric, KPI counters, and detailed at-risk parts table with demand quantity, total demand, ATP, and recommended actions.

**Data sources**: `EXECUTIVE_SUMMARY`, `PREDICTIONS_WITH_COST` (per-asset costs via `ASSET_COST_PROFILES`), `OEE_METRICS`, `COST_IMPACT_BY_ASSET`, `WORK_ORDERS`, `PROCUREMENT_RECOMMENDATIONS`.

---

### 6.2 Operations Center

**Purpose**: Real-time operational awareness — the page a Shift Supervisor monitors throughout the shift.

**What you see**:
- **7 KPI cards**: Total assets, Critical, Active alerts, Open WOs, Emergency WOs, WO Completion rate, Parts at risk.
- **5 segmented views**:
  - **Fleet status**: All 10 assets with stage badge, RUL, health score, failure mode, and recommended action badge (IMMEDIATE / THIS WEEK / NEXT WEEK) sourced from PREDICTIONS_WITH_COST.ACTION_WINDOW.
  - **Alert triage**: Active alerts sorted by severity with color-coded badges and messages.
  - **Shift handover**: AI-generated shift briefing (Cortex Complete) with immediate actions, assets to monitor, procurement status, and WO attention items. KPI metrics (critical actions, warnings, plant OEE, alerts). Procurement readiness panel with parts shortages and open POs.
  - **Work orders**: Open WOs table with type, priority, status, assigned technician, cost.
  - **Sensor feed**: Live/Recent/Stale status badge with last reading timestamp. Live 24-hour sensor data with asset filter, time range selector (1h/6h/12h/24h), latest reading KPIs (vibration magnitude, temperature, RPM, pressure, current, acoustic), channel time-series chart, and raw data export table. Cached with 60s TTL for near-real-time updates.

---

### 6.3 WO / PO Console

**Purpose**: Unified work order and purchase order management — persona-dependent actions.

**Persona-dependent access**:

| Persona | WO Actions | PO Tab | PO Actions |
|---|---|---|---|
| Technician | View (own WOs highlighted) | Hidden | — |
| Reliability Engineer | View | View only | — |
| Shift Supervisor | Start / Complete | View only | — |
| Plant Manager | Start / Complete | Full | Approve / Reject / Receive |
| Procurement Admin | View | Full | Approve / Reject / Receive |
| App Admin | Start / Complete | Full | Approve / Reject / Receive |

**4 tabs**:
- **Work orders**: Filterable by status/type/priority/asset. Technicians see "My WOs" first. Cards with type/status/priority badges, cost, assigned tech, dates, RESERVED/risk part badge (context-aware), linked PO, activity log. Start Work gated by ATP (disabled when no parts + "Alert Procurement" button). Complete flow prompts "Part used?" (consumed/released) and root cause selector. Auto-reserves on start, auto-releases reservation on complete. Aging warnings: reservation >7d on open WOs, WO >48h in_progress.
- **Purchase orders**: Filterable by status/risk/supplier. Cards with approval status, risk badge, supplier, dates. Approve/Reject/Receive (persona-gated). Rejection requires written reason (stored in REJECTION_REASON), impact notification to Shift Supervisor. Cancelled POs display rejection reason.
- **WO analytics**: Donut chart (count by type), bar chart (cost by type), bar chart (cost by asset), avg cost per type, completion rate.
- **Shortage simulation**: What-if part shortage analysis with Apply/Revert controls.

**Notifications**: Every action fires `LOG_APP_NOTIFICATION` for in-app + email. PO rejection includes asset/part/RUL impact context targeting Shift Supervisor. Part shortage alerts target Procurement Admin.

---

### 6.4 Maintenance Hub

**Purpose**: Deep asset-level diagnostics — the page a Technician or Reliability Engineer uses daily.

**What you see**:
- **Fleet Health Matrix**: All 10 assets with stage, RUL, fatigue, health, WO count (total + open).
- **Asset Deep-Dive** (select from dropdown):
  - **KPI Row 1**: Stage (badge), RUL (with delta warning if <72h), Health score, Failure mode (with confidence).
  - **KPI Row 2**: Degradation (with contextual label), Fatigue (with level label), Stress index, Transition probability.
  - **Failure DNA Chart**: 5 normalized risk signals as color-coded bars (red >0.7, orange >0.4, green).
- **Bottom panels** (2-column):
  - **Parts status**: Part name, ATP, on-hand, risk badge, lead time, gap, arrival date, PO creation button.
  - **Alerts + Maintenance** (combined): Active alerts with severity badges, divider, then recent maintenance timeline with WO cards showing type/priority badges, technician, timestamp, notes.

---

### 6.5 Procurement

**Purpose**: Parts availability and PO management — the page a Procurement Admin uses.

**5 segmented views**:
- **Procurement recommendations**: Risk-sorted asset cards with enhanced risk classification (CRITICAL_SHORTAGE/EXPEDITE/ORDER_NOW/TIGHT_BUFFER/NO_RISK/MONITOR_PO), buffer status badges (DEFICIT/TIGHT/SURPLUS), competing asset count, incoming PO info, ATP, lead time, gap, supplier, one-click PO creation.
- **Planned POs**: Dynamically generated PPOs aggregated by part from PROCUREMENT_RECOMMENDATIONS. Each PPO card shows priority score (weighted composite: RUL urgency 40%, deficit 30%, competing assets 20%, criticality 10%), order-by deadline with countdown, expedite vs standard arrival dates, auto-convert status. Actions: "Expedite" (creates PO with EMERGENCY priority), "Convert now" (creates PO at current priority), "Run auto-convert now" (batch conversion). Auto-conversion task (`AUTO_CONVERT_PLANNED_POS_TASK`) runs every 12 hours to convert overdue PPOs — created suspended, enable via Admin.
- **Stock insights**: Stock vs demand grouped bar chart (ATP/Demand/Incoming per part), part contention map showing which at-risk assets share parts, estimated days until stockout, net position (ATP + incoming - demand), and buffer status KPIs.
- **Parts inventory**: ATP table with on-hand, reserved, ATP, lead time, unit cost, supplier.
- **Purchase orders**: Open POs with auto-generate button.

**WO → Parts integration**: When a WO is started (status → in_progress), the system automatically reserves the recommended part via `RESERVE_PART_FOR_WORK_ORDER`. If no stock is available, a warning toast is displayed.

---

### 6.6 Digital Twin Simulator

**Purpose**: Monte Carlo what-if analysis — the page a Reliability Engineer uses to evaluate intervention strategies.

**What you see**:
- **Asset selector** (defaults to Warning-stage asset for meaningful comparison).
- **Asset KPIs**: Stage, RUL, Degradation, Fatigue.
- **3 Scenarios** side by side: A (Do Nothing), B (Reduce Load — sliders), C (Custom — load, delay, RPM sliders).
- **300 Monte Carlo simulations** (100 per scenario) via `SIMULATE_FAILURE_TWIN` UDF.
- **Scenario Comparison Table**: RUL P10/P50/P90, failure probability at 3/7/14 days, fails-before-maintenance %, expected cost, recommended intervention.
- **Simulation Summary**: Auto-generated text narrative identifying the lowest-cost scenario, cost savings vs worst scenario, 14-day failure probabilities, and actionable recommendations. Adapts to asset condition — flags exhausted intervention windows for heavily degraded assets.
- **Failure Probability Timeline**: Line chart showing probability curves at day 3/7/14 for all 3 scenarios.
- **RUL Distribution Comparison**: Grouped bar chart of P10/P50/P90 per scenario.
- **Part Arrival vs Failure Timing**: Lead time vs median simulated RUL with margin assessment (SAFE/TIGHT/ARRIVES AFTER FAILURE).

**Warning**: Assets with degradation >0.8 show near-certain failure across all scenarios. Select a Warning or Healthy asset for meaningful comparison.

---

### 6.7 Admin Panel

**Purpose**: Infrastructure monitoring, notification management, and test execution — restricted to Plant Manager and App Admin.

**9 sections** via segmented control:

| Section | Content | Actions |
|---|---|---|
| Tasks | 3 scheduled tasks with state/schedule | Resume / Suspend |
| Dynamic tables | 13 DTs with rows, storage, lag, refresh mode | Manual Refresh |
| Streams | 3 streams with stale/active status | Read-only |
| ML models | 12 models with F1/precision/recall, Cortex Search | Read-only |
| Cortex services | Agent, Semantic View, Search service status | Read-only |
| Notifications | Per-event email/in-app toggles, recipients, personas, priority | Save per event, Test send |
| Test suite | 6 test categories, inline execution with progress | Run tests per category |
| FinOps | Credit KPIs (warehouse/CoCo/containers/AI), resource monitor progress bar, daily credit trend chart, service-type breakdown chart, query cost table, storage top-10, DT refresh history, task execution history | Read-only |
| Simulation | Configurable sensor feed: asset selector, 5 scenarios (clean + 4 fault modes), severity slider, hours, credit estimation, history log | Run simulation |
| User management | All users with persona/email/line/active editing, add new user form with auto-generated ID | Edit / Create |
| Object inventory | Full Snowflake object counts + schema breakdown | Read-only |

---

### 6.8 Maintenance Copilot

**Purpose**: Natural-language interface to the entire platform — ask questions, run diagnostics, generate work orders via conversation.

**Features**:
- **Role-aware greeting** on page open (different per persona).
- **Suggested question pills** per persona (click to ask).
- **Dual LLM paths**:
  - **Fast path**: Data questions answered from pre-loaded plant context via `CORTEX.COMPLETE`.
  - **Agent path**: Complex tasks triggering the 7-tool Cortex Agent.
- **Status indicators**: "Retrieving plant data..." / "Searching maintenance history..." / "Running ML models..." while processing.
- **Session history**: New session button, previous sessions listed in sidebar, click to restore.
- **Greeting detection**: "hi/hello" gets a short friendly response, not a data dump.

**The 7 Agent Tools**:

| Tool | What It Does | Example Question |
|---|---|---|
| `maintenance_analytics` | Text-to-SQL via Semantic View | "What's the OEE for Line 1?" |
| `maintenance_history` | RAG search over 78 maintenance logs | "What repairs were done on Compressor A1?" |
| `diagnose_asset` | Fast M1-M4 diagnosis (failure mode, RUL, degradation, fatigue) | "Diagnose ASSET_005" |
| `deep_analysis` | LLM-powered M5-M7 (root cause, simulation, prescription) | "Run a full diagnosis on ASSET_005" |
| `simulate_scenario` | Monte Carlo what-if simulation | "What if we reduce load on ASSET_001 by 30%?" |
| `generate_work_order` | Create and file a work order | "Create a preventive WO for Fan F1" |
| `generate_purchase_order` | Create a purchase order for parts | "Order parts needed for Pump P2 repair" |

**Agent trigger keywords**: "generate work order", "create work order", "run diagnosis", "7-model", "full diagnosis", "simulate", "what-if", "monte carlo", "order parts", "create PO".

---

## 7. Dynamic Table Refresh Chain

```
SENSOR_READINGS (base table, 172K rows)
     │
     ▼
SENSOR_WITH_CONTEXT (CURATED DT)
ASSET_HEALTH_CURRENT (CURATED DT)
FAILURE_HISTORY (CURATED DT)
     │
     ├──► ROLLING_STATS (DT)         6h/24h rolling mean, std, max, crest, RMS, CoV
     ├──► SENSOR_INTERACTIONS (DT)    Cross-sensor: xy_corr, current_rpm_ratio, axis_dom
     ├──► TEMPORAL_MEMORY (DT)        Hours since breach, degradation velocity, trend slopes
     ├──► CROSS_DOMAIN (DT)           IT/OT fusion: days since maintenance, cumulative hours
     ├──► PHYSICS_COMPOSITE (DT)      Stress index, health score, ISO severity (INCREMENTAL)
     └──► FLEET_COMPARISON (DT)       Z-scores vs fleet mean, percentile rankings
            │
            ▼ (features joined in LIVE_PREDICTIONS)
     LIVE_PREDICTIONS (ML_MODELS DT) ← calls 3 UDFs + joins FATIGUE_SCORES
            │
            ├──► ACTIVE_ALERTS (ANALYTICS DT)     Multi-signal alert engine
            ├──► OEE_METRICS (ANALYTICS DT)        Per-asset-per-shift OEE
            └──► ANALYTICS views                    Cost, executive, procurement
```

**All DTs**: TARGET_LAG = '1 hour', WAREHOUSE = COMPUTE_WH.
**PHYSICS_COMPOSITE** uses INCREMENTAL refresh mode for efficiency.

---

## 8. Notification System

### Architecture
```
Action (WO start, PO approve, etc.)
  → CALL LOG_APP_NOTIFICATION(event_type, title, message, entity_id)
    → READ NOTIFICATION_SETTINGS for event_type
    → IF in_app_enabled: INSERT into APP_NOTIFICATIONS (one per target persona)
    → IF email_enabled: CALL SEND_MFGPULSE_EMAIL via MFGPULSE_EMAIL integration
```

### Event Types (16 total)

| Event | Default Personas | Default Priority |
|---|---|---|
| WO_CREATED | SHIFT_SUPERVISOR, PLANT_MANAGER, APP_ADMIN | NORMAL |
| WO_STARTED | TECHNICIAN, SHIFT_SUPERVISOR, PLANT_MANAGER, APP_ADMIN | NORMAL |
| WO_COMPLETED | SHIFT_SUPERVISOR, PLANT_MANAGER, APP_ADMIN | NORMAL |
| WO_CANCELLED | SHIFT_SUPERVISOR, PLANT_MANAGER, APP_ADMIN | NORMAL |
| WO_REASSIGNED | SHIFT_SUPERVISOR, PLANT_MANAGER, APP_ADMIN | NORMAL |
| WO_FOLLOWUP | SHIFT_SUPERVISOR, PLANT_MANAGER | NORMAL |
| PO_CREATED | PROCUREMENT_ADMIN, PLANT_MANAGER, APP_ADMIN | NORMAL |
| PO_APPROVED | PROCUREMENT_ADMIN, PLANT_MANAGER, APP_ADMIN | NORMAL |
| PO_REJECTED | PROCUREMENT_ADMIN, SHIFT_SUPERVISOR, PLANT_MANAGER, APP_ADMIN | HIGH |
| PO_RECEIVED | PROCUREMENT_ADMIN, PLANT_MANAGER, APP_ADMIN | NORMAL |
| PART_SHORTAGE_ALERT | PROCUREMENT_ADMIN, SHIFT_SUPERVISOR, PLANT_MANAGER | HIGH |
| DATA_STALE | PLANT_MANAGER, APP_ADMIN, SHIFT_SUPERVISOR | HIGH |
| MODEL_DRIFT | PLANT_MANAGER, APP_ADMIN | HIGH |
| MODEL_RETRAIN | PLANT_MANAGER, APP_ADMIN | NORMAL |
| SHORTAGE_SIM | PLANT_MANAGER, APP_ADMIN | LOW |
| SHORTAGE_REVERTED | PLANT_MANAGER, APP_ADMIN | LOW |

### APP_NOTIFICATIONS Table Schema
```
NOTIF_ID VARCHAR(200)          -- Composite key: EVENT_TYPE-PERSONA-TIMESTAMP
EVENT_TYPE VARCHAR(50)          -- e.g., WO_STARTED, PO_REJECTED
PERSONA_TARGET VARCHAR(50)      -- Target persona for this notification
TITLE VARCHAR(500)              -- Short title
MESSAGE VARCHAR(2000)           -- Detailed message body
ENTITY_ID VARCHAR(100)          -- WO_ID, PO_ID, or other entity reference
PRIORITY VARCHAR(20)            -- NORMAL, HIGH, LOW
IS_READ BOOLEAN                 -- Read status per persona
DISMISSED BOOLEAN               -- Dismissed by user
CREATED_AT TIMESTAMP_NTZ        -- Auto-set on insert
```

### Admin Controls (per event)
- Email on/off toggle
- In-app on/off toggle
- Email recipients (comma-separated)
- Target personas (multi-select)
- Priority (NORMAL / HIGH)
- Test notification button

---

## 9. Procurement System

### ATP Calculation
`AVAILABLE_TO_PROMISE = quantity_on_hand - reserved_quantity`

### Risk Classification (APICS/ASCM aligned)

| Condition | Risk Level | Recommended Action |
|---|---|---|
| Active reservation exists | RESERVED | MONITOR_RESERVATION |
| Open PO exists | — | MONITOR_EXISTING_PO |
| ATP=0, no incoming POs | CRITICAL_SHORTAGE | ESCALATE_CRITICAL_SHORTAGE |
| RUL < 72h, no open WO | — | ESCALATE_NO_WO |
| RUL < 72h, effective ATP >= required | REPLENISH_NOW | RESERVE_AND_REORDER |
| RUL < 72h, lead time infeasible | EXPEDITE | ESCALATE_CRITICAL_SHORTAGE |
| RUL < 72h, ATP insufficient | EXPEDITE | EXPEDITE_PO |
| Net position < 0 | ORDER_NOW | CREATE_PO |
| RUL < 336h, ATP insufficient, lead time infeasible | EXPEDITE | EXPEDITE_PO |
| RUL < 336h, ATP insufficient | ORDER_NOW | CREATE_PO |
| RUL < 336h, ATP sufficient | REPLENISH_NOW | RESERVE_AND_REORDER |
| All else | NO_RISK | NO_ACTION |

### Buffer Status (demand-aware, per APICS net requirements)

| Status | Condition | Meaning |
|---|---|---|
| SURPLUS | net_position >= competing_assets + 1 | Covers all demand + safety margin |
| ADEQUATE | net_position >= required_quantity | Covers immediate need |
| TIGHT | net_position >= 0 | Barely covers, no margin |
| DEFICIT | net_position < 0 | Demand exceeds supply |

### Gap Types (APICS lead time offset)

| Gap Type | Condition | Meaning |
|---|---|---|
| NO_GAP | lead_time <= RUL (in days) | Parts arrive within RUL window |
| REPLENISHMENT_GAP | effective ATP >= required, lead_time > RUL | Stock covers now, but reorder won't arrive in time |
| FULFILLMENT_GAP | effective ATP < required, lead_time > RUL | Can't serve demand from stock |

### PO Lifecycle
`draft → pending_approval → approved → ordered → shipped → received`

Duplicate prevention: checks for existing open PO on same PART_ID + ASSET_ID before creating.

### Planned Purchase Orders (PPOs)

PPOs are dynamically generated by `ANALYTICS.PLANNED_PURCHASE_ORDERS` (view) — they aggregate all at-risk demand for a given part into a single planned order. Key features:

- **Priority scoring**: Weighted composite — RUL urgency (40%), deficit severity (30%), competing assets (20%), stage criticality (10%).
- **Dual timing**: Standard arrival (full lead time) and expedite arrival (half lead time) with order-by deadlines for each.
- **Auto-conversion**: `DAG_CONVERT_PPOS` (child task in DAG) calls `AUTO_CONVERT_PLANNED_POS()` which converts overdue PPOs into actual POs with notification logging. Deduplication: checks `SOURCE = 'auto_planned'` to avoid duplicate auto-POs.
- **PPO status values**: `PLANNED`, `ORDER_SOON` (≤2 days to deadline), `REVIEW_AND_EXPEDITE`, `AUTO_CONVERTING` (deadline passed), `EXPEDITE_IMMEDIATELY` (critical shortage).

---

## 10. Automation & Scheduled Tasks

All automation runs as a single **Task DAG** (`MFGPULSE_AUTOMATION_DAG`) on `MFGPULSE_AUTOMATION_WH` (XS, 60s auto-suspend), monitored by `MFGPULSE_AUTOMATION_GUARD` (50 credits/month). The DAG ensures each step runs only after the previous completes with fresh data.

**DAG chain** (every 720 min):
```
MFGPULSE_AUTOMATION_DAG (root)     → Sensor + production data (persistent degradation)
    ↓ AFTER
DAG_REFRESH_FATIGUE                → Batch fatigue score computation (all assets)
    ↓ AFTER
DAG_REFRESH_DTS                    → Force refresh all 13 DTs in dependency order
    ↓ AFTER
DAG_GENERATE_WOS                   → Auto-create WOs for at-risk assets
    ↓ AFTER
DAG_GENERATE_POS                   → Auto-create POs for WOs needing parts
    ↓ AFTER
DAG_CONVERT_PPOS                   → Auto-convert overdue PPOs to actual POs
```

| Task | Type | Action | State |
|---|---|---|---|
| `MFGPULSE_AUTOMATION_DAG` | Root (720 min) | Calls `SIMULATE_ALL_FEEDS_RANDOM()` — unified sensor + production feed with persistent degradation, partial WO recovery, intermittent faults | SUSPENDED |
| `DAG_REFRESH_FATIGUE` | Child | Calls `REFRESH_FATIGUE_SCORES()` — batch-computes fatigue for all assets using latest feature DTs | RESUMED |
| `DAG_REFRESH_DTS` | Child | Calls `REFRESH_ALL_DTS()` — forces `ALTER DYNAMIC TABLE ... REFRESH` on all 13 DTs in dependency order (Layer 0→4) | RESUMED |
| `DAG_GENERATE_WOS` | Child | Calls `AUTO_GENERATE_WORK_ORDERS()` — creates WOs with notifications and procurement alerts | RESUMED |
| `DAG_GENERATE_POS` | Child | Calls `AUTO_GENERATE_PURCHASE_ORDERS()` — creates POs for at-risk assets | RESUMED |
| `DAG_CONVERT_PPOS` | Child | Calls `AUTO_CONVERT_PLANNED_POS()` — converts overdue PPOs to actual POs | RESUMED |

**To start the DAG**: Resume root task (`ALTER TASK ANALYTICS.MFGPULSE_AUTOMATION_DAG RESUME`). Children are already resumed and will fire automatically when the root completes.

---

## 11. Security

- All user-input SQL uses parameterized queries (`session.sql("CALL proc(:1, :2)", params=[val1, val2])`)
- No hardcoded secrets in any Python file (verified by security audit)
- Cortex Complete and DATA_AGENT_RUN use parameterized prompts
- Write operations (WO, PO, reservations) gated by persona role
- Admin panel restricted to PLANT_MANAGER and APP_ADMIN
- Notification email integration uses SYSTEM$SEND_SNOWFLAKE_NOTIFICATION (Snowflake-managed delivery)

---

## 12. Test Suite

62 test cases across 11 categories, runnable from Admin Panel or SQL worksheets.

| Category | Tests | Key Scenarios |
|---|---|---|
| TC-01: Data Integrity | 12 | Schemas, row counts, FKs, date ranges, DTs |
| TC-02: ML Pipeline | 10 | Predictions, value ranges, UDF smoke tests |
| TC-03: Procurement | 5 | ATP math, risk enums, supplier mappings |
| TC-04: Notifications | 3 | Event types, persona targeting, defaults |
| TC-05: WO/PO Lifecycle | 11 | Status transitions, completion dates, alerts, reservations |
| TC-06: Simulation | 4 | Healthy=0%, load reduction effects, CI ordering |
| TC-07: Copilot/Search | 2 | Asset coverage, Cortex Search accuracy benchmarks |
| TC-08: Persona Access | 5 | Page access matrix, admin restriction |
| TC-11: ML Edge Cases | 10 | UDF boundary inputs, nulls, zeros, extreme values |

Acceptance: >= 95% pass rate across all categories.

---

## 13. File Inventory

| Path | Purpose |
|---|---|
| `MFGPulse_AI_App/streamlit_app.py` | Main entry point — persona login, navigation, notification bell |
| `MFGPulse_AI_App/app_pages/*.py` | 8 Streamlit page modules (see Section 6) |
| `MFGPulse_AI_App/snowflake.yml` | Deployment manifest |
| `0 - Setup/scripts/deploy_one_time_consolidated.sql` | Master deployment script (14 checkpoints, all DDL + seed data) |
| `0 - Setup/scripts/*.sql` | Operational helper scripts (share, sync, emergency stop) |
| `0 - Setup/DEPLOYMENT_GUIDE.md` | Full deployment walkthrough + cross-instance instructions |
| `test_cases/test_*.sql` + `.py` | 9 test suite files (see Section 12) |
| `cortex_project/` | Cortex Agent + Semantic View YAML definitions |
| `docs/` | Technical Guide, User Guide, Process Flow, Architecture Diagram |

---

## 14. Quick Reference — Common Operations

| I want to... | Go to... | Action |
|---|---|---|
| See plant health at a glance | **Executive Dashboard** | Review KPI cards, OEE chart, OEE trend analysis, risk matrix |
| Track OEE trends over time | **Executive Dashboard** | Use OEE Trend Analysis chart, switch between OEE/Availability/Performance/Quality |
| Assess supply chain risk at a glance | **Executive Dashboard** | Review risk distribution donut, lead time gap chart, at-risk cost metric |
| Monitor live sensor data | **Operations Center** → Sensor feed | Select asset, time range, and channel. View latest KPIs and time-series chart |
| Investigate a specific asset | **Maintenance Hub** | Select asset, review Failure DNA + KPIs |
| Test intervention strategies | **Digital Twin** | Select asset, adjust sliders, compare 3 scenarios |
| Manage work orders | **WO/PO Console** | Filter, Start/Complete WOs |
| Approve/reject purchase orders | **WO/PO Console** | PO tab, Approve/Reject/Receive |
| Check parts availability | **Procurement** | View ATP, risk badges, create POs |
| Hand off to next shift | **Operations** → Shift handover | Review critical actions, procurement readiness |
| Ask a natural-language question | **Copilot** | Type or pick a suggestion pill |
| Run full 7-model diagnosis | **Copilot** | Ask "Run a full diagnosis on ASSET_XXX" |
| Configure notifications | **Admin Panel** → Notifications | Toggle email/in-app per event, set recipients |
| Monitor infrastructure costs | **Admin Panel** → FinOps | Credit KPIs, daily trend, query breakdown, storage, DT refresh |
| Run configurable simulation | **Admin Panel** → Simulation | Select asset, scenario, severity → generate sensor + production data |
| Manage users | **Admin Panel** → User management | Add, edit persona/email/line, activate/deactivate |
| Run test suite | **Admin Panel** → Test suite | Select category, click Run tests |
| Check data freshness | **Executive Dashboard** header badge | Auto-checked every DAG cycle; SLA breach fires DATA_STALE notification |
| Monitor model drift | **Admin Panel** → ML models (scroll down) | View FM/stage agreement KPIs, per-asset detail, drift warning banner |
| Review prediction accuracy | **Admin Panel** → ML models (scroll down) | Rolling 30-day accuracy from FEEDBACK_LOG, feedback entry detail |
| Compare KPIs over time | **Executive Dashboard** | KPI_SNAPSHOTS captured daily; OEE_PERIOD_COMPARISON for week-over-week |
| Refresh predictions manually | SQL worksheet | `ALTER DYNAMIC TABLE MFGPULSE_DB.ML_MODELS.LIVE_PREDICTIONS REFRESH` |
