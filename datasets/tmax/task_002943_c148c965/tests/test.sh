#!/bin/bash
set -e
mkdir -p /logs/verifier

cat > /tmp/sqlite_trace.c <<'TRACE_EOF'
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static void log_sql(const void *sql, int is16) {
    const char *path = getenv("SQL_TRACE_FILE");
    if (!path || !sql || is16) return;
    FILE *f = fopen(path, "a");
    if (f) {
        fprintf(f, "\n---SQL---\n%s\n", (const char *)sql);
        fclose(f);
    }
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*, const char*, int, sqlite3_stmt**, const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql, 0);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*, const char*, int, sqlite3_stmt**, const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql, 0);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*, const char*, int, unsigned int, sqlite3_stmt**, const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql, 0);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void*,int,char**,char**), void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3*, const char*, int (*)(void*,int,char**,char**), void*, char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql, 0);
    return real_fn(db, sql, cb, arg, errmsg);
}
TRACE_EOF

gcc -shared -fPIC /tmp/sqlite_trace.c -o /tmp/sqlite_trace.so -ldl

cat > /tmp/verify_task.py <<'PY_EOF'
import json
import os
import re
import sqlite3
import subprocess
from pathlib import Path

DB = Path('/home/user/papers.db')
SRC = Path('/home/user/analyze_citations.cpp')
BIN = Path('/home/user/analyze_citations')
CSV = Path('/home/user/citation_summary.csv')
TRACE = Path('/tmp/analyze_sql.trace')
PRELOAD = '/tmp/sqlite_trace.so'

EXPECTED_ORIGINAL = """depth,domain,count
1,Biology,3
1,Computer Science,2
1,Mathematics,2
1,Physics,3
2,Biology,7
2,Computer Science,8
2,Mathematics,7
2,Physics,8
3,Biology,12
3,Computer Science,13
3,Mathematics,12
3,Physics,13"""

def normalized_csv(path):
    assert path.is_file(), f'CSV file missing at {path}'
    return '\n'.join(line.strip() for line in path.read_text(encoding='utf-8').splitlines() if line.strip())

def assert_valid_index():
    assert DB.is_file(), f'Database file missing at {DB}'
    with sqlite3.connect(DB) as conn:
        indexes = conn.execute("PRAGMA index_list('citations')").fetchall()
        for idx in indexes:
            name = idx[1].replace("'", "''")
            columns = [row[2] for row in conn.execute(f"PRAGMA index_info('{name}')")]
            if columns and columns[0] == 'cited_id':
                return
    raise AssertionError("Required index on 'citations' table (starting with 'cited_id') was not found.")

def assert_expected_original_csv():
    actual = normalized_csv(CSV)
    expected = normalized_text(EXPECTED_ORIGINAL)
    assert actual == expected, f'CSV content does not match expected output.\nExpected:\n{expected}\nGot:\n{actual}'

def normalized_text(value):
    return '\n'.join(line.strip() for line in value.splitlines() if line.strip())

def table_rows():
    with sqlite3.connect(DB) as conn:
        papers = conn.execute('SELECT id,title,year,metadata_json FROM papers ORDER BY id').fetchall()
        citations = conn.execute('SELECT citing_id,cited_id FROM citations ORDER BY rowid').fetchall()
    return papers, citations

def drop_citation_indexes():
    with sqlite3.connect(DB) as conn:
        indexes = conn.execute("PRAGMA index_list('citations')").fetchall()
        for idx in indexes:
            if idx[3] == 'pk':
                continue
            name = idx[1].replace('"', '""')
            conn.execute(f'DROP INDEX IF EXISTS "{name}"')
        conn.commit()

def run_program():
    TRACE.unlink(missing_ok=True)
    CSV.unlink(missing_ok=True)
    env = os.environ.copy()
    env['LD_PRELOAD'] = PRELOAD
    env['SQL_TRACE_FILE'] = str(TRACE)
    result = subprocess.run([str(BIN)], cwd='/home/user', env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=30)
    assert result.returncode == 0, f'Program failed with exit code {result.returncode}.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    assert CSV.is_file(), 'Program did not generate /home/user/citation_summary.csv'

def assert_required_sql_observed():
    assert TRACE.is_file(), 'No SQLite API activity was observed while running the program'
    sql = TRACE.read_text(encoding='utf-8', errors='replace')
    assert re.search(r'\bCREATE\s+(?:UNIQUE\s+)?INDEX\b', sql, re.I | re.S), 'Program did not execute CREATE INDEX'
    assert re.search(r'\bWITH\s+RECURSIVE\b', sql, re.I | re.S), 'Program did not execute a recursive CTE'
    assert re.search(r'\bjson_(?:extract|value|query)\s*\(|->>', sql, re.I | re.S), 'Program did not use an SQLite JSON extraction function/operator'
    assert re.search(r'\bGROUP\s+BY\b', sql, re.I | re.S), 'Program did not execute SQL aggregation with GROUP BY'

