#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'AUDIT_EOF' > /tmp/count_interactions.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <unistd.h>

static void mark_access(const char *path) {
    if (!path || strcmp(path, "/app/interactions.csv") != 0) return;
    const char *log = getenv("INTERACTIONS_OPEN_LOG");
    if (!log) return;
    int fd = (int)syscall(SYS_openat, AT_FDCWD, log, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        syscall(SYS_write, fd, "1\n", 2);
        syscall(SYS_close, fd);
    }
}

FILE *fopen(const char *path, const char *mode) {
    static FILE *(*real_fn)(const char *, const char *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "fopen");
    mark_access(path);
    return real_fn(path, mode);
}

FILE *fopen64(const char *path, const char *mode) {
    static FILE *(*real_fn)(const char *, const char *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "fopen64");
    mark_access(path);
    return real_fn(path, mode);
}

int open(const char *path, int flags, ...) {
    static int (*real_fn)(const char *, int, ...);
    mode_t mode = 0;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "open");
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);
    }
    mark_access(path);
    return (flags & O_CREAT) ? real_fn(path, flags, mode) : real_fn(path, flags);
}

int open64(const char *path, int flags, ...) {
    static int (*real_fn)(const char *, int, ...);
    mode_t mode = 0;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "open64");
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);
    }
    mark_access(path);
    return (flags & O_CREAT) ? real_fn(path, flags, mode) : real_fn(path, flags);
}

int openat(int dirfd, const char *path, int flags, ...) {
    static int (*real_fn)(int, const char *, int, ...);
    mode_t mode = 0;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "openat");
    if (flags & O_CREAT) {
        va_list ap; va_start(ap, flags); mode = va_arg(ap, mode_t); va_end(ap);
    }
    mark_access(path);
    return (flags & O_CREAT) ? real_fn(dirfd, path, flags, mode) : real_fn(dirfd, path, flags);
}
AUDIT_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import math
import os
import secrets
import subprocess
import tempfile
import time
import pytest

CSV_PATH = '/app/interactions.csv'
SOURCE_PATH = '/home/user/fast_query.c'
BINARY_PATH = '/home/user/fast_query'
PIPELINE_PATH = '/home/user/run_pipeline.sh'
JSON_PATH = '/home/user/final_result.json'
AUDIT_SO = '/tmp/count_interactions.so'
EXPECTED_KEYS = {'start', 'end', 'path', 'total_weight'}


def load_graph(csv_path):
    graph = {}
    nodes = set()
    edge_weights = {}
    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or len(row) < 3:
                continue
            try:
                u, v, w = int(row[0]), int(row[1]), float(row[2])
            except ValueError:
                continue
            graph.setdefault(u, []).append((v, w))
            nodes.add(u)
            nodes.add(v)
            key = (u, v)
            if key not in edge_weights or w < edge_weights[key]:
                edge_weights[key] = w
    return graph, sorted(nodes), edge_weights


def get_true_shortest_path_from_graph(graph, start_node, end_node):
    pq = [(0.0, start_node, [start_node])]
    visited = set()
    while pq:
        w, u, path = heapq.heappop(pq)
        if u in visited:
            continue
        visited.add(u)
        if u == end_node:
            return path, w
        for v, weight in graph.get(u, []):
            if v not in visited:
                heapq.heappush(pq, (w + weight, v, path + [v]))
    return None, None


def assert_schema(result, start_node, end_node):
    assert isinstance(result, dict), 'Output must be a JSON object'
    assert set(result.keys()) == EXPECTED_KEYS, f'JSON keys must be exactly {sorted(EXPECTED_KEYS)}'
    assert isinstance(result['start'], int) and not isinstance(result['start'], bool)
    assert isinstance(result['end'], int) and not isinstance(result['end'], bool)
    assert result['start'] == start_node, f"Expected start node {start_node}, got {result['start']}"
    assert result['end'] == end_node, f"Expected end node {end_node}, got {result['end']}"
    assert isinstance(result['path'], list) and result['path'], 'path must be a nonempty JSON array'
    assert all(isinstance(x, int) and not isinstance(x, bool) for x in result['path'])
    assert isinstance(result['total_weight'], (int, float)) and not isinstance(result['total_weight'], bool)
    assert math.isfinite(float(result['total_weight']))


def parse_stdout(stdout, start_node, end_node):
    decoder = json.JSONDecoder()
    try:
        result, end = decoder.raw_decode(stdout.lstrip())
    except json.JSONDecodeError as exc:
        pytest.fail(f'fast_query stdout is not valid JSON: {exc}; stdout={stdout!r}')
    leading = len(stdout) - len(stdout.lstrip())
    assert stdout[leading + end:].strip() == '', 'fast_query stdout contains data other than the JSON result'
    assert_schema(result, start_node, end_node)
    return result


