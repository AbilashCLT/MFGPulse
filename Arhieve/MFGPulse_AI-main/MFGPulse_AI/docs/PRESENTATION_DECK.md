# MFGPulse AI — Presentation Deck Outline

*Slide-by-slide guide for the hackathon submission deck.*

---

## Slide 1 — Title

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│           ⚙️  MFGPulse AI                                  │
│                                                            │
│     Predictive Maintenance & OEE Command Center            │
│                                                            │
│     Converging IT + OT Data to Predict Failures,           │
│     Automate Work Orders, and Lift OEE                     │
│                                                            │
│     ─────────────────────────────────────────              │
│     100% Snowflake-Native | 12 ML models | 8 Dashboards    │
│     Built with CoCo (Cortex Code)                          │
│                                                            │
│     Team: Abik                                             │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Speaker notes**: One sentence — "MFGPulse AI is a predictive maintenance command center that converges shop-floor sensor data with ERP records on Snowflake to predict failures, automate work orders, and lift OEE."

---

## Slide 2 — The Problem

**Headline**: Unplanned Downtime Costs Manufacturers $50B/Year — Because IT and OT Data Never Meet

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│   OT (Shop Floor)          ╳          IT (ERP / CMMS)     │
│   ┌─────────────┐    DATA SILO    ┌────────────────┐      │
│   │ Vibration   │                  │ Work Orders    │      │
│   │ Temperature │    No link →     │ Maintenance    │      │
│   │ RPM         │    No context    │ Parts / POs    │      │
│   │ Pressure    │    No action     │ Suppliers      │      │
│   └─────────────┘                  └────────────────┘      │
│                                                            │
│                         ▼                                  │
│                                                            │
│   ┌────────────────────────────────────────────────────┐   │
│   │  REACTIVE MAINTENANCE                              │   │
│   │                                                    │   │
│   │  Machine breaks → Production stops →               │   │
│   │  Emergency repair (4.3x cost) → OEE drops          │   │
│   └────────────────────────────────────────────────────┘   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Key talking points**:
- Sensors generate terabytes — vibration, temperature, RPM, pressure, acoustic emission
- ERP holds the context — work orders, maintenance logs, parts inventory, supplier lead times
- They live in separate systems; failures are discovered after the fact
- Emergency repairs cost 4.3x more than planned maintenance (our data confirms this)
- The problem is not data. The problem is convergence.

---

## Slide 3 — The Solution

**Headline**: MFGPulse AI — From Data Silos to Predictive Action

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│  Sense → Converge → Predict → Diagnose → Act → Track      │
│                                                            │
│  ┌──────┐   ┌──────────┐   ┌──────────┐   ┌───────────┐  │
│  │172K+ │   │14 Dynamic│   │12 ML     │   │Cortex     │  │
│  │sensor│──▶│Tables    │──▶│Models    │──▶│Agent      │  │
│  │reads │   │(auto-    │   │(predict, │   │(diagnose, │  │
│  │6 ch. │   │ refresh) │   │ classify,│   │ simulate, │  │
│  │10    │   │IT + OT   │   │ simulate)│   │ prescribe)│  │
│  │assets│   │converged │   │          │   │           │  │
│  └──────┘   └──────────┘   └──────────┘   └─────┬─────┘  │
│                                                  │        │
│                                                  ▼        │
│  ┌──────────────────────────────────────────────────────┐ │
│  │  8-Page Command Center | 6 Personas | Notifications  │ │
│  │  WO/PO Lifecycle | Procurement Closed Loop           │ │
│  └──────────────────────────────────────────────────────┘ │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Key talking points**:
- 100% Snowflake-native — zero external services
- 14 Dynamic Tables auto-converge OT sensors with IT records (no manual ETL)
- 12 ML models answer: What will fail? When? Why? How bad? What to do?
- Cortex Agent enables natural-language diagnosis, simulation, and WO generation
- 8-page Streamlit app with role-based access for 6 manufacturing personas
- Closed-loop: prediction → work order → parts check → PO → notification → tracking

