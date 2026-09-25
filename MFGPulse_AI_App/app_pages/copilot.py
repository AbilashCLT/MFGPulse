import streamlit as st
import json
import re
import pandas as pd
import altair as alt
from datetime import datetime
from app_pages._shared import (
    load_executive_summary, load_predictions, load_live_predictions,
    load_alerts, load_oee_by_line, load_oee_loss,
    load_open_work_orders, load_maintenance_logs, load_procurement_recs,
    load_open_pos, PERSONA_CONFIG, DB, C, get_conn,
)

alt.renderers.enable("mimetype")

@st.cache_data(ttl=300)
def build_plant_context():
    conn = get_conn()
    exe = load_executive_summary()
    preds = load_predictions()
    live = load_live_predictions()
    alerts = load_alerts()
    oee = load_oee_by_line()
    loss = load_oee_loss()
    wos = load_open_work_orders()
    maint_logs = load_maintenance_logs()
    e = exe.iloc[0] if len(exe) > 0 else {}

    sections = []
    sections.append("=== EXECUTIVE SUMMARY ===")
    sections.append(f"Plant OEE: {e.get('PLANT_OEE', 0)}% (target: 85%). Critical assets: {e.get('CRITICAL_ASSETS', 0)}/{e.get('TOTAL_ASSETS', 10)}. Cost avoided: ${int(e.get('TOTAL_COST_AVOIDED', 0)):,}. Maintenance ROI: {e.get('MAINTENANCE_ROI_X', 0)}x. Early detection: {int(e.get('AVG_EARLY_DETECTION_DAYS', 0))} days avg.")
    sections.append("\n=== ASSET PREDICTIONS (sorted by urgency) ===")
    for _, r in preds.iterrows():
        sections.append(f"{r['ASSET_NAME']}: Stage={r['STAGE_PRED']}, RUL={r['RUL_HOURS']:.0f}h, Mode={r['FAILURE_MODE_PRED']}, FailureCost=${r.get('ESTIMATED_FAILURE_COST', 0):,.0f}, RepairCost=${r.get('PLANNED_REPAIR_COST', 0):,.0f}, CostOfInaction=${r.get('COST_OF_INACTION', 0):,.0f}, Action={r.get('ACTION_WINDOW', '')}, Part={r.get('RECOMMENDED_PART', '')}")
    sections.append("\n=== ACTIVE ALERTS ===")
    for _, r in alerts.iterrows():
        sections.append(f"{r['ASSET_NAME']}: {r['SEVERITY']} - {r['MESSAGE']}")
    sections.append("\n=== OEE BY LINE ===")
    for _, r in oee.iterrows():
        sections.append(f"{r['LINE_ID']}: OEE={r['OEE']}%, Avail={r['AVAIL']}%, Perf={r['PERF']}%, Qual={r['QUAL']}%")
    sections.append("\n=== MAINTENANCE LOGS ===")
    for _, r in maint_logs.head(20).iterrows():
        sections.append(f"[{r['TIMESTAMP']}] {r['ASSET_NAME']} | {(r.get('WO_TYPE') or 'unknown').upper()} ({r.get('PRIORITY', '')}) | {r['TECHNICIAN']} | {(r.get('NOTES_TEXT') or '')[:200]}")
    proc = load_procurement_recs()
    if len(proc) > 0:
        sections.append("\n=== PROCUREMENT STATUS ===")
        for _, r in proc.iterrows():
            sections.append(f"{r.get('ASSET_NAME','')}: Part={r.get('PART_NAME','')}, ATP={r.get('AVAILABLE_TO_PROMISE',0)}, LeadTime={r.get('LEAD_TIME_DAYS',0)}d, Gap={r.get('LEAD_TIME_GAP_DAYS',0)}d, Risk={r.get('PROCUREMENT_RISK','')}, Action={r.get('RECOMMENDED_PROCUREMENT_ACTION','')}")
        open_p = load_open_pos()
        sections.append(f"Open POs: {len(open_p)}")
    return "\n".join(sections)

