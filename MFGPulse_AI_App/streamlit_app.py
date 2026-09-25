import os
import streamlit as st

st.set_page_config(
    page_title="MFGPulse AI Command Center",
    layout="wide",
    page_icon=":material/precision_manufacturing:",
    initial_sidebar_state="collapsed",
)

# --- Dark Industrial Futuristic Theme CSS ---
st.html("""
<style>
/* Global dark industrial theme */
[data-testid="stAppViewContainer"] {
    background: linear-gradient(135deg, #0A0E1A 0%, #0D1321 50%, #0A0E1A 100%);
}
[data-testid="stSidebar"] {
    background: linear-gradient(180deg, #0D1321 0%, #111827 100%);
    border-right: 1px solid rgba(0, 212, 255, 0.15);
}

/* Glowing card borders */
[data-testid="stVerticalBlock"] > div > [data-testid="stContainer"][class*="border"] {
    border: 1px solid rgba(0, 212, 255, 0.2) !important;
    border-radius: 8px !important;
    background: rgba(17, 24, 39, 0.7) !important;
    box-shadow: 0 0 15px rgba(0, 212, 255, 0.05), inset 0 1px 0 rgba(0, 212, 255, 0.1) !important;
}

/* Metric styling */
[data-testid="stMetric"] {
    background: rgba(17, 24, 39, 0.6);
    border: 1px solid rgba(0, 212, 255, 0.15);
    border-radius: 8px;
    padding: 12px 16px;
}
[data-testid="stMetricLabel"] {
    color: #64748B !important;
    font-size: 0.75rem !important;
    text-transform: uppercase;
    letter-spacing: 0.05em;
}
[data-testid="stMetricValue"] {
    color: #00D4FF !important;
    font-weight: 700 !important;
}

/* Badge styling for critical/warning */
[data-testid="stBadge"] span[data-baseweb*="red"] {
    box-shadow: 0 0 8px rgba(239, 68, 68, 0.4);
}
[data-testid="stBadge"] span[data-baseweb*="orange"] {
    box-shadow: 0 0 8px rgba(245, 158, 11, 0.4);
}
[data-testid="stBadge"] span[data-baseweb*="green"] {
    box-shadow: 0 0 8px rgba(16, 185, 129, 0.4);
}

/* Primary button glow */
[data-testid="stButton"] button[kind="primary"] {
    background: linear-gradient(135deg, #00D4FF 0%, #0891B2 100%) !important;
    border: none !important;
    box-shadow: 0 0 20px rgba(0, 212, 255, 0.3) !important;
    color: #0A0E1A !important;
    font-weight: 600 !important;
}
[data-testid="stButton"] button[kind="primary"]:hover {
    box-shadow: 0 0 30px rgba(0, 212, 255, 0.5) !important;
}

/* Secondary buttons */
[data-testid="stButton"] button:not([kind="primary"]) {
    border: 1px solid rgba(0, 212, 255, 0.3) !important;
    color: #00D4FF !important;
}

/* Expander headers */
[data-testid="stExpander"] {
    border: 1px solid rgba(0, 212, 255, 0.15) !important;
    border-radius: 8px !important;
}

/* Slider track */
[data-testid="stSlider"] [data-baseweb="slider"] div[role="slider"] {
    background: #00D4FF !important;
    box-shadow: 0 0 10px rgba(0, 212, 255, 0.4);
}

/* Selectbox */
[data-testid="stSelectbox"] [data-baseweb="select"] {
    border-color: rgba(0, 212, 255, 0.2) !important;
}

/* Dataframe */
[data-testid="stDataFrame"] {
    border: 1px solid rgba(0, 212, 255, 0.15) !important;
    border-radius: 8px !important;
}

/* Altair chart container */
[data-testid="stVegaLiteChart"] {
    border-radius: 8px;
}

/* Tab styling */
[data-testid="stTab"] {
    color: #64748B !important;
}
[data-testid="stTab"][aria-selected="true"] {
    color: #00D4FF !important;
    border-bottom-color: #00D4FF !important;
}

/* Scrollbar */
::-webkit-scrollbar {
    width: 6px;
    height: 6px;
}
::-webkit-scrollbar-track {
    background: #0A0E1A;
}
::-webkit-scrollbar-thumb {
    background: rgba(0, 212, 255, 0.3);
    border-radius: 3px;
}

/* Navigation styling */
[data-testid="stSidebarNav"] a {
    color: #94A3B8 !important;
}
[data-testid="stSidebarNav"] a[aria-current="page"] {
    color: #00D4FF !important;
    background: rgba(0, 212, 255, 0.1) !important;
}

/* Headers */
h1, h2, h3, h4 {
    color: #E0E7FF !important;
}
</style>
""")

