# MFGPULSE_AUTOMATION_DAG — Full Execution Chain

## Overview

`MFGPULSE_AUTOMATION_DAG` is the root task of a 6-step sequential task DAG that drives the entire MFGPulse AI plant simulation and operations lifecycle. A single trigger takes the system from raw synthetic sensor data through feature engineering, ML predictions, alert generation, work order creation, and purchase order management — a complete plant operations cycle in one automated run.

```
MFGPULSE_AUTOMATION_DAG (root, 720 min)
  └─→ DAG_REFRESH_FATIGUE
        └─→ DAG_REFRESH_DTS
              └─→ DAG_GENERATE_WOS
                    └─→ DAG_GENERATE_POS
                          └─→ DAG_CONVERT_PPOS
```

---

## Infrastructure

| Component | Value |
|-----------|-------|
| **Root task** | `ANALYTICS.MFGPULSE_AUTOMATION_DAG` |
| **Schedule** | Every 720 minutes (12 hours) |
| **Warehouse** | `MFGPULSE_AUTOMATION_WH` (XS, 60s auto-suspend) |
| **Resource monitor** | `MFGPULSE_AUTOMATION_GUARD` (50 credits/month) |
| **Failure handling** | `SUSPEND_TASK_AFTER_NUM_FAILURES = 2` |
| **Default state** | All tasks created SUSPENDED |

### Resource Monitor Triggers

| Threshold | Action |
|-----------|--------|
| 75% (37.5 credits) | Notify |
| 90% (45 credits) | Suspend warehouse |
| 100% (50 credits) | Suspend immediately |

### Estimated Credit Consumption

| Task | Est. Credits/Run | Runs/Month (2×/day) | Monthly Credits |
|------|-----------------|---------------------|-----------------|
| SIMULATE_ALL_FEEDS_RANDOM | 0.020 | 60 | 1.20 |
| REFRESH_FATIGUE_SCORES | ~0.005 | 60 | 0.30 |
| REFRESH_ALL_DTS | ~0.010 | 60 | 0.60 |
| AUTO_GENERATE_WORK_ORDERS | 0.001 | 60 | 0.06 |
| AUTO_GENERATE_PURCHASE_ORDERS | 0.001 | 60 | 0.06 |
| AUTO_CONVERT_PLANNED_POS | 0.001 | 60 | 0.06 |
| **Total** | | | **~2.3** |

---

## Step 1 — Simulate Sensor Feeds (Root Task)

**Task:** `ANALYTICS.MFGPULSE_AUTOMATION_DAG`
**Calls:** `RAW_OT.SIMULATE_ALL_FEEDS_RANDOM()`
**Output:** ~490 sensor readings (48 per asset × 10 assets + production records)

### What It Does

Generates 12 hours of synthetic sensor readings and production output for all 10 assets. Unlike a simple random data generator, this procedure maintains **persistent degradation state** — each run reads the asset's current condition from `LIVE_PREDICTIONS` and builds on it.

### How It Works

#### 1. Context Gathering

For each asset in `ASSET_MASTER`, the procedure reads:

- **`CURRENT_DEG`** — Current degradation score (0.0–1.0) from `LIVE_PREDICTIONS`. This is the persistence mechanism: each cycle builds on the previous state rather than starting from scratch.
- **`HAS_RECENT_WO`** — Whether a work order was completed on this asset in the last 13 hours (one DAG cycle + 1-hour buffer). This detects maintenance recovery.

#### 2. Severity Calculation

**Path A — Recent maintenance (WO completed within 13h):**

```
severity = max(0.10, current_degradation × 0.30) + random(0.00, 0.05)
scenario = CLEAN
```

The asset "heals" — severity drops to roughly 30% of its pre-maintenance level plus minor noise. It always receives the CLEAN scenario (normal operating readings). This simulates real-world post-maintenance behavior where an asset returns to near-normal but may retain minor residual wear.

**Path B — No recent maintenance (persistent degradation):**

```
delta    = random(0.01, 0.06)
severity = min(0.95, current_degradation + delta)
```

The asset gets progressively worse. Degradation increases by 1–6% per 12-hour cycle, capped at 0.95 to prevent numerical overflow.

