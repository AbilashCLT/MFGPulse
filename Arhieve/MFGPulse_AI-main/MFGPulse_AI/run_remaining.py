"""Run remaining Checkpoint 11-12 statements using a robust parser."""
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
    warehouse='MFGPULSE_AUTOMATION_WH',
    database='MFGPULSE_DB',
    schema='PUBLIC'
)
cur = conn.cursor()

with open('/workspace/MFGPulse_AI/sql/deploy_one_time_consolidated.sql') as f:
    sql = f.read()

# Extract from CHECKPOINT 11 to CHECKPOINT 13
cp11_start = sql.find('-- CHECKPOINT 11: NOTIFICATIONS')
cp13_start = sql.find('-- CHECKPOINT 13-14: MANUAL STEPS')
if cp13_start == -1:
    section = sql[cp11_start:]
else:
    section = sql[cp11_start:cp13_start]

# Split by semicolons, respecting $$ and '' delimiters
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
            current.append(ch)
            i += 1
            continue
        elif ch == "'" and in_sq:
            if i+1 < len(section) and section[i+1] == "'":
                current.append("''")
                i += 2
                continue
            else:
                in_sq = False
                current.append(ch)
                i += 1
                continue
    if ch == ';' and not in_sq and not in_dq:
        stmt = ''.join(current).strip()
        # Remove leading comment-only lines
        lines = stmt.split('\n')
        clean = []
        started = False
        for line in lines:
            s = line.strip()
            if not started and (s == '' or s.startswith('--')):
                continue
            started = True
            clean.append(line)
        stmt = '\n'.join(clean).strip()
        if stmt and not all(l.strip().startswith('--') or l.strip() == '' for l in stmt.split('\n')):
            statements.append(stmt)
        current = []
        i += 1
        continue
    current.append(ch)
    i += 1

print(f"Found {len(statements)} statements in Checkpoints 11-12")

errors = []
for idx, stmt in enumerate(statements):
    preview = ' '.join(stmt.split()[:6])[:80]
    try:
        cur.execute(stmt)
        print(f"  [{idx+1}/{len(statements)}] OK: {preview}")
    except Exception as e:
        err = str(e).split('\n')[0][:250]
        errors.append((idx+1, preview, err))
        print(f"  [{idx+1}/{len(statements)}] ERROR: {preview}")
        print(f"    -> {err}")

print(f"\nResults: {len(statements)-len(errors)} succeeded, {len(errors)} failed")
if errors:
    print("\nFailed statements:")
    for i, p, e in errors:
        print(f"  #{i}: {p}")
        print(f"       {e}")

cur.close()
conn.close()
