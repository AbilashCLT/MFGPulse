# MFGPulse AI — Process Flow Documentation

> Complete business and technical workflow reference for the MFGPulse AI predictive maintenance platform.
>
> **Database:** `MFGPULSE_DB` | **Warehouse:** `MFGPULSE_AUTOMATION_WH` | **DAG Cycle:** Every 12 hours

---

## Table of Contents

1. [Data Ingestion & Simulation Flow](#1-data-ingestion--simulation-flow)
2. [Feature Engineering Pipeline](#2-feature-engineering-pipeline)
3. [Prediction & Classification Flow](#3-prediction--classification-flow)
4. [Alert Generation Flow](#4-alert-generation-flow)
5. [Work Order Lifecycle](#5-work-order-lifecycle)
6. [Procurement & Parts Flow](#6-procurement--parts-flow)
7. [Notification Dispatch Flow](#7-notification-dispatch-flow)
8. [Model Drift & Retraining Flow](#8-model-drift--retraining-flow)
9. [Shift Handover Flow](#9-shift-handover-flow)
10. [Digital Twin Simulation Flow](#10-digital-twin-simulation-flow)
11. [Copilot Conversational Flow](#11-copilot-conversational-flow)
12. [DAG Automation Flow](#12-dag-automation-flow)

---

## 1. Data Ingestion & Simulation Flow

Synthetic sensor data generation that models realistic asset degradation, repair recovery,
and stochastic failure scenarios across the entire asset fleet.

### Flow Diagram

```
┌─────────────────────────────┐
│  MFGPULSE_AUTOMATION_DAG    │
│  (every 12 hours)           │
└─────────────┬───────────────┘
              │
              ▼
┌─────────────────────────────────────────────────┐
│  SIMULATE_ALL_FEEDS_RANDOM()                    │
│                                                 │
│  FOR each asset IN ASSET_MASTER:                │
│  ┌────────────────────────────────────────────┐ │
│  │ 1. Read current degradation score          │ │
│  │    from LIVE_PREDICTIONS                   │ │
│  │                                            │ │
│  │ 2. Check WORK_ORDERS for WO completed      │ │
│  │    in last 13 hours                        │ │
│  │                                            │ │
│  │        ┌──── YES ────┐   ┌──── NO ────┐   │ │
│  │        ▼             │   ▼            │   │ │
│  │   Reset to CLEAN     │  Ratchet UP    │   │ │
│  │   severity = 30%     │  +0.01 to 0.06 │   │ │
│  │   of previous        │  cap at 0.95   │   │ │
│  │        │             │       │        │   │ │
│  │        └──────┬──────┘       │        │   │ │
│  │               ▼              │        │   │ │
│  │        10% random flicker    │        │   │ │
│  │        (temp improvement)    │        │   │ │
│  │               │              │        │   │ │
│  │               ▼              │        │   │ │
│  │   Assign failure scenario    │        │   │ │
│  │   by severity band:          │        │   │ │
│  │   Low  (<0.30): 80% CLEAN   │        │   │ │
│  │   Med  (0.30-0.60): mixed   │        │   │ │
│  │   High (>0.60): all fault   │        │   │ │
│  │               │              │        │   │ │
│  │               ▼              │        │   │ │
│  │   SIMULATE_SENSOR_FEED_     │        │   │ │
│  │   CONFIGURABLE(asset,       │        │   │ │
│  │   scenario, severity, 12h)  │        │   │ │
│  └────────────────────────────────────────────┘ │
│                                                 │
│  Log run to SIMULATION_CONFIG                   │
└─────────────────────────────────────────────────┘
              │
              ▼
┌─────────────────────────────┐
│  RAW_OT.SENSOR_READINGS     │
│  (new rows appended)        │
└─────────────────────────────┘
```

### Failure Scenarios

| Severity Band | CLEAN | BEARING_WEAR | THERMAL_DEGRADATION | MISALIGNMENT | IMBALANCE |
|---------------|-------|--------------|---------------------|--------------|-----------|
| Low (<0.30)   | 80%   | 10%          | —                   | —            | 10%       |
| Med (0.30–0.60) | 20% | 30%         | 25%                 | —            | 25%       |
| High (>0.60)  | —     | 30%          | 25%                 | 25%          | 20%       |

### Key Objects

| Object | Schema | Type | Role |
|--------|--------|------|------|
| `SIMULATE_ALL_FEEDS_RANDOM` | RAW_OT | Procedure | Root DAG entry — orchestrates all asset simulation |
| `SIMULATE_SENSOR_FEED_CONFIGURABLE` | RAW_OT | Procedure | Per-asset sensor signal generator |
| `SENSOR_READINGS` | RAW_OT | Table | Landing table for all sensor data |
| `ASSET_MASTER` | RAW_OT | Table | Asset registry (type, line, rated specs) |
| `LIVE_PREDICTIONS` | ML_MODELS | Dynamic Table | Current degradation state (feedback loop) |
| `WORK_ORDERS` | RAW_IT | Table | WO completion triggers severity reset |
| `SIMULATION_CONFIG` | RAW_IT | Table | Simulation run audit log |
| `SENSOR_READINGS_STREAM` | RAW_OT | Stream | Append-only CDC on new readings |

### Trigger

- **Mechanism:** DAG root task `MFGPULSE_AUTOMATION_DAG` (every 720 minutes / 12 hours)
- **Warehouse:** `MFGPULSE_AUTOMATION_WH`

### Persona Access

| Persona | Access |
|---------|--------|
| Data Engineer | Full control — manages simulation parameters, monitors pipeline |
| Plant Manager | Read-only — views freshness SLA dashboard |
| ML Engineer | Read-only — consumes raw data for feature development |

---

## 2. Feature Engineering Pipeline

Three-layer dynamic table cascade transforming raw sensor readings into 60+ ML-ready
features with automatic hourly refresh.

### Flow Diagram

```
                     RAW SOURCES
    ┌──────────────────┼──────────────────┐
    │                  │                  │
    ▼                  ▼                  ▼
SENSOR_READINGS   ASSET_MASTER      WORK_ORDERS
PRODUCTION_OUTPUT                   MAINTENANCE_LOGS
    │                  │                  │
    └──────────┬───────┘──────────┬───────┘
               │                  │
    ═══════════╪══════════════════╪═══════════════════
    LAYER 0    │  CURATED         │
    ═══════════╪══════════════════╪═══════════════════
               ▼                  ▼
    ┌──────────────────┐  ┌────────────────────┐
    │ SENSOR_WITH_     │  │ FAILURE_HISTORY    │
    │ CONTEXT          │  │                    │
    │ (readings +      │  │ (WOs + readings +  │
    │  asset + WOs)    │  │  logs + assets)    │
    └──────────────────┘  └────────────────────┘
    ┌──────────────────┐
    │ ASSET_HEALTH_    │
    │ CURRENT          │
    │ (latest per      │
    │  asset)          │
    └──────────────────┘

    ═══════════════════════════════════════════════════
    LAYER 1    ML_FEATURES (base features)
    ═══════════════════════════════════════════════════

    ┌─────────────┐  ┌─────────────┐  ┌──────────────┐
    │ ROLLING_    │  │ SENSOR_     │  │ PHYSICS_     │
    │ STATS       │  │ INTERACTIONS│  │ COMPOSITE    │
    │ (41 cols)   │  │ (7 cols)    │  │ (8 cols)     │
    │             │  │ INCREMENTAL │  │ INCREMENTAL  │
    │ 6h/24h     │  │             │  │              │
    │ windows    │  │ Cross-signal│  │ ISO 10816    │
    │ RMS, CoV,  │  │ correlations│  │ stress index │
    │ crest, Δ   │  │ & ratios    │  │ health score │
    └──────┬──────┘  └──────┬──────┘  └──────┬───────┘
           │                │                │
    ┌──────┴────────────────┴────────────────┴───────┐
    │              LABELED_DATA                      │
    │   (training labels: failure mode, RUL,         │
    │    degradation stage per asset-hour)            │
    └────────────────────────────────────────────────┘

    ═══════════════════════════════════════════════════
    LAYER 2    ML_FEATURES (advanced features)
    ═══════════════════════════════════════════════════

    ┌─────────────┐  ┌─────────────┐  ┌──────────────┐
    │ TEMPORAL_   │  │ FLEET_      │  │ CROSS_       │
    │ MEMORY      │  │ COMPARISON  │  │ DOMAIN       │
    │ (6 cols)    │  │ (5 cols)    │  │ (10 cols)    │
    │             │  │             │  │              │
    │ Degradation │  │ Z-scores vs │  │ Days since   │
    │ velocity    │  │ same-type   │  │ maintenance  │
    │ P-F interval│  │ fleet       │  │ Cumulative   │
    │ Trend       │  │ Percentile  │  │ cost & hours │
    │ reversals   │  │ rank        │  │ WO frequency │
    └──────┬──────┘  └──────┬──────┘  └──────┬───────┘
           │                │                │
           └────────────────┼────────────────┘
                            │
    ═══════════════════════════════════════════════════
    LAYER 3    ML_MODELS
    ═══════════════════════════════════════════════════
                            ▼
              ┌──────────────────────────┐
              │     LIVE_PREDICTIONS     │
              │  (17 output columns)     │
              │  All features + M1-M4    │
              │  model outputs merged    │
              └─────────────┬────────────┘
                            │
    ═══════════════════════════════════════════════════
    LAYER 4    ANALYTICS
    ═══════════════════════════════════════════════════
                            │
              ┌─────────────┼─────────────┐
              ▼             ▼             ▼
    ┌──────────────┐ ┌────────────┐ ┌──────────┐
    │ ACTIVE_      │ │ OEE_       │ │ Views:   │
    │ ALERTS       │ │ METRICS    │ │ COST_    │
    │ (24 cols)    │ │ (A×P×Q)    │ │ IMPACT   │
    │              │ │            │ │ EXEC_    │
    │ Severity +   │ │ Per-asset  │ │ SUMMARY  │
    │ escalation   │ │ per-shift  │ │ etc.     │
    └──────────────┘ └────────────┘ └──────────┘
```

### Feature Inventory (60+ features)

| Layer | Dynamic Table | Feature Count | Key Features | Refresh |
|-------|--------------|---------------|--------------|---------|
| 1 | `ROLLING_STATS` | 41 | 6h/24h mean, std, min, max, crest factor, peak-to-peak, RMS, CoV; rate-of-change; acceleration | FULL, 1hr |
| 1 | `SENSOR_INTERACTIONS` | 7 | XY correlation, vib-temp coupling, current/RPM ratio, axis dominance, acoustic/vib ratio | INCREMENTAL, 1hr |
| 1 | `PHYSICS_COMPOSITE` | 8 | Mechanical power, thermal efficiency, ISO 10816 severity, bearing defect indicator, stress index, composite health | INCREMENTAL, 1hr |
| 1 | `LABELED_DATA` | 5 | Failure mode label, hours-to-failure, degradation stage (0-4), severity, is_degrading | FULL, 1hr |
| 2 | `TEMPORAL_MEMORY` | 6 | Hours since breach, degradation velocity (30d), trend reversal count (7d), above-normal count (24h), 72h trend, degradation acceleration | FULL, 1hr |
| 2 | `FLEET_COMPARISON` | 5 | Vibration Z-score, temperature Z-score, percentile rank, ratio to fleet mean, worst-performer flag | FULL, 1hr |
| 2 | `CROSS_DOMAIN` | 10 | Days since maintenance, cumulative hours, historical failure count, maintenance effectiveness, temp/RPM deviation, workload intensity, WO frequency/1000h | FULL, 1hr |

### Key Objects

| Object | Schema | Type | Role |
|--------|--------|------|------|
| `ROLLING_STATS` | ML_FEATURES | Dynamic Table | Base statistical features (41 columns) |
| `SENSOR_INTERACTIONS` | ML_FEATURES | Dynamic Table | Cross-signal correlations (incremental) |
| `PHYSICS_COMPOSITE` | ML_FEATURES | Dynamic Table | Physics-informed features (incremental) |
| `TEMPORAL_MEMORY` | ML_FEATURES | Dynamic Table | Time-aware degradation tracking |
| `FLEET_COMPARISON` | ML_FEATURES | Dynamic Table | Peer-group benchmarking |
| `CROSS_DOMAIN` | ML_FEATURES | Dynamic Table | IT/OT convergence features |
| `LABELED_DATA` | ML_FEATURES | Dynamic Table | Supervised training labels |
| `ALL_DERIVED_FEATURES` | ML_FEATURES | View | Joins ROLLING_STATS + INTERACTIONS + PHYSICS (17 key features) |
| `FEATURE_CATALOG` | ML_FEATURES | View | 28-row metadata catalog documenting every feature |
| `SENSOR_WITH_CONTEXT` | CURATED | Dynamic Table | Readings enriched with asset metadata |
| `ASSET_HEALTH_CURRENT` | CURATED | Dynamic Table | Latest health snapshot per asset |
| `FAILURE_HISTORY` | CURATED | Dynamic Table | Historical failure records |

### Trigger

- **Mechanism:** Dynamic table auto-refresh (`target_lag = 1 hour`) — triggered automatically when upstream data changes
- **Manual override:** `REFRESH_ALL_DTS()` forces refresh of all 14 DTs in dependency order (Layer 0 → 1 → 2 → 3 → 4)

### Persona Access

| Persona | Access |
|---------|--------|
| ML Engineer | Full control — designs features, manages catalog, tunes refresh |
| Data Engineer | Full control — monitors DT health, manages incremental refresh |
| Data Scientist | Read-only — consumes features via training views |

---

## 3. Prediction & Classification Flow

Seven-model pipeline (M1–M7) combining physics-informed rules, statistical models,
Monte Carlo simulation, and LLM-powered reasoning for comprehensive asset diagnostics.

### Flow Diagram

```
         PREDICT_ALL(P_ASSET_ID)
         ┌──────────────────────────────────────┐
         │  Gather latest features from:        │
         │  • ROLLING_STATS                     │
         │  • SENSOR_INTERACTIONS               │
         │  • TEMPORAL_MEMORY                   │
         │  • PHYSICS_COMPOSITE                 │
         │  • FATIGUE_SCORES                    │
         └──────────────┬───────────────────────┘
                        │
         ┌──────────────┼──────────────────────────────┐
         │              ▼                              │
         │  ┌────────────────────────┐                 │
         │  │  M1: Failure Mode      │  SQL UDF        │
         │  │  PREDICT_FAILURE_MODE  │                 │
         │  │                        │                 │
         │  │  28 features →         │                 │
         │  │  Hierarchical rules:   │                 │
         │  │  • BEARING_WEAR        │                 │
         │  │  • THERMAL_DEGRADATION │                 │
         │  │  • MISALIGNMENT        │                 │
         │  │  • IMBALANCE           │                 │
         │  │  • NORMAL              │                 │
         │  │                        │                 │
         │  │  Output: mode +        │                 │
         │  │  confidence + per-     │                 │
         │  │  class probabilities   │                 │
         │  └───────────┬────────────┘                 │
         │              ▼                              │
         │  ┌────────────────────────┐                 │
         │  │  M2: RUL Estimator     │  SQL UDF        │
         │  │  PREDICT_RUL           │                 │
         │  │                        │                 │
         │  │  Formula:              │                 │
         │  │  (1 - fatigue) /       │                 │
         │  │  (deg_velocity / 24)   │                 │
         │  │                        │                 │
         │  │  Output: RUL hours     │                 │
         │  │  + confidence interval │                 │
         │  │  (lower/upper CI)      │                 │
         │  └───────────┬────────────┘                 │
         │              ▼                              │
         │  ┌────────────────────────┐                 │
         │  │  M3: Degradation Stage │  SQL UDF        │
         │  │  PREDICT_DEGRADATION_  │                 │
         │  │  STAGE                 │                 │
         │  │                        │                 │
         │  │  Maps to:              │                 │
         │  │  Healthy → Warning     │                 │
         │  │  → Critical            │                 │
         │  │                        │                 │
         │  │  Output: stage +       │                 │
         │  │  degradation_score +   │                 │
         │  │  transition_prob       │                 │
         │  └───────────┬────────────┘                 │
         │              ▼                              │
         │  ┌────────────────────────┐                 │
         │  │  M4: Hidden Fatigue    │  SQL UDF        │
         │  │  COMPUTE_FATIGUE_SCORE │                 │
         │  │                        │                 │
         │  │  6-component weighted: │                 │
         │  │  Impulsiveness    25%  │                 │
         │  │  Signal instab.  15%  │                 │
         │  │  Deg. accel.     20%  │                 │
         │  │  Energy ineffic. 15%  │                 │
         │  │  Axis corr shift 10%  │                 │
         │  │  Acoustic decoup 15%  │                 │
         │  │                        │                 │
         │  │  Output: 0-1 score     │                 │
         │  │  HEALTHY / ACCUMULATING│                 │
         │  │  / HIGH / CRITICAL     │                 │
         │  └───────────┬────────────┘                 │
         │              ▼                              │
         │  ┌────────────────────────┐                 │
         │  │  M5: Root Cause        │  LLM            │
         │  │  ANALYZE_ROOT_CAUSE    │  (Cortex)       │
         │  │                        │                 │
         │  │  Inputs: current       │                 │
         │  │  readings + M1-M4     │                 │
         │  │  outputs               │                 │
         │  │                        │                 │
         │  │  Output: root cause    │                 │
         │  │  analysis narrative    │                 │
         │  └───────────┬────────────┘                 │
         │              ▼                              │
         │  ┌────────────────────────┐                 │
         │  │  M6: Digital Twin      │  SQL UDF        │
         │  │  SIMULATE_FAILURE_TWIN │  (Monte Carlo)  │
         │  │                        │                 │
         │  │  100-run simulation:   │                 │
         │  │  • Failure prob @ 3/   │                 │
         │  │    7/14 days           │                 │
         │  │  • RUL P10/P50/P90    │                 │
         │  │  • Risk before maint.  │                 │
         │  │  • Expected cost       │                 │
         │  └───────────┬────────────┘                 │
         │              ▼                              │
         │  ┌────────────────────────┐                 │
         │  │  M7: Prescriptive AI   │  LLM            │
         │  │  PRESCRIBE_MAINTENANCE │  (llama3.1-70b) │
         │  │                        │                 │
         │  │  Context assembly:     │                 │
         │  │  • M1-M6 outputs       │                 │
         │  │  • Parts availability  │                 │
         │  │  • Repair vs failure   │                 │
         │  │    cost data           │                 │
         │  │                        │                 │
         │  │  Output JSON:          │                 │
         │  │  action, priority,     │                 │
         │  │  parts, optimal_window,│                 │
         │  │  cost_savings, risk    │                 │
         │  └───────────┬────────────┘                 │
         │              ▼                              │
         │  Assembled diagnostic JSON (all M1-M7)      │
         └─────────────────────────────────────────────┘
                        │
                        ▼
         ┌──────────────────────────┐
         │  ML_MODELS.              │
         │  LIVE_PREDICTIONS (DT)   │
         │  17 output columns       │
         │  auto-refresh 1 hour     │
         └──────────────────────────┘
```

### Model Summary

| Model | Name | Type | Method | Key Inputs | Key Outputs |
|-------|------|------|--------|------------|-------------|
| M1 | Failure Mode Classifier | `PREDICT_FAILURE_MODE` UDF | Physics-informed hierarchical rules | 28 features | Failure mode + confidence + 5 class probabilities |
| M2 | RUL Estimator | `PREDICT_RUL` UDF | Formula: `(1-fatigue) / (velocity/24)` | 8 features | RUL hours + lower/upper CI |
| M3 | Degradation Stage | `PREDICT_DEGRADATION_STAGE` UDF | Multi-signal thresholding | 7 features | Stage (Healthy/Warning/Critical) + transition probability |
| M4 | Hidden Fatigue | `COMPUTE_FATIGUE_SCORE` UDF | 6-component weighted formula | 9 features | Score 0–1 (Healthy/Accumulating/High/Critical) |
| M5 | Root Cause Analyzer | `ANALYZE_ROOT_CAUSE` Procedure | Cortex LLM reasoning | Readings + M1-M4 | Root cause narrative |
| M6 | Digital Twin | `SIMULATE_FAILURE_TWIN` UDF | 100-run Monte Carlo | vib, velocity, fatigue + what-if params | Failure prob, RUL distribution, cost |
| M7 | Prescriptive AI | `PRESCRIBE_MAINTENANCE` Procedure | Cortex LLM (llama3.1-70b) | All M1-M6 + parts + costs | Action plan, priority, optimal window, cost savings |

### Key Objects

| Object | Schema | Type | Role |
|--------|--------|------|------|
| `PREDICT_ALL` | ML_MODELS | Procedure | Master orchestrator — calls M1 through M7 in sequence |
| `PREDICT_FAILURE_MODE` | ML_MODELS | SQL UDF | M1 — physics-informed failure mode classifier |
| `PREDICT_RUL` | ML_MODELS | SQL UDF | M2 — remaining useful life estimator |
| `PREDICT_DEGRADATION_STAGE` | ML_MODELS | SQL UDF | M3 — degradation stage mapper |
| `COMPUTE_FATIGUE_SCORE` | ML_MODELS | SQL UDF | M4 — hidden fatigue detector |
| `ANALYZE_ROOT_CAUSE` | ML_MODELS | Procedure | M5 — LLM root cause analysis |
| `SIMULATE_FAILURE_TWIN` | ML_MODELS | SQL UDF | M6 — Monte Carlo digital twin |
| `PRESCRIBE_MAINTENANCE` | ML_MODELS | Procedure | M7 — LLM prescriptive maintenance |
| `ANOMALY_SCORER` | ML_MODELS | SQL UDF | Anomaly detection scoring |
| `LIVE_PREDICTIONS` | ML_MODELS | Dynamic Table | Consolidated prediction output (Layer 3) |
| `FATIGUE_SCORES` | ML_MODELS | Table | Time-series fatigue scores per asset |
| `MODEL_REGISTRY` | ML_MODELS | Table | Model versioning and metadata |

### Trigger

- **LIVE_PREDICTIONS DT:** Auto-refresh (`target_lag = 1 hour`) when upstream features change
- **REFRESH_FATIGUE_SCORES:** Called by DAG task `DAG_REFRESH_FATIGUE` before DT refresh
- **PREDICT_ALL:** Can be called on-demand per asset (e.g., from Copilot)

### Persona Access

| Persona | Access |
|---------|--------|
| ML Engineer | Full control — develops and registers models, monitors accuracy |
| Reliability Engineer | Read-only — consumes predictions, validates against domain knowledge |
| Plant Manager | Read-only — views prediction dashboards and alerts |
| Maintenance Technician | Read-only — receives prescriptive maintenance actions (M7) |

---

## 4. Alert Generation Flow

Automated severity classification and escalation based on prediction outputs, fatigue
scores, RUL thresholds, and work order history.

### Flow Diagram

```
┌──────────────────────────┐     ┌──────────────────────────┐
│  ML_MODELS.              │     │  RAW_IT.                 │
│  LIVE_PREDICTIONS        │     │  WORK_ORDERS             │
│                          │     │  (last 90 days)          │
└────────────┬─────────────┘     └────────────┬─────────────┘
             │                                │
             └────────────┬───────────────────┘
                          │
                          ▼
             ┌────────────────────────────────────┐
             │  ANALYTICS.ACTIVE_ALERTS (DT)      │
             │  target_lag = 1 hour               │
             │                                    │
             │  Severity Classification:          │
             │  ┌──────────────────────────────┐  │
             │  │                              │  │
             │  │  CRITICAL                    │  │
             │  │  stage = 'Critical'          │  │
             │  │  AND (RUL < 24h              │  │
             │  │       OR fatigue > 0.85)     │  │
             │  │          │                   │  │
             │  │  WARNING                     │  │
             │  │  stage = 'Critical'          │  │
             │  │  OR RUL < 72h                │  │
             │  │  OR fatigue > 0.7            │  │
             │  │          │                   │  │
             │  │  WATCH                       │  │
             │  │  stage = 'Warning'           │  │
             │  │  OR fatigue > 0.4            │  │
             │  │          │                   │  │
             │  │  INFO                        │  │
             │  │  fatigue > 0.2               │  │
             │  │  AND stage = 'Healthy'       │  │
             │  │  (hidden fatigue warning)    │  │
             │  │                              │  │
             │  └──────────────────────────────┘  │
             │                                    │
             │  Alert Types:                      │
             │  • FAILURE_PREDICTION              │
             │  • HIDDEN_FATIGUE                  │
             │  • LOW_RUL                         │
             │  • DEGRADATION                     │
             │                                    │
             │  Chronic Flag:                     │
             │  is_chronic = TRUE when            │
             │  >2 WOs in 90 days                 │
             │                                    │
             │  Auto-Escalation:                  │
             │  WARNING → 12hr escalation         │
             │  WATCH   → 24hr escalation         │
             │  CRITICAL → no further             │
             └─────────────┬──────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
     ┌──────────────┐ ┌────────┐ ┌──────────────┐
     │ ALERT_SUMMARY│ │ Shift  │ │ ARCHIVE_     │
     │ (view)       │ │ Handovr│ │ ALERTS()     │
     │              │ │        │ │ → ALERT_     │
     │ Aggregated   │ │        │ │   HISTORY    │
     │ counts &     │ │        │ │              │
     │ trends       │ │        │ │ Resolved →   │
     │              │ │        │ │ archive      │
     └──────────────┘ └────────┘ └──────────────┘
```

### Alert Message Template

```
"{asset_name}: {failure_mode} detected. RUL: {X}hrs. Fatigue: {Y}. Stage: {Z}.
 CHRONIC: {N} work orders in 90 days."
```

### Key Objects

| Object | Schema | Type | Role |
|--------|--------|------|------|
| `ACTIVE_ALERTS` | ANALYTICS | Dynamic Table | 24-column alert generation with severity/escalation |
| `ALERT_SUMMARY` | ANALYTICS | View | Aggregated alert counts and trends |
| `ALERT_HISTORY` | ANALYTICS | Table | Archived resolved alerts |
| `ARCHIVE_ALERTS` | ANALYTICS | Procedure | Moves resolved alerts to history |

### Trigger

- **Mechanism:** Dynamic table auto-refresh (`target_lag = 1 hour`)
- **Archive:** DAG task `DAG_ARCHIVE_ALERTS` runs after DT refresh

### Persona Access

| Persona | Access |
|---------|--------|
| Plant Manager | Primary consumer — alert dashboard, escalation review |
| Reliability Engineer | Reviews alert patterns, chronic asset identification |
| Maintenance Technician | Receives relevant alerts for assigned assets |
| Shift Supervisor | Shift handover alert summary |

---

## 5. Work Order Lifecycle

End-to-end workflow from anomaly detection through work order creation, technician
assignment, execution, completion, and feedback loop back into the simulation.

### Flow Diagram

```
┌──────────────┐     ┌──────────────┐
│ LIVE_        │     │ ACTIVE_      │
│ PREDICTIONS  │     │ ALERTS       │
└──────┬───────┘     └──────┬───────┘
       │                    │
       └────────┬───────────┘
                │
    ┌───────────┼───────────────┐
    │           ▼               │
    │  ┌─────────────────┐     │
    │  │ AUTO_GENERATE_  │     │  (DAG task)
    │  │ WORK_ORDERS()   │     │
    │  └────────┬────────┘     │
    │           │              │
    │           ▼              ▼
    │  ┌─────────────────────────────┐
    │  │ GENERATE_WORK_ORDER(        │  (manual or auto)
    │  │   asset_id,                 │
    │  │   priority,                 │
    │  │   action,                   │
    │  │   parts_needed,             │
    │  │   estimated_cost            │
    │  │ )                           │
    │  └─────────────┬───────────────┘
    │                │
    │     ┌──────────┼──────────┐
    │     │          │          │
    │     ▼          ▼          ▼
    │  Auto-gen   Find next   Check parts
    │  WO ID      technician  availability
    │  WO-AUTO-   from SHIFT_ in PARTS_
    │  YYYYMMDD-  SCHEDULE    INVENTORY
    │  HH24MISS   (by line)
    │     │          │          │
    │     └──────────┼──────────┘
    │                │
    │                ▼
    │  ┌─────────────────────────────┐
    │  │  WORK_ORDERS table          │
    │  │  Status: OPEN               │
    │  │  Type: EMERGENCY or         │
    │  │        CORRECTIVE           │
    │  └─────────────┬───────────────┘
    │                │
    │                ▼
    │  ┌─────────────────────────────┐
    │  │  Status: IN_PROGRESS        │
    │  │  (technician starts work)   │
    │  └─────────────┬───────────────┘
    │                │
    │                ▼
    │  ┌─────────────────────────────┐
    │  │  Status: COMPLETED          │
    │  │  (technician closes WO)     │
    │  └─────────────┬───────────────┘
    │                │
    │       ┌────────┼──────────┐
    │       ▼        ▼          ▼
    │  ┌─────────┐  ┌────────┐  ┌──────────────────┐
    │  │FEEDBACK │  │  WO    │  │ SIMULATION       │
    │  │_LOG     │  │ STREAM │  │ FEEDBACK LOOP    │
    │  │         │  │        │  │                  │
    │  │ LOG_    │  │ CDC    │  │ Next DAG cycle:  │
    │  │FEEDBACK │  │ capture│  │ severity resets  │
    │  │()       │  │        │  │ to 30% (CLEAN)   │
    │  └─────────┘  └────────┘  └──────────────────┘
    └────────────────────────────────────────────────┘
```

### Status Flow

```
    OPEN ──────► IN_PROGRESS ──────► COMPLETED
     │                                   │
     │  WO-AUTO-YYYYMMDD-HH24MISS      │
     │  assigned_to = next tech          │
     │  on asset's line                  ▼
     │                           Triggers severity
     │                           reset in next
     │                           simulation cycle
     └───────────────────────────────────┘
```

### Key Objects

| Object | Schema | Type | Role |
|--------|--------|------|------|
| `AUTO_GENERATE_WORK_ORDERS` | ANALYTICS | Procedure | Auto-creates WOs from predictions |
| `GENERATE_WORK_ORDER` | ANALYTICS | Procedure | Core WO creation with tech assignment |
| `WORK_ORDERS` | RAW_IT | Table | Work order master table |
| `WORK_ORDERS_STREAM` | RAW_IT | Stream | CDC on WO inserts/updates/deletes |
| `SHIFT_SCHEDULE` | RAW_IT | Table | Technician availability by line |
| `PARTS_INVENTORY` | RAW_IT | Table | Parts availability check |
| `FEEDBACK_LOG` | ML_MODELS | Table | Technician feedback on predictions |
| `LOG_FEEDBACK` | ML_MODELS | Procedure | Records prediction accuracy feedback |

### Trigger

- **Auto:** DAG task `DAG_GENERATE_WOS` (after DT refresh)
- **Manual:** Direct call to `GENERATE_WORK_ORDER()` from UI or Copilot

### Persona Access

| Persona | Access |
|---------|--------|
| Maintenance Technician | Primary — receives assignments, updates status, provides feedback |
| Shift Supervisor | Assigns and prioritizes work orders |
| Plant Manager | Reviews WO backlog and completion rates |
| Reliability Engineer | Analyzes WO patterns, validates prediction accuracy |

---

## 6. Procurement & Parts Flow

Risk-aware procurement pipeline from prediction-driven demand identification through
supplier selection, purchase order creation, planned PO auto-conversion, and parts reservation.

### Flow Diagram

```
┌────────────────────┐  ┌──────────────────┐  ┌─────────────────┐
│  LIVE_PREDICTIONS  │  │  PARTS_INVENTORY │  │  PART_SUPPLIERS  │
│  (failure modes,   │  │  (on_hand, lead  │  │  (preferred,     │
│   RUL, stage)      │  │   time, compat)  │  │   cost, lead)    │
└────────┬───────────┘  └────────┬─────────┘  └────────┬────────┘
         │                       │                      │
         └───────────────┬───────┘──────────────────────┘
                         │
                         ▼
         ┌───────────────────────────────────────┐
         │  PROCUREMENT_RECOMMENDATIONS (view)   │
         │  31 columns                           │
         │                                       │
         │  Risk Classification:                 │
         │  ┌─────────────────────────────────┐  │
         │  │ CRITICAL_SHORTAGE               │  │
         │  │   ATP=0 AND lead_time > RUL     │  │
         │  │          │                      │  │
         │  │ EXPEDITE                        │  │
         │  │   standard lead > RUL           │  │
         │  │   (but expedite may work)       │  │
         │  │          │                      │  │
         │  │ ORDER_NOW                       │  │
         │  │   ATP < safety stock            │  │
         │  │          │                      │  │
         │  │ REPLENISH_NOW                   │  │
         │  │   low stock, not urgent         │  │
         │  │          │                      │  │
         │  │ NO_RISK                         │  │
         │  │   sufficient stock + time       │  │
         │  └─────────────────────────────────┘  │
         │                                       │
         │  Actions: ESCALATE_CRITICAL_SHORTAGE  │
         │  → EXPEDITE_PO → CREATE_PO            │
         │  → RESERVE_AND_REORDER → MONITOR      │
         └───────────────┬───────────────────────┘
                         │
              ┌──────────┼──────────┐
              ▼          ▼          ▼
   ┌──────────────┐  ┌──────────────────────┐
   │ PLANNED_     │  │ AUTO_GENERATE_       │
   │ PURCHASE_    │  │ PURCHASE_ORDERS()    │
   │ ORDERS (view)│  │                      │
   │              │  │ For each actionable  │
   │ Aggregated   │  │ recommendation:      │
   │ demand by    │  │ RUL < 336h OR        │
   │ part with    │  │ Warning/Critical     │
   │ priority     │  └──────────┬───────────┘
   │ scoring:     │             │
   │ 40% RUL      │             ▼
   │ 30% deficit  │  ┌──────────────────────┐
   │ 20% competing│  │ GENERATE_PURCHASE_   │
   │ 10% critical │  │ ORDER()              │
   │              │  │                      │
   │ Auto-convert │  │ • Duplicate check    │
   │ deadline     │  │ • Preferred supplier │
   │ computed     │  │   → cheapest active  │
   └──────┬───────┘  │ • Procurement risk   │
          │          │   (RUL vs lead time) │
          │          │ • Insert PO + lines  │
          │          │ • Fire notification  │
          ▼          └──────────┬───────────┘
   ┌──────────────┐             │
   │ AUTO_CONVERT_│             ▼
   │ PLANNED_POS()│  ┌──────────────────────┐
   │              │  │ PURCHASE_ORDERS      │
   │ When auto-   │  │ PURCHASE_ORDER_LINES │
   │ convert      │  │                      │
   │ deadline     │  │ source: 'prediction' │
   │ reached:     │  │ or 'auto_planned'    │
   │ PPO → PO     │  └──────────────────────┘
   │              │             │
   │ Selects best │             ▼
   │ supplier     │  ┌──────────────────────┐
   └──────┬───────┘  │ RESERVE_PART_FOR_    │
          │          │ WORK_ORDER()         │
          │          │                      │
          └──────────┤ • Check ATP from     │
                     │   PARTS_AVAILABLE_   │
                     │   TO_PROMISE view    │
                     │ • Reject if          │
                     │   insufficient       │
                     │ • Create reservation │
                     │   in PART_           │
                     │   RESERVATIONS       │
                     └──────────────────────┘
```

### Key Objects

| Object | Schema | Type | Role |
|--------|--------|------|------|
| `PROCUREMENT_RECOMMENDATIONS` | ANALYTICS | View | 31-col risk assessment joining predictions + inventory |
| `PLANNED_PURCHASE_ORDERS` | ANALYTICS | View | Aggregated demand with priority scoring |
| `PARTS_AVAILABLE_TO_PROMISE` | ANALYTICS | View | ATP = on_hand - reserved + incoming POs |
| `PROACTIVE_REORDER` | ANALYTICS | View | Parts needing proactive reorder |
| `SUPPLIER_SCORECARD` | ANALYTICS | View | Multi-factor supplier scoring (delivery 40%, cost 30%, rejection 30%) |
| `AUTO_GENERATE_PURCHASE_ORDERS` | ANALYTICS | Procedure | Creates POs from actionable recommendations |
| `GENERATE_PURCHASE_ORDER` | ANALYTICS | Procedure | Core PO creation with supplier selection |
| `AUTO_CONVERT_PLANNED_POS` | ANALYTICS | Procedure | PPO → PO auto-conversion at deadline |
| `RESERVE_PART_FOR_WORK_ORDER` | ANALYTICS | Procedure | ATP check + reservation creation |
| `PARTS_INVENTORY` | RAW_IT | Table | Parts stock and compatibility |
| `PART_SUPPLIERS` | RAW_IT | Table | Supplier-part mapping with costs |
| `SUPPLIERS` | RAW_IT | Table | Supplier master data |
| `PURCHASE_ORDERS` | RAW_IT | Table | PO header records |
| `PURCHASE_ORDER_LINES` | RAW_IT | Table | PO line items with risk metadata |
| `PART_RESERVATIONS` | RAW_IT | Table | Part reservations for WOs |

### Trigger

- **PO Generation:** DAG task `DAG_GENERATE_POS` (after WO generation)
- **PPO Conversion:** DAG task `DAG_CONVERT_PPOS` (after PO generation)
- **Manual:** Direct call to `GENERATE_PURCHASE_ORDER()` or `RESERVE_PART_FOR_WORK_ORDER()`

### Persona Access

| Persona | Access |
|---------|--------|
| Procurement Manager | Primary — reviews recommendations, approves POs, manages suppliers |
| Plant Manager | Reviews procurement KPIs, cost impact |
| Maintenance Technician | Views parts availability for assigned WOs |
| Supply Chain Analyst | Analyzes supplier scorecard, lead time trends |

---

## 7. Notification Dispatch Flow

Centralized event-driven notification system routing alerts through in-app and email
channels based on configurable per-event-type settings and persona targeting.

### Flow Diagram

```
   Any System Event (e.g., PO_CREATED)
                │
                ▼
   ┌─────────────────────────────────────────┐
   │  LOG_APP_NOTIFICATION(                  │
   │    event_type,                          │
   │    title,                               │
   │    message,                             │
   │    entity_id                            │
   │  )                                      │
   └─────────────────┬───────────────────────┘
                     │
                     ▼
   ┌─────────────────────────────────────────┐
   │  Read NOTIFICATION_SETTINGS             │
   │  for event_type                         │
   │                                         │
   │  Fields:                                │
   │  • email_enabled (BOOLEAN)              │
   │  • in_app_enabled (BOOLEAN)             │
   │  • email_recipients (CSV)               │
   │  • notify_personas (CSV)                │
   │  • priority (STRING)                    │
   └─────────┬───────────────┬───────────────┘
             │               │
    ┌────────┘               └────────┐
    ▼                                 ▼
   IN-APP PATH                    EMAIL PATH
    │                                 │
    ▼                                 ▼
┌───────────────────┐   ┌────────────────────────┐
│ For each persona  │   │ IF email_enabled:      │
│ in notify_personas│   │                        │
│ (SPLIT_TO_TABLE): │   │ Build HTML email body  │
│                   │   │ <div style=            │
│ INSERT into       │   │  "font-family:         │
│ APP_NOTIFICATIONS │   │   sans-serif">         │
│                   │   │                        │
│ • notif_id (UUID) │   │ SEND_MFGPULSE_EMAIL(  │
│ • persona_target  │   │   subject,             │
│ • priority        │   │   body_html,           │
│ • is_read = FALSE │   │   recipients           │
│ • created_at      │   │ )                      │
└───────────────────┘   └───────────┬────────────┘
                                    │
                                    ▼
                        ┌────────────────────────┐
                        │ SYSTEM$SEND_SNOWFLAKE_ │
                        │ NOTIFICATION           │
                        │                        │
                        │ Integration:           │
                        │ MFGPULSE_EMAIL         │
                        │ (outbound email)       │
                        │                        │
                        │ Splits comma-separated │
                        │ recipients into        │
                        │ individual sends       │
                        └────────────────────────┘
```

### Known Event Types

| Event Type | Triggered By | Typical Personas |
|------------|-------------|------------------|
| `PO_CREATED` | `GENERATE_PURCHASE_ORDER`, `AUTO_CONVERT_PLANNED_POS` | Procurement Manager, Plant Manager |

### Key Objects

| Object | Schema | Type | Role |
|--------|--------|------|------|
| `LOG_APP_NOTIFICATION` | RAW_IT | Procedure | Central notification dispatcher |
| `SEND_MFGPULSE_EMAIL` | RAW_IT | Procedure | Email sender via Snowflake notification |
| `NOTIFICATION_SETTINGS` | RAW_IT | Table | Per-event-type routing configuration |
| `APP_NOTIFICATIONS` | RAW_IT | Table | In-app notification inbox |
| `MFGPULSE_EMAIL` | — | Notification Integration | Outbound email integration |

### Trigger

- **Mechanism:** Called programmatically by any procedure that generates a notable event
- **Currently wired:** PO creation (both manual and auto-converted)

### Persona Access

| Persona | Access |
|---------|--------|
| App Admin | Manages notification settings, configures routing rules |
| All Personas | Receive notifications based on `notify_personas` configuration |

---

## 8. Model Drift & Retraining Flow

Continuous comparison of rule-based predictions against native ML models to detect
drift, with accuracy tracking from technician feedback and automated retraining triggers.

### Flow Diagram

```
   ┌────────────────────────────┐
   │  DAG_CHECK_DRIFT           │
   │  (after DT refresh)        │
   └──────────────┬─────────────┘
                  │
                  ▼
   ┌────────────────────────────┐
   │  COMPUTE_NATIVE_           │
   │  PREDICTIONS()             │
   │                            │
   │  Run native ML models      │
   │  on same inputs as         │
   │  rule-based UDFs           │
   └──────────────┬─────────────┘
                  │
                  ▼
   ┌────────────────────────────┐
   │  DRIFT_COMPARISON table    │
   │                            │
   │  Per asset:                │
   │  • rule_failure_mode       │
   │  • native_failure_mode     │
   │  • rule_stage              │
   │  • native_stage            │
   │  • rule_rul                │
   │  • native_rul              │
   │  • compared_at             │
   └──────────────┬─────────────┘
                  │
                  ▼
   ┌────────────────────────────┐     ┌────────────────────────┐
   │  DRIFT_METRICS (view)     │     │  MODEL_ACCURACY_LIVE   │
   │                            │     │  (view)                │
   │  Aggregates:               │     │                        │
   │  • FM agreement %          │     │  From FEEDBACK_LOG:    │
   │  • Stage agreement %       │     │  • FM accuracy %       │
   │  • All disagreements       │     │  • Stage accuracy %    │
   │    with details            │     │  • False alarm rate %  │
   │                            │     │  • Last 30 days        │
   └──────────────┬─────────────┘     └────────────┬───────────┘
                  │                                │
                  └────────────┬───────────────────┘
                               │
                               ▼
                  ┌────────────────────────────┐
                  │  RETRAIN_IF_NEEDED()       │
                  │                            │
                  │  Checks:                   │
                  │  • Drift exceeds threshold │
                  │  • Accuracy below target   │
                  │  • Sufficient feedback      │
                  │    volume                   │
                  │                            │
                  │  Actions:                  │
                  │  • Retrain models           │
                  │  • Update MODEL_REGISTRY    │
                  │  • Log new version          │
                  └────────────────────────────┘
```

### Feedback Loop

```
   Technician completes WO
            │
            ▼
   LOG_FEEDBACK(wo_id, asset_id, root_cause, confirmed_by)
            │
            ▼
   FEEDBACK_LOG table
            │
            ▼
   MODEL_ACCURACY_LIVE view (30-day rolling accuracy)
            │
            ▼
   Feeds into RETRAIN_IF_NEEDED() decision
```

### Key Objects

| Object | Schema | Type | Role |
|--------|--------|------|------|
| `COMPUTE_NATIVE_PREDICTIONS` | ML_MODELS | Procedure | Runs native ML for drift comparison |
| `DRIFT_COMPARISON` | ML_MODELS | Table | Side-by-side rule vs native predictions |
| `DRIFT_METRICS` | ML_MODELS | Secure View | Aggregated agreement/disagreement metrics |
| `MODEL_ACCURACY_LIVE` | ML_MODELS | View | 30-day rolling accuracy from feedback |
| `FEEDBACK_LOG` | ML_MODELS | Table | Technician prediction accuracy feedback |
| `MODEL_REGISTRY` | ML_MODELS | Table | Model version history |
| `RETRAIN_IF_NEEDED` | ML_MODELS | Procedure | Automated retraining trigger |
| `LOG_FEEDBACK` | ML_MODELS | Procedure | Records technician feedback |

### Trigger

- **Drift check:** DAG task `DAG_CHECK_DRIFT` (runs in parallel with alert archive and WO generation)
- **Feedback:** Manual — technician calls `LOG_FEEDBACK()` after WO completion
- **Retrain:** Automated when drift or accuracy thresholds are breached

### Persona Access

| Persona | Access |
|---------|--------|
| ML Engineer | Full control — monitors drift, triggers retraining, manages registry |
| Reliability Engineer | Reviews drift metrics, validates model alignment |
| Maintenance Technician | Provides feedback via `LOG_FEEDBACK()` |

---

## 9. Shift Handover Flow

Automated aggregation of critical KPIs, active alerts, cost impact, and plant OEE into
a structured handover report for shift transitions.

### Flow Diagram

```
   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐
   │ LIVE_        │  │ ACTIVE_      │  │ WORK_ORDERS  │
   │ PREDICTIONS  │  │ ALERTS       │  │              │
   └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
          │                 │                  │
   ┌──────┴───────┐  ┌──────┴───────┐  ┌──────┴───────┐
   │ PRODUCTION_  │  │ OEE_METRICS  │  │ COST_IMPACT  │
   │ OUTPUT       │  │              │  │              │
   └──────┬───────┘  └──────┬───────┘  └──────┬───────┘
          │                 │                  │
          └─────────────────┼──────────────────┘
                            │
                            ▼
           ┌────────────────────────────────────┐
           │  SHIFT_HANDOVER_VIEW               │
           │                                    │
           │  Aggregates:                       │
           │  • Critical actions                │
           │    (Critical + RUL < 72h)          │
           │    with asset details              │
           │  • Warning count                   │
           │  • Plant OEE breakdown             │
           │    (Availability × Performance     │
           │     × Quality)                     │
           │  • Alert counts (urgent + total)   │
           │  • Cost impact                     │
           │    (avoided, prevented, ROI)       │
           └─────────────────┬──────────────────┘
                             │
                             ▼
           ┌────────────────────────────────────┐
           │  GENERATE_SHIFT_HANDOVER_SUMMARY() │
           │                                    │
           │  • Pulls from SHIFT_HANDOVER_VIEW  │
           │  • Formats structured report       │
           │  • Optionally: LLM narrative       │
           │    summary generation              │
           │  • Stores in SHIFT_HANDOVER_       │
           │    HISTORY                         │
           └─────────────────┬──────────────────┘
                             │
                             ▼
           ┌────────────────────────────────────┐
           │  SHIFT_HANDOVER_HISTORY            │
           │  (historical handover records)     │
           └────────────────────────────────────┘
```

### Key Objects

| Object | Schema | Type | Role |
|--------|--------|------|------|
| `SHIFT_HANDOVER_VIEW` | ANALYTICS | View | Aggregated KPIs for current shift |
| `GENERATE_SHIFT_HANDOVER_SUMMARY` | ANALYTICS | Procedure | Generates formal handover report |
| `SHIFT_HANDOVER_HISTORY` | ANALYTICS | Table | Historical handover archive |
| `OEE_METRICS` | ANALYTICS | Dynamic Table | OEE = Availability × Performance × Quality |
| `COST_IMPACT` | ANALYTICS | View | ROI and cost avoidance metrics |
| `EXECUTIVE_SUMMARY` | ANALYTICS | View | Plant-wide dashboard metrics |

### Trigger

- **Mechanism:** Manual or scheduled at shift boundaries
- **DAG task:** `DAG_SNAPSHOT_KPIS` captures KPI state at end of DAG cycle

### Persona Access

| Persona | Access |
|---------|--------|
| Shift Supervisor | Primary — creates and reviews handover reports |
| Plant Manager | Reviews handover trends, plant performance |
| Incoming Shift Operator | Receives handover report at shift start |

---

## 10. Digital Twin Simulation Flow

Monte Carlo simulation engine modeling stochastic asset degradation with what-if
scenario analysis for maintenance planning and cost optimization.

### Flow Diagram

```
   ┌─────────────────────────────────────────────┐
   │  Input Parameters                           │
   │                                             │
   │  Required:                                  │
   │  • current_vib_mag (current vibration)      │
   │  • degradation_velocity (mm/s/day)          │
   │  • fatigue_score (0-1)                      │
   │                                             │
   │  What-If Levers:                            │
   │  • load_reduction_pct (0-100%)              │
   │  • maintenance_delay_days (0+)              │
   │  • rpm_adjustment_pct (-50% to +50%)        │
   └───────────────────────┬─────────────────────┘
                           │
                           ▼
   ┌─────────────────────────────────────────────┐
   │  SIMULATE_FAILURE_TWIN() — SQL UDF          │
   │                                             │
   │  ┌───────────────────────────────────────┐  │
   │  │  Apply what-if adjustments:           │  │
   │  │  • Load: 60% effect on deg. rate      │  │
   │  │  • RPM: 30% effect on deg. rate       │  │
   │  └───────────────────────────────────────┘  │
   │                                             │
   │  FOR sim = 1 TO 100:                        │
   │  ┌───────────────────────────────────────┐  │
   │  │  random_rate = 0.5x to 2.0x           │  │
   │  │                                       │  │
   │  │  FOR day = 1 TO 14:                   │  │
   │  │    fatigue += deg_velocity ×           │  │
   │  │              random_rate / 24          │  │
   │  │                                       │  │
   │  │    IF random() < shock_prob:           │  │
   │  │      fatigue += random(0.05, 0.15)    │  │
   │  │      (shock_prob: 5%→50% over time)   │  │
   │  │                                       │  │
   │  │    Record fatigue @ day 3, 7, 14      │  │
   │  │    Record if fatigue > 0.85 (failed)  │  │
   │  └───────────────────────────────────────┘  │
   │                                             │
   │  Aggregate 100 runs:                        │
   │  • failure_prob @ day 3 / 7 / 14           │
   │  • RUL percentiles: P10, P50, P90          │
   │  • fails_before_maintenance %               │
   │  • recommended_intervention urgency         │
   │  • expected_cost =                          │
   │      $520 (repair) + $12,000 × fail_prob   │
   └───────────────────────┬─────────────────────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
     ┌──────────────┐  ┌────────┐  ┌──────────────┐
     │  M6 output   │  │ What-if│  │ Cost impact  │
     │  in          │  │ UI     │  │ analysis     │
     │  PREDICT_ALL │  │ slider │  │              │
     │  pipeline    │  │ compare│  │ Repair vs    │
     │              │  │        │  │ failure cost │
     └──────────────┘  └────────┘  └──────────────┘
```

### Key Objects

| Object | Schema | Type | Role |
|--------|--------|------|------|
| `SIMULATE_FAILURE_TWIN` | ML_MODELS | SQL UDF | 100-run Monte Carlo simulation engine |
| `PREDICT_ALL` | ML_MODELS | Procedure | Invokes M6 as part of full diagnostic pipeline |
| `COST_IMPACT` | ANALYTICS | View | Cost avoidance and ROI calculations |
| `COST_IMPACT_BY_ASSET` | ANALYTICS | View | Per-asset cost analysis |
| `ASSET_COST_PROFILES` | ANALYTICS | Table | Per-asset emergency failure and planned repair base costs |

### Trigger

- **Pipeline:** Automatically invoked as M6 within `PREDICT_ALL(asset_id)`
- **Interactive:** Can be called standalone with what-if parameters from Copilot or UI

### Persona Access

| Persona | Access |
|---------|--------|
| Reliability Engineer | Primary — runs what-if scenarios for maintenance planning |
| Plant Manager | Reviews cost impact projections |
| ML Engineer | Validates simulation accuracy against actuals |

---

## 11. Copilot Conversational Flow

Natural language interface routing user queries through the 7-model pipeline and
Cortex LLM reasoning for conversational asset diagnostics and maintenance planning.

### Flow Diagram

```
   ┌─────────────────────────────┐
   │  User Query                 │
   │  (natural language)         │
   │                             │
   │  "What's wrong with        │
   │   ASSET_003?"              │
   │  "When will pump 5 fail?"  │
   │  "What if we reduce load   │
   │   by 20%?"                 │
   └──────────────┬──────────────┘
                  │
                  ▼
   ┌─────────────────────────────┐
   │  Cortex Agent (AGENT schema)│
   │                             │
   │  Tool Routing:              │
   │  ┌───────────────────────┐  │
   │  │ Asset diagnostics     │  │
   │  │ → PREDICT_ALL()       │  │
   │  │                       │  │
   │  │ What-if scenarios     │  │
   │  │ → SIMULATE_FAILURE_   │  │
   │  │   TWIN()              │  │
   │  │                       │  │
   │  │ Work order actions    │  │
   │  │ → GENERATE_WORK_      │  │
   │  │   ORDER()             │  │
   │  │                       │  │
   │  │ Parts lookup          │  │
   │  │ → PROCUREMENT_        │  │
   │  │   RECOMMENDATIONS     │  │
   │  │                       │  │
   │  │ Fleet overview        │  │
   │  │ → EXECUTIVE_SUMMARY   │  │
   │  │                       │  │
   │  │ Feedback              │  │
   │  │ → LOG_FEEDBACK()      │  │
   │  └───────────────────────┘  │
   └──────────────┬──────────────┘
                  │
                  ▼
   ┌─────────────────────────────┐
   │  Execution                  │
   │                             │
   │  • M5 (Root Cause) and M7  │
   │    (Prescriptive) use      │
   │    Cortex LLM              │
   │    (llama3.1-70b) for      │
   │    natural language         │
   │    reasoning                │
   │                             │
   │  • Structured JSON output   │
   │    from M1-M7 assembled    │
   │    into conversational      │
   │    response                 │
   └──────────────┬──────────────┘
                  │
                  ▼
   ┌─────────────────────────────┐
   │  Response to User           │
   │                             │
   │  "ASSET_003 shows bearing  │
   │   wear (87% confidence).   │
   │   RUL: 156 hours.          │
   │   Recommended: Schedule    │
   │   bearing replacement      │
   │   within 5 days.           │
   │   Parts available: YES     │
   │   Est. cost: $1,200        │
   │   Cost if delayed: $12,500"│
   └─────────────────────────────┘
```

### Key Objects

| Object | Schema | Type | Role |
|--------|--------|------|------|
| `AGENT` | — | Schema | Cortex Agent deployment schema |
| `PREDICT_ALL` | ML_MODELS | Procedure | Full M1-M7 diagnostic pipeline |
| `ANALYZE_ROOT_CAUSE` | ML_MODELS | Procedure | M5 — LLM root cause (Cortex) |
| `PRESCRIBE_MAINTENANCE` | ML_MODELS | Procedure | M7 — LLM prescription (llama3.1-70b) |
| `EXECUTIVE_SUMMARY` | ANALYTICS | View | Plant-wide summary for fleet queries |
| `PROCUREMENT_RECOMMENDATIONS` | ANALYTICS | View | Parts availability for action queries |

### Trigger

- **Mechanism:** User-initiated via conversational UI (Streamlit or Cortex Agent)
- **Backend:** Cortex LLM calls via `SNOWFLAKE.CORTEX.COMPLETE()`

### Persona Access

| Persona | Access |
|---------|--------|
| Maintenance Technician | Primary — asks about assigned assets, gets prescriptive actions |
| Plant Manager | Fleet overview, cost projections, what-if scenarios |
| Reliability Engineer | Deep diagnostics, root cause validation |
| Shift Supervisor | Quick status checks during shift operations |

---

## 12. DAG Automation Flow

Complete 10-task dependency chain orchestrating the entire MFGPulse automation cycle
from data simulation through KPI snapshots on a 12-hour schedule.

### Dependency Diagram

```
   ┌─────────────────────────────────────────────────────────────┐
   │  MFGPULSE_AUTOMATION_DAG                                   │
   │  Schedule: EVERY 720 MINUTES (12 hours)                    │
   │  Warehouse: MFGPULSE_AUTOMATION_WH                         │
   │  Status: SUSPENDED                                         │
   └─────────────────────────┬───────────────────────────────────┘
                             │
                             │  CALL RAW_OT.SIMULATE_ALL_FEEDS_RANDOM()
                             │
               ┌─────────────┼─────────────────┐
               │             │                 │
               ▼             │                 ▼
   ┌───────────────────┐     │     ┌───────────────────────┐
   │ T2: DAG_CHECK_    │     │     │ T3: DAG_REFRESH_      │
   │ FRESHNESS         │     │     │ FATIGUE               │
   │                   │     │     │                       │
   │ CHECK_DATA_       │     │     │ REFRESH_FATIGUE_      │
   │ FRESHNESS()       │     │     │ SCORES()              │
   │                   │     │     │                       │
   │ (parallel)        │     │     │ Computes new fatigue  │
   └───────────────────┘     │     │ for recent readings   │
                             │     └───────────┬───────────┘
                             │                 │
                             │                 ▼
                             │     ┌───────────────────────┐
                             │     │ T4: DAG_REFRESH_DTS   │
                             │     │                       │
                             │     │ REFRESH_ALL_DTS()     │
                             │     │                       │
                             │     │ Forces refresh of     │
                             │     │ all 14 dynamic tables │
                             │     │ in dependency order:  │
                             │     │ L0 → L1 → L2 → L3 → L4│
                             │     └───────────┬───────────┘
                             │                 │
                             │     ┌───────────┼───────────────┐
                             │     │           │               │
                             │     ▼           ▼               ▼
                             │ ┌─────────┐ ┌─────────┐ ┌──────────────┐
                             │ │T5: DAG_ │ │T6: DAG_ │ │T7: DAG_      │
                             │ │ARCHIVE_ │ │CHECK_   │ │GENERATE_WOS  │
                             │ │ALERTS   │ │DRIFT    │ │              │
                             │ │         │ │         │ │AUTO_GENERATE_│
                             │ │ARCHIVE_ │ │COMPUTE_ │ │WORK_ORDERS() │
                             │ │ALERTS() │ │NATIVE_  │ │              │
                             │ │         │ │PREDICT..│ │              │
                             │ │(parallel│ │         │ │(sequential)  │
                             │ │ leaf)   │ │(parallel│ │              │
                             │ │         │ │ leaf)   │ │              │
                             │ └─────────┘ └─────────┘ └──────┬───────┘
                             │                                │
                             │                                ▼
                             │                     ┌──────────────────┐
                             │                     │T8: DAG_GENERATE_ │
                             │                     │POS               │
                             │                     │                  │
                             │                     │AUTO_GENERATE_    │
                             │                     │PURCHASE_ORDERS() │
                             │                     └────────┬─────────┘
                             │                              │
                             │                              ▼
                             │                     ┌──────────────────┐
                             │                     │T9: DAG_CONVERT_  │
                             │                     │PPOS              │
                             │                     │                  │
                             │                     │AUTO_CONVERT_     │
                             │                     │PLANNED_POS()     │
                             │                     └────────┬─────────┘
                             │                              │
                             │                              ▼
                             │                     ┌──────────────────┐
                             │                     │T10: DAG_SNAPSHOT_│
                             │                     │KPIS              │
                             │                     │                  │
                             │                     │SNAPSHOT_KPIS()   │
                             │                     │(terminal task)   │
                             │                     └──────────────────┘
                             │
   ══════════════════════════╪═══════════════════════════════════
   EXECUTION TIMELINE        │
   ══════════════════════════╪═══════════════════════════════════
                             │
   Phase 1: Data Generation  │  T1 (root)
   Phase 2: Feature Prep     │  T2 ∥ T3 (parallel)
   Phase 3: Pipeline Refresh │  T4 (sequential after T3)
   Phase 4: Business Logic   │  T5 ∥ T6 ∥ T7 (parallel after T4)
   Phase 5: Procurement      │  T8 → T9 (sequential after T7)
   Phase 6: Snapshot         │  T10 (terminal after T9)
```

### Task Summary

| # | Task Name | Procedure Called | Predecessor | Parallelism |
|---|-----------|-----------------|-------------|-------------|
| T1 | `MFGPULSE_AUTOMATION_DAG` | `SIMULATE_ALL_FEEDS_RANDOM()` | — (root, scheduled) | — |
| T2 | `DAG_CHECK_FRESHNESS` | `CHECK_DATA_FRESHNESS()` | T1 | Parallel with T3 |
| T3 | `DAG_REFRESH_FATIGUE` | `REFRESH_FATIGUE_SCORES()` | T1 | Parallel with T2 |
| T4 | `DAG_REFRESH_DTS` | `REFRESH_ALL_DTS()` | T3 | Sequential |
| T5 | `DAG_ARCHIVE_ALERTS` | `ARCHIVE_ALERTS()` | T4 | Parallel with T6, T7 |
| T6 | `DAG_CHECK_DRIFT` | `COMPUTE_NATIVE_PREDICTIONS()` | T4 | Parallel with T5, T7 |
| T7 | `DAG_GENERATE_WOS` | `AUTO_GENERATE_WORK_ORDERS()` | T4 | Parallel with T5, T6 |
| T8 | `DAG_GENERATE_POS` | `AUTO_GENERATE_PURCHASE_ORDERS()` | T7 | Sequential |
| T9 | `DAG_CONVERT_PPOS` | `AUTO_CONVERT_PLANNED_POS()` | T8 | Sequential |
| T10 | `DAG_SNAPSHOT_KPIS` | `SNAPSHOT_KPIS()` | T9 | Terminal |

### Key Objects

| Object | Schema | Type | Role |
|--------|--------|------|------|
| `MFGPULSE_AUTOMATION_DAG` | ANALYTICS | Task (root) | DAG entry point, 12-hour schedule |
| `DAG_CHECK_FRESHNESS` | ANALYTICS | Task | Data freshness SLA validation |
| `DAG_REFRESH_FATIGUE` | ANALYTICS | Task | Fatigue score computation |
| `DAG_REFRESH_DTS` | ANALYTICS | Task | Forces all 14 DT refreshes in order |
| `DAG_ARCHIVE_ALERTS` | ANALYTICS | Task | Alert lifecycle management |
| `DAG_CHECK_DRIFT` | ANALYTICS | Task | Model drift detection |
| `DAG_GENERATE_WOS` | ANALYTICS | Task | Automated work order creation |
| `DAG_GENERATE_POS` | ANALYTICS | Task | Automated purchase order creation |
| `DAG_CONVERT_PPOS` | ANALYTICS | Task | Planned PO auto-conversion |
| `DAG_SNAPSHOT_KPIS` | ANALYTICS | Task | KPI snapshot capture |
| `MFGPULSE_AUTOMATION_WH` | — | Warehouse | X-Small Gen2, auto-suspend 60s |
| `MFGPULSE_AUTOMATION_GUARD` | — | Resource Monitor | Budget protection for DAG execution |

### Trigger

- **Mechanism:** Scheduled — every 720 minutes (12 hours)
- **Current status:** SUSPENDED (user-suspended)
- **Resume:** `ALTER TASK MFGPULSE_AUTOMATION_DAG RESUME;`

### Persona Access

| Persona | Access |
|---------|--------|
| Data Engineer | Full control — manages DAG schedule, monitors execution, resumes/suspends |
| App Admin | Manages warehouse and resource monitor settings |
| Plant Manager | Views DAG execution status and pipeline health |

---

## Appendix: Schema Map

```
MFGPULSE_DB
├── RAW_OT ─────── Sensor readings, asset master, ambient, metadata
│                   Streams: SENSOR_READINGS_STREAM
│                   Procedures: SIMULATE_ALL_FEEDS_RANDOM,
│                               SIMULATE_SENSOR_FEED_CONFIGURABLE,
│                               GENERATE_SENSOR_DATA
│
├── RAW_IT ─────── Work orders, parts, suppliers, POs, shifts,
│                   notifications, users
│                   Streams: WORK_ORDERS_STREAM, MAINTENANCE_LOGS_STREAM
│                   Procedures: LOG_APP_NOTIFICATION,
│                               SEND_MFGPULSE_EMAIL
│
├── CURATED ────── 3 dynamic tables (Layer 0)
│                   SENSOR_WITH_CONTEXT, ASSET_HEALTH_CURRENT,
│                   FAILURE_HISTORY
│
├── ML_FEATURES ── 7 dynamic tables (Layers 1-2) + training views
│                   + FEATURE_CATALOG
│
├── ML_MODELS ──── LIVE_PREDICTIONS (DT, Layer 3)
│                   7 model UDFs/procedures (M1-M7)
│                   FATIGUE_SCORES, DRIFT_COMPARISON,
│                   FEEDBACK_LOG, MODEL_REGISTRY
│
├── ANALYTICS ──── ACTIVE_ALERTS, OEE_METRICS (DTs, Layer 4)
│                   15 business views
│                   11 procedures (WO, PO, PPO, alerts, KPI)
│                   10 DAG tasks
│
├── AGENT ─────── Cortex Agent (conversational AI)
│
└── PUBLIC ─────── DEPLOYMENT_LOG
```