AGENT_KEYWORDS = ["generate work order", "create work order", "file work order", "run diagnosis", "7-model", "predict_all", "full diagnosis", "simulate", "what-if", "what if", "monte carlo"]

_RANKING_KEYWORDS = re.compile(
    r'(?i)\b(most\s+critical|least\s+critical|worst|safest|highest[\s-]risk|lowest[\s-]risk'
    r'|most\s+urgent|least\s+urgent|healthiest|most\s+degraded|most\s+at[\s-]risk'
    r'|least\s+at[\s-]risk|next\s+to\s+fail|rank.*(?:asset|equipment|machine)s?\s+by)\b'
)

def needs_agent(q):
    if _RANKING_KEYWORDS.search(q):
        return True
    return any(kw in q.lower() for kw in AGENT_KEYWORDS)

_RANKING_PATTERNS = {
    "most_critical": re.compile(r'(?i)\b(most\s+critical|worst|highest[\s-]risk|most\s+urgent|most\s+at[\s-]risk)\b'),
    "least_critical": re.compile(r'(?i)\b(least\s+critical|safest|lowest[\s-]risk|least\s+urgent|least\s+at[\s-]risk)\b'),
    "most_degraded": re.compile(r'(?i)\b(most\s+degraded|worst\s+health|lowest\s+health)\b'),
    "healthiest": re.compile(r'(?i)\b(healthiest|best\s+health|highest\s+health|most\s+healthy)\b'),
    "next_failure": re.compile(r'(?i)\b(fail\s+next|next\s+to\s+fail|shortest\s+rul|lowest\s+rul)\b'),
}

_RANKING_SQL = {
    "most_critical": (
        f"SELECT ASSET_ID, ASSET_NAME FROM {DB}.ML_MODELS.LIVE_PREDICTIONS "
        "ORDER BY COMPOSITE_HEALTH_SCORE ASC, RUL_HOURS ASC, STRESS_INDEX DESC LIMIT 1"
    ),
    "least_critical": (
        f"SELECT ASSET_ID, ASSET_NAME FROM {DB}.ML_MODELS.LIVE_PREDICTIONS "
        "ORDER BY COMPOSITE_HEALTH_SCORE DESC, RUL_HOURS DESC, STRESS_INDEX ASC LIMIT 1"
    ),
    "most_degraded": (
        f"SELECT ASSET_ID, ASSET_NAME FROM {DB}.ML_MODELS.LIVE_PREDICTIONS "
        "ORDER BY DEGRADATION_SCORE DESC LIMIT 1"
    ),
    "healthiest": (
        f"SELECT ASSET_ID, ASSET_NAME FROM {DB}.ML_MODELS.LIVE_PREDICTIONS "
        "ORDER BY COMPOSITE_HEALTH_SCORE DESC, RUL_HOURS DESC, STRESS_INDEX ASC LIMIT 1"
    ),
    "next_failure": (
        f"SELECT ASSET_ID, ASSET_NAME FROM {DB}.ML_MODELS.LIVE_PREDICTIONS "
        "ORDER BY RUL_HOURS ASC LIMIT 1"
    ),
}

_ASSET_REF_PATTERN = re.compile(
    r'(?i)(the\s+)?(most\s+critical|least\s+critical|worst|safest|highest[\s-]risk|lowest[\s-]risk'
    r'|most\s+urgent|least\s+urgent|most\s+at[\s-]risk|least\s+at[\s-]risk'
    r'|most\s+degraded|healthiest|most\s+healthy|best\s+health|worst\s+health'
    r'|next\s+to\s+fail)\s+(asset|equipment|machine)'
)


def resolve_asset_reference(question):
    """Resolve vague asset references via SQL against LIVE_PREDICTIONS (replaces 8B LLM resolver)."""
    q_lower = question.lower()

    matched_key = None
    for key, pattern in _RANKING_PATTERNS.items():
        if pattern.search(q_lower):
            matched_key = key
            break

    if matched_key is None:
        return question, None

    sql = _RANKING_SQL[matched_key]
    try:
        session = get_conn().session()
        result = session.sql(sql).collect()
        if not result:
            return question, None
        aid = str(result[0]["ASSET_ID"])
        aname = str(result[0]["ASSET_NAME"])
        rewritten = _ASSET_REF_PATTERN.sub(f'{aname} ({aid})', question)
        if rewritten == question:
            rewritten = question.rstrip(".!? ") + f" — specifically {aname} ({aid})."
        return rewritten, f"{aname} ({aid}) — {matched_key} by SQL lookup"
    except Exception:
        return question, None

