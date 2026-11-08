#!/bin/bash
set +e
mkdir -p /logs/verifier

cat > /tmp/sqlite_trace.c <<'TRACE_EOF'
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static void log_text(const char *kind, const char *text) {
    const char *path = getenv("SQLITE_TRACE_LOG");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "%s\n%s\n--END--\n", kind, text ? text : "(null)");
    fclose(f);
}

int sqlite3_open(const char *filename, sqlite3 **ppDb) {
    static int (*real_fn)(const char *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open");
    log_text("OPEN", filename);
    return real_fn(filename, ppDb);
}

int sqlite3_open_v2(const char *filename, sqlite3 **ppDb, int flags, const char *zVfs) {
    static int (*real_fn)(const char *, sqlite3 **, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    log_text("OPEN_V2", filename);
    return real_fn(filename, ppDb, flags, zVfs);
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void *, int, char **, char **),
                 void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_text("EXEC", sql);
    return real_fn(db, sql, callback, arg, errmsg);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_text("PREPARE_V2", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_text("PREPARE_V3", sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}
TRACE_EOF

gcc -shared -fPIC -o /tmp/libsqlite_trace.so /tmp/sqlite_trace.c -ldl -lsqlite3
trace_status=$?
gcc -O2 -o /tmp/analyze_bom_from_source /home/user/workspace/analyze_bom.c -lsqlite3
build_status=$?

cat > /tmp/test_final_state.py <<'TEST_EOF'
import json
import math
import os
import secrets
import subprocess
from pathlib import Path

SOURCE = Path('/home/user/workspace/analyze_bom.c')
EXE = Path('/home/user/workspace/analyze_bom')
REBUILT = Path('/tmp/analyze_bom_from_source')
CSV = Path('/home/user/data/parts.csv')
PLAN = Path('/home/user/workspace/query_plan.txt')
RESULT = Path('/home/user/workspace/bom_result.json')
TRACE_LIB = '/tmp/libsqlite_trace.so'


def assert_result(expected):
    assert RESULT.is_file(), f'{RESULT} is missing.'
    content = RESULT.read_text(encoding='utf-8')
    try:
        data = json.loads(content)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'{RESULT} does not contain valid JSON: {exc}')
    assert isinstance(data, dict), 'bom_result.json must contain one JSON object.'
    assert 'top_part_id' in data, "JSON result is missing 'top_part_id'."
    assert data['top_part_id'] == 1, f"Expected top_part_id to be 1, got {data['top_part_id']}."
    assert 'total_assembly_cost' in data, "JSON result is missing 'total_assembly_cost'."
    cost = float(data['total_assembly_cost'])
    assert math.isfinite(cost), 'total_assembly_cost must be finite.'
    assert abs(cost - expected) <= 1e-6 * max(1.0, abs(expected)), \
        f'Expected total_assembly_cost to be {expected}, got {cost}.'


def assert_plan():
    assert PLAN.is_file(), f'{PLAN} is missing.'
    content = PLAN.read_text(encoding='utf-8', errors='ignore').upper()
    assert 'USING INDEX' in content or 'USING COVERING INDEX' in content, \
        'query_plan.txt does not indicate that an index was used.'


def expected_cost(rows):
    children = {}
    costs = {}
    for part_id, parent_id, qty, unit_cost in rows:
        costs[part_id] = float(unit_cost)
        if parent_id is not None:
            children.setdefault(parent_id, []).append((part_id, qty))

    def total(part_id):
        return costs[part_id] + sum(qty * total(child) for child, qty in children.get(part_id, []))
    return total(1)


def write_csv(rows):
    lines = ['part_id,parent_id,qty_per_parent,unit_cost']
    for part_id, parent_id, qty, cost in rows:
        parent = 'NULL' if parent_id is None else str(parent_id)
        lines.append(f'{part_id},{parent},{qty},{cost}')
    CSV.write_text('\n'.join(lines) + '\n', encoding='utf-8')


def random_rows():
    count = 8 + secrets.randbelow(5)
    rows = [(1, None, 1, f'{(secrets.randbelow(40) + 1) / 10:.1f}')]
    for part_id in range(2, count + 1):
        parent = 1 + secrets.randbelow(part_id - 1)
        qty = 1 + secrets.randbelow(5)
        cost = f'{(secrets.randbelow(250) + 1) / 10:.1f}'
        rows.append((part_id, parent, qty, cost))
    return rows


def run_case(binary, rows, trace=False):
    write_csv(rows)
    for output in (PLAN, RESULT):
        try:
            output.unlink()
        except FileNotFoundError:
            pass

    trace_path = Path(f'/tmp/sqlite-trace-{secrets.token_hex(8)}.log')
    env = os.environ.copy()
    if trace:
        env['LD_PRELOAD'] = TRACE_LIB
        env['SQLITE_TRACE_LOG'] = str(trace_path)

    proc = subprocess.run(
        [str(binary)], cwd='/home/user/workspace', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert proc.returncode == 0, \
        f'{binary} exited with {proc.returncode}. stderr: {proc.stderr[-2000:]}'
    assert_plan()
    assert_result(expected_cost(rows))

    if trace:
        assert trace_path.is_file(), 'The rebuilt C program made no observable SQLite API calls.'
        trace_text = trace_path.read_text(encoding='utf-8', errors='ignore').lower()
        entries = [entry for entry in trace_text.split('--end--') if entry.strip()]
        assert any(':memory:' in entry for entry in entries), \
            "The program did not open SQLite's :memory: database."
        assert any('create table' in entry and 'bom' in entry and
                   all(col in entry for col in ('part_id', 'parent_id', 'qty_per_parent', 'unit_cost'))
                   for entry in entries), 'The required bom table was not created through SQLite.'
        assert any('insert into' in entry and 'bom' in entry for entry in entries), \
            'No SQLite INSERT into bom was executed.'
        assert any('create index' in entry and 'parent_id' in entry for entry in entries), \
            'No SQLite index on parent_id was created.'
        assert any('explain query plan' in entry and 'with recursive' in entry for entry in entries), \
            'EXPLAIN QUERY PLAN was not executed for a recursive query.'
        assert trace_text.count('with recursive') >= 2, \
            'The recursive query was explained but not also executed.'
        assert 'json_object' in trace_text, \
            "The executed SQLite SQL did not use json_object."
        trace_path.unlink(missing_ok=True)


def test_complete_bom_workflow():
    assert os.path.isfile('/usr/include/sqlite3.h'), \
        'libsqlite3-dev is not installed (sqlite3.h missing).'

    assert SOURCE.is_file(), f'{SOURCE} is missing.'
    source_text = SOURCE.read_text(encoding='utf-8', errors='ignore')
    assert 'json_object' in source_text, \
        "The C source code does not appear to use SQLite's json_object function."

    assert EXE.is_file(), f'{EXE} is missing.'
    assert os.access(EXE, os.X_OK), f'{EXE} is not executable.'
    with EXE.open('rb') as f:
        assert f.read(4) == b'\x7fELF', f'{EXE} is not a compiled executable.'

    # Preserve all original checks against the artifacts produced by the agent.
    assert_plan()
    assert_result(70.0)

    # Exercise the submitted executable on unpredictable BOMs.
    for _ in range(3):
        run_case(EXE, random_rows(), trace=False)

    # Recompile the submitted source, then verify both behavior and actual SQLite SQL.
    assert REBUILT.is_file() and os.access(REBUILT, os.X_OK), \
        'analyze_bom.c could not be compiled against libsqlite3.'
    for _ in range(2):
        run_case(REBUILT, random_rows(), trace=True)
TEST_EOF

if [ "$trace_status" -eq 0 ] && [ "$build_status" -eq 0 ] && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