---

## Slide 4 — Architecture

**Headline**: 7-Schema Layered Pipeline — Ingestion to Action

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│  RAW_OT (sensors)──┐                                      │
│                     ├──▶ CURATED (3 DTs)                   │
│  RAW_IT (ERP)──────┘         │                             │
│      3 Streams               ▼                             │
│      11 Tasks         ML_FEATURES (7 DTs)                  │
│                              │                             │
│                              ▼                             │
│                       ML_MODELS                            │
│                    LIVE_PREDICTIONS (DT)                    │
│                    12 models │ Cortex Search                │
│                              │                             │
│                              ▼                             │
│                        ANALYTICS                           │
│                    Alerts │ OEE │ Cost                      │
│                    17 views │ 27 procedures                  │
│                              │                             │
│                              ▼                             │
│                          AGENT                             │
│                 Semantic View (6 tables, 21 VQRs)          │
│                 Cortex Agent (5 tools)                      │
│                              │                             │
│                              ▼                             │
│                  Streamlit (8 pages, 6 personas)           │
│                  Email + In-App Notifications               │
│                                                            │
│  Snowflake Features Used:                                  │
│  Dynamic Tables │ Cortex Complete │ Cortex Search │        │
│  Cortex Agent │ Semantic View │ Snowflake ML │             │
│  Streams │ Tasks │ Streamlit │ Notification Integration    │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Key talking points**:
- Strict layer separation — data flows downward, no circular dependencies
- LIVE_PREDICTIONS is the single source of truth for all dashboards
- Dynamic Tables handle the entire ETL — no Airflow, no cron, no manual scheduling
- INCREMENTAL refresh on PHYSICS_COMPOSITE and SENSOR_INTERACTIONS for efficiency
- Cortex Agent has genuine tool-use: procedures and functions as backends, not just a chatbot wrapper

---

## Slide 5 — IT/OT Convergence (Requirement 1)

**Headline**: Correlating Sensor Streams with ERP Context — Automatically

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│   OT Data (RAW_OT)              IT Data (RAW_IT)          │
│   ├─ SENSOR_READINGS (172K)     ├─ WORK_ORDERS            │
│   │  vibration x/y/z            ├─ MAINTENANCE_LOGS       │
│   │  temperature, RPM           ├─ PARTS_INVENTORY        │
│   │  current, acoustic          ├─ SUPPLIERS              │
│   │  pressure                   ├─ PRODUCTION_OUTPUT      │
│   ├─ ASSET_MASTER (10)          ├─ SHIFT_SCHEDULE         │
│   ├─ SENSOR_METADATA            ├─ PURCHASE_ORDERS        │
│   └─ AMBIENT_CONDITIONS         └─ USERS (6 personas)     │
│                                                            │
│              ▼ Auto-converged via Dynamic Tables ▼         │
│                                                            │
│   SENSOR_WITH_CONTEXT (DT)                                 │
│   = Sensor readings + asset metadata + production +        │
│     vibration magnitude + temp/RPM ratios +                │
│     hours since last maintenance                           │
│                                                            │
│   CROSS_DOMAIN (DT)                                        │
│   = Sensor features + days since last WO +                 │
│     cumulative operating hours + WO count                  │
│                                                            │
│   Result: Every sensor reading carries full IT context     │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Key talking points**:
- Not a one-time join — continuously refreshed via Dynamic Tables
- SENSOR_WITH_CONTEXT enriches every reading with asset metadata, shift context, and ambient conditions
- CROSS_DOMAIN fuses sensor features with maintenance history (days since last WO, cumulative hours)
- FAILURE_HISTORY captures 7-day pre-failure sensor windows for pattern learning
- 3 CDC Streams ensure changes propagate automatically

---

## Slide 6 — 12 ML models (Requirement 2a)