def fast_llm_answer(question, role_context):
    q_lower = question.strip().lower().rstrip("!?.")
    is_greeting = q_lower in ("hi", "hello", "hey", "good morning", "good afternoon", "good evening", "howdy", "sup", "yo")

    if is_greeting:
        system_prompt = f"""You are MFGPulse AI Maintenance Copilot. The user ({role_context}) just greeted you. Respond with a brief, friendly greeting. Introduce yourself in one sentence and ask how you can help with maintenance, assets, or plant operations today. Keep it under 3 sentences. Do not dump data."""
    else:
        system_prompt = f"""You are MFGPulse AI Maintenance Copilot for a plant with 10 assets, 3 production lines, 7 ML models. Speaking to a {role_context}.
RULES: Use exact numbers. For at-risk assets always state "Repair cost $X vs Failure cost $Y — Cost of inaction: $Z". RUL < 24h = URGENT prefix. Use markdown headers, bold, bullet points. If the question is general or conversational, respond naturally without forcing data into the answer.
QUESTION: {question}
DATA:
{build_plant_context()}"""
    session = get_conn().session()
    try:
        result = session.sql("SELECT SNOWFLAKE.CORTEX.COMPLETE('llama3.1-70b', ?) AS R", params=[system_prompt]).collect()
    except Exception as ex:
        return f"Copilot temporarily unavailable: {ex}"
    return str(result[0]["R"]) if result else "Could not generate response."

def call_agent(question, role_context):
    contextualized_q = f"[Speaking as a {role_context}] {question}"
    request_body = json.dumps({"messages": [{"role": "user", "content": [{"type": "text", "text": contextualized_q}]}]})
    try:
        session = get_conn().session()
        result = session.sql(
            f"SELECT SNOWFLAKE.CORTEX.DATA_AGENT_RUN('{DB}.AGENT.MAINTENANCE_COPILOT', ?) AS RESPONSE",
            params=[request_body],
        ).collect()
        if not result:
            return "No response from the agent. Please try again."
        try:
            resp = json.loads(str(result[0]["RESPONSE"]))
            parts = []
            for block in resp.get("content", []):
                btype = block.get("type", "")
                if btype == "text" and block.get("text", "").strip():
                    parts.append(block["text"].strip())
                elif btype == "tool_result":
                    # tool_result may contain nested content list or a plain text field
                    nested = block.get("content", [])
                    if isinstance(nested, list):
                        for item in nested:
                            if isinstance(item, dict) and item.get("text", "").strip():
                                parts.append(item["text"].strip())
                            elif isinstance(item, str) and item.strip():
                                parts.append(item.strip())
                    elif isinstance(nested, str) and nested.strip():
                        parts.append(nested.strip())
                    if block.get("text", "").strip():
                        parts.append(block["text"].strip())
            full_text = "\n\n".join(parts) if parts else (
                "The agent completed but returned no diagnostic text. "
                "Try specifying an asset ID (e.g., 'Run 7-model diagnosis on ASSET_005')."
            )
            if len(full_text) > 8000:
                last_newline = full_text[:8000].rfind("\n")
                full_text = full_text[:last_newline if last_newline > 6000 else 8000] + "\n\n*(truncated)*"
            return full_text
        except (json.JSONDecodeError, KeyError):
            raw = str(result[0]["RESPONSE"])
            if len(raw) > 8000:
                last_newline = raw[:8000].rfind("\n")
                raw = raw[:last_newline if last_newline > 6000 else 8000] + "\n\n*(truncated)*"
            return raw
    except Exception as ex:
        return f"Agent error: {ex}. Try rephrasing your question or use a simpler query."