conn = st.connection("snowflake", ttl=int(os.getenv("SNOWFLAKE_CONNECTION_TTL", "120")))
st.session_state.conn = conn

if "selected_asset" not in st.session_state:
    st.session_state.selected_asset = "ASSET_001"

if "persona" not in st.session_state:
    st.session_state.persona = None

from app_pages._shared import PERSONA_CONFIG, load_users, load_unread_notifications, NOTIF_ICON, DB, clear_all_caches

if st.session_state.persona is None:
    users = load_users()
    user_map = dict(zip(
        users["USERNAME"] + " (" + users["PERSONA"].str.replace("_", " ").str.title() + ")",
        users["PERSONA"],
    ))

    # ─── Futuristic Login Header ───
    st.html("""
    <div style="text-align:center; padding: 30px 0 10px 0;">
        <div style="font-size:2.2rem; font-weight:800; color:#E0E7FF; letter-spacing:0.02em;">
            ⚙ MFGPulse AI
        </div>
        <div style="font-size:0.8rem; color:#00D4FF; text-transform:uppercase; letter-spacing:0.15em;
                    margin-top:4px;">
            Predictive Maintenance &amp; OEE Command Center
        </div>
        <div style="font-size:0.7rem; color:#64748B; margin-top:8px; max-width:600px; margin-left:auto; margin-right:auto;">
            Converging IT and OT data to predict failures, automate work orders, and lift Overall Equipment Effectiveness — 100% Snowflake-native
        </div>
    </div>
    """)

    with st.container(horizontal=True):
        with st.container(border=True):
            st.html("""
            <div style="text-align:center;">
                <div style="color:#00D4FF; font-size:1.4rem; font-weight:800;">12</div>
                <div style="color:#00D4FF; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600;">ML models</div>
                <div style="color:#64748B; font-size:0.68rem; margin-top:4px;">Failure, RUL, degradation, fatigue, root cause, simulation</div>
            </div>
            """)
        with st.container(border=True):
            st.html("""
            <div style="text-align:center;">
                <div style="color:#F59E0B; font-size:1.4rem; font-weight:800;">4</div>
                <div style="color:#F59E0B; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600;">Alert levels</div>
                <div style="color:#64748B; font-size:0.68rem; margin-top:4px;">Multi-signal engine with email and in-app notifications</div>
            </div>
            """)
        with st.container(border=True):
            st.html("""
            <div style="text-align:center;">
                <div style="color:#10B981; font-size:1.4rem; font-weight:800;">7</div>
                <div style="color:#10B981; font-size:0.65rem; text-transform:uppercase; letter-spacing:0.08em; font-weight:600;">AI Copilot tools</div>
                <div style="color:#64748B; font-size:0.68rem; margin-top:4px;">Analytics, search, diagnosis, deep analysis, simulation, work orders, purchase orders</div>
            </div>
            """)

    selected = st.selectbox(
        ":material/login: Sign in as",
        list(user_map.keys()),
        index=None,
        placeholder="Select your profile to continue",
    )

    if selected:
        sel_persona = user_map[selected]
        sel_cfg = PERSONA_CONFIG.get(sel_persona, PERSONA_CONFIG["TECHNICIAN"])
        page_labels = {
            "executive": "Executive Dashboard", "operations": "Operations Center",
            "wo_po": "WO/PO Console", "maintenance": "Maintenance Hub",
            "procurement": "Procurement", "digital_twin": "Digital Twin",
            "admin": "Admin Panel", "copilot": "Copilot",
        }
        with st.container(border=True):
            st.html(f"""
            <div style="display:flex; align-items:center; gap:10px;">
                <div>
                    <div style="color:#E0E7FF; font-weight:700; font-size:0.9rem;">{sel_cfg['label']}</div>
                    <div style="color:#64748B; font-size:0.72rem; margin-top:2px;">
                        {len(sel_cfg['pages'])} pages — {" · ".join([page_labels.get(p, p) for p in sel_cfg["pages"]])}
                    </div>
                </div>
            </div>
            """)

        if st.button("Enter command center", type="primary", icon=":material/arrow_forward:", use_container_width=True):
            st.session_state.persona = sel_persona
            st.session_state.username = selected.split(" (")[0]
            st.rerun()
    else:
        st.caption("Select a user profile above to preview your dashboard access and sign in.")

    st.html("""
    <div style="text-align:center; margin-top:20px; padding:10px; border-top:1px solid rgba(0,212,255,0.1);">
        <span style="color:#64748B; font-size:0.65rem; letter-spacing:0.05em;">
            10 Assets · 3 Production Lines · 172K+ Sensor Readings · 13 Dynamic Tables · 6 Personas · 80+ Test Cases
        </span>
    </div>
    """)
    st.stop()