**Headline**: 7 Questions, 12 Models — Every Prediction Dimension Covered

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│   Model   Question         Method          Output          │
│   ─────   ────────         ──────          ──────          │
│   M1      WHAT will fail?  Rule ensemble   5-class mode    │
│   M2      WHEN?            Physics regr.   RUL (P10/50/90) │
│   M3      HOW BAD now?     Composite score Healthy/Warn/Cr │
│   M4      HIDDEN damage?   Cumulative dmg  Fatigue 0→1     │
│   M5      WHY failing?     LLM + RAG       Root cause text │
│   M6      WHAT-IF?         Monte Carlo     Fail prob 3/7/14│
│   M7      WHAT TO DO?      LLM prescribe   WO + parts+cost│
│                                                            │
│   + 3 Native Snowflake ML:                                 │
│     Classification (failure mode, degradation)             │
│     Forecast (RUL time series)                             │
│     + Anomaly Detection scores (50K+)                      │
│                                                            │
│   All feed into LIVE_PREDICTIONS → single source of truth  │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Key talking points**:
- Not a single prediction — a 7-model diagnostic chain orchestrated by PREDICT_ALL
- M1-M4 run automatically on every Dynamic Table refresh
- M5-M7 run on-demand via Copilot or Agent
- M6 (Digital Twin): 100 stochastic Monte Carlo paths per scenario, 3 scenarios = 300 simulations
- Native Snowflake ML adds statistical rigor: Classification on 142K rows, Forecast on 20K rows, AnomalyDetection on 50K scores
- Physics-informed models are deliberate — more interpretable and trusted by reliability engineers than black-box DL

---

## Slide 7 — Natural Language + Agent (Requirement 2b)

**Headline**: Ask in English, Get a Diagnosis — Cortex Agent with 5 Tools

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│  User: "Why is Compressor A1 degrading? What should I do?" │
│                                                            │
│              ▼ Cortex Agent decides which tools ▼          │
│                                                            │
│  ┌──────────────────┐  ┌──────────────────────────────┐   │
│  │ maintenance_     │  │ maintenance_history           │   │
│  │ analytics        │  │ (Cortex Search RAG)           │   │
│  │ (Semantic View   │  │ Searches 78 maintenance docs  │   │
│  │  text-to-SQL)    │  │ for similar past failures     │   │
│  └──────────────────┘  └──────────────────────────────┘   │
│  ┌──────────────────┐  ┌──────────────────────────────┐   │
│  │ predict_all      │  │ simulate_scenario             │   │
│  │ (7-model chain)  │  │ (Monte Carlo what-if)         │   │
│  │ Full diagnosis   │  │ "What if we reduce load 20%?" │   │
│  └──────────────────┘  └──────────────────────────────┘   │
│  ┌──────────────────────────────────────────────────────┐  │
│  │ generate_work_order                                  │  │
│  │ "Create a preventive WO for Fan F1"                  │  │
│  │ Auto-assigns technician, checks parts, files WO      │  │
│  └──────────────────────────────────────────────────────┘  │
│                                                            │
│  Response adapts to persona:                               │
│    Technician → step-by-step repair + part numbers         │
│    Plant Manager → cost-impact summary + ROI               │
│    Supervisor → shift briefing format                      │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Key talking points**:
- Cortex Agent with genuine tool-use — not a chatbot wrapper
- Semantic View (21 VQRs) ensures text-to-SQL accuracy for analytics
- Cortex Search RAG over 78 maintenance documents for root cause investigation
- Agent chains tools: search history → diagnose → simulate → prescribe → generate WO
- Persona-aware responses: same question, different format per role
- Session history: previous conversations persisted and restorable

---

## Slide 8 — Command Center Experience (Requirement 3)

