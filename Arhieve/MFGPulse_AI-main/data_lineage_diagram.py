import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.patches import FancyBboxPatch
import numpy as np
from IPython.display import display, Image as IPImage
import io

fig, ax = plt.subplots(1, 1, figsize=(28, 36))
ax.set_xlim(-1, 27)
ax.set_ylim(-1, 37)
ax.axis('off')
fig.patch.set_facecolor('#0D1117')
ax.set_facecolor('#0D1117')

COLORS = {
    'base_table': '#1B4332',
    'stream': '#4A1942',
    'procedure': '#6B3A0A',
    'curated_dt': '#1A3A5C',
    'feature_dt': '#2D1B69',
    'ml_model': '#6B1A1A',
    'prediction_dt': '#8B4513',
    'analytics_dt': '#0B4F6C',
    'view': '#3D3D00',
    'task': '#4A2C2A',
    'agent': '#1B5E20',
}

def draw_box(ax, x, y, w, h, label, color, fontsize=7, text_color='#E6EDF3', alpha=0.85):
    box = FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.1",
                          facecolor=color, edgecolor='#484F58', linewidth=0.8, alpha=alpha, zorder=2)
    ax.add_patch(box)
    lines = label.split('\n')
    for i, line in enumerate(lines):
        fs = fontsize if i > 0 else fontsize + 0.5
        fw = 'bold' if i == 0 else 'normal'
        ax.text(x + w/2, y + h - 0.25 - i*0.38, line, ha='center', va='top',
                fontsize=fs, color=text_color, fontweight=fw, zorder=3,
                fontfamily='monospace')

def draw_arrow(ax, x1, y1, x2, y2, color='#8B949E', style='->', lw=0.8):
    ax.annotate('', xy=(x2, y2), xytext=(x1, y1),
                arrowprops=dict(arrowstyle=style, color=color, lw=lw, connectionstyle='arc3,rad=0.0'),
                zorder=1)

def draw_section(ax, x, y, w, h, title, color='#30363D'):
    rect = mpatches.FancyBboxPatch((x, y), w, h, boxstyle="round,pad=0.15",
                                    facecolor='#0D1117', edgecolor=color, linewidth=1.5,
                                    linestyle='--', alpha=0.9, zorder=0)
    ax.add_patch(rect)
    ax.text(x + 0.3, y + h - 0.15, title, fontsize=11, color='#58A6FF', fontweight='bold',
            fontfamily='monospace', zorder=1, va='top')

# == SECTION 1: INGESTION LAYER ==
draw_section(ax, 0, 30.5, 26.5, 6.2, 'INGESTION LAYER -- Base Tables & Data Generation', '#1F6FEB')

bw, bh = 3.2, 0.9
draw_box(ax, 0.5, 35.2, bw, bh, 'RAW_OT.ASSET_MASTER\n10 assets', COLORS['base_table'])
draw_box(ax, 4.2, 35.2, bw, bh, 'RAW_OT.SENSOR_METADATA\n23 sensors', COLORS['base_table'])
draw_box(ax, 7.9, 35.2, bw+0.6, bh, 'RAW_OT.SENSOR_READINGS\n~172K rows (proc-generated)', COLORS['base_table'])
draw_box(ax, 12.2, 35.2, bw, bh, 'RAW_OT.AMBIENT_\nCONDITIONS (190 days)', COLORS['base_table'])

draw_box(ax, 0.5, 33.8, bw, bh, 'RAW_IT.WORK_ORDERS\n22+ work orders', COLORS['base_table'])
draw_box(ax, 4.2, 33.8, bw+0.3, bh, 'RAW_IT.MAINTENANCE_LOGS\n26+ maint. records', COLORS['base_table'])
draw_box(ax, 8.3, 33.8, bw, bh, 'RAW_IT.PRODUCTION_\nOUTPUT (~3330 rows)', COLORS['base_table'])
draw_box(ax, 12.2, 33.8, bw, bh, 'RAW_IT.SHIFT_SCHEDULE\n~1710 shifts', COLORS['base_table'])
draw_box(ax, 16, 33.8, bw, bh, 'RAW_IT.PARTS_INVENTORY\n15 parts', COLORS['base_table'])

