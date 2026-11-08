#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import ctypes
import json
import os
import shutil
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
LIB = HOME / 'libgraph.so'
SOURCE = HOME / 'libgraph.c'
SCRIPT = HOME / 'integration_test.py'
LOG = HOME / 'execution_plan.log'
API = HOME / 'api_responses'


def run_integration():
    subprocess.run(
        ['python3', str(SCRIPT)],
        cwd=str(HOME),
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_libgraph_so_exists():
    assert os.path.isfile('/home/user/libgraph.so'), '/home/user/libgraph.so is missing. Did you compile the C library?'


def test_integration_test_exists():
    assert os.path.isfile('/home/user/integration_test.py'), '/home/user/integration_test.py is missing.'


def test_libgraph_c_fixed():
    c_path = '/home/user/libgraph.c'
    assert os.path.isfile(c_path), f'{c_path} is missing.'

    with open(c_path, 'r') as f:
        content = f.read()

    assert 'int* result = (int*)malloc(num_nodes * sizeof(int));' not in content or 'calloc(num_nodes + 1' in content or 'malloc((num_nodes + 1)' in content, \
        "The memory allocation bug for 'result' in libgraph.c does not appear to be fixed."


def test_source_is_memory_safe_under_asan(tmp_path):
    harness = tmp_path / 'harness.c'
    executable = tmp_path / 'harness'
    harness.write_text(r'''
#include <stdlib.h>
int* resolve_dependencies(int, int, int*, int*);
int main(void) {
    const int n = 257;
    int *u = malloc((n - 1) * sizeof(int));
    int *v = malloc((n - 1) * sizeof(int));
    if (!u || !v) return 10;
    for (int i = 0; i < n - 1; ++i) { u[i] = i; v[i] = i + 1; }
    int *result = resolve_dependencies(n, n - 1, u, v);
    if (!result) return 11;
    for (int i = 0; i < n; ++i) if (result[i] != i) return 12;
    if (result[n] != -1) return 13;
    free(result); free(u); free(v);
    return 0;
}
''')
    subprocess.run([
        'gcc', '-fsanitize=address', '-fno-omit-frame-pointer', '-g',
        str(harness), str(SOURCE), '-o', str(executable)
    ], check=True, timeout=20, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    env = os.environ.copy()
    env['ASAN_OPTIONS'] = 'detect_leaks=0:abort_on_error=1'
    subprocess.run([str(executable)], check=True, timeout=20, env=env,
                   stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def test_compiled_library_resolves_derived_graphs():
    lib = ctypes.CDLL(str(LIB))
    resolve = lib.resolve_dependencies
    resolve.argtypes = [ctypes.c_int, ctypes.c_int,
                        ctypes.POINTER(ctypes.c_int), ctypes.POINTER(ctypes.c_int)]
    resolve.restype = ctypes.POINTER(ctypes.c_int)
    libc = ctypes.CDLL(None)
    libc.free.argtypes = [ctypes.c_void_p]

    graphs = [
        (6, [(0, 2), (1, 2), (2, 3), (2, 4), (4, 5)]),
        (8, [(0, 3), (1, 3), (2, 4), (3, 5), (4, 5), (5, 6), (5, 7)]),
        (33, [(i, i + 1) for i in range(32)]),
    ]
    for n, edges in graphs:
        m = len(edges)
        u = (ctypes.c_int * m)(*[a for a, _ in edges])
        v = (ctypes.c_int * m)(*[b for _, b in edges])
        result = resolve(n, m, u, v)
        assert bool(result), 'resolve_dependencies returned NULL'
        try:
            order = [result[i] for i in range(n)]
            assert result[n] == -1, 'resolve_dependencies did not place the sentinel at result[num_nodes]'
            assert sorted(order) == list(range(n)), 'Result is not a permutation of all graph nodes'
            positions = {node: i for i, node in enumerate(order)}
            for source, destination in edges:
                assert positions[source] < positions[destination], \
                    f'Invalid topological order for edge {source}->{destination}'
        finally:
            libc.free(ctypes.cast(result, ctypes.c_void_p))


def test_integration_imports_ctypes_and_executes_on_original_data():
    tree = ast.parse(SCRIPT.read_text(), filename=str(SCRIPT))
    imports_ctypes = any(
        (isinstance(node, ast.Import) and any(alias.name == 'ctypes' for alias in node.names)) or
        (isinstance(node, ast.ImportFrom) and node.module == 'ctypes')
        for node in ast.walk(tree)
    )
    assert imports_ctypes, 'integration_test.py must use Python ctypes'

    if LOG.exists():
        LOG.unlink()
    run_integration()

    log_path = '/home/user/execution_plan.log'
    assert os.path.isfile(log_path), f'{log_path} is missing. The integration test script did not create it.'
    with open(log_path, 'r') as f:
        content = f.read().strip()
    expected_plan = 'AuthService,DataFetch,DataClean,FeatureEng,ModelTrain'
    assert content == expected_plan, f"Execution plan in {log_path} is incorrect. Expected '{expected_plan}', got '{content}'."


def test_integration_parses_dynamic_data_and_calls_library(tmp_path):
    marker = Path('/tmp/libgraph_verifier_marker')
    spy_source = tmp_path / 'spy.c'
    spy_library = tmp_path / 'libgraph_spy.so'
    spy_source.write_text(r'''
#include <stdio.h>
static int output[] = {0, 3, 1, 2, -1, 999};
int* resolve_dependencies(int n, int m, int* u, int* v) {
    int needed[4][2] = {{0,3}, {3,1}, {1,2}, {-1,-1}};
    int valid = (n == 4 && m == 3);
    for (int k = 0; k < 3; ++k) {
        int found = 0;
        for (int i = 0; i < m; ++i)
            if (u[i] == needed[k][0] && v[i] == needed[k][1]) found++;
        if (found != 1) valid = 0;
    }
    FILE *f = fopen("/tmp/libgraph_verifier_marker", "w");
    if (f) { fputs(valid ? "VALID" : "INVALID", f); fclose(f); }
    return output;
}
''')
    subprocess.run(['gcc', '-shared', '-fPIC', str(spy_source), '-o', str(spy_library)],
                   check=True, timeout=20, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    original_library = LIB.read_bytes()
    original_mode = LIB.stat().st_mode
    original_files = {p.name: p.read_bytes() for p in API.iterdir() if p.is_file()}
    try:
        for path in API.iterdir():
            if path.is_file():
                path.unlink()
        records = {
            'one.json': {'id': 'Zebra', 'requires': ['Alpha']},
            'two.json': {'id': 'Omega', 'requires': ['Mid']},
            'three.json': {'id': 'Alpha', 'requires': []},
            'four.json': {'id': 'Mid', 'requires': ['Zebra']},
        }
        for name, record in records.items():
            (API / name).write_text(json.dumps(record))

        shutil.copyfile(spy_library, LIB)
        if marker.exists():
            marker.unlink()
        if LOG.exists():
            LOG.unlink()

        run_integration()
        assert marker.is_file(), 'integration_test.py did not call resolve_dependencies from /home/user/libgraph.so'
        assert marker.read_text() == 'VALID', \
            'The C library received incorrect node IDs or dependency edge directions; IDs must be alphabetically mapped'
        assert LOG.is_file(), 'The dynamic integration run did not create execution_plan.log'
        assert LOG.read_text().strip() == 'Alpha,Zebra,Mid,Omega', \
            'The integration script did not read the sentinel-terminated C result and map IDs back correctly'
    finally:
        LIB.write_bytes(original_library)
        os.chmod(LIB, original_mode)
        for path in API.iterdir():
            if path.is_file():
                path.unlink()
        for name, data in original_files.items():
            (API / name).write_bytes(data)
        if marker.exists():
            marker.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