**Headline**: 8 Pages, 6 Personas — Not a Dashboard, an Operational Workflow

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│  ┌──────────────┐  ┌───────────────┐  ┌────────────────┐  │
│  │  Executive    │  │  Operations   │  │  WO/PO         │  │
│  │  Dashboard    │  │  Center       │  │  Console       │  │
│  │              │  │               │  │                │  │
│  │  OEE, costs, │  │  Fleet status,│  │  Create, start,│  │
│  │  ROI, risk   │  │  alert triage,│  │  complete WOs. │  │
│  │  matrix, WO  │  │  shift hand-  │  │  Approve, ship,│  │
│  │  cost donut, │  │  over, WOs    │  │  receive POs.  │  │
│  │  OEE trend,  │  │               │  │  Bulk select + │  │
│  │  supply risk │  │               │  │  bulk actions.  │  │
│  │  donut+gaps  │  │               │  │                │  │
│  └──────────────┘  └───────────────┘  └────────────────┘  │
│  ┌──────────────┐  ┌───────────────┐  ┌────────────────┐  │
│  │  Maintenance  │  │  Procurement  │  │  Digital Twin  │  │
│  │  Hub          │  │               │  │                │  │
│  │              │  │               │  │                │  │
│  │  Failure DNA, │  │  ATP, risk    │  │  Monte Carlo   │  │
│  │  KPIs, parts, │  │  badges, PO   │  │  3 scenarios,  │  │
│  │  alerts+hist  │  │  auto-gen     │  │  300 paths     │  │
│  └──────────────┘  └───────────────┘  └────────────────┘  │
│  ┌──────────────┐  ┌───────────────┐                      │
│  │  Admin Panel  │  │  Copilot      │   Persona Access:   │
│  │              │  │               │   Tech   → 5 pages  │
│  │  Infra, DTs,  │  │  NL assistant │   Eng    → 6 pages  │
│  │  models, test │  │  5 agent      │   Supv   → 6 pages  │
│  │  suite, FinOps│  │  tools        │   PM     → 7 pages  │
│  │  notif config │  │               │   Proc   → 5 pages  │
│  └──────────────┘  └───────────────┘   Admin  → 8 pages  │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Key talking points**:
- Dashboards show data. Command centers enable action. MFGPulse AI does both.
- OEE Trend Analysis: 185-day daily trend per production line with plant-wide average and 85% target line. Switchable metric view (OEE/Availability/Performance/Quality) — enables trend tracking without spreadsheets
- Supply Chain Risk Overview: risk distribution donut, lead time gap chart by asset, at-risk cost metric — at-a-glance exposure assessment for Plant Managers
- Live Sensor Feed: 24-hour sensor data with asset/time-range filters, channel time-series charts, latest KPIs, and raw data export — replaces manual historian checks
- Alert triage: 4 severity levels (Critical/Warning/Watch/Info), sorted, with failure mode, RUL, and chronic asset flags
- WO parts tracking: each work order shows recommended part, ATP, procurement risk, linked PO, and full activity log (reassignment + follow-up history)
- Digital Twin text summary: auto-generated narrative identifying lowest-cost scenario, cost savings, and 14-day failure probability assessment
- Data-driven summaries: every page has an LLM-generated executive summary via Cortex Complete (llama3.1-8b) — boardroom-ready narratives with outcomes, risks, and next steps. Cached per data hash for credit efficiency.
- Action loop: Alert → Diagnose → Create WO → Check parts → Create PO → Approve → Track → Notify
- WO/PO Console: single and bulk operations — select multiple WOs/POs for batch start, complete, approve, reject, or status transitions. ATP validation gates bulk start actions.
- Persona-gated: Technicians see their WOs. Supervisors start/complete. Procurement approves POs. Admins see everything.
- Notification bell: in-app alerts per persona with 15s auto-refresh + admin-configurable email delivery

---

## Slide 9 — The Closed Loop (Differentiator)

