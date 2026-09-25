# MFGPulse AI — Hackathon Demo Video Script

## "The Failure Genome"

**Duration:** 3:30 - 4:00 | **Format:** Screen recording + voiceover | **Resolution:** 1920x1080

---

## Table of Contents

1. [Strategy & Philosophy](#strategy--philosophy)
2. [Pre-Recording Checklist](#pre-recording-checklist)
3. [Segment 1: The Hook (0:00 - 0:30)](#segment-1-the-hook-000---030)
4. [Segment 2: Cortex Agent (0:30 - 1:45)](#segment-2-cortex-agent---talk-to-the-plant-030---145)
5. [Segment 3: Digital Twin (1:45 - 2:45)](#segment-3-digital-twin---what-if-we-do-nothing-145---245)
6. [Segment 4: The Pipeline (2:45 - 3:30)](#segment-4-the-pipeline---it-never-sleeps-245---330)
7. [Segment 5: The Close (3:30 - 4:00)](#segment-5-the-close---montage--tagline-330---400)
8. [Skills & Capabilities Matrix](#coco-skills--capabilities-demonstrated)
9. [Recovery Playbook](#if-something-goes-wrong)
10. [Quick-Reference Cheat Sheet](#cheat-sheet-tape-to-monitor)

---

## Strategy & Philosophy

### Why This Structure Wins

Hackathon judges have seen 50 demos. You have **8 seconds** before they mentally check out. The winning formula:

1. **Lead with the outcome, not the setup.** No slides, no problem statement. Open cold on the most impressive visual.
2. **Reverse pyramid.** Most impactful thing first. If they tune out at minute 2, they've already seen the best.
3. **Numbers over adjectives.** "$47,000 failure cost" hits harder than "expensive downtime."
4. **Show, don't explain.** Don't say "a dynamic table is..." — show it refreshing.
5. **Confidence, not apology.** Never say "if we had more time" or "this is a prototype."

### The Narrative Arc

```
HOOK: "$47K problem caught for $3.2K"
  → HERO: AI Agent diagnoses + generates work order autonomously
    → DEPTH: Digital Twin simulates 3 futures with Monte Carlo
      → SCALE: Serverless pipeline that never sleeps
        → CLOSE: "The Failure Genome" — tagline + numbers
```

### What Judges Are Scoring

| Criteria | How We Score |
|----------|-------------|
| **Technical depth** | 12 ML models, Cortex Agent with 5 tools, Monte Carlo UDF, 13 dynamic tables |
| **End-to-end workflow** | Sensor data → Feature engineering → Prediction → Alert → Work order |
| **CoCo usage** | Agent orchestration, SQL authoring, Streamlit app, pipeline deployment |
| **Business impact** | Dollar values on every screen — cost avoided, ROI, cost of inaction |
| **Polish** | Dark industrial theme, persona-based access, glowing cyan UI |

---

## Pre-Recording Checklist

### Environment Setup

```
[ ] Browser: Chrome, 90% zoom, bookmarks bar HIDDEN, dark mode
[ ] Close: Slack, email, Teams, all notification sources
[ ] Screen recorder: 1920x1080, system audio OFF, mic ON
[ ] Two browser tabs ready:
    - Tab 1: Streamlit app (running, warmed up)
    - Tab 2: Snowsight CoCo chat (clean conversation, no history)
```

### Data Readiness

```
[ ] Sensor readings are recent (within last 24h for "live" feel)
[ ] At least ONE asset is in Critical stage (dramatic tension)
[ ] At least TWO assets are in Warning stage (shows range)
[ ] Work orders exist in the system (for history context)
[ ] Maintenance logs are populated (for Cortex Search)
```

### App Verification

```
[ ] Streamlit app loads without errors
[ ] Login as "Plant Manager" persona works
[ ] All 8 pages navigate without errors
[ ] Executive Dashboard shows OEE + cost data
[ ] Copilot agent responds to test prompt
[ ] Digital Twin renders 3 scenarios
[ ] Admin Panel shows DT/Stream/Task status
```

### Warm-Up (5 minutes before recording)

```
[ ] Open Streamlit app → navigate through all pages once (cache warming)
[ ] Open CoCo chat → send one test prompt to warm the agent
[ ] Verify the exact prompts below produce good output
[ ] Clear CoCo chat history for clean recording
[ ] Set browser tab to Executive Dashboard (starting position)
```

---

## SEGMENT 1: The Hook [0:00 - 0:30]

> **Goal:** Visceral impact. Judges see a polished, production-grade app with real business stakes in 10 seconds.

**Screen:** Streamlit app — Executive Dashboard, already loaded as Plant Manager

| Timestamp | Screen Action | Voiceover (speak exactly this) |
|-----------|--------------|-------------------------------|
| 0:00 | Dashboard visible. Camera lingers on OEE donut + cost cards. | *"This compressor is seventy-two hours from catastrophic failure."* |
| 0:05 | Mouse slowly hovers over the critical asset's cost-of-inaction card | *"Unplanned replacement: forty-seven thousand dollars. Catching it early with predictive maintenance: thirty-two hundred."* |
| 0:12 | Mouse moves to the "Cost Avoided" big number at top | *"MFGPulse AI just caught it."* |
| 0:16 | Slow scroll down — reveal asset risk table with red/yellow/green staging | *"Ten industrial assets, three production lines, twelve ML models — all running inside Snowflake."* |
| 0:24 | Scroll back to top. Deliberate pause. | *"Let me show you how. Starting with the AI agent."* |
| 0:28 | **Click "Maintenance Copilot"** in sidebar | *(silence during transition)* |

### Key Visual Moments
- The OEE donut chart with glowing cyan
- Red "CRITICAL" badges on at-risk assets
- The big dollar figure for cost avoided
- The dark industrial theme — this should look like a control room

---

## SEGMENT 2: Cortex Agent — "Talk to the Plant" [0:30 - 1:45]

> **Goal:** Show the hero feature — a 5-tool Cortex Agent that chains 7 ML models and generates real work orders.

**Screen:** Copilot page with empty chat

### Part A: Full Diagnosis [0:30 - 1:20]

| Timestamp | Screen Action | Voiceover |
|-----------|--------------|-----------|
| 0:30 | Copilot page loads. Chat input is visible. | *"This is the Maintenance Copilot — a Cortex Agent with five specialized tools."* |
| 0:36 | Click into the chat input box | *"It can diagnose assets, analyze root cause from maintenance history, simulate failures, and generate work orders."* |
| 0:42 | **Type exactly:** | |

```
Diagnose the most critical asset and tell me why it's failing
```

| Timestamp | Screen Action | Voiceover |
|-----------|--------------|-----------|
| 0:44 | Press Enter. Response starts streaming. | *[Pause 3 seconds — let the agent visibly work]* |
| 0:47 | Agent queries semantic view to rank assets | *"First, it queries the semantic view to identify the most critical asset by composite health score..."* |
| 0:53 | Agent calls `diagnose_asset` — fast M1-M4 results appear | *"...then runs four ML models in under two seconds — failure mode classification, remaining useful life, degradation staging, and physics-based fatigue scoring."* |
| 1:02 | Agent chains to `deep_analysis` — M5-M7 results stream in | *"Now it chains to deep analysis — LLM root cause with evidence from seventy-eight maintenance log entries, Monte Carlo failure simulation, and a prescriptive maintenance recommendation."* |
| 1:14 | Full response visible. Scroll slowly through the diagnosis. | *"Seven models. One agent call. The root cause cites specific technician notes. The prescription includes parts, cost, and urgency window."* |

### Part B: Work Order Generation [1:20 - 1:45]

| Timestamp | Screen Action | Voiceover |
|-----------|--------------|-----------|
| 1:20 | Click into chat input again | *"Now watch this."* |
| 1:22 | **Type exactly:** | |

```
Generate an emergency work order for it
```

| Timestamp | Screen Action | Voiceover |
|-----------|--------------|-----------|
| 1:24 | Press Enter. Agent calls `generate_work_order`. | *[Pause — let it complete, ~5 seconds]* |
| 1:30 | Work order confirmation appears: WO ID, assigned technician, parts list, cost estimate | *"Work order created. Technician assigned from the shift schedule. Parts availability checked against inventory. Repair cost versus failure cost calculated."* |
| 1:40 | Mouse highlights the work order ID in the response | *"From sensor anomaly to filed work order — fully autonomous. Zero external services."* |
| 1:43 | **Click "Digital Twin"** in sidebar | *(silence during transition)* |

### What Judges Should Notice
- The agent **chains tools automatically** (semantic view → diagnose → deep analysis → work order)
- Each tool call is visible in the response (multi-step reasoning)
- The work order is **real** — it writes to the database
- Maintenance history search cites **specific log entries** (Cortex Search)

---

## SEGMENT 3: Digital Twin — "What If We Do Nothing?" [1:45 - 2:45]

> **Goal:** Stochastic simulation running as a SQL UDF. Three scenarios, real math, visual impact.

**Screen:** Digital Twin page

| Timestamp | Screen Action | Voiceover |
|-----------|--------------|-----------|
| 1:45 | Page loads with asset selector dropdown | *"The Digital Twin runs Monte Carlo simulations — three hundred stochastic paths per scenario, all inside a Snowflake SQL UDF."* |
| 1:52 | **Select the same critical asset** from dropdown | *"Same asset the agent just flagged."* |
| 1:55 | Three scenario cards render with glowing bar charts | *[Pause 2 full seconds — let the visuals land. This is a wow moment.]* |
| 1:57 | Mouse hovers over **Baseline scenario** card (do nothing) | *"Baseline — do nothing. Failure probability climbs to [read the number]% at fourteen days."* |
| 2:05 | Mouse moves to **Reduced Load scenario** card | *"Reduce RPM by twenty percent — probability drops significantly. Buys a week for planned maintenance."* |
| 2:14 | Mouse moves to **Immediate Maintenance scenario** card | *"Immediate intervention — near-zero failure risk. Three thousand dollars versus forty-seven thousand."* |
| 2:22 | Scroll down to the detailed section — RUL distributions (P10/P50/P90), cost comparison table | *"Each scenario shows the full RUL distribution — tenth percentile, median, ninetieth percentile — with expected cost impact."* |
| 2:32 | Scroll to procurement timing section (if visible) | *"The system cross-references parts lead time with the intervention window — tells you if you can afford to wait."* |
| 2:38 | Scroll back up to three scenario cards side by side | *"The shift supervisor sees this on their phone at 3am and makes the right call. Data, not gut feel."* |
| 2:43 | **Click "Admin Panel"** in sidebar | *(silence during transition)* |

### What Judges Should Notice
- Three scenarios rendered simultaneously with distinct risk profiles
- Real probability numbers, not hand-waved estimates
- Cost impact attached to every scenario (business speaks dollars)
- The Monte Carlo runs as a **SQL UDF** — zero external compute

---

## SEGMENT 4: The Pipeline — "It Never Sleeps" [2:45 - 3:30]

> **Goal:** Show the engineering depth — the pipeline is serverless, self-healing, and fully automated.

**Screen:** Admin Control Panel

| Timestamp | Screen Action | Voiceover |
|-----------|--------------|-----------|
| 2:45 | Admin panel loads — infrastructure monitoring section | *"Under the hood — the entire pipeline is serverless and self-healing."* |
| 2:50 | **Scroll to Dynamic Tables section** — show 13 DTs with refresh status and lag | *"Thirteen dynamic tables auto-refresh with one-hour target lag. Raw sensor data flows through feature engineering to live predictions — no orchestration code needed."* |
| 2:58 | **Scroll to Streams section** — 3 CDC streams with status | *"Three change data capture streams catch every new sensor reading, work order, and maintenance log the moment it lands."* |
| 3:05 | **Scroll to Task DAG section** — 6 tasks shown with dependency chain | *"Six DAG tasks handle what dynamic tables can't — drift monitoring, alert generation, notification dispatch."* |
| 3:12 | **Scroll to ML Model Registry section** — native models + drift metrics | *"Four native Snowflake ML models with automated drift monitoring. If rule-based and native model predictions diverge past eighty percent, the system flags it."* |
| 3:20 | **Scroll to Cortex Services section** — Search + Agent listed | *"Cortex Search indexes seventy-eight maintenance documents for root cause investigation. The Copilot agent ties every layer together."* |
| 3:26 | Pause on the full admin view | *"Twenty-two SQL scripts deployed from this workspace via CoCo. Everything you've seen — built here."* |
| 3:30 | Begin clicking through pages for montage | *(transition)* |

### What Judges Should Notice
- **13 dynamic tables** = zero ETL orchestration for most of the pipeline
- **Streams** = real-time CDC, not batch polling
- **Task DAG** = dependency-aware orchestration for complex flows
- **Drift monitoring** = the system watches itself

---

## SEGMENT 5: The Close — Montage + Tagline [3:30 - 4:00]

> **Goal:** Rapid-fire visual proof of breadth, then land the tagline.

| Timestamp | Screen Action | Voiceover |
|-----------|--------------|-----------|
| 3:30 | **Click "Operations Center"** — fleet status grid with red/yellow/green, live sensor sparklines | *"Six personas, each seeing exactly what they need."* |
| 3:34 | **Click "Maintenance Hub"** — asset health matrix, failure DNA diagnostic cards | *"Every failure has a DNA — sensor signatures, degradation patterns, operational context."* |
| 3:38 | **Click "Procurement"** — ATP table with risk colors, auto-PO recommendations | *"Procurement knows what to order before the technician asks."* |
| 3:42 | **Click "Executive Dashboard"** — land on the big OEE + cost avoided | *[Slow down. This is the landing.]* |
| 3:45 | Camera lingers on cost avoided number | *"MFGPulse AI reads the Failure Genome."* |
| 3:48 | Hold. Let the dashboard breathe. | *"Ten assets. A hundred seventy-two thousand sensor readings. Twelve ML models. One Cortex Agent. Six personas."* |
| 3:54 | Hold. | *"One hundred percent Snowflake-native. Co-authored with CoCo."* |
| 3:58 | Fade to black / end recording | — |

---

## CoCo Skills & Capabilities Demonstrated

### Capability Matrix (3 Modular Skills)

| # | CoCo Capability | Demo Segment | Technical Components | Proof of Depth |
|---|----------------|-------------|---------------------|---------------|
| 1 | **Cortex Agent with Multi-Tool Orchestration** | Segment 2 (0:30-1:45) | 5-tool agent: Cortex Analyst (semantic view), Cortex Search, 2 stored procedures, 1 SQL UDF | Agent autonomously chains: rank assets → M1-M4 fast diagnosis → M5-M7 deep analysis → file work order |
| 2 | **Snowflake-Native ML + Digital Twin** | Segment 3 (1:45-2:45) | Monte Carlo SQL UDF (`SIMULATE_FAILURE_TWIN`), 300 stochastic paths, P10/P50/P90 distributions | 3-scenario comparison with real probability calculations and cost attribution — all in a UDF |
| 3 | **Serverless Pipeline Architecture** | Segment 4 (2:45-3:30) | 3 streams, 13 dynamic tables, 6 DAG tasks, 4 native ML models, drift monitoring | Self-healing pipeline: CDC streams → auto-refresh DTs → ML predictions → alerts → notifications |

### End-to-End Workflow Proof

```
Input:   172K sensor readings (15-min intervals) from 23 sensors on 10 assets
           ↓
Process: Streams → Dynamic Tables (feature engineering) → ML Models (7 custom + 4 native)
           → Cortex Agent (diagnosis + root cause + simulation)
           ↓
Output:  Predictive alerts, work orders, procurement POs, executive OEE reports
           — all visible in a 6-persona Streamlit command center
```

---

## If Something Goes Wrong

### Recovery Playbook

| Problem | Recovery | What to Say |
|---------|----------|-------------|
| **Agent responds slowly (>10s)** | Let it run. Don't click away. | *"Real-time inference across seven models — worth the wait."* |
| **Agent gives unexpected output** | Scroll past quickly, focus on the structure | *"The agent adapts its response to the asset's current state."* |
| **Page fails to load** | Click a different page, come back | Skip it. Don't mention it. Move to next segment. |
| **Data looks stale** | Ignore dates entirely | Don't draw attention to timestamps. Focus on the metrics. |
| **Streamlit shows an error banner** | Refresh the page once | *"Let me refresh —"* then continue. One refresh max. |
| **Digital Twin shows flat scenarios** | Pick a different asset from dropdown | *"Let me pick an asset with more active degradation..."* |
| **You forget the voiceover line** | State the technical fact plainly | Any true statement about what's on screen is fine. Don't freeze. |

### Emergency Abort Order
If multiple things break, jump directly to the Close (Segment 5). The montage of working pages + tagline still delivers 80% of the impact.

---

## Cheat Sheet (Tape to Monitor)

```
╔══════════════════════════════════════════════════════════════╗
║  MFGPULSE AI DEMO — CHEAT SHEET                            ║
╠══════════════════════════════════════════════════════════════╣
║                                                              ║
║  [0:00] EXEC DASHBOARD — linger on cost, scroll risk table   ║
║         "$47K failure, $3.2K to catch it"                    ║
║                                                              ║
║  [0:30] COPILOT — type:                                      ║
║         "Diagnose the most critical asset and tell me        ║
║          why it's failing"                                   ║
║         → wait for 7-model chain                             ║
║         Then type:                                           ║
║         "Generate an emergency work order for it"            ║
║         → wait for WO confirmation                           ║
║                                                              ║
║  [1:45] DIGITAL TWIN — select same critical asset            ║
║         → hover each scenario: baseline / reduced / fix      ║
║         "300 stochastic paths, SQL UDF"                      ║
║                                                              ║
║  [2:45] ADMIN PANEL — scroll through:                        ║
║         DTs (13) → Streams (3) → Tasks (6) → ML (4+drift)   ║
║         "22 SQL scripts, deployed via CoCo"                  ║
║                                                              ║
║  [3:30] MONTAGE — Ops → Maint → Procurement → Exec          ║
║         "The Failure Genome"                                 ║
║         "100% Snowflake-native. Co-authored with CoCo."      ║
║                                                              ║
║  PROMPTS TO COPY:                                            ║
║  1. Diagnose the most critical asset and tell me why         ║
║     it's failing                                             ║
║  2. Generate an emergency work order for it                  ║
║                                                              ║
║  IF BROKEN: Jump to montage (3:30). Tagline still works.     ║
╚══════════════════════════════════════════════════════════════╝
```

---

## Voiceover Delivery Guide

### Pacing Rules
- **Speed:** ~150 words/minute (fast but clear, not rushed)
- **Filler words:** Zero. No "um", "so", "basically", "essentially"
- **Numbers:** Always say the number. "$47,000" not "a lot"
- **Pauses:** 1-2 second pause after each key reveal. Let it breathe.
- **Tone:** Confident engineer. State facts. Not a sales pitch.

### What NOT to Do
- Don't explain Snowflake primitives ("a dynamic table is a table that...")
- Don't show raw SQL scripts being executed
- Don't demonstrate error handling or edge cases
- Don't mention time pressure or what you'd do with more time
- Don't start with slides, logos, or a problem statement
- Don't read text off the screen — describe what's happening

### What TO Do
- Let impressive visuals sit on screen for 2 seconds before talking
- Use the mouse pointer as a visual guide (hover over the thing you're describing)
- Speak in short, declarative sentences
- End every segment with a technical fact, not a feeling
- Match energy: start strong, middle confident, close powerful

---

*Document generated for MFGPulse AI Hackathon Demo. Co-authored with CoCo.*
