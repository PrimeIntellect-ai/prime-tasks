#!/bin/bash
mkdir -p /logs/verifier

cat << 'SHIM_EOF' > /tmp/sqlite_trace.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static void log_line(const char *kind, const void *ptr, const char *text) {
    const char *path = getenv("SQLITE_TRACE_FILE");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "%s|%p|%s\n", kind, ptr, text ? text : "");
    fclose(f);
}

int sqlite3_open(const char *filename, sqlite3 **ppDb) {
    static int (*real_fn)(const char *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open");
    int rc = real_fn(filename, ppDb);
    log_line("OPEN", ppDb ? *ppDb : NULL, filename);
    return rc;
}

int sqlite3_open_v2(const char *filename, sqlite3 **ppDb, int flags, const char *zVfs) {
    static int (*real_fn)(const char *, sqlite3 **, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    int rc = real_fn(filename, ppDb, flags, zVfs);
    log_line("OPEN", ppDb ? *ppDb : NULL, filename);
    return rc;
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    int rc = real_fn(db, sql, n, stmt, tail);
    log_line("PREP", stmt ? *stmt : NULL, sql);
    return rc;
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    int rc = real_fn(db, sql, n, flags, stmt, tail);
    log_line("PREP", stmt ? *stmt : NULL, sql);
    return rc;
}

int sqlite3_bind_text(sqlite3_stmt *stmt, int idx, const char *value, int n, void (*destroy)(void *)) {
    static int (*real_fn)(sqlite3_stmt *, int, const char *, int, void (*)(void *)) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_text");
    log_line("BIND_TEXT", stmt, "");
    return real_fn(stmt, idx, value, n, destroy);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*callback)(void *, int, char **, char **), void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_line("EXEC", db, sql);
    return real_fn(db, sql, callback, arg, errmsg);
}
SHIM_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess

SOURCE = '/home/user/analyze_graph.c'
OUTPUT = '/home/user/top_datasets.csv'
DATASET = '/home/user/datasets.jsonl'
PROGRAM = '/tmp/analyze_graph_test'
SHIM = '/tmp/libsqlite_trace.so'


def test_c_source_file_exists():
    file_path = '/home/user/analyze_graph.c'
    assert os.path.exists(file_path), f"C source file {file_path} is missing."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."


def test_csv_output_exists():
    file_path = '/home/user/top_datasets.csv'
    assert os.path.exists(file_path), f"Output CSV file {file_path} is missing. Did the program run successfully?"
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."


def test_csv_output_content():
    file_path = '/home/user/top_datasets.csv'
    expected_csv = """astronomy,ds08,2,1
astronomy,ds09,2,2
astronomy,ds10,2,3
genomics,ds01,3,1
genomics,ds03,2,2
genomics,ds02,1,3
physics,ds05,4,1
physics,ds04,2,2
physics,ds06,1,3"""

    expected_lines = sorted([line.strip() for line in expected_csv.strip().split('\n')])

    with open(file_path, 'r') as f:
        actual_lines = sorted([line.strip() for line in f.read().strip().split('\n') if line.strip()])

    assert actual_lines == expected_lines, (
        f"CSV content does not match expected output.\n"
        f"Expected (sorted):\n{expected_lines}\n"
        f"Actual (sorted):\n{actual_lines}"
    )


def expected_rows(documents):
    groups = {}
    for doc in documents:
        degree = len(doc['dependencies'])
        if degree >= 1:
            groups.setdefault(doc['domain'], []).append((doc['id'], degree))

    rows = []
    for domain, nodes in groups.items():
        nodes.sort(key=lambda item: (-item[1], item[0]))
        for rank, (node_id, degree) in enumerate(nodes, 1):
            rows.append(f'{domain},{node_id},{degree},{rank}')
    return sorted(rows)


def make_case(tag):
    token = secrets.token_hex(5)
    d1 = f'domain_{tag}_{token}_a'
    d2 = f'domain_{tag}_{token}_b'
    ids = [f'node_{tag}_{token}_{i:02d}' for i in range(9)]
    return [
        {'id': ids[4], 'domain': d1, 'dependencies': [ids[0], ids[1]]},
        {'id': ids[1], 'domain': d1, 'dependencies': [ids[2], ids[3], ids[4]]},
        {'id': ids[0], 'domain': d1, 'dependencies': [ids[8], ids[7], ids[6]]},
        {'id': ids[2], 'domain': d1, 'dependencies': []},
        {'id': ids[8], 'domain': d2, 'dependencies': [ids[0]]},
        {'id': ids[6], 'domain': d2, 'dependencies': [ids[0], ids[1]]},
        {'id': ids[5], 'domain': d2, 'dependencies': [ids[2], ids[3]]},
        {'id': ids[7], 'domain': d2, 'dependencies': []},
    ]


def parse_trace(path):
    records = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            parts = line.rstrip('\n').split('|', 2)
            if len(parts) == 3:
                records.append(tuple(parts))
    return records


def test_program_compiles_runs_and_uses_required_sqlite_features():
    subprocess.run(
        ['gcc', '-shared', '-fPIC', '/tmp/sqlite_trace.c', '-o', SHIM, '-ldl'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )
    subprocess.run(
        ['gcc', '-O3', SOURCE, '-o', PROGRAM, '-lsqlite3'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
    )

    original_data = open(DATASET, 'rb').read()
    try:
        for case_number in range(2):
            documents = make_case(str(case_number))
            with open(DATASET, 'w', encoding='utf-8') as f:
                for document in documents:
                    f.write(json.dumps(document, separators=(',', ':')) + '\n')

            if os.path.exists(OUTPUT):
                os.unlink(OUTPUT)
            trace = f'/tmp/sqlite_trace_{case_number}_{secrets.token_hex(6)}.log'
            env = os.environ.copy()
            env['LD_PRELOAD'] = SHIM
            env['SQLITE_TRACE_FILE'] = trace
            result = subprocess.run(
                [PROGRAM], cwd='/home/user', env=env, timeout=15,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True,
            )
            assert result.returncode == 0, (
                f'Compiled program exited with {result.returncode}.\n'
                f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
            )
            assert os.path.isfile(OUTPUT), 'Running the compiled program did not create the CSV output.'

            with open(OUTPUT, encoding='utf-8') as f:
                raw_lines = f.read().splitlines()
            assert all(line and len(line.split(',')) == 4 for line in raw_lines), (
                'CSV must contain only headerless domain,id,out_degree,domain_rank rows.'
            )
            assert sorted(raw_lines) == expected_rows(documents), (
                f'Program output was incorrect for generated input.\n'
                f'Expected: {expected_rows(documents)}\nActual: {sorted(raw_lines)}'
            )

            records = parse_trace(trace)
            assert any(kind == 'OPEN' and text == ':memory:' for kind, ptr, text in records), (
                'Program did not open an in-memory SQLite database.'
            )

            sql_records = [(kind, ptr, text) for kind, ptr, text in records if kind in ('PREP', 'EXEC')]
            all_sql = '\n'.join(text for kind, ptr, text in sql_records).lower()
            assert re.search(r'create\s+table(?:\s+if\s+not\s+exists)?\s+nodes\b', all_sql), (
                'Program did not create the required nodes table.'
            )

            insert_statements = [
                (ptr, text) for kind, ptr, text in records
                if kind == 'PREP'
                and re.search(r'insert\s+into\s+nodes\b', text, re.I)
                and '?' in text
            ]
            bound_ptrs = {ptr for kind, ptr, text in records if kind == 'BIND_TEXT'}
            assert insert_statements, 'Loading did not use a prepared INSERT INTO nodes statement with a ? parameter.'
            assert any(ptr in bound_ptrs for ptr, text in insert_statements), (
                'The parameterized nodes INSERT was not populated with sqlite3_bind_text.'
            )
            assert 'json_extract' in all_sql, 'Executed SQL did not use SQLite json_extract.'
            assert 'json_each' in all_sql, 'Executed SQL did not use SQLite json_each to unnest dependencies.'
            assert re.search(r'\brank\s*\(\s*\)\s*over\b', all_sql), (
                'Executed SQL did not use RANK() OVER as required.'
            )
    finally:
        with open(DATASET, 'wb') as f:
            f.write(original_data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