**Headline**: Prediction to Procurement to Resolution — Fully Connected

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│        ┌──────────────────────────────────┐                │
│        │  1. PREDICT                      │                │
│        │  ML models detect bearing wear   │                │
│        │  on Compressor A1. RUL: 96 hrs.  │                │
│        └───────────────┬──────────────────┘                │
│                        ▼                                   │
│        ┌──────────────────────────────────┐                │
│        │  2. ALERT                        │                │
│        │  ACTIVE_ALERTS DT generates      │                │
│        │  WARNING severity alert.         │                │
│        └───────────────┬──────────────────┘                │
│                        ▼                                   │
│        ┌──────────────────────────────────┐                │
│        │  3. DIAGNOSE                     │                │
│        │  Copilot: root cause = bearing   │                │
│        │  wear from historical vibration  │                │
│        │  pattern (RAG cites log entry).  │                │
│        └───────────────┬──────────────────┘                │
│                        ▼                                   │
│        ┌──────────────────────────────────┐                │
│        │  4. SIMULATE                     │                │
│        │  Digital Twin: reduce load 20%   │                │
│        │  extends RUL to 168 hrs.         │                │
│        │  "Safe window for planned repair"│                │
│        └───────────────┬──────────────────┘                │
│                        ▼                                   │
│        ┌──────────────────────────────────┐                │
│        │  5. ACT                          │                │
│        │  Create WO (1 click or Copilot). │                │
│        │  Auto-assign technician from     │                │
│        │  shift schedule.                 │                │
│        └───────────────┬──────────────────┘                │
│                        ▼                                   │
│        ┌──────────────────────────────────┐                │
│        │  6. PROCURE                      │                │
│        │  Check ATP → bearing kit short.  │                │
│        │  Create PO → approve → track     │                │
│        │  arrival vs RUL deadline.        │                │
│        └───────────────┬──────────────────┘                │
│                        ▼                                   │
│        ┌──────────────────────────────────┐                │
│        │  7. NOTIFY + TRACK              │                │
│        │  Email + in-app to supervisor.   │                │
│        │  WO tracked to completion.       │                │
│        │  Cost: $2,400 repair vs          │                │
│        │        $10,300 emergency failure. │                │
│        └──────────────────────────────────┘                │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Key talking points**:
- This is not a prediction dashboard with a "create PO" button bolted on
- Each step connects to the next through Snowflake-native objects (DTs, procedures, views, notifications)
- ATP check happens before WO assignment — no "parts unavailable" surprises
- Digital Twin simulation provides data-driven justification for intervention timing
- Cost of inaction: $10,317 (emergency) vs $2,417 (planned) = 4.3x multiplier

---

## Slide 10 — Live Demo Flow

**Headline**: 5-Minute Walkthrough Path

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│  Demo Step          Page              What to Show         │
│  ──────────         ────              ────────────         │
│                                                            │
│  1. Login           Login screen      Select Plant Manager │
│     (15 sec)                          → 7 pages appear     │
│                                                            │
│  2. Plant pulse     Executive         OEE = 61.7%,         │
│     (45 sec)        Dashboard         6 critical assets,   │
│                                       $47K cost avoided,   │
│                                       3.3x ROI, WO donut  │
│                                                            │
│  3. Alert triage    Operations        2 Critical + 4 Warn  │
│     (30 sec)        Center            alerts. Click one.   │
│                                                            │
│  4. Deep dive       Maintenance       Select critical      │
│     (45 sec)        Hub               asset → Failure DNA  │
│                                       5 risk signals,      │
│                                       parts status         │
│                                                            │
│  5. Ask the AI      Copilot           "Run a full          │
│     (60 sec)                          diagnosis on         │
│                                       ASSET_001"           │
│                                       → 7-model output     │
│                                                            │
│  6. What-if         Digital Twin      3 scenarios,          │
│     (45 sec)                          probability curves,  │
│                                       RUL distribution,    │
│                                       part arrival timing  │
│                                                            │
│  7. Take action     WO/PO Console    Create WO →           │
│     (30 sec)                          notification fires   │
│                                       → bell shows alert   │
│                                                            │
│  8. Admin check     Admin Panel       Show DT status,      │
│     (30 sec)                          run 1 test category  │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Key talking points**:
- Demo tells a story: see the problem → investigate → diagnose → simulate → act → confirm
- Switch persona mid-demo (Technician view vs Plant Manager view) to show role-based access
- Copilot demo: one natural-language question triggers the full 7-model diagnostic chain
- Notification fires live — audience sees the bell update in real time