draw_box(ax, 16, 35.2, bw+1, bh, 'PROC: GENERATE_\nSENSOR_DATA() -> 172K rows', COLORS['procedure'])
draw_box(ax, 20.5, 35.2, bw+1.8, bh, 'PROC: SIMULATE_SENSOR_\nFEED_CONFIGURABLE(asset,scenario)', COLORS['procedure'])

draw_box(ax, 0.5, 32.2, bw+0.5, 0.7, 'STREAM: SENSOR_READINGS_STREAM', COLORS['stream'])
draw_box(ax, 5.2, 32.2, bw+0.8, 0.7, 'STREAM: MAINTENANCE_LOGS_STREAM', COLORS['stream'])
draw_box(ax, 10.2, 32.2, bw+0.5, 0.7, 'STREAM: WORK_ORDERS_STREAM', COLORS['stream'])

draw_box(ax, 20.0, 33.8, 3.0, bh, 'RAW_IT.SUPPLIERS\n5 suppliers', COLORS['base_table'])
draw_box(ax, 23.3, 33.8, 3.0, bh, 'RAW_IT.PURCHASE_\nORDERS + LINES', COLORS['base_table'])

draw_arrow(ax, 17.5, 35.2, 10.5, 36.1)
draw_arrow(ax, 22.5, 35.2, 10.5, 36.1)
draw_arrow(ax, 10.2, 35.2, 2.5, 32.9)
draw_arrow(ax, 5.7, 33.8, 7.0, 32.9)
draw_arrow(ax, 2.5, 33.8, 2.5, 32.9)

# == SECTION 2: CURATED LAYER ==
draw_section(ax, 0, 27.5, 26.5, 2.8, 'CURATED LAYER -- Dynamic Tables (target_lag = 2 days)', '#8957E5')

draw_box(ax, 0.5, 28.0, 5.5, 1.2, 'DT: CURATED.SENSOR_WITH_CONTEXT\nREADINGS + ASSET + SENSOR + AMBIENT', COLORS['curated_dt'])
draw_box(ax, 6.5, 28.0, 5.5, 1.2, 'DT: CURATED.ASSET_HEALTH_CURRENT\nLatest reading per asset (10 rows)', COLORS['curated_dt'])
draw_box(ax, 12.5, 28.0, 5.5, 1.2, 'DT: CURATED.FAILURE_HISTORY\nPre-failure sensor patterns (12 rows)', COLORS['curated_dt'])

draw_arrow(ax, 2.5, 32.2, 3.2, 29.2, lw=1.0)
draw_arrow(ax, 7.5, 32.2, 9.2, 29.2, lw=1.0)
draw_arrow(ax, 12, 32.2, 15.2, 29.2, lw=1.0)

# == SECTION 3: FEATURE ENGINEERING LAYER ==
draw_section(ax, 0, 19.5, 26.5, 7.8, 'FEATURE ENGINEERING LAYER -- ML_FEATURES Dynamic Tables & Views', '#DA3633')

draw_box(ax, 0.5, 25.5, 5.5, 1.2, 'DT: ML_FEATURES.ROLLING_STATS\n24h/72h rolling mean, std, range, slope', COLORS['feature_dt'])
draw_box(ax, 6.5, 25.5, 5.5, 1.2, 'DT: ML_FEATURES.SENSOR_INTERACTIONS\nCross-sensor ratios & products', COLORS['feature_dt'])
draw_box(ax, 12.5, 25.5, 5.5, 1.2, 'DT: ML_FEATURES.PHYSICS_COMPOSITE\nBearing wear, thermal, imbalance indices', COLORS['feature_dt'])
draw_box(ax, 19, 25.5, 5.0, 1.2, 'DT: ML_FEATURES.LABELED_DATA\nLabeled training samples', COLORS['feature_dt'])