persona = st.session_state.get("persona", "TECHNICIAN")
persona_label = PERSONA_CONFIG.get(persona, {}).get("label", "Technician")

SUGGESTIONS = {
    "TECHNICIAN": {
        ":material/build: What should I fix first?": "Which asset has the most urgent repair needed? Give me parts and steps.",
        ":material/warning: Compressor A1 repair plan": "I need to repair Compressor A1. What parts, failure mode, and repair steps?",
    },
    "RELIABILITY_ENGINEER": {
        ":material/troubleshoot: Why is A1 degrading?": "Why is Compressor A1 showing degradation? Root cause analysis.",
        ":material/science: Run full diagnosis": "Run a full 7-model diagnosis on Compressor A1.",
    },
    "SHIFT_SUPERVISOR": {
        ":material/summarize: Shift handover": "Give me the end-of-shift handover summary.",
        ":material/monitor_heart: Plant status": "What is the current health status of all assets?",
    },
    "PLANT_MANAGER": {
        ":material/payments: Cost savings report": "What is our maintenance ROI and total cost avoided?",
        ":material/trending_down: Worst performing line": "Which production line is underperforming and why?",
    },
    "PROCUREMENT_ADMIN": {
        ":material/inventory: Parts status": "Which assets need parts? Are we in stock?",
        ":material/local_shipping: Lead time risks": "Are there any parts with lead time longer than maintenance window?",
    },
    "APP_ADMIN": {
        ":material/monitor_heart: System health": "What is the current health status of all assets and the plant OEE?",
        ":material/analytics: Full diagnostics": "Run a full 7-model diagnosis on the most critical asset.",
    },
}

st.markdown("#### Maintenance copilot")
st.caption(f"AI-powered assistant — speaking as **{persona_label}**")

with st.expander("About this page", expanded=False, icon=":material/info:"):
    st.markdown("""
**Purpose**: Natural-language interface to the entire platform — ask questions, run diagnostics, simulate scenarios, and generate work orders via conversation.

**Two response paths**:
- **Fast path** — Data questions (OEE, costs, status) answered from pre-loaded plant context via Cortex Complete. Faster, no tool calls.
- **Agent path** — Complex tasks routed to the 7-tool Cortex Agent. Triggers: "diagnosis", "simulate", "work order", "purchase order", "history", "root cause".

**7 Agent tools**:
| Tool | Trigger keywords | What it does |
|---|---|---|
| maintenance_analytics | OEE, trend, how many | Text-to-SQL via Semantic View (19 VQRs) |
| maintenance_history | history, repairs, root cause | RAG search over maintenance log documents |
| diagnose_asset | diagnose, check asset | Fast M1-M4 diagnosis (failure mode, RUL, degradation, fatigue) |
| deep_analysis | full diagnosis, 7-model, root cause | LLM-powered M5-M7 (root cause, simulation, prescription) |
| simulate_scenario | simulate, what-if, monte carlo | 100-path Monte Carlo simulation |
| generate_work_order | create WO, generate work order | Creates and files a work order |
| generate_purchase_order | order parts, create PO, procure | Creates a purchase order with supplier resolution |

**Sections**:
- **Suggested questions** — Persona-specific quick-action pills (e.g., technicians see diagnostic prompts, managers see cost prompts)
- **Chat interface** — Full conversational UI with message history, role-specific avatars, and loading status indicators
- **Sidebar: New session** — Start a fresh conversation, archiving the current one
- **Sidebar: Tools** — Lists the 7 available tools: Semantic View, Cortex Search, Diagnose Asset, Deep Analysis, Simulator, Work Orders, Purchase Orders
- **Sidebar: Session history** — Browse and restore previous chat sessions with title, timestamp, and message count

**Tips**: Be specific with asset IDs ("ASSET_005") or names ("Compressor A1"). The Copilot adapts response format to your persona — technicians get step-by-step actions, managers get cost summaries.
""")

# --- Session management ---
if "copilot_sessions" not in st.session_state:
    st.session_state.copilot_sessions = []
