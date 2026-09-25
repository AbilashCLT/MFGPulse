# Session 3 — Instant Work Order Reassignment and Part Shortage Simulation

- **Session ID**: 278328852
- **Date**: September 7, 2026
- **Messages**: 10 (3 user, 6 agent blocks)
- **Duration**: ~1 hour
- **Work**: WO reassignment feature, part shortage simulation, sensor feed enhancements

---

┌─ USER [11:00] ───────────────────────────────────────────────────────────────┐
│ WO Re-Assign & Follow-Up trigger - Make it instant and show success message once it's done Simulate Part shortage scenario
└──────────────────────────────────────────────────────────────────────────────┘

┌─ AGENT ──────────────────────────────────────────────────────────────────────┐
│ Let me read the current app code to understand the WO Re-Assign and Part Shortage sections.
│ 
│   read (pending)
│   /workspace/MFGPulse_AI/failure-genome-dashboard/streamlit_app.py
│ Now let me find the WO Re-Assign and Part Shortage related code in the WO/PO console page.
│ 
│   read (pending)
│   /workspace/MFGPulse_AI/failure-genome-dashboard/app_pages/wo_po_console…
└──────────────────────────────────────────────────────────────────────────────┘

┌─ AGENT ──────────────────────────────────────────────────────────────────────┐
│ Let me check the shared module for relevant helpers and data loaders.
│ 
│   task (pending)
│   Find part shortage and inventory code
└──────────────────────────────────────────────────────────────────────────────┘

┌─ AGENT ──────────────────────────────────────────────────────────────────────┐
│ Now I have full context. Here's the plan:
│ 
│ ---
│ 
│ ## Plan
│ 
│ ### 1. WO Re-Assign & Follow-Up — instant feedback with success message
│ 
│ **Problem**: In `app_pages/wo_po_console.py:115-133`, the Reassign button calls `st.success()` then `st.rerun()` — the rerun fires so fast the success message is never visible. The Follow-up button shows `st.success()` but never reruns, so data stays stale.
│ 
│ **Fix** (lines 107–133 of `wo_po_console.py`):
│ - Replace `st.success(...)` with `st.toast(...)` for both Reassign and Follow-up actions — toast messages survive across reruns.
│ - Add `st.rerun()` after the Follow-up notification so data refreshes immediately.
│ - Add `load_all_work_orders.clear()` before `st.rerun()` in Follow-up (currently missing) so the WO list reflects the notification.
│ 
│ Concretely:
│ - Line 122: `st.success(f"Reassigned to {new_assignee}")` → `st.toast(f"Reassigned {wo['WO_ID']} to {new_assignee}", icon=":material/swap_horiz:")`
│ - Line 133: `st.success("Follow-up notification sent")` → `st.toast("Follow-up sent for " + wo['WO_ID'], icon=":material/mail:")` + add `st.rerun()` after it.
│ 
│ ### 2. Simulate Part Shortage scenario
│ 
│ **Approach**: Add a new **"Simulate part shortage"** section inside the WO/PO console (as a new tab/segment alongside "Work orders", "Purchase orders", "WO analytics"), gated to `CAN_MANAGE_WO` or `CAN_MANAGE_PO` personas. It will:
│ 
│ - Load `load_parts_atp()` (already in `_shared.py`) to show current ATP (available-to-promise) inventory.
│ - Let the user pick a part and set a simulated on-hand quantity (slider or number input).
│ - Show a **before vs. after** comparison: which WOs would be blocked, which assets affected, and a projected procurement risk upgrade (e.g., NO_RISK → CRITICAL_SHORTAGE).
│ - Optionally let the user "apply" the simulation by actually updating `RAW_IT.PARTS_INVENTORY` to trigger the downstream dynamic tables/procurement recommendations (with a confirmation dialog and a revert button).
│ - This is a read-heavy simulation — no permanent data mutation unless the user explicitly confirms.
│ 
│ **Files changed**:
│ - `app_pages/wo_po_console.py` — add "Shortage simulation" to the segmented control tabs, implement the simulation UI.
│ - `app_pages/_shared.py` — add `load_parts_inventory()` if we need raw inventory data beyond what `load_parts_atp()` provides (need to verify columns).
│ 
│ ---
│ 
│ Two files touched, all changes scoped to the WO/PO console page. Shall I proceed, or would you like to adjust anything (e.g., put the simulation on the Procurement page instead, or change the simulation scope)?
└──────────────────────────────────────────────────────────────────────────────┘

┌─ USER [11:56] ───────────────────────────────────────────────────────────────┐
│ Go ahead
└──────────────────────────────────────────────────────────────────────────────┘