**Intermittent recovery flicker (10% chance):**

When severity > 0.30, there is a 10% probability the severity spontaneously drops by 0.10–0.20:

```
if severity > 0.30 AND random() < 0.10:
    severity = max(0.15, severity - random(0.10, 0.20))
```

This simulates real-world behavior where degrading machines occasionally produce normal readings due to thermal cycling, load changes, or measurement noise. It prevents monotonic degradation ramps that would be trivially easy for ML models to predict, forcing more robust anomaly detection.

#### 3. Scenario Selection (Probability Tables)

The failure scenario is randomly selected based on the current severity band:

| Severity Band | CLEAN | BEARING_WEAR | THERMAL_DEGRADATION | MISALIGNMENT | IMBALANCE |
|---------------|-------|-------------|-------------------|-------------|-----------|
| **< 0.30** (Healthy) | 80% | 10% | 0% | 0% | 10% |
| **0.30–0.59** (Warning) | 20% | 30% | 25% | 0% | 25% |
| **≥ 0.60** (Critical) | 0% | 30% | 25% | 25% | 20% |

Design rationale:

- **Healthy assets** mostly run clean but can show early bearing/imbalance signs (realistic early-onset faults).
- **Warning-band assets** retain a 20% chance of clean readings (intermittent fault behavior).
- **Critical assets never generate clean data** — they always exhibit a failure signature.
- **Misalignment** only appears at high severity because it is typically a sudden-onset fault.
- **Thermal degradation** is absent from healthy assets because it requires sustained thermal stress to manifest.

#### 4. Signal Generation (per asset)

Calls `RAW_OT.SIMULATE_SENSOR_FEED_CONFIGURABLE(asset_id, scenario, severity, 12)` which generates:

- **48 sensor readings** (12 hours × 4 readings/hour, one every 15 minutes)
- **1 production output record** per asset

Each scenario produces a distinct physics fingerprint across 8 sensor channels:

| Channel | CLEAN | BEARING_WEAR | THERMAL_DEGRADATION | MISALIGNMENT | IMBALANCE |
|---------|-------|-------------|-------------------|-------------|-----------|
| Vibration X | 1.5 ± 0.3 (baseline) | 2.0 + sev×8×(1+sev), random spikes at sev>0.8 | 1.6 + sev×0.5 (mild) | 2.5 + sev×5 + sinusoidal oscillation | 1.8 + sev×2 |
| Vibration Y | 1.3 ± 0.3 | 1.8 + sev×6×(1+0.5×sev) | 1.4 + sev×0.4 (mild) | 2.2 + sev×6.5 + cosinusoidal oscillation | 1.5 + sev×7×(1+sev) — dominant |
| Vibration Z | 1.1 ± 0.25 | 1.5 + sev×4 | 1.2 + sev×0.3 (mild) | 2.0 + sev×5.5 | 1.2 + sev×1.5 |
| Temperature | 50% rated | 50% + sev×15% rated | 55% + sev×40%×(1+0.3×sev) + sinusoidal cycling — dominant | 52% + sev×8% rated | Nominal |
| RPM | Nominal ± 0.3% | Nominal | Nominal | Nominal | Drops sev×8% |
| Pressure | 6.0 ± 0.2 bar | 6.5 + sev×1.5 | Nominal | Nominal | Nominal |
| Current | 10.5 ± 0.4 A | 11.5 + sev×3 | Nominal | 12 + sev×8×(1+sev) — dominant | Nominal |
| Acoustic | 65 ± 2 dB | 72 + sev×18, spikes at sev>0.7 | Nominal | 70 + sev×12 | 68 + sev×6 |

**Scenario physics rationale:**

- **Bearing wear:** Dominant radial vibration (X-axis), elevated acoustic signature from metal-on-metal contact, pressure buildup from friction, nonlinear severity scaling with random spike bursts at high degradation.
- **Thermal degradation:** Almost entirely temperature-driven with sinusoidal cycling from thermal expansion/contraction, minimal vibration impact — a slow-burn failure mode.
- **Misalignment:** All vibration axes elevated with phase-offset sinusoidal/cosinusoidal patterns (the hallmark of angular misalignment), very high current draw as the motor fights mechanical resistance.
- **Imbalance:** Dominant tangential vibration (Y-axis), RPM drops under centrifugal load, moderate acoustic increase.

