#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import struct
import subprocess
import time
import pytest

FAST_BIN = "/home/user/fast_backup"
SOURCE = "/home/user/fast_backup.c"
LEGACY_BIN = "/app/legacy_backup_bin"
REBUILT_BIN = "/tmp/fast_backup_from_source"
GRAPH = "/home/user/graph_data.bin"
MAX_NODES = 200000


def run_program(path, args, timeout=8):
    try:
        proc = subprocess.run(
            [path] + [str(x) for x in args],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            timeout=timeout,
            check=False,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{path} timed out for arguments {args}")
    assert proc.returncode == 0, (
        f"{path} failed for arguments {args} with exit code {proc.returncode}: "
        f"{proc.stdout.decode('utf-8', errors='replace')}"
    )
    return proc.stdout


def load_adjacency():
    adjacency = {}
    with open(GRAPH, "rb") as f:
        while True:
            record = f.read(8)
            if not record:
                break
            assert len(record) == 8, "graph_data.bin contains a partial edge"
            u, v = struct.unpack("<II", record)
            adjacency.setdefault(u, []).append(v)
    return adjacency


def expected_output(adjacency, root, depth, page_size, page_num):
    if root < MAX_NODES:
        visited = {root}
        frontier = [root]
    else:
        visited = set()
        frontier = []

    for _ in range(depth):
        next_frontier = []
        for u in frontier:
            for v in adjacency.get(u, ()):
                if v < MAX_NODES and v not in visited:
                    visited.add(v)
                    next_frontier.append(v)
        frontier = next_frontier

    values = sorted(visited)
    start = page_size * page_num
    if start > len(values):
        start = len(values)
    end = min(start + page_size, len(values))
    page_values = values[start:end]
    text = (
        f'{{"root": {root}, "depth": {depth}, '
        f'"total_reachable": {len(values)}, "page": {page_num}, '
        f'"results": {page_values}}}\n'
    )
    return text.encode("utf-8"), len(values)


def test_fast_backup_exists_and_executable():
    assert os.path.exists(FAST_BIN), f"File {FAST_BIN} does not exist. Did you compile your C program?"
    assert os.path.isfile(FAST_BIN), f"{FAST_BIN} is not a file."
    assert os.access(FAST_BIN, os.X_OK), f"File {FAST_BIN} is not executable."
    with open(FAST_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{FAST_BIN} is not a compiled ELF executable."

    assert os.path.exists(SOURCE), f"Required source file {SOURCE} does not exist."
    assert os.path.isfile(SOURCE), f"{SOURCE} is not a file."
    assert os.path.getsize(SOURCE) > 0, f"{SOURCE} is empty."

    compile_proc = subprocess.run(
        ["gcc", "-O2", "-std=c11", SOURCE, "-o", REBUILT_BIN],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        check=False,
    )
    assert compile_proc.returncode == 0, (
        "fast_backup.c did not compile successfully:\n"
        + compile_proc.stdout.decode("utf-8", errors="replace")
    )
    assert os.access(REBUILT_BIN, os.X_OK)

    with open(FAST_BIN, "rb") as submitted, open(LEGACY_BIN, "rb") as legacy:
        assert submitted.read() != legacy.read(), "fast_backup must not be a copy of the legacy binary."


def test_fast_backup_correctness_and_speedup():
    adjacency = load_adjacency()

    # Preserve the original oracle comparison and 50x speed assertion.
    fixed_args = [42, 3, 50, 0]
    start_leg = time.perf_counter()
    try:
        leg_out = subprocess.check_output(
            [LEGACY_BIN] + [str(x) for x in fixed_args],
            stderr=subprocess.STDOUT,
        )
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Legacy binary failed: {e.output.decode('utf-8', errors='ignore')}")
    leg_time = time.perf_counter() - start_leg

    start_fast = time.perf_counter()
    fast_out = run_program(FAST_BIN, fixed_args, timeout=8)
    fast_time = time.perf_counter() - start_fast

    try:
        leg_json = json.loads(leg_out.decode("utf-8"))
    except json.JSONDecodeError:
        pytest.fail("Legacy binary did not output valid JSON.")
    try:
        fast_json = json.loads(fast_out.decode("utf-8"))
    except json.JSONDecodeError:
        pytest.fail("Your fast_backup binary did not output valid JSON.")

    assert leg_json == fast_json, f"Output mismatch. Expected: {leg_json}, Got: {fast_json}"
    speedup = leg_time / max(fast_time, 0.001)
    assert speedup >= 50.0, (
        f"Speedup too low. Required: >= 50.0x, Achieved: {speedup:.2f}x "
        f"(Legacy time: {leg_time:.4f}s, Fast time: {fast_time:.4f}s)"
    )

    fixed_expected, _ = expected_output(adjacency, *fixed_args)
    assert fast_out == fixed_expected, "Output does not use the required exact JSON formatting."

    # Compile and benchmark the required source independently so the submitted
    # executable cannot be an unrelated fixed-output program.
    start_rebuilt = time.perf_counter()
    rebuilt_fixed_out = run_program(REBUILT_BIN, fixed_args, timeout=8)
    rebuilt_time = time.perf_counter() - start_rebuilt
    assert rebuilt_fixed_out == fixed_expected
    rebuilt_speedup = leg_time / max(rebuilt_time, 0.001)
    assert rebuilt_speedup >= 50.0, (
        f"Program compiled from fast_backup.c is too slow: {rebuilt_speedup:.2f}x speedup"
    )

    rng = secrets.SystemRandom()
    source_nodes = list(adjacency.keys())

    # Cases are selected only after the agent has finished. They cover depth 0,
    # multiple BFS depths, nonzero and out-of-range pages, and a dense depth-3 BFS.
    cases = [
        (150000, 0, 1, 0),
        (150000, 2, 7, 1),
        (rng.choice(range(101)), 3, rng.choice([1, 7, 31, 97]), rng.randrange(0, 8)),
    ]
    for depth in (0, 1, 2, 3):
        root = rng.choice(source_nodes)
        page_size = rng.choice([1, 2, 7, 19, 53, 113])
        _, total = expected_output(adjacency, root, depth, page_size, 0)
        possible_pages = [0, 1, total // page_size, total // page_size + 2]
        cases.append((root, depth, page_size, rng.choice(possible_pages)))

    dense_root = rng.choice(range(101))
    _, dense_total = expected_output(adjacency, dense_root, 2, 17, 0)
    cases.extend([
        (dense_root, 2, 17, 0),
        (dense_root, 2, 17, 1),
        (dense_root, 2, 17, dense_total // 17),
        (dense_root, 2, 17, dense_total // 17 + 3),
    ])

    for args in cases:
        expected, _ = expected_output(adjacency, *args)
        for program in (FAST_BIN, REBUILT_BIN):
            actual = run_program(program, args, timeout=8)
            assert actual == expected, (
                f"Incorrect output from {program} for arguments {args}.\n"
                f"Expected: {expected.decode('utf-8', errors='replace')}"
                f"Got: {actual.decode('utf-8', errors='replace')}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