┌─ AGENT ──────────────────────────────────────────────────────────────────────┐
│ 
│   exit_plan_mode (pending)
│ 
│   system_todo_write (pending)
│   {"todos":[{"content":"Fix WO Reassign: replace st.success with st.toast…
│ Starting with the Reassign fix — switching `st.success` to `st.toast` so the message persists across the `st.rerun()`.
│ 
│   edit (pending)
│   /workspace/MFGPulse_AI/failure-genome-dashboard/app_pages/wo_po_console…
│ 
│   system_todo_write (pending)
│   {"todos":[{"content":"Fix WO Reassign: replace st.success with st.toast…
│ Now fixing the Follow-up button — switching to toast and adding rerun.
│ 
│   edit (pending)
│   /workspace/MFGPulse_AI/failure-genome-dashboard/app_pages/wo_po_console…
│ 
│   system_todo_write (pending)
│   {"todos":[{"content":"Fix WO Reassign: replace st.success with st.toast…
│ Now let me check the `load_parts_atp` function and the PARTS_INVENTORY table to understand the data available for the simulation.
│ 
│   read (pending)
│   /workspace/MFGPulse_AI/failure-genome-dashboard/app_pages/_shared.py
│ Good. Now I have the data model clear. Let me also check what columns are in `PARTS_INVENTORY` and the procurement recommendations to build the simulation properly.
│ 
│   snowflake_sql_execute (pending)
│   Get PARTS_INVENTORY table schema
│ 
│   snowflake_sql_execute (pending)
│   Sample parts inventory data
│ 
│   snowflake_sql_execute (pending)
│   Sample procurement recommendations
│ 
│   snowflake_sql_execute (pending)
│   Sample parts ATP data
│ 
│   snowflake_sql_execute (pending)
│   Sample parts inventory data
└──────────────────────────────────────────────────────────────────────────────┘

┌─ AGENT ──────────────────────────────────────────────────────────────────────┐
│ Now I have the full data model. Let me build the shortage simulation tab. I'll add it to the segmented control in the WO/PO console.
│ 
│   read (pending)
│   /workspace/MFGPulse_AI/failure-genome-dashboard/app_pages/wo_po_console…
│ 
│   edit (pending)
│   /workspace/MFGPulse_AI/failure-genome-dashboard/app_pages/wo_po_console…
│ Now add "Shortage simulation" to the tabs and gate it to management personas:
│ 
│   edit (pending)
│   /workspace/MFGPulse_AI/failure-genome-dashboard/app_pages/wo_po_console…
│ Now add the shortage simulation section at the end of the file. Let me first read the end of the file:
│ 
│   read (pending)
│   /workspace/MFGPulse_AI/failure-genome-dashboard/app_pages/wo_po_console…
│ 
│   edit (pending)
│   /workspace/MFGPulse_AI/failure-genome-dashboard/app_pages/wo_po_console…
│ 
│   system_todo_write (pending)
│   {"todos":[{"content":"Fix WO Reassign: replace st.success with st.toast…
│ All three changes are done. Here's a summary:
│ 
│ **WO Reassign & Follow-up (instant + success message)**
│ - Both actions now use `st.toast()` instead of `st.success()` — toast messages persist across the `st.rerun()` so users see the confirmation immediately.
│ - Follow-up now also clears the WO cache and calls `st.rerun()` to refresh data instantly (was missing before).
│ 
│ **Part Shortage Simulation** — new "Shortage simulation" tab in the WO/PO console (visible to Shift Supervisors, Plant Managers, App Admins, and Procurement Admins):
│ - Pick any part from `PARTS_INVENTORY`, set a simulated on-hand quantity (defaults to 0).
│ - Shows a before/after KPI row (current vs. simulated qty, lead time, unit cost).
│ - Lists dependent assets and open WOs at risk in a two-column layout.
│ - Computes a projected risk level (CRITICAL_SHORTAGE / EXPEDITE / ORDER_NOW / NO_RISK) with estimated resupply delay and cost exposure.
│ - "Apply shortage" writes the simulated quantity to the live `PARTS_INVENTORY` table so downstream dynamic tables (ATP, procurement recommendations) refresh automatically. "Revert to original" restores the original value. Both use toast notifications.
└──────────────────────────────────────────────────────────────────────────────┘

┌─ USER [12:00] ───────────────────────────────────────────────────────────────┐
│ Show procurement recommendations with critical shortage risk
└──────────────────────────────────────────────────────────────────────────────┘

┌─ AGENT ──────────────────────────────────────────────────────────────────────┐
│ 
│   snowflake_sql_execute (pending)
│   Procurement recommendations with critical shortage risk
│ No rows currently have `CRITICAL_SHORTAGE` risk. Let me check what risk levels exist right now.
│ 
│   snowflake_sql_execute (pending)
│   Distribution of procurement risk levels
│ All 8 procurement recommendations are currently `NO_RISK`. This is a good scenario to use the new **Shortage Simulation** tab — you can simulate a critical shortage to see the downstream impact.
│ 
│ For example, `PART-013` (Turbine Blade Set) already has **0 units on hand**, but it doesn't appear in procurement recommendations because no asset currently needs it. The parts with the lowest stock that *do* have active recommendations are:
│ 
│ | Part | On-hand | Assets |
│ |---|---|---|
│ | Shaft Sleeve - Compressor | 1 | Compressor A1, A2 |
│ | Grundfos CR-32 Impeller | 1 | Pump P1, P2 |
│ 
│ To trigger a `CRITICAL_SHORTAGE`, go to the **WO / PO console → Shortage simulation** tab, select one of these parts (e.g., Shaft Sleeve - Compressor), set simulated quantity to **0**, and click **Apply shortage**. The downstream dynamic tables (`PARTS_AVAILABLE_TO_PROMISE`, `PROCUREMENT_RECOMMENDATIONS`) will refresh and you'll see the risk escalate to `CRITICAL_SHORTAGE` with affected WOs and cost exposure displayed. You can revert afterward with one click.
└──────────────────────────────────────────────────────────────────────────────┘