**Production output also degrades:**

| Condition | Units Produced | Good Units |
|-----------|---------------|------------|
| CLEAN | 100 | 98 |
| Severity ≤ 0.7 | max(50, 100 − sev×50) | max(40, 98 − sev×58) |
| Severity > 0.7 | max(20, 100 − sev×80) | max(10, 98 − sev×88) |

#### 5. Audit Trail

After all assets are processed, an entry is written to `RAW_IT.SIMULATION_CONFIG`:

```
ASSET_ID: 'ALL_RANDOM'
SCENARIO: 'PERSISTENT_DEGRADATION'
ROWS_GENERATED: total_assets × 49
ESTIMATED_CREDITS: 0.15
CREATED_BY: 'SIMULATE_ALL_FEEDS_RANDOM'
```

### What Happens Next

New sensor readings and production records are now in the raw tables. The WORK_ORDERS_STREAM on `RAW_IT.WORK_ORDERS` and the base table changes will propagate through the Dynamic Table dependency chain when Step 3 forces a refresh.

---

## Step 2 — Refresh Fatigue Scores

**Task:** `ANALYTICS.DAG_REFRESH_FATIGUE`
**Runs after:** Step 1 (root task)
**Calls:** `ML_MODELS.REFRESH_FATIGUE_SCORES()`

### What It Does

Computes the M4 fatigue score (cumulative damage model, UDF `COMPUTE_FATIGUE_SCORE`) for all new sensor readings that arrived since the last refresh.

### How It Works

1. Joins `ML_FEATURES.ROLLING_STATS` with `PHYSICS_COMPOSITE` and `SENSOR_INTERACTIONS` on asset + timestamp.
2. Calls `COMPUTE_FATIGUE_SCORE()` with 9 parameters: crest factor, coefficient of variation, peak-to-peak, rate of change, acceleration, energy balance ratio, stress index, XY correlation, and acoustic-vibration ratio.
3. Inserts into `ML_MODELS.FATIGUE_SCORES` with a level label:

| Fatigue Score | Level |
|--------------|-------|
| > 0.7 | CRITICAL |
| > 0.4 | HIGH |
| > 0.2 | ACCUMULATING |
| ≤ 0.2 | HEALTHY |

4. Only processes readings newer than the last computed score (`WHERE timestamp > max(existing)`).
5. Limits to 48 rows per asset (12 hours of data at 4 readings/hour) via `QUALIFY ROW_NUMBER()`.

### What Happens Next

Fresh fatigue scores are available for the `LIVE_PREDICTIONS` Dynamic Table, which uses them as input to the RUL and degradation stage models.

---

## Step 3 — Refresh All 13 Dynamic Tables

**Task:** `ANALYTICS.DAG_REFRESH_DTS`
**Runs after:** Step 2
**Calls:** `ANALYTICS.REFRESH_ALL_DTS()`

### What It Does

Forces an immediate refresh of all 13 Dynamic Tables in strict dependency order, ensuring predictions reflect the latest sensor data and fatigue scores.

### How It Works

Executes `ALTER DYNAMIC TABLE ... REFRESH` in 5 layers:

```
Layer 0 — Raw → Curated (3 DTs)
├── CURATED.SENSOR_WITH_CONTEXT         (sensor readings + asset metadata)
├── CURATED.ASSET_HEALTH_CURRENT        (latest health snapshot per asset)
└── CURATED.FAILURE_HISTORY             (historical failure events)

Layer 1 — Raw → Features (4 DTs)
├── ML_FEATURES.ROLLING_STATS           (6h/24h rolling statistics: RMS, crest factor, etc.)
├── ML_FEATURES.PHYSICS_COMPOSITE       (stress index, ISO severity, health score) [INCREMENTAL]
├── ML_FEATURES.SENSOR_INTERACTIONS     (cross-sensor correlations, XY coupling)
└── ML_FEATURES.LABELED_DATA            (training labels from WO history)

Layer 2 — Features → Advanced Features (3 DTs)
├── ML_FEATURES.TEMPORAL_MEMORY         (degradation velocity, trend reversals)
├── ML_FEATURES.FLEET_COMPARISON        (z-scores vs fleet, percentile ranks)
└── ML_FEATURES.CROSS_DOMAIN            (maintenance history + sensor cross-features)

Layer 3 — Features + Fatigue → Predictions (1 DT)
└── ML_MODELS.LIVE_PREDICTIONS          (runs M1-M4 UDFs: failure mode, RUL, stage, fatigue)

Layer 4 — Predictions → Business (2 DTs)
├── ANALYTICS.ACTIVE_ALERTS             (severity rules: CRITICAL/WARNING/WATCH/INFO)
└── ANALYTICS.OEE_METRICS               (OEE per asset per shift)
```