persona = st.session_state.persona
cfg = PERSONA_CONFIG.get(persona, PERSONA_CONFIG["TECHNICIAN"])

all_pages = {
    "executive": st.Page("app_pages/executive_dashboard.py", title="Executive dashboard", icon=":material/analytics:"),
    "operations": st.Page("app_pages/operations_dashboard.py", title="Operations center", icon=":material/dashboard:"),
    "wo_po": st.Page("app_pages/wo_po_console.py", title="WO / PO console", icon=":material/assignment:"),
    "maintenance": st.Page("app_pages/maintenance_dashboard.py", title="Maintenance hub", icon=":material/troubleshoot:"),
    "procurement": st.Page("app_pages/procurement_dashboard.py", title="Procurement", icon=":material/local_shipping:"),
    "digital_twin": st.Page("app_pages/digital_twin.py", title="Digital twin", icon=":material/science:"),
    "admin": st.Page("app_pages/admin_control_panel.py", title="Admin panel", icon=":material/admin_panel_settings:"),
    "copilot": st.Page("app_pages/copilot.py", title="Maintenance copilot", icon=":material/smart_toy:"),
}

nav_pages = [all_pages[k] for k in cfg["pages"] if k in all_pages]

with st.sidebar:
    st.markdown(f"**{cfg['icon']} {st.session_state.username}**")
    st.caption(cfg["label"])

    load_unread_notifications.clear()
    notifs = load_unread_notifications(persona)
    if st.session_state.get("_notifs_cleared"):
        notifs = notifs.iloc[:0]
        st.session_state._notifs_cleared = False
    notif_count = len(notifs) if len(notifs) > 0 else 0
    if notif_count > 0:
        with st.expander(f":material/notifications_active: **{notif_count} notification{'s' if notif_count != 1 else ''}**", expanded=False):
            for _, n in notifs.iterrows():
                icon = NOTIF_ICON.get(n["EVENT_TYPE"], ":material/info:")
                pri_color = "red" if n["PRIORITY"] == "HIGH" else "blue"
                with st.container(border=True):
                    st.markdown(f"{icon} **{n['TITLE']}**")
                    st.caption(f"{n['MESSAGE'][:120]}")
                    st.caption(f"{str(n['CREATED_AT'])[:16]} | {n['ENTITY_ID']}")
            if st.button("Mark all read", icon=":material/done_all:", use_container_width=True):
                try:
                    session = conn.session()
                    session.sql(
                        f"UPDATE {DB}.RAW_IT.APP_NOTIFICATIONS SET IS_READ = TRUE WHERE PERSONA_TARGET = :1 AND IS_READ = FALSE",
                        params=[persona],
                    ).collect()
                except Exception:
                    pass
                load_unread_notifications.clear()
                st.session_state._notifs_cleared = True
                st.rerun()
    else:
        st.caption(":material/notifications: No new notifications")

    st.divider()
    if st.button("Switch user", icon=":material/logout:", use_container_width=True):
        keys_to_clear = [k for k in st.session_state.keys() if k not in ("conn",)]
        for k in keys_to_clear:
            del st.session_state[k]
        st.rerun()
    if st.button("Refresh data", icon=":material/refresh:", use_container_width=True):
        st.cache_data.clear()
        st.rerun()

page = st.navigation(nav_pages, position="top")
page.run()
