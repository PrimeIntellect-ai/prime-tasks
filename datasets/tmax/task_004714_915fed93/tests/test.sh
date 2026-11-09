#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TRACE_EOF' > /tmp/sqltrace.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void log_sql(const char *sql, int n) {
    const char *path = getenv("SQL_TRACE_FILE");
    if (!path || !sql) return;
    if (n < 0) n = (int)strlen(sql);
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) return;
    write(fd, sql, (size_t)n);
    write(fd, "\n--TRACE-END--\n", 15);
    close(fd);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql, n);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql, n);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void *, int, char **, char **),
                 void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql, -1);
    return real_fn(db, sql, callback, arg, errmsg);
}
TRACE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import subprocess

DB_PATH = '/home/user/backups.db'
OUT_PATH = '/home/user/restore_cost.txt'
EXE_PATH = '/home/user/pipeline'
TRACE_LIB = '/tmp/libsqltrace.so'

BASE_ROWS = [
    ('bkp_100', 'FULL', 5000, 1600000000),
    ('bkp_101', 'INC', 250, 1600086400),
    ('bkp_102', 'INC', 120, 1600172800),
    ('bkp_103', 'INC', 300, 1600259200),
    ('bkp_104', 'INC', 150, 1600345600),
    ('bkp_105', 'INC', 80, 1600432000),
    ('bkp_106', 'INC', 90, 1600518400),
]

def strip_comments(text):
    text = re.sub(r'/\*.*?\*/', ' ', text, flags=re.S)
    text = re.sub(r'//[^\n]*', ' ', text)
    return text

def reset_database(rows=BASE_ROWS):
    try:
        os.remove(DB_PATH)
    except FileNotFoundError:
        pass
    con = sqlite3.connect(DB_PATH)
    con.execute('CREATE TABLE backup_metadata (id TEXT PRIMARY KEY, type TEXT, size_mb INTEGER, timestamp INTEGER)')
    con.executemany('INSERT INTO backup_metadata VALUES (?, ?, ?, ?)', rows)
    con.commit()
    con.close()

def compile_pipeline():
    proc = subprocess.run(
        ['gcc', '/home/user/pipeline.c', '-o', EXE_PATH, '-lsqlite3'],
        capture_output=True,
    )
    assert proc.returncode == 0, f"Failed to compile pipeline.c:\n{proc.stderr.decode()}"

def assert_window_sql(sql):
    normalized = re.sub(r'\s+', ' ', sql.upper())
    assert re.search(r'\bSUM\s*\(\s*(?:[A-Z_]\w*\.)?SIZE_MB\s*\)\s*OVER\s*\(', normalized), \
        f"No executed SQL statement used SUM(size_mb) as a window function. Trace:\n{sql}"
    assert re.search(r'\bORDER\s+BY\s+(?:[A-Z_]\w*\.)?TIMESTAMP(?:\s+ASC)?\b', normalized), \
        f"The executed window query was not ordered by timestamp ascending. Trace:\n{sql}"
    assert re.search(r'\bBACKUP_METADATA\b', normalized), \
        f"The executed window query did not query backup_metadata. Trace:\n{sql}"

def run_pipeline(ids):
    trace_path = f"/tmp/sqltrace-{os.getpid()}-{secrets.token_hex(8)}.log"
    try:
        os.remove(OUT_PATH)
    except FileNotFoundError:
        pass
    env = os.environ.copy()
    env['LD_PRELOAD'] = TRACE_LIB
    env['SQL_TRACE_FILE'] = trace_path
    input_data = ''.join(x + '\n' for x in ids)
    proc = subprocess.run(
        [EXE_PATH], input=input_data.encode(), capture_output=True,
        env=env, timeout=10,
    )
    assert proc.returncode == 0, f"Pipeline execution failed:\n{proc.stderr.decode()}"
    assert os.path.exists(OUT_PATH), f"{OUT_PATH} was not created by the pipeline."
    with open(OUT_PATH, 'rb') as f:
        output = f.read()
    assert os.path.exists(trace_path), 'The program did not execute a traceable SQLite query.'
    with open(trace_path, 'r', errors='replace') as f:
        trace = f.read()
    os.remove(trace_path)
    assert_window_sql(trace)
    return output

def test_cypher_query_exists_and_valid():
    """Verify that the Cypher query file exists and contains a MATCH clause."""
    cypher_path = '/home/user/chain.cypher'
    assert os.path.exists(cypher_path), f"{cypher_path} does not exist."
    with open(cypher_path, 'r') as f:
        content = f.read().upper()
    assert "MATCH" in content, "The Cypher query does not contain a MATCH clause."