All DTs have `TARGET_LAG = '2 days'` for normal auto-refresh, but the DAG forces immediate refresh to keep the cycle synchronized.

### What Happens Next

`LIVE_PREDICTIONS` now contains up-to-date predictions for all 10 assets:
- **M1** — Predicted failure mode (bearing_wear, thermal_degradation, misalignment, imbalance, normal)
- **M2** — Remaining Useful Life in hours (with confidence intervals)
- **M3** — Degradation stage (Healthy, Warning, Critical) with transition probability
- **M4** — Fatigue score (0.0–1.0)

`ACTIVE_ALERTS` has refreshed severity levels. `OEE_METRICS` reflects the latest production output.

---

## Step 4 — Auto-Generate Work Orders

**Task:** `ANALYTICS.DAG_GENERATE_WOS`
**Runs after:** Step 3
**Calls:** `ANALYTICS.AUTO_GENERATE_WORK_ORDERS()`

### What It Does

Scans freshly updated predictions and creates work orders for at-risk assets that don't already have open WOs.

### How It Works

#### Eligibility Filter

An asset qualifies if ALL of:
- `RUL_HOURS < 200` OR `DEGRADATION_SCORE > 0.6` OR `FAILURE_MODE_PRED != 'normal'`
- No existing WO in `open` or `in_progress` status for this asset

#### WO Type and Priority Classification

| Condition | WO Type | Priority | Labor Hours | Estimated Cost |
|-----------|---------|----------|-------------|----------------|
| RUL < 48h | emergency | EMERGENCY | 8 | $1,300 |
| RUL < 120h | corrective | HIGH | 6 | $1,100 |
| RUL ≥ 120h, deg > 0.7 | preventive | MEDIUM | 4 | $900 |
| RUL ≥ 120h, deg ≤ 0.7 | preventive | LOW | 4 | $900 |

#### Technician Assignment

Round-robin across 4 technicians: Mike Torres → Sarah Chen → James Wright → Maria Garcia.

#### Notifications

For each created WO:
- **`WO_CREATED`** notification with asset name, WO type, RUL, failure mode, priority, and assigned technician.
- **`PART_SHORTAGE_ALERT`** notification if the asset needs a part, no open PO exists, and RUL < 120h.

#### WO ID Format

```
WO-AUTO-{asset_number}-{YYYYMMDD_HH24MISS}
Example: WO-AUTO-001-20260926_143022
```

### What Happens Next

New work orders appear in the WO/PO Console. Technicians can start work, and the system has flagged any parts shortages. The next step creates purchase orders for those parts.

---

## Step 5 — Auto-Generate Purchase Orders

**Task:** `ANALYTICS.DAG_GENERATE_POS`
**Runs after:** Step 4
**Calls:** `ANALYTICS.AUTO_GENERATE_PURCHASE_ORDERS()`

### What It Does

Creates purchase orders for parts needed by at-risk assets, using procurement recommendations computed from the refreshed predictions.

### How It Works

#### Eligibility Filter

Reads from `ANALYTICS.PROCUREMENT_RECOMMENDATIONS` where:
- `RECOMMENDED_PROCUREMENT_ACTION` is `CREATE_PO`, `EXPEDITE_PO`, or `ESCALATE_CRITICAL_SHORTAGE`
- No existing open PO (`OPEN_PO_ID IS NULL`)
- Asset is at risk: `RUL_HOURS < 336` OR `STAGE_PRED IN ('Warning', 'Critical')` OR `FAILURE_MODE_PRED != 'normal'`

