"""Migrate UDFs and procs from PUBLIC to their correct schemas using GET_DDL."""
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
    database='MFGPULSE_DB'
)
cur = conn.cursor()

# UDFs to move from PUBLIC to ML_MODELS
udfs = [
    ('COMPUTE_FATIGUE_SCORE', '(FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT)'),
    ('PREDICT_DEGRADATION_STAGE', '(FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT)'),
    ('PREDICT_FAILURE_MODE', '(FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT)'),
    ('PREDICT_RUL', '(FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT)'),
    ('SIMULATE_FAILURE_TWIN', '(FLOAT,FLOAT,FLOAT,FLOAT,FLOAT,FLOAT)'),
]

for name, sig in udfs:
    fqn = f'MFGPULSE_DB.PUBLIC.{name}{sig}'
    try:
        cur.execute(f"SELECT GET_DDL('FUNCTION', '{fqn}') AS ddl")
        ddl = cur.fetchone()[0]
        # Replace schema: change "name" to ML_MODELS."name"
        ddl = ddl.replace(f'"{name}"(', f'ML_MODELS."{name}"(', 1)
        cur.execute(ddl)
        print(f"  OK: ML_MODELS.{name}")
    except Exception as e:
        print(f"  ERROR: {name} -> {str(e)[:200]}")

# Procedures to move from PUBLIC to ML_MODELS
cur.execute("SHOW PROCEDURES IN SCHEMA MFGPULSE_DB.PUBLIC")
procs = cur.fetchall()
print(f"\nProcedures in PUBLIC: {len(procs)}")

# Map of proc names to target schemas
proc_schema_map = {
    'PRESCRIBE_MAINTENANCE': 'ML_MODELS',
    'ANALYZE_ROOT_CAUSE': 'ML_MODELS',
    'PREDICT_ALL': 'ML_MODELS',
    'AUTO_GENERATE_WORK_ORDERS': 'ANALYTICS',
    'GENERATE_SHIFT_HANDOVER_SUMMARY': 'ANALYTICS',
    'GENERATE_WORK_ORDER': 'ANALYTICS',
}

for row in procs:
    pname = row[1]  # name column
    args = row[8]   # arguments column
    if pname not in proc_schema_map:
        continue
    target_schema = proc_schema_map[pname]
    # Parse argument types from the arguments string
    # Format: "NAME(TYPE, TYPE) RETURN TYPE"
    m = re.match(r'\w+\((.*?)\)\s+RETURN', args)
    if not m:
        print(f"  SKIP: {pname} (can't parse args: {args[:80]})")
        continue
    arg_types = m.group(1)
    fqn = f'MFGPULSE_DB.PUBLIC.{pname}({arg_types})'
    try:
        cur.execute(f"SELECT GET_DDL('PROCEDURE', '{fqn}') AS ddl")
        ddl = cur.fetchone()[0]
        # Replace schema
        ddl = ddl.replace(f'"{pname}"(', f'{target_schema}."{pname}"(', 1)
        cur.execute(ddl)
        print(f"  OK: {target_schema}.{pname}")
    except Exception as e:
        print(f"  ERROR: {pname} -> {str(e)[:300]}")

# Verify
print("\n--- Verification ---")
for schema in ['ML_MODELS', 'ANALYTICS']:
    cur.execute(f"SHOW USER FUNCTIONS IN SCHEMA MFGPULSE_DB.{schema}")
    funcs = cur.fetchall()
    print(f"  Functions in {schema}: {len(funcs)} -> {[r[1] for r in funcs]}")
    cur.execute(f"SHOW PROCEDURES IN SCHEMA MFGPULSE_DB.{schema}")
    procs_v = cur.fetchall()
    print(f"  Procedures in {schema}: {len(procs_v)} -> {[r[1] for r in procs_v]}")

cur.close()
conn.close()