draw_box(ax, 0.5, 23.5, 5.5, 1.2, 'DT: ML_FEATURES.TEMPORAL_MEMORY\nLag features & trend acceleration', COLORS['feature_dt'])
draw_box(ax, 6.5, 23.5, 5.5, 1.2, 'DT: ML_FEATURES.FLEET_COMPARISON\nAsset vs fleet avg z-scores', COLORS['feature_dt'])
draw_box(ax, 12.5, 23.5, 5.5, 1.2, 'DT: ML_FEATURES.CROSS_DOMAIN\nIT/OT fusion (sensor + work orders)', COLORS['feature_dt'])

draw_box(ax, 19, 23.5, 5.0, 1.2, 'PROC: COMPUTE_FATIGUE_\nSCORE -> ML_MODELS.\nFATIGUE_SCORES', COLORS['procedure'])

draw_box(ax, 0.5, 21.2, 5.5, 1.5, 'VIEW: ALL_DERIVED_FEATURES\n+ ALL_DERIVED_FEATURES_\nINFERENCE (union of all DTs)', COLORS['view'])
draw_box(ax, 6.5, 21.2, 5.5, 1.5, 'VIEWS: TRAIN_FAILURE_MODE\nTRAIN_RUL | TRAIN_TRAJECTORY\nTRAIN_ANOMALY (training sets)', COLORS['view'])
draw_box(ax, 12.5, 21.2, 5.5, 1.5, 'VIEW: FEATURE_CATALOG\nAll features with metadata\n+ HEALTHY_DERIVED_FEATURES', COLORS['view'])

for sx in [3.2, 9.2, 15.2]:
    for tx in [3.2, 9.2, 15.2]:
        draw_arrow(ax, sx, 28.0, tx, 26.7, color='#6E40C9', lw=0.6)

for sx in [3.2, 9.2, 15.2]:
    for tx in [3.2, 9.2, 15.2]:
        draw_arrow(ax, sx, 25.5, tx, 24.7, color='#6E40C9', lw=0.6)

for sx in [3.2, 9.2, 15.2]:
    for tx in [3.2, 9.2, 15.2]:
        draw_arrow(ax, sx, 23.5, tx, 22.7, color='#6E40C9', lw=0.5)

# == SECTION 4: PREDICTION LAYER ==
draw_section(ax, 0, 13, 26.5, 6.3, 'PREDICTION LAYER -- ML Models & Live Predictions', '#F85149')

draw_box(ax, 0.5, 17.5, 3.8, 1.2, 'UDF M1: FAILURE_MODE\nCLASSIFIER (5 modes)', COLORS['ml_model'])
draw_box(ax, 4.8, 17.5, 3.8, 1.2, 'UDF M2: RUL_ESTIMATOR\nDays remaining', COLORS['ml_model'])
draw_box(ax, 9.1, 17.5, 3.8, 1.2, 'UDF M3: DEGRADATION\nSTAGER (3 classes)', COLORS['ml_model'])
draw_box(ax, 13.4, 17.5, 3.8, 1.2, 'UDF M4: FATIGUE_\nSCORE (0-100)', COLORS['ml_model'])

draw_box(ax, 0.5, 16.0, 3.8, 1.0, 'PROC M5: ROOT_CAUSE\nANALYSIS', COLORS['ml_model'])
draw_box(ax, 4.8, 16.0, 3.8, 1.0, 'UDF M6: FAILURE_TWIN\nSIMULATOR (Monte Carlo)', COLORS['ml_model'])
draw_box(ax, 9.1, 16.0, 3.8, 1.0, 'PROC M7: PRESCRIPTIVE\nMAINTENANCE AI', COLORS['ml_model'])