#### Priority Mapping

| Procurement Risk | PO Priority |
|-----------------|-------------|
| CRITICAL_SHORTAGE | EMERGENCY |
| EXPEDITE | EXPEDITE |
| All others | HIGH |

#### Duplicate Prevention

Calls `ANALYTICS.GENERATE_PURCHASE_ORDER()` which checks for existing POs for the same asset+part before creating. If a duplicate is found, the PO is skipped.

#### Result

Returns `{status: 'COMPLETE', pos_created: N, pos_skipped: M}`.

### What Happens Next

New POs are in `pending_approval` status. They need manual approval via the WO/PO Console. The final step checks if any planned POs have hit their deadline.

---

## Step 6 — Auto-Convert Planned Purchase Orders

**Task:** `ANALYTICS.DAG_CONVERT_PPOS`
**Runs after:** Step 5
**Calls:** `ANALYTICS.AUTO_CONVERT_PLANNED_POS()`

### What It Does

Checks all Planned Purchase Orders (PPOs) whose order-by deadline has passed and converts them to real purchase orders.

### How It Works

#### Deadline Calculation

The `PLANNED_PURCHASE_ORDERS` view computes for each PPO:

```
ORDER_BY_DEADLINE = EARLIEST_REQUIRED_BY − LEAD_TIME_DAYS
```

A PPO becomes eligible when:
- `AUTO_CONVERT_DUE = TRUE` (today ≥ ORDER_BY_DEADLINE)
- `PPO_STATUS` is `AUTO_CONVERTING` or `EXPEDITE_IMMEDIATELY`

#### PPO Status Ladder

| Status | Condition |
|--------|-----------|
| PLANNED | Deadline far away |
| ORDER_SOON | Within 2 days of deadline |
| REVIEW_AND_EXPEDITE | Has expedite risk flag |
| AUTO_CONVERTING | Past the order-by deadline |
| EXPEDITE_IMMEDIATELY | Critical shortage (ATP < 0) |

#### Conversion Logic

For each eligible PPO:

1. **Duplicate check** — Skip if an active `auto_planned` PO already exists for this part.
2. **Supplier selection** — Pick the cheapest active supplier for the part (from `PART_SUPPLIERS` joined with `SUPPLIERS`).
3. **Create PO** with ID `PO-AUTO-YYYYMMDD-{PART_ID}`, status `pending_approval`, source `auto_planned`, created by `SYSTEM_AUTO_CONVERT`.
4. **Create PO line items** from `PROCUREMENT_RECOMMENDATIONS` — one line per asset needing the part.
5. **Send notification** — `PO_CREATED` event noting the auto-conversion.

#### Key Detail

Auto-conversion does **not** auto-approve. Created POs land in `pending_approval` status and still require manual approval through the WO/PO Console. The automation ensures POs are created before supplier lead times make on-time delivery impossible.

### Result

Returns `{status: 'COMPLETE', converted: N, skipped: M, run_at: timestamp}`.

---

## End-to-End Data Flow

```
Sensor Simulation          Feature Engineering           ML Predictions
─────────────────          ───────────────────           ──────────────
Step 1:                    Step 3 (Layer 0-2):           Step 3 (Layer 3):
SENSOR_READINGS ──────────→ ROLLING_STATS ──────────────→ LIVE_PREDICTIONS
PRODUCTION_OUTPUT          PHYSICS_COMPOSITE              (M1: Failure Mode)
                           SENSOR_INTERACTIONS             (M2: RUL Hours)
Step 2:                    TEMPORAL_MEMORY                 (M3: Degradation Stage)
FATIGUE_SCORES ──────────→ FLEET_COMPARISON                (M4: Fatigue Score)
                           CROSS_DOMAIN
                           LABELED_DATA

Business Actions           Procurement
────────────────           ───────────
Step 3 (Layer 4):          Step 5:
ACTIVE_ALERTS              AUTO_GENERATE_PURCHASE_ORDERS
OEE_METRICS                    ↓
    ↓                      Step 6:
Step 4:                    AUTO_CONVERT_PLANNED_POS
AUTO_GENERATE_WORK_ORDERS      ↓
    ↓                      POs in pending_approval
WOs in open status         (manual approval required)
```