if "active_session_id" not in st.session_state:
    st.session_state.active_session_id = None
if "chat_messages" not in st.session_state:
    st.session_state.chat_messages = []

WELCOME = {
    "TECHNICIAN": "Hey there! I'm your Maintenance Copilot. I can help you figure out what to fix first, look up parts, check asset health, or walk you through a repair plan. What are you working on?",
    "RELIABILITY_ENGINEER": "Welcome back. I'm your Maintenance Copilot with access to 7 ML models, maintenance history, and fleet-wide sensor analytics. I can run root cause analysis, full diagnostics, or Monte Carlo simulations. What would you like to investigate?",
    "SHIFT_SUPERVISOR": "Good to see you. I'm the Maintenance Copilot — I can give you shift handover summaries, current plant status, alert triage, and work order updates. How can I help with your shift?",
    "PLANT_MANAGER": "Welcome. I'm the MFGPulse AI Copilot. I can brief you on plant OEE, maintenance ROI, cost avoidance, and asset risk across all 3 production lines. What would you like to review?",
    "PROCUREMENT_ADMIN": "Hi! I'm your Maintenance Copilot. I can check parts availability, lead-time risks, ATP status, and help you manage purchase orders. What do you need?",
    "APP_ADMIN": "Welcome, Admin. I'm the MFGPulse AI Copilot with full access to all diagnostics, simulations, and plant data. What would you like to look into?",
}

if not st.session_state.chat_messages:
    greeting = WELCOME.get(persona, WELCOME["TECHNICIAN"])
    st.session_state.chat_messages.append({"role": "assistant", "content": greeting})

def _new_session():
    if st.session_state.chat_messages:
        first_user = next((m["content"][:60] for m in st.session_state.chat_messages if m["role"] == "user"), "Untitled")
        st.session_state.copilot_sessions.append({
            "id": st.session_state.active_session_id or datetime.now().strftime("%Y%m%d_%H%M%S"),
            "title": first_user,
            "messages": list(st.session_state.chat_messages),
            "persona": persona,
            "timestamp": datetime.now().strftime("%b %d, %H:%M"),
            "msg_count": len(st.session_state.chat_messages),
        })
    st.session_state.chat_messages = []
    st.session_state.active_session_id = datetime.now().strftime("%Y%m%d_%H%M%S")
    st.session_state._last_pill = None

def _load_session(idx):
    if st.session_state.chat_messages:
        _save_current_session()
    session = st.session_state.copilot_sessions[idx]
    st.session_state.chat_messages = list(session["messages"])
    st.session_state.active_session_id = session["id"]

def _save_current_session():
    if not st.session_state.chat_messages:
        return
    sid = st.session_state.active_session_id
    for i, s in enumerate(st.session_state.copilot_sessions):
        if s["id"] == sid:
            st.session_state.copilot_sessions[i]["messages"] = list(st.session_state.chat_messages)
            st.session_state.copilot_sessions[i]["msg_count"] = len(st.session_state.chat_messages)
            return
    first_user = next((m["content"][:60] for m in st.session_state.chat_messages if m["role"] == "user"), "Untitled")
    st.session_state.copilot_sessions.append({
        "id": sid or datetime.now().strftime("%Y%m%d_%H%M%S"),
        "title": first_user,
        "messages": list(st.session_state.chat_messages),
        "persona": persona,
        "timestamp": datetime.now().strftime("%b %d, %H:%M"),
        "msg_count": len(st.session_state.chat_messages),
    })

if st.session_state.active_session_id is None:
    st.session_state.active_session_id = datetime.now().strftime("%Y%m%d_%H%M%S")

persona_suggestions = SUGGESTIONS.get(persona, {})
selected = st.pills("Suggested questions:", list(persona_suggestions.keys()), label_visibility="collapsed", key="copilot_pills")
if selected and st.session_state.get("_last_pill") != selected:
    st.session_state._last_pill = selected
    question = persona_suggestions[selected]
    st.session_state.chat_messages.append({"role": "user", "content": question})
    st.session_state.pending_question = question
    st.rerun()

