"""Re-create UDFs/procs from the deploy file, forcing fully-qualified DB.SCHEMA names."""
import os, re
import snowflake.connector

token_path = os.environ.get('SNOWFLAKE_TOKEN_FILE_PATH', '/snowflake/session/token')
with open(token_path) as f:
    token = f.read().strip()

conn = snowflake.connector.connect(
    account=os.environ.get('SNOWFLAKE_ACCOUNT', ''),
    host=os.environ.get('SNOWFLAKE_HOST', ''),
    token=token,
    authenticator='oauth',
    role='ACCOUNTADMIN',
    warehouse='MFGPULSE_AUTOMATION_WH'
)
cur = conn.cursor()
cur.execute("USE DATABASE MFGPULSE_DB")

with open('/workspace/MFGPulse_AI/sql/deploy_one_time_consolidated.sql') as f:
    sql = f.read()

# Extract statements between CHECKPOINT 6 and CHECKPOINT 7
cp6_start = sql.find('-- CHECKPOINT 6: UDFs AND ML PROCEDURES')
cp7_start = sql.find('-- CHECKPOINT 7: DYNAMIC TABLES')
section = sql[cp6_start:cp7_start]

# Split by semicolons respecting quotes
statements = []
current = []
in_sq = False
in_dq = False
i = 0
while i < len(section):
    ch = section[i]
    if not in_sq and i+1 < len(section) and section[i:i+2] == '$$':
        current.append('$$')
        i += 2
        in_dq = not in_dq
        continue
    if not in_dq:
        if ch == "'" and not in_sq:
            in_sq = True
        elif ch == "'" and in_sq:
            if i+1 < len(section) and section[i+1] == "'":
                current.append("'")
                i += 2
                continue
            else:
                in_sq = False
    if ch == ';' and not in_sq and not in_dq:
        stmt = ''.join(current).strip()
        if stmt and ('CREATE OR REPLACE FUNCTION' in stmt or 'CREATE OR REPLACE PROCEDURE' in stmt):
            statements.append(stmt)
        current = []
        i += 1
        continue
    current.append(ch)
    i += 1

print(f"Found {len(statements)} CREATE FUNCTION/PROCEDURE statements in Checkpoint 6")

for idx, stmt in enumerate(statements):
    # Get the object name
    m = re.search(r'(FUNCTION|PROCEDURE)\s+(\S+)\(', stmt, re.IGNORECASE)
    name = m.group(2) if m else "unknown"
    try:
        cur.execute(stmt)
        print(f"  [{idx+1}] OK: {name}")
    except Exception as e:
        err = str(e).split('\n')[0][:200]
        print(f"  [{idx+1}] ERROR: {name} -> {err}")

# Also handle procedures from Checkpoint 9 area (ANALYTICS schema)
# These are already in the correct schema in the file, re-running just to be safe
cp9_procs = [
    "ANALYTICS.AUTO_GENERATE_WORK_ORDERS",
    "ANALYTICS.GENERATE_SHIFT_HANDOVER_SUMMARY",
    "ANALYTICS.GENERATE_WORK_ORDER",
]
# Check if they exist in correct schema
for proc in cp9_procs:
    schema = proc.split('.')[0]
    name = proc.split('.')[1]
    cur.execute(f"SHOW PROCEDURES LIKE '{name}' IN SCHEMA MFGPULSE_DB.{schema}")
    rows = cur.fetchall()
    if rows:
        print(f"  {proc}: EXISTS in {schema}")
    else:
        print(f"  {proc}: MISSING from {schema}")

cur.close()
conn.close()
print("\nDone.")
