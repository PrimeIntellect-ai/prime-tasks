#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'WRAP_EOF' > /tmp/sqlite_runtime_wrapper.c
#include <sqlite3.h>
#include <stdio.h>
#include <string.h>
#include <ctype.h>

static int contains_ci(const char *s, const char *needle) {
    if (!s || !needle) return 0;
    size_t n = strlen(needle);
    for (; *s; ++s) {
        size_t i = 0;
        while (i < n && s[i] && tolower((unsigned char)s[i]) == tolower((unsigned char)needle[i])) i++;
        if (i == n) return 1;
    }
    return 0;
}

static void mark(const char *value) {
    FILE *f = fopen("/tmp/sqlite_runtime_seen", "a");
    if (f) {
        fprintf(f, "%s\n", value);
        fclose(f);
    }
}

static int trace_callback(unsigned type, void *ctx, void *p, void *x) {
    (void)ctx;
    (void)x;
    if (type == SQLITE_TRACE_STMT) {
        const char *sql = sqlite3_sql((sqlite3_stmt *)p);
        if (sql && contains_ci(sql, "with") && contains_ci(sql, "recursive"))
            mark("RECURSIVE");
        if (sql && contains_ci(sql, "create") && contains_ci(sql, "table") &&
            contains_ci(sql, "edges") && contains_ci(sql, "source") &&
            contains_ci(sql, "target") && contains_ci(sql, "latency"))
            mark("EDGES_SCHEMA");
    }
    return 0;
}

int agent_sqlite3_open(const char *filename, sqlite3 **db) {
    int rc = sqlite3_open(filename, db);
    if (rc == SQLITE_OK) {
        if (filename && strcmp(filename, ":memory:") == 0) mark("MEMORY_DB");
        sqlite3_trace_v2(*db, SQLITE_TRACE_STMT, trace_callback, NULL);
    }
    return rc;
}

int agent_sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *vfs) {
    int rc = sqlite3_open_v2(filename, db, flags, vfs);
    if (rc == SQLITE_OK) {
        if (filename && strcmp(filename, ":memory:") == 0) mark("MEMORY_DB");
        sqlite3_trace_v2(*db, SQLITE_TRACE_STMT, trace_callback, NULL);
    }
    return rc;
}
WRAP_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import subprocess

import networkx as nx
import pytest

SOURCE = '/home/user/shortest_path.c'
BUILD = '/app/sqlite/build.sh'
CSV_PATH = '/app/data/network.csv'
OUTPUT = '/home/user/min_latency.txt'
BINARY = '/tmp/shortest_path_agent'
INSTRUMENTED = '/tmp/shortest_path_instrumented'
FLOAT_RE = re.compile(r'[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?')


def expected_from_csv():
    graph = nx.DiGraph()
    with open(CSV_PATH, newline='') as f:
        for row in csv.reader(f):
            if not row:
                continue
            graph.add_edge(row[0], row[1], weight=float(row[2]))
    try:
        return nx.shortest_path_length(
            graph, source='NODE_START', target='NODE_END', weight='weight'
        )
    except nx.NetworkXNoPath:
        pytest.fail('No path found in the ground truth graph, something is wrong with the setup.')


def run_and_check(binary, expected):
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run([binary], stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=30)
    assert result.returncode == 0, (
        f'Compiled program exited with {result.returncode}. stderr: {result.stderr}'
    )
    assert os.path.isfile(OUTPUT), f'The output file {OUTPUT} is missing after executing the C program.'
    with open(OUTPUT) as f:
        content = f.read().strip()
    assert FLOAT_RE.fullmatch(content), (
        f"The output file {OUTPUT} does not contain only a valid floating-point number. Found: '{content}'"
    )
    value = float(content)
    error = abs(value - expected)
    assert error <= 0.01, (
        f'Absolute error {error:.4f} exceeds threshold 0.01. '
        f'Agent computed {value}, but true shortest path latency is {expected:.4f}.'
    )


