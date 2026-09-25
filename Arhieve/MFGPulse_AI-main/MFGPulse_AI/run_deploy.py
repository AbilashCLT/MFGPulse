import json, os, re, sys

def split_sql_statements(sql_text):
    """Split SQL into statements, respecting string literals and $$ blocks."""
    statements = []
    current = []
    i = 0
    in_single_quote = False
    in_dollar_quote = False
    line_num = 1
    stmt_start_line = 1
    
    while i < len(sql_text):
        ch = sql_text[i]
        
        if ch == '\n':
            line_num += 1
        
        # Handle $$ delimiters
        if not in_single_quote and i + 1 < len(sql_text) and sql_text[i:i+2] == '$$':
            current.append('$$')
            i += 2
            in_dollar_quote = not in_dollar_quote
            continue
        
        # Handle single quotes (with '' escape)
        if not in_dollar_quote:
            if ch == "'" and not in_single_quote:
                in_single_quote = True
                current.append(ch)
                i += 1
                continue
            elif ch == "'" and in_single_quote:
                if i + 1 < len(sql_text) and sql_text[i+1] == "'":
                    current.append("''")
                    i += 2
                    continue
                else:
                    in_single_quote = False
                    current.append(ch)
                    i += 1
                    continue
        
        # Handle semicolons (statement terminators)
        if ch == ';' and not in_single_quote and not in_dollar_quote:
            stmt = ''.join(current).strip()
            if stmt and not stmt.startswith('--'):
                # Remove leading comments-only lines
                lines = stmt.split('\n')
                non_comment_found = False
                cleaned = []
                for line in lines:
                    stripped = line.strip()
                    if not non_comment_found and (stripped == '' or stripped.startswith('--')):
                        continue
                    non_comment_found = True
                    cleaned.append(line)
                stmt = '\n'.join(cleaned).strip()
                if stmt and not all(l.strip().startswith('--') or l.strip() == '' for l in stmt.split('\n')):
                    statements.append((stmt_start_line, stmt))
            current = []
            stmt_start_line = line_num
            i += 1
            continue
        
        current.append(ch)
        i += 1
    
    # Handle last statement without trailing semicolon
    stmt = ''.join(current).strip()
    if stmt and not stmt.startswith('--'):
        lines = stmt.split('\n')
        non_comment_found = False
        cleaned = []
        for line in lines:
            stripped = line.strip()
            if not non_comment_found and (stripped == '' or stripped.startswith('--')):
                continue
            non_comment_found = True
            cleaned.append(line)
        stmt = '\n'.join(cleaned).strip()
        if stmt and not all(l.strip().startswith('--') or l.strip() == '' for l in stmt.split('\n')):
            statements.append((stmt_start_line, stmt))
    
    return statements

def get_stmt_type(stmt):
    """Get first keyword(s) for display."""
    s = re.sub(r'--[^\n]*\n', '', stmt).strip()
    words = s.split()[:5]
    return ' '.join(words)[:80]

def main():
    token_path = os.environ.get('SNOWFLAKE_TOKEN_FILE_PATH', '/snowflake/session/token')
    with open(token_path) as f:
        token = f.read().strip()
    
    import snowflake.connector
    conn = snowflake.connector.connect(
        account=os.environ.get('SNOWFLAKE_ACCOUNT', ''),
        host=os.environ.get('SNOWFLAKE_HOST', ''),
        token=token,
        authenticator='oauth',
        database='MFGPULSE_DB',
        schema='PUBLIC',
        role='ACCOUNTADMIN',
        warehouse='MFGPULSE_AUTOMATION_WH'
    )
    
    with open('/workspace/MFGPulse_AI/sql/deploy_one_time_consolidated.sql') as f:
        sql_text = f.read()
    
    statements = split_sql_statements(sql_text)
    print(f"Parsed {len(statements)} statements")
    
    errors = []
    success_count = 0
    cur = conn.cursor()
    
    for idx, (line_num, stmt) in enumerate(statements):
        stmt_preview = get_stmt_type(stmt)
        try:
            cur.execute(stmt)
            success_count += 1
            # Print progress every 10 statements
            if (idx + 1) % 10 == 0:
                print(f"  [{idx+1}/{len(statements)}] OK - {stmt_preview}")
        except Exception as e:
            err_msg = str(e).split('\n')[0][:200]
            errors.append({
                'index': idx + 1,
                'line': line_num,
                'preview': stmt_preview,
                'error': err_msg,
                'stmt': stmt[:500]
            })
            print(f"  [{idx+1}/{len(statements)}] ERROR at line {line_num}: {stmt_preview}")
            print(f"    -> {err_msg}")
    
    cur.close()
    conn.close()
    
    print(f"\n{'='*60}")
    print(f"RESULTS: {success_count} succeeded, {len(errors)} failed out of {len(statements)} statements")
    print(f"{'='*60}")
    
    if errors:
        print("\nFAILED STATEMENTS:")
        for e in errors:
            print(f"\n--- Statement #{e['index']} (line {e['line']}) ---")
            print(f"Preview: {e['preview']}")
            print(f"Error:   {e['error']}")
            print(f"SQL:     {e['stmt'][:300]}...")
    
    # Write errors to file for further processing
    with open('/workspace/MFGPulse_AI/deploy_errors.json', 'w') as f:
        json.dump(errors, f, indent=2)
    
    return len(errors)

if __name__ == '__main__':
    sys.exit(main())