def test_cypher_query_has_required_path_semantics():
    with open('/home/user/chain.cypher', 'r') as f:
        content = strip_comments(f.read()).upper()
    assert re.match(r'^\s*MATCH\b', content), 'The Cypher file must contain an actual MATCH query.'
    path_match = re.search(r'\bMATCH\s+([A-Z_]\w*)\s*=\s*', content)
    assert path_match, 'The MATCH clause must bind the dependency path so its nodes can be returned.'
    path_var = path_match.group(1)
    assert re.search(r'\{[^}]*\bID\s*:\s*[\'\"]BKP_105[\'\"][^}]*\}', content), \
        "The path must start from the backup whose id is 'bkp_105'."
    assert re.search(r'-\s*\[[^]]*\bDEPENDS_ON\b[^]]*\*[^]]*\]\s*->', content), \
        'The query must traverse a variable-length DEPENDS_ON relationship in the outgoing direction.'
    assert re.search(r'\{[^}]*\bTYPE\s*:\s*[\'\"]FULL[\'\"][^}]*\}', content), \
        "The path must terminate at a backup whose type is 'FULL'."
    assert re.search(r'\bNODES\s*\(\s*' + re.escape(path_var) + r'\s*\)', content), \
        'The query must obtain all nodes in the matched path.'
    return_clause = re.search(r'\bRETURN\b(.+?)(?:;|$)', content, flags=re.S)
    assert return_clause and re.search(r'\.\s*ID\b', return_clause.group(1)), \
        'The query must return the id property of path backups.'
    assert ',' not in return_clause.group(1), 'The RETURN clause must return only backup IDs.'

def test_c_pipeline_exists_and_uses_window_function():
    """Verify that the C pipeline source exists and uses a SQL Window Function."""
    c_path = '/home/user/pipeline.c'
    assert os.path.exists(c_path), f"{c_path} does not exist."
    with open(c_path, 'r') as f:
        content = f.read().upper()
    assert "OVER" in content, "The C program does not seem to use a SQL Window Function (missing OVER clause)."

def test_c_source_uses_sqlite_api_and_real_window_expression():
    with open('/home/user/pipeline.c', 'r') as f:
        source = strip_comments(f.read())
    upper = source.upper()
    assert re.search(r'#\s*INCLUDE\s*[<\"]SQLITE3\.H[>\"]', upper), 'pipeline.c must include sqlite3.h.'
    assert re.search(r'\bSQLITE3_OPEN(?:_V2)?\s*\(', upper), 'pipeline.c must open the SQLite database with the SQLite C API.'
    assert re.search(r'\bSQLITE3_(?:PREPARE(?:_V2|_V3)?|EXEC)\s*\(', upper), 'pipeline.c must execute SQL with the SQLite C API.'
    literals = re.findall(r'"((?:\\.|[^"\\])*)"', source, flags=re.S)
    sql_text = ''.join(bytes(x, 'utf-8').decode('unicode_escape', errors='replace') for x in literals).upper()
    assert re.search(r'\bSUM\s*\(\s*(?:[A-Z_]\w*\.)?SIZE_MB\s*\)\s*OVER\s*\(', sql_text), \
        'The SQL text must contain a SUM(size_mb) window expression.'
    assert re.search(r'\bORDER\s+BY\s+(?:[A-Z_]\w*\.)?TIMESTAMP(?:\s+ASC)?\b', sql_text), \
        'The window expression must order rows by timestamp ascending.'

def test_pipeline_execution_and_output():
    """Compile the C program, run it with mock input, and verify the output."""
    c_path = '/home/user/pipeline.c'
    assert os.path.exists(c_path), f"Cannot compile because {c_path} is missing."
    reset_database()
    compile_pipeline()
    input_ids = ['bkp_105', 'bkp_104', 'bkp_103', 'bkp_102', 'bkp_101', 'bkp_100']
    output = run_pipeline(input_ids)
    cost = output.decode().strip()
    assert cost == "5900", f"Expected restore cost to be 5900, but got '{cost}'."
    assert output == b'5900\n', 'restore_cost.txt must contain exactly one integer and a newline.'

def test_pipeline_queries_database_for_varied_subsets_and_values():
    ids = [row[0] for row in BASE_ROWS]
    cases = [
        ['bkp_106'],
        ['bkp_100', 'bkp_103', 'bkp_105'],
        ['bkp_104', 'bkp_101'],
        ['bkp_106', 'bkp_102', 'bkp_100', 'bkp_105'],
    ]
    for case_no, selected in enumerate(cases):
        sizes = {backup_id: 1000 + secrets.randbelow(900000) for backup_id in ids}
        timestamps = list(range(1700000000, 1700000000 + len(ids) * 97, 97))
        timestamps = timestamps[case_no:] + timestamps[:case_no]
        rows = []
        for i, backup_id in enumerate(ids):
            backup_type = 'FULL' if backup_id == 'bkp_100' else 'INC'
            rows.append((backup_id, backup_type, sizes[backup_id], timestamps[i]))
        reset_database(rows)
        output = run_pipeline(list(reversed(selected)) if case_no % 2 else selected)
        expected = sum(sizes[x] for x in selected)
        assert output == f'{expected}\n'.encode(), \
            f'Expected exactly {expected} for IDs {selected}, but got {output!r}.'
TEST_EOF

if gcc -shared -fPIC /tmp/sqltrace.c -o /tmp/libsqltrace.so -ldl -lsqlite3 \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