def make_case(case_number):
    def weight(low, span):
        return round((low + secrets.randbelow(span)) / 100.0, 2)

    edges = {
        ('NODE_START', 'A'): weight(80, 220),
        ('A', 'B'): weight(80, 220),
        ('B', 'NODE_END'): weight(80, 220),
        ('NODE_START', 'C'): weight(100, 350),
        ('C', 'D'): weight(100, 350),
        ('D', 'NODE_END'): weight(100, 350),
        ('NODE_START', 'NODE_END'): weight(900, 500),
        ('A', 'C'): weight(40, 300),
        ('C', 'A'): weight(40, 300),
        ('B', 'A'): weight(40, 300),
        ('D', 'B'): weight(40, 300),
        ('B', 'D'): weight(40, 300),
        ('C', 'NODE_START'): weight(40, 300),
    }
    # Change topology between runs while retaining directed cycles and at least one path.
    if case_number % 2:
        edges[('A', 'D')] = weight(40, 250)
    else:
        edges[('C', 'B')] = weight(40, 250)
    with open(CSV_PATH, 'w', newline='') as f:
        writer = csv.writer(f, lineterminator='\n')
        for (u, v), w in edges.items():
            writer.writerow([u, v, f'{w:.2f}'])
    return expected_from_csv()


def test_build_script_fixed():
    assert os.path.isfile(BUILD), f'File {BUILD} is missing.'
    with open(BUILD) as f:
        content = f.read()
    assert '-lpthread' in content, f"The build script {BUILD} was not fixed to use '-lpthread'."
    assert '-lpthead' not in content, f"The build script {BUILD} still contains the typo '-lpthead'."


def test_c_source_exists_and_is_c_sqlite_source():
    assert os.path.isfile(SOURCE), f'File {SOURCE} is missing.'
    with open(SOURCE, errors='replace') as f:
        source = f.read()
    uncommented = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    assert re.search(r'#\s*include\s*[<"][^>"]*sqlite3\.h[>"]', uncommented), \
        'The C source does not include sqlite3.h.'
    assert re.search(r'\bsqlite3_open(?:_v2)?\s*\(', uncommented), \
        'The C source does not open a SQLite database.'
    assert re.search(r'\bint\s+main\s*\(', uncommented), \
        'The submitted file does not define a C main function.'


def test_compile_and_execute_on_original_data():
    if os.path.exists(BINARY):
        os.unlink(BINARY)
    result = subprocess.run([BUILD, SOURCE, BINARY], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=90)
    assert result.returncode == 0, f'build.sh failed to compile the source: {result.stderr}'
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), \
        'build.sh did not produce an executable binary.'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'build.sh did not produce a native ELF binary.'
    run_and_check(BINARY, expected_from_csv())


def test_compiled_program_handles_unseen_graphs():
    for i in range(3):
        run_and_check(BINARY, make_case(i))


def test_sqlite_and_recursive_cte_are_executed_at_runtime():
    source_obj = '/tmp/agent_source.o'
    sqlite_obj = '/tmp/sqlite3.o'
    wrapper_obj = '/tmp/sqlite_wrapper.o'
    for path in (source_obj, sqlite_obj, wrapper_obj, INSTRUMENTED, '/tmp/sqlite_runtime_seen'):
        if os.path.exists(path):
            os.unlink(path)

    commands = [
        ['gcc', '-O2', '-I/app/sqlite',
         '-Dsqlite3_open=agent_sqlite3_open',
         '-Dsqlite3_open_v2=agent_sqlite3_open_v2',
         '-c', SOURCE, '-o', source_obj],
        ['gcc', '-O2', '-I/app/sqlite', '-c', '/app/sqlite/sqlite3.c', '-o', sqlite_obj],
        ['gcc', '-O2', '-I/app/sqlite', '-c', '/tmp/sqlite_runtime_wrapper.c', '-o', wrapper_obj],
        ['gcc', source_obj, wrapper_obj, sqlite_obj, '-o', INSTRUMENTED,
         '-lpthread', '-ldl', '-lm'],
    ]
    for command in commands:
        result = subprocess.run(command, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                text=True, timeout=90)
        assert result.returncode == 0, (
            'The submitted C source could not be built with runtime SQLite instrumentation: '
            + result.stderr
        )

    run_and_check(INSTRUMENTED, make_case(99))
    assert os.path.isfile('/tmp/sqlite_runtime_seen'), \
        'The C program did not execute through the embedded SQLite API.'
    with open('/tmp/sqlite_runtime_seen') as f:
        markers = set(f.read().splitlines())
    assert 'MEMORY_DB' in markers, 'The C program did not create an in-memory SQLite database.'
    assert 'EDGES_SCHEMA' in markers, \
        'The C program did not execute a CREATE TABLE statement for edges(source, target, latency).'
    assert 'RECURSIVE' in markers, \
        'The C program did not execute a SQL statement using a recursive CTE.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