draw_box(ax, 17.7, 17.5, 4.0, 1.2, 'NATIVE N1: FAILURE\nMODE CLASSIFIER', COLORS['ml_model'])
draw_box(ax, 22.0, 17.5, 4.0, 1.2, 'NATIVE N3: RUL\nFORECAST', COLORS['ml_model'])
draw_box(ax, 17.7, 16.0, 4.0, 1.0, 'NATIVE N2: DEGRAD.\nSTAGER', COLORS['ml_model'])
draw_box(ax, 22.0, 16.0, 4.0, 1.0, 'NATIVE N4: ANOMALY\nDETECTOR', COLORS['ml_model'])

draw_box(ax, 5.5, 14.0, 8, 1.2, 'DT: ML_MODELS.LIVE_PREDICTIONS\nCalls M1-M4 per asset (10 rows, target_lag=2d)', COLORS['prediction_dt'], fontsize=8)
draw_box(ax, 14.5, 14.0, 5.5, 1.2, 'TABLE: ML_MODELS.\nFATIGUE_SCORES (6.7K rows)\n+ ANOMALY_SCORES', COLORS['prediction_dt'])

for tx in [2.4, 6.7, 11.0, 15.3]:
    draw_arrow(ax, 3.2, 21.2, tx, 18.7, color='#F85149', lw=0.7)
    draw_arrow(ax, 9.2, 21.2, tx, 18.7, color='#F85149', lw=0.5)

for sx in [2.4, 6.7, 11.0, 15.3]:
    draw_arrow(ax, sx, 17.5, 9.5, 15.2, color='#F85149', lw=0.8)

# == SECTION 5: ANALYTICS & SERVING LAYER ==
draw_section(ax, 0, 5.0, 26.5, 7.8, 'ANALYTICS & SERVING LAYER -- Alerts, OEE, Agent, Streamlit', '#238636')

draw_box(ax, 0.5, 11.0, 5.5, 1.2, 'DT: ANALYTICS.ACTIVE_ALERTS\nSeverity-based alert engine', COLORS['analytics_dt'])
draw_box(ax, 6.5, 11.0, 5.5, 1.2, 'DT: ANALYTICS.OEE_METRICS\nPer-asset per-shift OEE', COLORS['analytics_dt'])

draw_box(ax, 12.5, 11.0, 4.2, 1.2, 'VIEW: ALERT_SUMMARY\n+ EXECUTIVE_SUMMARY', COLORS['view'])
draw_box(ax, 17.2, 11.0, 4.5, 1.2, 'VIEW: COST_IMPACT\n+ PREDICTIONS_WITH_COST', COLORS['view'])
draw_box(ax, 22.0, 11.0, 4.2, 1.2, 'VIEW: SHIFT_HANDOVER\n+ PROCUREMENT VIEWS (5)', COLORS['view'])

draw_box(ax, 0.5, 8.8, 5.5, 1.5, 'CORTEX SEARCH SERVICE\nML_MODELS.MAINTENANCE_\nSEARCH (RAG index)', COLORS['agent'], fontsize=7.5)
draw_box(ax, 6.5, 8.8, 5.5, 1.5, 'SEMANTIC VIEW\nAGENT.MAINTENANCE_\nSEMANTIC_VIEW (6 tables, 24 VQRs)', COLORS['agent'], fontsize=7.5)
draw_box(ax, 12.5, 8.8, 5.5, 1.5, 'CORTEX AGENT\nMAINTENANCE_COPILOT\n5 tools (SQL, RAG, predict, sim, WO)', COLORS['agent'], fontsize=7.5)

draw_box(ax, 0.5, 6.8, 5.5, 1.3, 'PROC: AUTO_GENERATE_\nWORK_ORDERS -> WORK_ORDERS', COLORS['procedure'])
draw_box(ax, 6.5, 6.8, 5.5, 1.3, 'PROC: AUTO_GENERATE_\nPURCHASE_ORDERS -> POs + Lines', COLORS['procedure'])