for msg in st.session_state.chat_messages:
    avatar = ":material/person:" if msg["role"] == "user" else ":material/precision_manufacturing:"
    with st.chat_message(msg["role"], avatar=avatar):
        st.markdown(msg["content"])

if "pending_question" in st.session_state and st.session_state.pending_question:
    pending = st.session_state.pending_question
    st.session_state.pending_question = None
    is_agent = needs_agent(pending)
    with st.chat_message("assistant", avatar=":material/precision_manufacturing:"):
        if is_agent:
            status = st.status("Running 7-model agent diagnosis...", expanded=True)
            status.write(":material/search: Identifying target asset...")
            resolved_q, resolution_info = resolve_asset_reference(pending)
            if resolution_info:
                status.write(f":material/target: Identified asset: {resolution_info}")
            else:
                status.write(":material/info: No asset resolution needed")
            status.write(":material/model_training: Running ML models...")
        else:
            resolved_q = pending
            status = st.status("Copilot analyzing...", expanded=True)
            status.write(":material/database: Retrieving plant data...")
            status.write(":material/psychology: Generating response...")
        response = call_agent(resolved_q, persona_label) if is_agent else fast_llm_answer(resolved_q, persona_label)
        status.update(label="Analysis complete", state="complete", expanded=False)
        st.markdown(response)
    st.session_state.chat_messages.append({"role": "assistant", "content": response})

if prompt := st.chat_input(f"Ask as {persona_label}..."):
    st.session_state.chat_messages.append({"role": "user", "content": prompt})
    with st.chat_message("user", avatar=":material/person:"):
        st.markdown(prompt)
    is_agent = needs_agent(prompt)
    with st.chat_message("assistant", avatar=":material/precision_manufacturing:"):
        if is_agent:
            status = st.status("Running 7-model agent diagnosis...", expanded=True)
            status.write(":material/search: Identifying target asset...")
            resolved_q, resolution_info = resolve_asset_reference(prompt)
            if resolution_info:
                status.write(f":material/target: Identified asset: {resolution_info}")
            else:
                status.write(":material/info: No asset resolution needed")
            status.write(":material/model_training: Running ML models...")
        else:
            resolved_q = prompt
            status = st.status("Copilot analyzing...", expanded=True)
            status.write(":material/database: Retrieving plant data...")
            status.write(":material/psychology: Generating response...")
        response = call_agent(resolved_q, persona_label) if is_agent else fast_llm_answer(resolved_q, persona_label)
        status.update(label="Analysis complete", state="complete", expanded=False)
        st.markdown(response)
    st.session_state.chat_messages.append({"role": "assistant", "content": response})

with st.sidebar:
    st.markdown("#### Copilot")

    if st.button("New session", use_container_width=True, type="primary", icon=":material/add_comment:"):
        _new_session()
        st.rerun()

    st.divider()
    st.markdown("**Tools**")
    st.caption("Semantic View — OEE, alerts, predictions")
    st.caption("Cortex Search — 26 maintenance logs (RAG)")
    st.caption("PREDICT_ALL — 7-model diagnosis")
    st.caption("Simulator — Monte Carlo what-if")
    st.caption("Work Orders — Create, assign, cost")

    sessions = st.session_state.copilot_sessions
    if sessions:
        st.divider()
        st.markdown("**Previous sessions**")
        for idx in range(len(sessions) - 1, -1, -1):
            s = sessions[idx]
            is_active = s["id"] == st.session_state.active_session_id
            label = s["title"][:45] + ("..." if len(s["title"]) > 45 else "")
            with st.container(border=is_active):
                c1, c2 = st.columns([4, 1])
                with c1:
                    if st.button(
                        label,
                        key=f"sess_{s['id']}",
                        use_container_width=True,
                        disabled=is_active,
                        icon=":material/chat:" if not is_active else ":material/chat_bubble:",
                    ):
                        _load_session(idx)
                        st.rerun()
                with c2:
                    st.caption(s["timestamp"])
                st.caption(f"{s['msg_count']} messages | {s.get('persona', 'N/A')}")