def install_dynamic_fixture():
    papers = [
        (1, 'Root', 2024, {'domain': 'Root'}),
        (2, 'A', 2024, {'domain': 'Alpha'}),
        (3, 'B', 2024, {'domain': 'Beta'}),
        (4, 'C', 2024, {'domain': 'Alpha'}),
        (5, 'D', 2024, {'domain': 'Gamma'}),
        (6, 'E', 2024, {'domain': 'Beta'}),
        (7, 'F', 2024, {'domain': 'Gamma'}),
        (8, 'G', 2024, {'domain': 'Delta'}),
        (9, 'H', 2024, {'domain': 'Alpha'}),
        (10, 'I', 2024, {'domain': 'Delta'}),
        (11, 'J', 2024, {'domain': 'Beta'}),
        (12, 'K', 2024, {'domain': 'Beta'}),
        (13, 'Depth4', 2024, {'domain': 'Ignored'}),
        (20, 'Noise', 2024, {'domain': 'Noise'}),
    ]
    citations = [
        (2,1), (3,1), (4,1),
        (5,2), (6,2), (7,3), (8,4),
        (9,5), (10,6), (11,7), (12,8),
        (13,9), (20,13),
    ]
    with sqlite3.connect(DB) as conn:
        conn.execute('DELETE FROM citations')
        conn.execute('DELETE FROM papers')
        conn.executemany('INSERT INTO papers(id,title,year,metadata_json) VALUES (?,?,?,?)',
                         [(i,t,y,json.dumps(m)) for i,t,y,m in papers])
        conn.executemany('INSERT INTO citations(citing_id,cited_id) VALUES (?,?)', citations)
        conn.commit()

def derive_expected_csv():
    query = """
    WITH RECURSIVE hierarchy(id, depth) AS (
      SELECT citing_id, 1 FROM citations WHERE cited_id = 1
      UNION ALL
      SELECT c.citing_id, h.depth + 1
      FROM citations c JOIN hierarchy h ON c.cited_id = h.id
      WHERE h.depth < 3
    )
    SELECT h.depth, json_extract(p.metadata_json, '$.domain'), COUNT(*)
    FROM hierarchy h JOIN papers p ON p.id = h.id
    GROUP BY h.depth, json_extract(p.metadata_json, '$.domain')
    ORDER BY h.depth, json_extract(p.metadata_json, '$.domain')
    """
    with sqlite3.connect(DB) as conn:
        rows = conn.execute(query).fetchall()
    return 'depth,domain,count\n' + '\n'.join(f'{d},{domain},{count}' for d, domain, count in rows)

assert SRC.is_file(), f'C++ source file missing at {SRC}'
assert BIN.is_file(), f'Compiled program missing at {BIN}'
assert os.access(BIN, os.X_OK), f'{BIN} is not executable'
assert BIN.read_bytes()[:4] == b'\x7fELF', f'{BIN} is not an ELF executable'

# Preserve the original verifier's assertions against the agent's submitted state.
assert_valid_index()
assert_expected_original_csv()

original_db = DB.read_bytes()
initial_csv = CSV.read_bytes() if CSV.exists() else None
restored_csv = None
try:
    subprocess.run(['g++', '-O3', '-std=c++17', str(SRC), '-lsqlite3', '-o', str(BIN)],
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
    assert BIN.is_file() and os.access(BIN, os.X_OK) and BIN.read_bytes()[:4] == b'\x7fELF'

    before = table_rows()
    drop_citation_indexes()
    run_program()
    assert table_rows() == before, 'Program modified data in papers or citations'
    assert_valid_index()
    assert_expected_original_csv()
    assert_required_sql_observed()
    restored_csv = CSV.read_bytes()

    install_dynamic_fixture()
    drop_citation_indexes()
    expected_dynamic = derive_expected_csv()
    dynamic_before = table_rows()
    run_program()
    assert table_rows() == dynamic_before, 'Program modified fixture data in papers or citations'
    assert_valid_index()
    assert_required_sql_observed()
    actual_dynamic = normalized_csv(CSV)
    assert actual_dynamic == normalized_text(expected_dynamic), (
        f'Program failed the independently derived fixture.\nExpected:\n{expected_dynamic}\nGot:\n{actual_dynamic}'
    )
finally:
    DB.write_bytes(original_db)
    if restored_csv is not None:
        CSV.write_bytes(restored_csv)
    elif initial_csv is not None:
        CSV.write_bytes(initial_csv)
    else:
        CSV.unlink(missing_ok=True)
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
