# MFGPulse AI — User Guide

*Your complete guide to the Predictive Maintenance & OEE Command Center.*

---

## Table of Contents

1. [Getting Started](#getting-started)
2. [Personas and Navigation](#personas-and-navigation)
3. [Executive Dashboard](#executive-dashboard)
4. [Operations Center](#operations-center)
5. [WO/PO Management Console](#wopo-management-console)
6. [Maintenance Hub](#maintenance-hub)
7. [Procurement Dashboard](#procurement-dashboard)
8. [Digital Twin Simulator](#digital-twin-simulator)
9. [Admin Control Panel](#admin-control-panel)
10. [Maintenance Copilot](#maintenance-copilot)
11. [Notifications](#notifications)
12. [Common Workflows](#common-workflows)
13. [Tips and Best Practices](#tips-and-best-practices)
14. [FAQ](#faq)

---

## Getting Started

### Opening the App

Open the Streamlit app in Snowsight. You will see a user selector in the sidebar — choose your user profile to log in. The app automatically filters navigation to show only the pages relevant to your persona.

### Sidebar Controls

Every page includes a sidebar with:

- **User selector** — Switch between user profiles to see different persona views
- **Notification bell** — Shows unread notification count; click to expand and view/dismiss notifications
- **Refresh data** — Clears all cached data and reloads from Snowflake

### Understanding Color Codes

The app uses consistent color coding across all pages:

| Color | Meaning |
|---|---|
| **Red** | Critical — immediate attention required (Critical stage, CRITICAL_SHORTAGE, emergency WO, high severity alert) |
| **Orange** | Warning — action needed soon (Warning stage, EXPEDITE risk, corrective WO, medium severity) |
| **Blue** | Informational — monitor or scheduled (ORDER_NOW, open status, low severity) |
| **Green** | Healthy — no action needed (Healthy stage, NO_RISK, completed, preventive WO) |
| **Gray** | Inactive or cancelled |

---

## Personas and Navigation

MFGPulse AI supports 6 user personas. Each persona sees a curated set of pages and action permissions tailored to their role.

### Technician
**Focus**: Hands-on asset diagnostics and assigned work orders.

- **Primary pages**: Maintenance Hub (asset deep-dives, failure DNA), WO/PO Console (view your assigned WOs)
- **Key actions**: View work order details, check parts availability, ask the Copilot for diagnosis
- **Restrictions**: Cannot start/complete WOs (supervisor handles this), cannot see PO tab, no admin access

### Reliability Engineer
**Focus**: Failure pattern analysis and intervention planning.

- **Primary pages**: Maintenance Hub, Digital Twin (Monte Carlo simulation), WO/PO Console
- **Key actions**: Analyze failure DNA profiles, run what-if simulations, compare intervention strategies
- **Unique access**: Digital Twin simulator (not available to other non-admin personas)

### Shift Supervisor
**Focus**: Operational awareness and shift handover.

- **Primary pages**: Operations Center (fleet status, alert triage, shift handover), WO/PO Console
- **Key actions**: Start/complete work orders, triage alerts by severity, prepare shift handover summaries
- **Unique access**: Can manage WO status transitions (start, complete)

### Plant Manager
**Focus**: Plant-wide KPIs, cost analysis, and strategic oversight.

- **Primary pages**: Executive Dashboard (OEE, cost impact, ROI), Operations Center, Admin Panel
- **Key actions**: Review OEE trends, analyze maintenance costs, manage infrastructure, configure notifications
- **Unique access**: Executive Dashboard (financials), Admin Panel (infrastructure + notifications)

### Procurement Admin
**Focus**: Parts availability, supplier management, and purchase order lifecycle.

- **Primary pages**: Procurement Dashboard, WO/PO Console (full PO management)
- **Key actions**: Approve/reject POs, receive shipments, monitor supply chain risk, auto-generate POs
- **Unique access**: Full PO management (approve, reject, receive)

### Application Admin
**Focus**: Full platform administration and super-admin access.

- **Primary pages**: All 8 pages — every feature of the platform
- **Key actions**: Everything — manage infrastructure, configure notifications, run tests, manage WOs and POs, run simulations
- **Unique access**: Only persona with access to every page simultaneously

---

## Executive Dashboard

**Available to**: Shift Supervisor, Plant Manager, App Admin

The Executive Dashboard provides plant-wide KPIs and financial impact analysis — the page a Plant Manager opens first each morning.

### KPI Cards (Top Row)

| KPI | What It Means |
|---|---|
| **Plant OEE** | Overall Equipment Effectiveness across all lines (target: 85%+) |
| **Critical Assets** | Count of assets in Critical degradation stage |
| **Cost Avoided** | Financial impact prevented by predictive maintenance |
| **Maintenance ROI** | Return on maintenance investment (cost avoided / total spend) |
| **Early Detection Days** | Average days of advance warning before failures |
| **Emergency WOs** | Count of emergency work orders (lower is better) |
| **Total WO Spend** | Total cost across all work orders |
| **OEE Improvement** | Potential OEE gain if all losses are addressed |

### Charts and Tables

- **Executive Summary** (expander) — LLM-generated boardroom-ready narrative via Cortex Complete, synthesizing plant OEE, critical assets, costs, and risks into a structured executive brief. Cached per session — click "Regenerate" for a fresh summary.
- **OEE by Production Line** — Grouped bar chart breaking down Availability, Performance, and Quality per line. Helps identify which line is underperforming and why.
- **OEE Loss Attribution** — Which assets cause the most availability, performance, and quality loss. Prioritize maintenance on these assets for maximum OEE improvement.
- **OEE Trend Analysis** — Daily multi-line chart showing OEE trends over time per production line, with a dashed plant-wide average and a green 85% target reference line. Use the metric selector dropdown to switch between OEE, Availability, Performance, and Quality views. Covers 185 days of data. Useful for identifying seasonal patterns, the impact of maintenance campaigns, and whether the plant is trending toward or away from the 85% target.
- **Maintenance Cost by Asset** — Vertical bars color-coded by degradation stage. Tooltip shows failure mode, RUL, and cost breakdown.
- **Asset Risk Matrix** — Sortable table with stage, failure mode, RUL, action window, estimated failure cost, repair cost, cost of inaction, and parts status.
- **Work Order Cost Breakdown** — Donut chart by WO type (emergency / corrective / preventive) with summary KPIs: open WO count, emergency WO count, total spend.
- **Supply Chain Risk Overview** — KPI counters (Critical Shortage, Expedite, Order Now, Open POs, At-Risk Cost), a risk distribution donut chart showing the proportion of each risk level, a lead time gap bar chart showing gap days per at-risk asset color-coded by risk severity, and a detail table of at-risk items with ATP, lead time, gap, risk level, and recommended action.

---

## Operations Center

**Available to**: All personas except Technician (who starts at Maintenance Hub)

The Operations Center provides real-time operational awareness — the page a Shift Supervisor monitors throughout a shift.

### KPI Bar

Seven KPI cards at the top: Total assets, Critical count, Active alerts, Open WOs, Emergency WOs, WO Completion rate, Parts at risk.

### Five Segmented Views

**Fleet Status** — All 10 assets in a sortable table with degradation stage badge, RUL (hours), health score (0-100), failure mode, and **ACTION_WINDOW** badge showing how many hours remain before the next required intervention. Uses the PREDICTIONS_WITH_COST view for cost-aware prioritization.

**Alert Triage** — Active alerts sorted by severity (Critical > Warning > Info). Each alert shows severity badge, asset name, failure mode, message, and RUL. Use this to prioritize technician dispatch.

**Shift Handover** — Designed for end-of-shift reporting:
- Critical action count, warnings, current plant OEE, total active alerts
- Procurement readiness panel showing parts with shortages and open POs
- **LLM-generated shift briefing** — An AI-produced narrative summary via Cortex Complete (llama3.1-8b) that synthesizes all critical items, warnings, and recommendations into a handover brief. Cached per session; click "Regenerate" for a fresh briefing.

**Work Orders** — Open work orders with type, priority, status, assigned technician, and estimated cost. Filter and sort to track progress.

**Sensor Feed** — Live 24-hour sensor data from all assets:
- **Data freshness badge** — Shows **LIVE** (< 10 min), **RECENT** (10-60 min), or **STALE** (> 60 min) based on Snowflake server time (`CURRENT_TIMESTAMP()::TIMESTAMP_NTZ`) comparison against the latest reading timestamp
- **Asset filter** — Select a single asset or view all assets simultaneously
- **Time range** — Last 1h, 6h, 12h, or 24h (client-side filtering from a single cached query)
- **Latest reading KPIs** — Vibration magnitude (mm/s), Temperature (°C), RPM, Pressure (bar), Current (A), Acoustic (dB)
- **Channel time-series** — Select from Vibration, Temperature, RPM, or Current to view a multi-line chart over time, one line per asset
- **Raw data export** — Expandable table with all sensor readings for the selected asset/time range (up to 200 rows)

---

## WO/PO Management Console

**Available to**: All personas (with varying permissions)

The unified console for managing Work Orders and Purchase Orders. What you can do depends on your persona.

### Permissions by Persona

| Persona | View WOs | Start/Complete WOs | View POs | Approve/Reject/Receive POs |
|---|---|---|---|---|
| Technician | Own WOs only | No | No | No |
| Reliability Engineer | All | No | View only | No |
| Shift Supervisor | All | Yes | View only | No |
| Plant Manager | All | Yes | All | Yes |
| Procurement Admin | All | No | All | Yes |
| App Admin | All | Yes | All | Yes |

### Work Orders Tab

- **Filters**: Status (open, in_progress, completed, cancelled), Type (emergency, corrective, preventive), Priority, Asset
- **Technician view**: "My Work Orders" section appears first, showing only WOs assigned to you, followed by all other WOs
- **WO cards**: Each card shows WO ID, type badge (color-coded), status badge, priority badge, asset name, assigned technician, estimated cost, created date, notes, and **aging warning** (amber > 48h, red > 72h for open/in_progress WOs)
- **Parts badge**: Each WO requiring a part shows a reservation-aware badge:
  - **RESERVED** (green) — Part reserved for this WO in PART_RESERVATIONS
  - **NO_RISK** (green) — ATP > 0, no reservation needed yet
  - **ORDER_NOW** / **EXPEDITE** / **CRITICAL_SHORTAGE** (color-coded) — Part at risk, procurement action needed

**Start Work** — ATP-gated flow:
  - If part required and ATP ≤ 0 with no open PO → Start is disabled; an "Alert Procurement" button sends a PART_SHORTAGE_ALERT notification
  - If part required and ATP ≤ 0 but a PO is in progress → Start allowed with a warning ("Parts incoming...")
  - If part available → Normal start with automatic part reservation via `RESERVE_PART_FOR_WORK_ORDER`

**Complete Work** — 2-step confirmation flow:
  1. Click "Complete" → A confirmation panel expands inline
  2. Select "Was the part used?" (Yes — consumed / No — returned to stock)
  3. Select "Root cause confirmed" from dropdown (bearing_wear, thermal_degradation, imbalance, misalignment, electrical_fault, false_alarm, other)
  4. Click "Confirm completion" → Updates WORK_ORDERS with ROOT_CAUSE_CONFIRMED and PART_USED, releases or consumes the part reservation in PART_RESERVATIONS, decrements PARTS_INVENTORY if consumed, logs prediction feedback via ML_MODELS.LOG_FEEDBACK, and triggers WO_COMPLETED notification

**Cancel Work Order** — Available on `open` WOs only:
  1. Click "Cancel WO" → Confirmation prompt appears
  2. Click "Confirm cancel" → Sets status to `cancelled`, releases any active part reservations, triggers WO_CANCELLED notification

- **Reassign**: Expand the "Reassign / Follow-up" panel on any open or in_progress WO to change the assigned technician. Sends a WO_REASSIGNED notification.
- **Follow-up email**: From the same panel, add an optional note and click "Send follow-up" to trigger a WO_FOLLOWUP notification (in-app + email if configured). Use this to escalate, add urgency context, or nudge an assignee.

**Bulk Operations** (Shift Supervisor, Plant Manager, App Admin):

Toggle "Select multiple" above the WO list to enable multi-select mode. Checkboxes appear next to each active (non-completed) work order card. Use "Select all visible" to check all filtered WOs, or check individual cards.

The bulk action bar appears when items are selected:
- **Bulk Start** — Starts all selected open WOs that pass ATP validation. WOs blocked by unavailable parts (ATP=0, no open PO) are skipped with a count reported. Each eligible WO gets a part reservation if ATP > 0.
- **Bulk Complete** — For selected in-progress WOs. Prompts once for shared "Was the part used?" and "Root cause confirmed" values, then applies to all selected WOs. Each WO goes through the full completion flow (reservation release, inventory update, sensor injection, feedback logging).
- **Deselect all** — Clears selection and exits any confirmation flow.

### Purchase Orders Tab

- **Filters**: Status, Risk level, Supplier
- **PO cards**: Each card shows PO ID, supplier name, status badge, risk badge, part name, asset, quantity, cost, required-by date, and expected arrival
- **Approve**: Moves PO to approved status. Triggers PO_APPROVED notification.
- **Reject** — 2-step flow with reason capture:
  1. Click "Reject" → A text area expands inline requiring a rejection reason
  2. Enter the reason (required, cannot be blank) and confirm
  3. Updates PURCHASE_ORDERS with REJECTION_REASON, REJECTED_BY, REJECTED_AT, and status → cancelled
  4. Sends PO_REJECTED notification (targets Procurement Admin + Shift Supervisor + Plant Manager)
- **Mark ordered**: Transitions from `approved` → `ordered` (tracks fulfillment pipeline)
- **Mark shipped**: Transitions from `ordered` → `shipped`
- **Receive**: Moves PO to received status, **increments PARTS_INVENTORY.QUANTITY_ON_HAND** for the received parts. Triggers PO_RECEIVED notification.

**Bulk Operations** (Procurement Admin, Plant Manager, App Admin):

Toggle "Select multiple" above the PO list. Checkboxes appear next to each active (non-received/cancelled) PO card.

The bulk action bar shows context-aware buttons based on selected PO statuses:
- **Bulk Approve** — Approves all selected pending_approval POs. Each triggers a PO_APPROVED notification.
- **Bulk Reject** — For pending_approval POs. Prompts for a shared rejection reason (required), then rejects all selected with the same reason. Impact notifications sent per PO.
- **Bulk Mark Received** — Receives all selected POs (approved/ordered/shipped). Increments inventory per PO.
- **Bulk Mark Ordered / Shipped** — Transitions selected POs to the next status in the pipeline.
- **Deselect all** — Clears selection.

### WO Analytics Tab

- **Count by Type** — Donut chart: how many emergency vs corrective vs preventive WOs
- **Cost by Type** — Bar chart: total spend per WO type
- **Cost by Asset** — Bar chart: which assets consume the most maintenance budget
- **Summary metrics**: Average cost per WO type, overall completion rate

---

## Maintenance Hub

**Available to**: Technician, Reliability Engineer, Shift Supervisor, Plant Manager, Procurement Admin, App Admin

The Maintenance Hub is the deep asset-level diagnostic page — where technicians and reliability engineers spend most of their time.

### Fleet Health Matrix

A table of all 10 assets showing:
- **Stage** — Degradation stage badge (Critical / Warning / Healthy)
- **RUL** — Remaining Useful Life in hours
- **Fatigue** — Hidden fatigue level (healthy / accumulating / high / critical)
- **Health** — Composite health score (0-100)
- **WO Count** — Total and open work orders for the asset

Click any asset (or use the dropdown) to open the deep-dive.

### Asset Deep-Dive

**KPI Row 1** (4 cards):
- **Stage** — Degradation stage with color badge
- **RUL** — Hours remaining with contextual delta ("Critical" if < 72h, "Low" if < 168h)
- **Health Score** — 0-100 composite score
- **Failure Mode** — Predicted failure mode with confidence percentage

**KPI Row 2** (4 cards):
- **Degradation** — Score (0-1) with label ("Critical" > 0.7, "Moderate" > 0.4, "Low")
- **Fatigue** — Score (0-1) with fatigue level label
- **Stress Index** — Physics-based stress metric
- **Transition Probability** — Likelihood of moving to a worse stage

**Failure DNA Chart** — 5 normalized risk signals displayed as color-coded horizontal bars:
- Degradation score, Fatigue score, Transition probability, Stress index, Health loss (inverted health)
- Red bars (> 0.7) indicate critical signals, orange (> 0.4) warning, green is healthy

### Bottom Panels (Two Columns)

**Left — Parts Status**: Parts required for this asset with:
- Part name, ATP (Available-to-Promise), on-hand quantity
- Risk badge (CRITICAL_SHORTAGE / EXPEDITE / ORDER_NOW / NO_RISK)
- Lead time, supply gap, expected arrival date
- **PO guard**: If an open PO already exists for this part+asset, shows "PO in progress" instead of the Create PO button to prevent duplicates
- "Create PO" button for one-click purchase order generation (when no open PO exists)

**Right — Alerts & Maintenance History** (combined container):
- **Active Alerts**: Severity badges, alert messages, triggered conditions
- **Divider**
- **Recent Maintenance**: Timeline of maintenance work shown as cards with WO ID, technician name, type badge, priority badge, timestamp, and notes

---

## Procurement Dashboard

**Available to**: Technician, Reliability Engineer, Shift Supervisor, Plant Manager, Procurement Admin, App Admin

### Five Segmented Views

**Procurement Recommendations** — Risk-sorted asset cards showing:
- Risk level badge (CRITICAL_SHORTAGE, EXPEDITE, ORDER_NOW, NO_RISK)
- Part name, ATP, lead time, supply gap, supplier name
- Competing asset count and net position for shared parts
- Buffer status badge (SURPLUS, TIGHT, DEFICIT)
- Incoming PO info (quantity and arrival date)
- One-click "Create PO" button (generates a purchase order with auto-populated fields)

**Planned POs** — Dynamically generated purchase order recommendations aggregated by part:
- Consolidates multiple assets needing the same part into a single planned PO
- Priority score based on RUL urgency (40%), deficit severity (30%), competing assets (20%), criticality (10%)
- Order-by deadline and expedite deadline with countdown indicators
- Auto-conversion: PPOs automatically convert to actual POs if no manual action is taken before the order-by deadline (12-hour check cycle, suspended by default)
- Manual actions: "Expedite" (creates PO with EMERGENCY priority) or "Convert now" (creates PO at current priority)
- "Run auto-convert now" button for on-demand batch conversion

**Stock Insights** — Per-part inventory health:
- Buffer KPIs (Deficit, Tight, Surplus counts, total demand vs total ATP)
- Stock vs demand chart per part (ATP, demand, incoming POs)
- Part contention map for parts shared by multiple at-risk assets
- Estimated days until stockout

**Parts Inventory** — Full ATP table:
- Part ID, Part name, On-hand, Reserved, ATP, Lead time (days), Unit cost, Supplier
- Sorted by ATP ascending (lowest availability first)

**Purchase Orders** — Open POs with auto-generate button for bulk PO creation based on procurement recommendations.

---

## Digital Twin Simulator

**Available to**: Reliability Engineer, App Admin

The Digital Twin runs Monte Carlo simulations to compare intervention strategies before committing resources.

### How It Works

1. **Select an asset** from the dropdown (defaults to a Warning-stage asset for meaningful comparison — assets with degradation > 0.8 show near-certain failure regardless of intervention)
2. **Review asset KPIs**: Stage, RUL, Degradation, Fatigue
3. **Configure 3 scenarios**:
   - **Scenario A** — Do Nothing (baseline, no intervention)
   - **Scenario B** — Reduce Load (adjust load reduction slider)
   - **Scenario C** — Custom (load reduction, maintenance delay, RPM reduction sliders)
4. **Run simulation**: 100 stochastic paths per scenario (300 total) via the `SIMULATE_FAILURE_TWIN` UDF

### Results

- **Scenario Comparison Table**: Side-by-side RUL (P10/P50/P90 percentiles), failure probability at 3/7/14 days, percentage of paths that fail before next maintenance, expected cost, and recommended intervention
- **Failure Probability Timeline**: Line chart showing probability curves across 3, 7, and 14 days for all scenarios. Lower curves = better intervention.
- **RUL Distribution Comparison**: Grouped bar chart of P10/P50/P90 per scenario. Higher bars = more remaining life.
- **Part Arrival vs Failure Timing**: Compares part lead time against median simulated RUL with margin assessment:
  - SAFE — Parts arrive well before predicted failure
  - TIGHT — Parts arrive close to predicted failure
  - ARRIVES AFTER FAILURE — Parts arrive too late; escalation needed

### Important Note

Assets in advanced degradation (> 0.8) will show near-100% failure probability across all scenarios. This is expected — the simulation correctly models that severely degraded assets have exhausted their intervention window. Select a Warning-stage or Healthy asset to see meaningful differentiation between scenarios.

---

## Admin Control Panel

**Available to**: Plant Manager, App Admin

The Admin Panel provides infrastructure monitoring, notification management, and test execution through 8 tabbed sections.

### Tasks
Monitor the **11-task automation DAG** and 2 legacy tasks. The DAG runs on a dedicated **MFGPULSE_AUTOMATION_WH** warehouse (isolated from interactive queries on COMPUTE_WH). Tasks execute in strict sequential order:

1. **MFGPULSE_AUTOMATION_DAG** (root) — Calls `SIMULATE_ALL_FEEDS_RANDOM` to generate unified sensor + production data with persistent degradation and intermittent faults
2. **DAG_REFRESH_FATIGUE** — Calls `REFRESH_FATIGUE_SCORES` to recompute fatigue for all assets
3. **DAG_REFRESH_DTS** — Calls `REFRESH_ALL_DTS` to force-refresh all 13 dynamic tables
4. **DAG_GENERATE_WOS** — Calls `AUTO_GENERATE_WORK_ORDERS` to create WOs for critical assets
5. **DAG_GENERATE_POS** — Calls `AUTO_GENERATE_PURCHASE_ORDERS` for parts-at-risk
6. **DAG_CONVERT_PPOS** — Calls `AUTO_CONVERT_PLANNED_POS` to convert overdue planned POs

View task state (STARTED/SUSPENDED), schedule (720 min), warehouse, and predecessors. Resume or suspend tasks with one click. The DAG root has a 720-minute (12h) schedule; child tasks are triggered sequentially via the `AFTER` clause.

### Dynamic Tables
All 13 dynamic tables with row counts, storage bytes, target lag, refresh mode, and current state. Manually trigger a refresh for any table.

### Streams
3 CDC streams (sensor readings, maintenance logs, work orders) with stale/active status.

### ML Models
12 registered ML models with performance metrics (F1 score, precision, recall where applicable). Also shows Cortex Search service status and document count.

### Cortex Services
Status of the Cortex Agent (MAINTENANCE_COPILOT), Semantic View, and Search service.

### Notifications
Per-event configuration for all 7 notification event types:
- **Email toggle** — Enable/disable email delivery
- **In-app toggle** — Enable/disable in-app notifications
- **Email recipients** — Comma-separated email addresses
- **Target personas** — Multi-select which personas receive notifications
- **Priority** — NORMAL or HIGH
- **Test button** — Send a test notification to verify configuration
- **Notification log** — View recent notifications with timestamps and delivery status

### Test Suite
Run the automated test suite directly from the Admin Panel:
- 6 test categories (Data Integrity, ML Pipeline, Procurement, Notifications, WO/PO Lifecycle, Simulation Scenarios)
- Select a category, click "Run Tests" to execute
- Progress bar shows real-time execution status
- Summary KPIs: Total tests, Passed, Failed, Pass rate
- Detailed results table with test name, status, and assertion details
- **Acceptance criteria**: >= 95% pass rate across all categories

### FinOps
Infrastructure cost monitoring for the MFGPulse AI platform — all data pulled from Snowflake system views (read-only, no new tables needed).

- **Credit summary KPIs** — Warehouse, CoCo, Container Services, AI Functions, and total credits consumed over the last 30 days
- **Resource monitors** — Two monitors displayed:
  - **MFGPULSE_CREDIT_GUARD** — Protects COMPUTE_WH (interactive queries, Streamlit). Shows quota, used, remaining with progress bar.
  - **MFGPULSE_AUTOMATION_GUARD** — Protects MFGPULSE_AUTOMATION_WH (DAG tasks, DT refreshes). Shows quota, used, remaining with progress bar.
  - Both display threshold labels (alert at 75%, suspend at 90%, hard stop at 100%)
- **Daily warehouse credit trend** — Stacked bar chart showing both COMPUTE_WH and MFGPULSE_AUTOMATION_WH daily credit consumption (last 30 days)
- **Credit breakdown by service type** — Horizontal bar chart of all Snowflake service types (warehouse, CoCo, containers, AI functions, Cortex Search, etc.) ranked by credit consumption
- **Query cost breakdown** — Top 12 query types by execution time, showing query count, total execution minutes, and cloud services credits consumed
- **Top tables by storage** — Largest tables/DTs by MB, with row counts
- **Dynamic table refresh history** — Per-DT refresh count, rows inserted, and average refresh duration in seconds
- **Task execution history** — Scheduled task run count, credits consumed, average duration, and last run time (shows helpful message when tasks are suspended)

### Simulation
Configurable sensor feed and production data generator for testing clean and fault scenarios.

- **Asset selector** — Target a single asset or all 10 at once
- **Scenario selector** — Clean operation, Bearing wear, Thermal degradation, Imbalance, or Misalignment
- **Severity slider** (0.0-1.0) — Controls degradation intensity for fault scenarios (hidden for clean). 0 = barely detectable onset, 1 = critical failure
- **Hours input** — Duration of simulated data (1-168 hours, default 12)
- **Estimated cost** — Auto-calculated before execution: row count, production records, and estimated COMPUTE_WH credits
- **Scenario reference** — Collapsible table showing each failure mode's sensor signature (which channels are affected and how)
- **Run simulation** — Calls `SIMULATE_SENSOR_FEED_CONFIGURABLE` with progress indicator, logs to SIMULATION_CONFIG table
- **Simulation history** — Table of recent runs with asset, scenario, severity, status, rows generated, estimated credits, timestamps

### User Management
Add, edit, and deactivate application users.

- **User summary KPIs** — Total users, active count, persona count
- **User cards** — Each user shown with username, email, persona badge, active status, and line assignment. Expand to edit persona (selectbox from 6 options), email, line ID, and active toggle.
- **Add new user** — Form with username, email, persona selector, and optional line ID. Auto-generates USER_ID.
- Changes take effect immediately — edited personas update the login screen and page access on next login.

### Object Inventory
Full Snowflake object counts and per-schema breakdown — tables, views, procedures, UDFs, streams, tasks, dynamic tables.

---

## Maintenance Copilot

**Available to**: All personas

The Copilot is a natural-language AI assistant powered by Snowflake Cortex that can answer questions about your plant, run diagnostics, search maintenance history, simulate scenarios, and generate work orders — all through conversation.

### Getting Started

When you open the Copilot, you'll see a role-specific welcome greeting. For example:
- **Technician**: "Hey there! I'm your Maintenance Copilot..."
- **Plant Manager**: "Welcome. I'm the MFGPulse AI Copilot, ready to help with plant analytics..."
- **App Admin**: "Welcome, Admin. I'm the MFGPulse AI Copilot with full platform access..."

### Quick Question Pills

Below the chat, you'll see suggested question pills tailored to your persona. Click any pill to instantly ask that question — the pill text appears as your message and the Copilot begins responding with a progress indicator.

### Two Response Paths

The Copilot uses two different AI paths depending on your question:

**Fast Path (Data Questions)** — For questions about plant metrics, asset status, OEE, etc. Uses pre-loaded plant data + Cortex Complete (llama3.1-70b) for immediate answers. You'll see "Retrieving plant data..." in the status indicator.

**Agent Path (Complex Tasks)** — For diagnostics, simulations, work orders, purchase orders, and maintenance history searches. Routes to the 7-tool Cortex Agent. You'll see "Searching maintenance history..." or "Running ML models..." depending on the tool being used.

### Agent Trigger Keywords

Use these keywords to activate specific agent tools:

| Keyword | What It Does | Example |
|---|---|---|
| "run diagnosis" / "full diagnosis" / "7-model" | Runs all 7 ML models on an asset | "Run a full diagnosis on ASSET_005" |
| "generate work order" / "create work order" | Creates a new work order | "Create a preventive WO for Fan F1" |
| "simulate" / "what-if" / "monte carlo" | Runs Monte Carlo simulation | "What if we reduce load on ASSET_001 by 30%?" |
| "search maintenance" / "history" / "what repairs" | Searches maintenance logs via RAG | "What repairs were done on Compressor A1?" |
| "OEE" / "trend" / "how many" | Text-to-SQL analytics query | "What's the OEE for Line 1 this week?" |

### Session Management

- **New Session** — Click "New session" in the sidebar to start a fresh conversation
- **Previous Sessions** — Past conversations are listed in the sidebar; click to restore any previous session
- **Sessions persist** for the duration of your Streamlit session (browser tab)

### Tips

- For casual greetings ("hi", "hello"), the Copilot responds conversationally without loading plant data
- Be specific about asset IDs when asking for diagnostics — "ASSET_005" or asset names like "Compressor A1"
- The Copilot remembers context within a session, so you can ask follow-up questions

---

## Notifications

MFGPulse AI has a dual notification system: **email** (via Snowflake-managed integration) and **in-app** (persona-targeted bell icon in the sidebar).

### How Notifications Work

1. An action occurs (e.g., a work order is started, a PO is approved)
2. The system calls `LOG_APP_NOTIFICATION` with the event type, title, message, and entity ID
3. The procedure reads `NOTIFICATION_SETTINGS` to determine:
   - Is email enabled for this event? → Send via MFGPULSE_EMAIL integration
   - Is in-app enabled? → Create a notification record per target persona
4. In-app notifications appear in the sidebar bell icon with an unread count

### Notification Events

| Event | Triggered When |
|---|---|
| WO_CREATED | A new work order is created |
| WO_STARTED | A work order is started (status → in_progress) |
| WO_COMPLETED | A work order is completed |
| PO_CREATED | A new purchase order is created |
| PO_APPROVED | A purchase order is approved |
| PO_REJECTED | A purchase order is rejected |
| PO_RECEIVED | A purchase order shipment is received |
| WO_REASSIGNED | A work order is reassigned to a different technician |
| WO_FOLLOWUP | A follow-up/escalation is sent for a work order |

### Managing Notifications (Admin)

Go to **Admin Panel → Notifications** to configure per-event settings. See the [Admin Control Panel](#admin-control-panel) section for details.

---

## Common Workflows

### Workflow 1: Responding to a Critical Alert

```
1. Operations Center → Alert Triage → Identify critical alert
2. Maintenance Hub → Select the flagged asset → Review Failure DNA
3. Copilot → "Run a full diagnosis on ASSET_XXX"
4. Digital Twin → Compare intervention strategies (if Reliability Engineer)
5. WO/PO Console → Create work order
6. Procurement → Verify parts availability, create PO if needed
7. Notifications sent to supervisors and managers
```

### Workflow 2: Shift Handover

```
1. Operations Center → Shift Handover tab
2. Review: Critical actions needed, warnings, current OEE
3. Check procurement readiness (parts shortages, open POs)
4. Brief incoming supervisor on priority items
```

### Workflow 3: Procurement Cycle

```
1. Procurement Dashboard → Procurement Recommendations
2. Review CRITICAL_SHORTAGE and EXPEDITE items
3. Click "Create PO" for needed parts (guard prevents duplicates if PO already exists)
4. WO/PO Console → PO tab → Approve the new PO
5. Monitor expected arrival date vs asset RUL
6. WO/PO Console → Receive when shipment arrives
7. Notification confirms receipt
```

### Workflow 4: Using the Digital Twin

```
1. Digital Twin → Select a Warning-stage asset
2. Review current KPIs (stage, RUL, degradation, fatigue)
3. Set Scenario B: Reduce load by 20%
4. Set Scenario C: Reduce load by 30% + delay maintenance
5. Compare failure probability timelines
6. Choose the intervention with best cost/risk tradeoff
7. Create a work order based on the recommended strategy
```

### Workflow 5: Running Tests (Admin)

```
1. Admin Panel → Test Suite section
2. Select a test category (e.g., "Data Integrity")
3. Click "Run Tests"
4. Monitor progress bar
5. Review pass/fail results and KPI summary
6. Target: >= 95% pass rate across all categories
```

---

## Tips and Best Practices

### For Technicians
- Start each shift at the **Maintenance Hub** to check your asset assignments
- Use the **Copilot** for quick diagnostics — "What's wrong with ASSET_003?" is faster than navigating multiple pages
- Check the **notification bell** regularly for new work order assignments

### For Reliability Engineers
- Use the **Digital Twin** to justify maintenance recommendations with data — the scenario comparison table provides cost estimates for each intervention strategy
- The **Failure DNA chart** in Maintenance Hub reveals which risk signals are driving predictions
- Ask the Copilot to "run a full diagnosis" before scheduling preventive maintenance

### For Shift Supervisors
- Keep the **Operations Center** open during shifts for real-time fleet monitoring
- The **Shift Handover** view is designed to generate handoff notes — review it 30 minutes before shift change
- Use the **WO/PO Console** to track work order progress and start/complete WOs as technicians report status

### For Plant Managers
- Start with the **Executive Dashboard** for a plant-wide health snapshot
- Use the **OEE Trend Analysis** chart to track whether OEE is trending toward the 85% target — switch between OEE/Availability/Performance/Quality to pinpoint which component is dragging performance
- Review the **Supply Chain Risk Overview** donut chart and lead time gap chart to quickly assess procurement exposure without drilling into the Procurement page
- Drill into the **Asset Risk Matrix** to identify high cost-of-inaction items
- Review **WO Cost Breakdown** trends — a high emergency-to-preventive ratio indicates reactive maintenance patterns

### For Procurement Admins
- Process the **Procurement Recommendations** daily — cards now show competing assets, buffer status (DEFICIT/TIGHT/SURPLUS), and incoming PO info
- Use the **Stock Insights** tab to visualize demand vs supply per part, identify contention (multiple assets needing the same part), and track estimated days until stockout
- The **ATP** (Available-to-Promise) view shows real availability after reservations — parts are auto-reserved when WOs are started
- Use the **WO/PO Console** for approval workflows — don't let POs sit in pending_approval

### General Tips
- **Refresh data** in the sidebar clears all caches and reloads from Snowflake
- All timestamps are in Snowflake NTZ (no timezone) — the app uses `CURRENT_TIMESTAMP()::TIMESTAMP_NTZ` for server-time comparisons
- Dynamic tables refresh with a 1-hour target lag — for immediate predictions, use the Admin Panel to manually refresh LIVE_PREDICTIONS

---

## FAQ

**Q: Why do I see fewer pages than other users?**
Pages are filtered by persona. Each persona sees only the pages relevant to their role. If you need access to additional pages, ask your admin to update your persona assignment, or log in as Application Admin.

**Q: The Digital Twin shows 100% failure probability for every scenario — is it broken?**
No. Assets with advanced degradation (> 0.8) have exhausted their intervention window and will show near-certain failure regardless of scenario. This is the correct simulation result. Select a Warning-stage or Healthy asset to see meaningful differentiation between strategies.

**Q: How do I enable email notifications?**
Go to Admin Panel → Notifications → Select an event type → Toggle "Email" ON → Enter recipient email addresses → Click Save. The app uses Snowflake's MFGPULSE_EMAIL integration for delivery.

**Q: How often does the data refresh?**
Dynamic tables use a 1-hour target lag. The 11-task automation DAG runs every 12 hours (720 min) to simulate new sensor/production data and refresh downstream objects. Click "Refresh data" in the sidebar for an immediate cache clear (reads latest from Snowflake). In-app notifications refresh every 15 seconds. Other data caches have a 2-minute TTL.

**Q: What are the two warehouses for?**
**COMPUTE_WH** handles interactive queries (Streamlit app, ad-hoc SQL, DT refreshes). **MFGPULSE_AUTOMATION_WH** handles background automation (DAG tasks, scheduled procedures). Separating them ensures background jobs don't compete with interactive users for compute. Each warehouse has its own resource monitor.

**Q: What happens when I reject a PO?**
A rejection reason is required. The PO is cancelled with the reason, rejector, and timestamp recorded. If the rejected PO was linked to an active work order, the Shift Supervisor receives an impact notification so they can take corrective action.

**Q: What happens when I complete a work order?**
You'll be asked whether the part was consumed or returned to stock, and to confirm the root cause. The part reservation is automatically released (returned to ATP) or consumed based on your answer. The WO is marked completed with the confirmed root cause for analytics.

**Q: Can I ask the Copilot anything?**
The Copilot is trained on plant data and maintenance context. It can answer questions about asset health, OEE, maintenance history, failure predictions, and run simulations. For casual greetings, it responds conversationally. For questions outside the plant domain, it will note its scope.

**Q: How do I generate a work order from the Copilot?**
Ask: "Generate a preventive work order for ASSET_005" or "Create an emergency WO for Compressor A1". The agent will create the WO with auto-populated fields from the prediction data.

**Q: What does "Cost of Inaction" mean?**
It's the estimated financial impact if a predicted failure is ignored: `failure_cost - planned_repair_cost`. A high cost of inaction means preventive action is strongly justified.

**Q: How do I run the test suite?**
Admin Panel → Test Suite → Select a category → Run Tests. The acceptance threshold is >= 95% pass rate. Tests run directly against MFGPULSE_DB and verify data integrity, ML pipeline outputs, procurement logic, and more.

**Q: What are the 7 Copilot Agent tools?**
1. **maintenance_analytics** — Text-to-SQL via Semantic View (OEE, costs, trends)
2. **maintenance_history** — RAG search over 78 maintenance log documents
3. **diagnose_asset** — Fast M1-M4 diagnosis (failure mode, RUL, degradation, fatigue)
4. **deep_analysis** — LLM-powered M5-M7 (root cause, Monte Carlo simulation, prescriptive recommendation)
5. **simulate_scenario** — Monte Carlo what-if simulation with adjustable parameters
6. **generate_work_order** — Create and file a work order with auto-assigned technician and parts reservation
7. **generate_purchase_order** — Create a purchase order with supplier resolution, lead time, and risk classification

**Q: Who receives notifications?**
Each event type has configurable target personas. By default, WO events (including reassign and follow-up) go to Shift Supervisor, Plant Manager, and App Admin. PO events go to Procurement Admin, Plant Manager, and App Admin. Admins can change this in Admin Panel → Notifications.