draw_box(ax, 18.5, 6.5, 7.5, 3.5, 'TASK DAG (every 12h)\n-----------------------------\n(1) SIMULATE_ALL_FEEDS\n(2) REFRESH_FATIGUE_SCORES\n(3) REFRESH_ALL_DTS (13 DTs)\n(4) AUTO_GENERATE_WOs\n(5) AUTO_GENERATE_POs\n(6) AUTO_CONVERT_PLANNED_POs', COLORS['task'], fontsize=7)

draw_box(ax, 12.5, 5.5, 5.5, 2.5, 'STREAMLIT DASHBOARD\nMFGPulse Command Center\n-----------------------------\n6 personas | 7 pages\nOEE | Ops | Maint | Twin\nProcurement | Admin | Copilot', COLORS['agent'], fontsize=7)

draw_arrow(ax, 7.5, 14.0, 3.2, 12.2, color='#3FB950', lw=1.0)
draw_arrow(ax, 11.5, 14.0, 9.2, 12.2, color='#3FB950', lw=1.0)

draw_arrow(ax, 5.5, 11.6, 12.5, 11.6, color='#3FB950', lw=0.7)
draw_arrow(ax, 11.5, 11.6, 17.2, 11.6, color='#3FB950', lw=0.7)

draw_arrow(ax, 3.2, 11.0, 3.2, 10.3, color='#3FB950', lw=0.7)
draw_arrow(ax, 9.2, 11.0, 9.2, 10.3, color='#3FB950', lw=0.7)
draw_arrow(ax, 3.2, 8.8, 14.5, 10.3, color='#3FB950', lw=0.5)
draw_arrow(ax, 9.2, 8.8, 14.5, 10.3, color='#3FB950', lw=0.5)

draw_arrow(ax, 15.2, 8.8, 15.2, 8.0, color='#3FB950', lw=0.8)

draw_arrow(ax, 22.3, 10.0, 22.3, 11.0, color='#D29922', lw=0.8, style='->')

# == TITLE ==
ax.text(13.25, 36.65, 'MFGPulse AI -- Complete Data Lineage', ha='center', va='bottom',
        fontsize=18, color='#F0F6FC', fontweight='bold', fontfamily='monospace')
ax.text(13.25, 36.35, 'FAILURE_GENOME_DB  |  7 schemas  |  19 tables  |  13 dynamic tables  |  22 views  |  7 ML models  |  6-task DAG',
        ha='center', va='bottom', fontsize=9, color='#8B949E', fontfamily='monospace')

# == LEGEND ==
legend_items = [
    ('Base Table', COLORS['base_table']),
    ('Stream (CDC)', COLORS['stream']),
    ('Procedure / UDF', COLORS['procedure']),
    ('Curated DT', COLORS['curated_dt']),
    ('Feature DT', COLORS['feature_dt']),
    ('ML Model', COLORS['ml_model']),
    ('Prediction DT/Table', COLORS['prediction_dt']),
    ('Analytics DT', COLORS['analytics_dt']),
    ('View', COLORS['view']),
    ('Task DAG', COLORS['task']),
    ('Agent / Search / App', COLORS['agent']),
]

for i, (label, color) in enumerate(legend_items):
    x = 0.5 + (i % 6) * 4.4
    y = -0.6 if i < 6 else -1.2
    rect = mpatches.FancyBboxPatch((x, y), 0.4, 0.3, boxstyle="round,pad=0.02",
                                    facecolor=color, edgecolor='#484F58', linewidth=0.5)
    ax.add_patch(rect)
    ax.text(x + 0.55, y + 0.15, label, fontsize=7, color='#C9D1D9', va='center', fontfamily='monospace')

plt.tight_layout(pad=0.5)

buf = io.BytesIO()
plt.savefig(buf, format='png', dpi=180, bbox_inches='tight',
            facecolor='#0D1117', edgecolor='none')
buf.seek(0)
plt.close(fig)

with open('/tmp/mfgpulse_data_lineage.png', 'wb') as f:
    f.write(buf.getvalue())

display(IPImage(data=buf.getvalue()))
print("Lineage diagram rendered successfully")