---

## Slide 11 — Impact & Metrics

**Headline**: Measurable Outcomes from the Live System

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│   │   $47,400     │  │    3.3x      │  │    4.3x      │   │
│   │  Cost Avoided │  │ Maint. ROI   │  │ Emergency    │   │
│   │              │  │              │  │ Cost Penalty │   │
│   └──────────────┘  └──────────────┘  └──────────────┘   │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│   │   560K+       │  │    12        │  │    80+       │   │
│   │ Sensor Reads  │  │  ML Models   │  │  Test Cases  │   │
│   │  Processed    │  │  Operational │  │  Automated   │   │
│   └──────────────┘  └──────────────┘  └──────────────┘   │
│                                                            │
│   Time Savings:                                            │
│   ┌────────────────────────────────────────────────────┐   │
│   │  Root cause investigation   4 hours → 30 seconds   │   │
│   │  Shift handover prep        45 min → instant       │   │
│   │  Work order creation        20 min → 1 click       │   │
│   │  Procurement risk review    2 hours → automatic    │   │
│   │  Failure prediction         Reactive → Predictive  │   │
│   │  Intervention planning      Gut feel → Monte Carlo │   │
│   └────────────────────────────────────────────────────┘   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Key talking points**:
- All metrics from the live EXECUTIVE_SUMMARY view — not projections
- $47,400 cost avoided across 10 assets in 30 days
- 3.3x ROI on maintenance spend ($59,515 total spend)
- Emergency failures cost $10,317 avg vs $2,417 for planned repairs
- Root cause that took 4 hours is now a 30-second Copilot query
- 80+ automated tests runnable from Admin Panel (not just developer tests)

---

## Slide 12 — Scalability & Beyond the Demo

**Headline**: Demo-Ready Today, Enterprise-Ready Tomorrow

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│   Scale Dimension     Demo              Production         │
│   ───────────────     ────              ──────────         │
│   Assets              10                1,000+             │
│   Sensor volume       172K (30 days)    Millions (years)   │
│   Plants              1                 Multi-plant        │
│   ML models           12                Per-asset-type     │
│   Users               9                 Enterprise-wide    │
│   Notifications       16 event types     Custom events      │
│                                                            │
│   No architectural changes required.                       │
│   Dynamic Tables, UDFs, and views scale automatically.     │
│                                                            │
│   ─────────────────────────────────────────                │
│                                                            │
│   Extensions:                                              │
│   ┌────────────────────────────────────────────────────┐   │
│   │  Real OT ── Snowpipe/Kafka from OPC-UA/MQTT       │   │
│   │  ERP     ── SAP PM / Oracle EAM / Maximo          │   │
│   │  ML      ── Deep learning via Snowpark ML          │   │
│   │  Multi-plant ── PLANT_ID dimension + drill-down    │   │
│   │  Compliance  ── FDA 21 CFR Part 11, ISO 55000      │   │
│   │  Distribution ── Snowflake Native App on Mktplace  │   │
│   └────────────────────────────────────────────────────┘   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Key talking points**:
- Architecture built for scale: Dynamic Tables, elastic compute, INCREMENTAL refresh
- LIVE_PREDICTIONS interface stays the same — swap UDFs for deep learning models without UI changes
- Snowflake Native App packaging enables Marketplace distribution
- Real OT integration: replace simulated task with Snowpipe from OPC-UA — everything downstream works unchanged

---

## Slide 13 — Technical Stack Summary