def run_query(binary, start_node, end_node, audit=False, timeout=2.0):
    env = os.environ.copy()
    marker = None
    if audit:
        fd, marker = tempfile.mkstemp(prefix='interactions-open-', dir='/tmp')
        os.close(fd)
        env['LD_PRELOAD'] = AUDIT_SO
        env['INTERACTIONS_OPEN_LOG'] = marker
    try:
        proc = subprocess.run(
            [binary, str(start_node), str(end_node)],
            capture_output=True, text=True, timeout=timeout, env=env
        )
        assert proc.returncode == 0, f'fast_query failed with exit code {proc.returncode}. Stderr: {proc.stderr}'
        result = parse_stdout(proc.stdout, start_node, end_node)
        if audit:
            with open(marker, 'r') as f:
                accesses = sum(1 for line in f if line.strip() == '1')
            assert accesses == 1, f'fast_query must open /app/interactions.csv exactly once per query; observed {accesses} opens'
        return result, proc.stdout
    finally:
        if marker and os.path.exists(marker):
            os.unlink(marker)


def assert_shortest_result(result, best_weight, edge_weights):
    path = result['path']
    assert path[0] == result['start'] and path[-1] == result['end']
    path_weight = 0.0
    for u, v in zip(path, path[1:]):
        assert (u, v) in edge_weights, f'Output path uses nonexistent edge {u}->{v}'
        path_weight += edge_weights[(u, v)]
    assert abs(path_weight - best_weight) < 1e-4, f'Output path weight {path_weight} is not shortest weight {best_weight}'
    assert abs(float(result['total_weight']) - best_weight) < 1e-4, f"Expected weight {best_weight}, got {result['total_weight']}"


def test_pipeline_and_fast_query():
    start_node = 452
    end_node = 8910

    assert os.path.isfile(CSV_PATH), f'Missing interactions dataset at {CSV_PATH}'
    assert os.path.isfile(SOURCE_PATH), f'Missing C source at {SOURCE_PATH}'
    assert os.path.isfile(PIPELINE_PATH), f'Missing pipeline script at {PIPELINE_PATH}'

    # The verifier itself runs the required pipeline, so stale independently-created
    # artifacts cannot satisfy the checks.
    for path in (BINARY_PATH, JSON_PATH):
        if os.path.lexists(path):
            os.unlink(path)
    pipeline = subprocess.run(['/bin/bash', PIPELINE_PATH], capture_output=True, text=True, timeout=30)
    assert pipeline.returncode == 0, f'Pipeline failed with exit code {pipeline.returncode}. Stderr: {pipeline.stderr}'

    assert os.path.isfile(BINARY_PATH), f'Pipeline did not create {BINARY_PATH}'
    assert os.access(BINARY_PATH, os.X_OK), f'Binary at {BINARY_PATH} is not executable'
    with open(BINARY_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'fast_query must be a compiled native executable'
    assert os.path.isfile(JSON_PATH), f'Pipeline did not create {JSON_PATH}'

    graph, nodes, edge_weights = load_graph(CSV_PATH)
    best_path, best_weight = get_true_shortest_path_from_graph(graph, start_node, end_node)
    assert best_path is not None, f'No path found between {start_node} and {end_node} in truth data'

    with open(JSON_PATH, 'r') as f:
        try:
            final_result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'{JSON_PATH} is not valid JSON')
    assert_schema(final_result, start_node, end_node)
    assert final_result['path'] == best_path, f"Expected path {best_path}, got {final_result['path']}"
    assert abs(float(final_result['total_weight']) - best_weight) < 1e-4, f"Expected weight {best_weight}, got {final_result['total_weight']}"

    # Preserve the original performance assertion and additionally validate stdout.
    begin = time.monotonic()
    target_result, target_stdout = run_query(BINARY_PATH, start_node, end_node, audit=False, timeout=2.0)
    runtime = time.monotonic() - begin
    assert runtime <= 0.5, f'Runtime {runtime:.4f}s exceeded threshold of 0.5s'
    assert target_result['path'] == best_path, f"Expected path {best_path}, got {target_result['path']}"
    assert abs(float(target_result['total_weight']) - best_weight) < 1e-4
    assert final_result == target_result, 'Pipeline final_result.json does not match fast_query stdout'

    # Compile the submitted C source independently to ensure the source itself is functional.
    rebuilt = '/tmp/fast_query_rebuilt'
    compile_proc = subprocess.run(
        ['gcc', '-O2', '-std=c11', SOURCE_PATH, '-o', rebuilt],
        capture_output=True, text=True, timeout=20
    )
    assert compile_proc.returncode == 0, f'fast_query.c failed to compile: {compile_proc.stderr}'
    assert os.access(rebuilt, os.X_OK)

    # Secretly selected parameterized queries prevent a fixed-output executable from passing.
    rng = secrets.SystemRandom()
    checked = 0
    attempts = 0
    while checked < 3 and attempts < 30:
        attempts += 1
        s = rng.choice(nodes)
        e = rng.choice(nodes)
        if s == e:
            continue
        truth_path, truth_weight = get_true_shortest_path_from_graph(graph, s, e)
        if truth_path is None:
            continue
        for binary in (BINARY_PATH, rebuilt):
            result, _ = run_query(binary, s, e, audit=True, timeout=2.0)
            assert_shortest_result(result, truth_weight, edge_weights)
        checked += 1
    assert checked == 3, 'Could not obtain enough reachable parameterized test pairs'
TEST_EOF

if gcc -shared -fPIC -O2 /tmp/count_interactions.c -o /tmp/count_interactions.so -ldl && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