---

## Feedback Loop

The DAG creates a closed-loop system:

1. **Simulation reads predictions** — Step 1 uses `LIVE_PREDICTIONS.DEGRADATION_SCORE` to determine each asset's starting severity.
2. **Maintenance resets degradation** — When a WO is completed (via the UI), Step 1 detects `HAS_RECENT_WO` and drops severity to ~30% of pre-maintenance levels.
3. **New data updates predictions** — Steps 2–3 refresh the feature pipeline and predictions with the new (healthy or degraded) sensor data.
4. **Predictions drive actions** — Steps 4–6 create WOs and POs based on the updated predictions.
5. **Actions close the loop** — WO completion triggers maintenance recovery in the next cycle.

This means the plant simulation self-evolves: assets degrade over time, trigger WOs, get repaired, recover, and the cycle continues — mimicking a real manufacturing plant lifecycle.

---

## Startup / Shutdown

### To Enable

Resume tasks bottom-up (children before root):

```sql
ALTER TASK ANALYTICS.DAG_CONVERT_PPOS RESUME;
ALTER TASK ANALYTICS.DAG_GENERATE_POS RESUME;
ALTER TASK ANALYTICS.DAG_GENERATE_WOS RESUME;
ALTER TASK ANALYTICS.DAG_REFRESH_DTS RESUME;
ALTER TASK ANALYTICS.DAG_REFRESH_FATIGUE RESUME;
ALTER TASK ANALYTICS.MFGPULSE_AUTOMATION_DAG RESUME;
```

### To Disable

Suspend root first (stops the entire chain):

```sql
ALTER TASK ANALYTICS.MFGPULSE_AUTOMATION_DAG SUSPEND;
```

### To Trigger Manually

```sql
EXECUTE TASK ANALYTICS.MFGPULSE_AUTOMATION_DAG;
```

### To Check Status

```sql
-- Task state
SHOW TASKS IN SCHEMA MFGPULSE_DB.ANALYTICS;

-- Recent execution history
SELECT NAME, STATE, SCHEDULED_TIME, COMPLETED_TIME, ERROR_MESSAGE
FROM TABLE(INFORMATION_SCHEMA.TASK_HISTORY(
    SCHEDULED_TIME_RANGE_START => DATEADD('day', -1, CURRENT_TIMESTAMP()),
    RESULT_LIMIT => 20
))
WHERE NAME LIKE '%DAG%' OR NAME LIKE '%MFGPULSE_AUTOMATION%'
ORDER BY SCHEDULED_TIME DESC;
```

---

## Tables Written

| Step | Tables Modified |
|------|----------------|
| 1 | `RAW_OT.SENSOR_READINGS`, `RAW_IT.PRODUCTION_OUTPUT`, `RAW_IT.SIMULATION_CONFIG` |
| 2 | `ML_MODELS.FATIGUE_SCORES` |
| 3 | 13 Dynamic Tables (auto-refreshed, not direct writes) |
| 4 | `RAW_IT.WORK_ORDERS`, `RAW_IT.APP_NOTIFICATIONS` |
| 5 | `RAW_IT.PURCHASE_ORDERS`, `RAW_IT.PURCHASE_ORDER_LINES`, `RAW_IT.APP_NOTIFICATIONS` |
| 6 | `RAW_IT.PURCHASE_ORDERS`, `RAW_IT.PURCHASE_ORDER_LINES`, `RAW_IT.APP_NOTIFICATIONS` |

---

## Failure Behavior

- The DAG auto-suspends after **2 consecutive failures** (`SUSPEND_TASK_AFTER_NUM_FAILURES = 2`).
- If any child task fails, subsequent children in the chain **do not execute** (strict sequential dependency).
- The resource monitor suspends the warehouse at 90% of the 50-credit monthly budget, preventing runaway costs.
- Individual procedure errors within Steps 4–6 are caught with `EXCEPTION WHEN OTHER THEN NULL` for non-critical operations (notifications, part shortage alerts), so a notification failure does not abort the entire step.