**Headline**: 100% Snowflake-Native — Zero External Services

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│   Category            Snowflake Feature        Count       │
│   ────────            ─────────────────        ─────       │
│   Data Pipeline       Dynamic Tables           14          │
│   Change Capture      Streams                  3           │
│   ML Predictions      SQL UDFs + Procedures    6 + 7       │
│   Native ML           Snowflake.ML             3 models    │
│   LLM Reasoning       Cortex Complete          llama3.1-70b│
│   RAG Search          Cortex Search            78 docs     │
│   AI Agent            Cortex Agent             5 tools     │
│   Semantic Layer      Cortex Semantic View     21 VQRs     │
│   Simulation          Monte Carlo UDF          300 paths   │
│   Frontend            Streamlit in Snowflake   8 pages     │
│   Notifications       SYSTEM$SEND_SNOWFLAKE    16 events   │
│   Scheduling          Tasks                    11          │
│   Security            Parameterized SQL        everywhere  │
│   Cost Governance     Resource Monitor         250 cr/mo   │
│   FinOps              ACCOUNT_USAGE views      6 panels    │
│                                                            │
│   Built with CoCo:   sql-author, streamlit-in-workspaces, │
│                       agent-studio, machine-learning,      │
│                       snowflake-tasks, data-governance     │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## Slide 14 — Judging Criteria Recap

**Headline**: How MFGPulse AI Meets Each Criterion

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│  REAL-WORLD RELEVANCE                                      │
│  ✓ 6 personas modeled after real manufacturing roles       │
│  ✓ Closed-loop procurement (ATP → PO → supplier → track)  │
│  ✓ Cost-of-inaction analysis on every prediction           │
│  ✓ Shift handover, notification routing, RBAC              │
│                                                            │
│  TECHNICAL EXECUTION                                       │
│  ✓ 100% Snowflake-native (Dynamic Tables, Cortex AI,      │
│    Snowflake ML, Streams, Tasks, Streamlit)                │
│  ✓ 14-stage auto-refreshing pipeline, no manual ETL       │
│  ✓ Cortex Agent with genuine 5-tool orchestration          │
│  ✓ Parameterized SQL, resource monitor, 80+ tests (8 test files)  │
│  ✓ FinOps dashboard with ACCOUNT_USAGE cost visibility     │
│                                                            │
│  SOLUTION COMPLETENESS                                     │
│  ✓ End-to-end: Sense→Converge→Predict→Diagnose→           │
│    Decide→Act→Track→Learn                                  │
│  ✓ 8 pages, 12 models, 16 notification event types         │
│  ✓ Digital Twin with 300 Monte Carlo simulations           │
│  ✓ Bulk WO/PO operations with ATP validation               │
│  ✓ Test suite in Admin Panel, 12 documentation files       │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## Slide 15 — Closing

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│           ⚙️  MFGPulse AI                                  │
│                                                            │
│     "Every machine failure has a DNA.                      │
│      MFGPulse AI decodes it before                         │
│      the breakdown happens."                               │
│                                                            │
│     ─────────────────────────────────────────              │
│                                                            │
│     12 ML models  │  14 Dynamic Tables  │  5-Tool Agent    │
│     8 Pages  │  6 Personas  │  80+ Tests  │  0 External    │
│                                                            │
│     100% Snowflake-Native                                  │
│     Built with CoCo (Cortex Code)                          │
│                                                            │
│     Thank You                                              │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

---

## Appendix Slides (if time permits or Q&A)

### A1 — Notification System Architecture
- 16 event types, LOG_APP_NOTIFICATION dispatcher, NOTIFICATION_SETTINGS table, admin-configurable per event, email + in-app dual delivery

### A2 — Monte Carlo Digital Twin Detail
- 100 paths per scenario, physics-based degradation projection, failure probability at 3/7/14 days, P10/P50/P90 RUL bounds, part arrival vs failure timing

### A3 — Semantic View & VQR Detail
- 6 tables mapped, 17 verified query representations, text-to-SQL accuracy via VQRs

### A4 — Test Suite Detail
- 11 categories, 80+ tests, acceptance criteria (>= 95% pass rate), runnable from Admin Panel

### A5 — Object Inventory
```
Schemas: 7  |  Tables: 30 + 14 DTs = 44  |  Views: 31  |  Models: 12
UDFs: 6  |  Procedures: 27  |  Streams: 3  |  Tasks: 11
Cortex Search: 1  |  Semantic View: 1  |  Agent: 1
Pages: 8  |  Personas: 6  |  Events: 16  |  Files: 82
Admin: 12 sections (incl. Simulation + User Mgmt + FinOps)
```

---

## Slide 16 — Build Cost & Efficiency

**Headline**: Built in Under 39 Hours for 91 Credits — 6 Credits of Actual Compute

```
┌────────────────────────────────────────────────────────────┐
│                                                            │
│   BUILD COST                                               │
│   ──────────                                               │
│                                                            │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│   │    91.42      │  │    6.02      │  │   221/400    │   │
│   │ Total Credits │  │  Warehouse   │  │  Remaining   │   │
│   │    Used       │  │  Only        │  │  (55% left)  │   │
│   └──────────────┘  └──────────────┘  └──────────────┘   │
│                                                            │
│   Credit Breakdown:                                        │
│   ┌────────────────────────────────────────────────────┐   │
│   │  CoCo (Cortex Code)      85.11 cr   93.1%  ██████ │   │
│   │  COMPUTE_WH (X-SMALL)     6.02 cr    6.6%  ▌      │   │
│   │  Container Services        0.28 cr    0.3%         │   │
│   │  AI Functions              0.01 cr    0.0%         │   │
│   │  Cortex Search            ~0.00 cr    0.0%         │   │
│   └────────────────────────────────────────────────────┘   │
│                                                            │
│   The entire Snowflake infrastructure — 35 tables,         │
│   13 Dynamic Tables, 12 ML models, 5 UDFs, 13 procedures, │
│   Cortex Search, and all queries — cost 6.02 credits       │
│   on an X-SMALL warehouse.                                 │
│                                                            │
│   Ongoing cost: < 1 credit/day (app + DTs + Cortex Search) │
│                                                            │
│   BUILD TIMELINE                                           │
│   ──────────────                                           │
│                                                            │
│   ┌──────────────┐  ┌──────────────┐  ┌──────────────┐   │
│   │   ~39 hrs     │  │   32,539     │  │    1.6 hrs   │   │
│   │ Wall Clock    │  │   Queries    │  │  SQL Exec    │   │
│   │ (2 days)      │  │  Executed    │  │   Time       │   │
│   └──────────────┘  └──────────────┘  └──────────────┘   │
│                                                            │
│   What 91.42 credits built:                                │
│   82 files │ 7 schemas │ 44 tables/DTs │ 31 views │       │
│   12 ML models │ 6 UDFs │ 27 procedures │ 8 pages │       │
│   1 Cortex Agent │ 1 Semantic View │ 80+ tests │ 12 docs  │
│   12-section Admin Panel (FinOps + Simulation + User Mgmt) │
│                                                            │
│   Account Budget:                                          │
│   ┌────────────────────────────────────────────────────┐   │
│   │  ████████████░░░░░░░░░░░  179/400 used (44.8%)    │   │
│   │  221 credits remaining — comfortable runway        │   │
│   └────────────────────────────────────────────────────┘   │
│                                                            │
└────────────────────────────────────────────────────────────┘
```

**Speaker notes**:
- Total build cost: 91.42 credits out of a 400-credit account budget (22.9%) — 221 credits remaining
- 93% of credits went to CoCo (the AI that co-authored the solution). Actual Snowflake compute was only 6.02 credits on the smallest warehouse size (X-SMALL)
- 32,539 queries executed in 95.6 minutes of SQL execution time across ~39 hours of wall clock
- This demonstrates that a production-grade predictive maintenance platform — with 12 ML models, 14 Dynamic Tables, a 5-tool AI Agent, 8 Streamlit pages, and 80+ test cases — can be built efficiently on Snowflake with CoCo as the development copilot
- The resource monitor (MFGPULSE_CREDIT_GUARD) ensures ongoing cost governance at 250 credits/month with auto-suspend at 90%
- Ongoing infrastructure costs under 1 credit/day — app, DT refreshes, Cortex Search combined
