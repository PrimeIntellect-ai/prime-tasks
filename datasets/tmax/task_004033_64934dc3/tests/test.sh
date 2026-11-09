#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import random
import re
import subprocess
import tempfile
import pytest

EXPECTED_EDGES = [(i, i + 1, i * 5 + 5) for i in range(10)]


def test_extracted_edges_file():
    extracted_path = "/home/user/extracted_edges.txt"
    assert os.path.isfile(extracted_path), f"Extracted edges file missing at {extracted_path}"
    with open(extracted_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines, "Extracted edges file is empty"

    parsed = []
    patterns = [
        re.compile(r"^(\d+)\s+(\d+)\s+(\d+)$"),
        re.compile(r"^ACCESS:\s*\[?(\d+)\]?\s*->\s*\[?(\d+)\]?\s+\[?(\d+)\]?$", re.IGNORECASE),
    ]
    for line in lines:
        match = next((pattern.fullmatch(line) for pattern in patterns if pattern.fullmatch(line)), None)
        assert match is not None, f"Malformed extracted edge: {line!r}"
        parsed.append(tuple(map(int, match.groups())))

    assert parsed == EXPECTED_EDGES, f"Extracted edges do not match the access-log video: {parsed!r}"


def test_checker_executable():
    checker_path = "/home/user/checker"
    source_path = "/home/user/checker.c"
    assert os.path.isfile(source_path), f"C source missing at {source_path}"
    assert os.path.isfile(checker_path), f"Checker binary missing at {checker_path}"
    assert os.access(checker_path, os.X_OK), f"Checker binary at {checker_path} is not executable"
    with open(checker_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Checker must be a compiled native executable"


def generate_test_case(rng):
    V = rng.randint(10, 500)
    E = rng.randint(10, 5000)
    edges = []
    lines = [f"{V} {E}"]
    for _ in range(E):
        u = rng.randint(0, V - 1)
        v = rng.randint(0, V - 1)
        w = rng.randint(1, 1000)
        edges.append((u, v, w))
        lines.append(f"{u} {v} {w}")

    Q = rng.randint(10, 1000)
    queries = []
    lines.append(str(Q))
    for _ in range(Q):
        start = rng.randint(0, V - 1)
        target = rng.randint(0, V - 1)
        queries.append((start, target))
        lines.append(f"{start} {target}")

    return "\n".join(lines) + "\n", V, edges, queries


def expected_output(V, edges, queries):
    graph = [[] for _ in range(V)]
    for u, v, w in edges:
        graph[u].append((v, w))

    cache = {}
    output = []
    for start, target in queries:
        if start not in cache:
            distances = [None] * V
            distances[start] = 0
            queue = [(0, start)]
            while queue:
                distance, u = heapq.heappop(queue)
                if distances[u] != distance:
                    continue
                for v, weight in graph[u]:
                    candidate = distance + weight
                    if distances[v] is None or candidate < distances[v]:
                        distances[v] = candidate
                        heapq.heappush(queue, (candidate, v))
            cache[start] = distances
        answer = cache[start][target]
        output.append(str(-1 if answer is None else answer))
    return "\n".join(output) + "\n"


def run_checker(path, test_input, case_number):
    try:
        proc = subprocess.run(
            [path],
            input=test_input,
            text=True,
            capture_output=True,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Checker {path} timed out on test case {case_number}.")
    if proc.returncode != 0:
        pytest.fail(
            f"Checker {path} crashed on test case {case_number}. "
            f"Return code: {proc.returncode}\nStderr: {proc.stderr}"
        )
    return proc.stdout


def test_fuzz_equivalence():
    agent_path = "/home/user/checker"
    source_path = "/home/user/checker.c"
    assert os.path.isfile(agent_path), f"Agent binary missing at {agent_path}"
    assert os.path.isfile(source_path), f"Agent C source missing at {source_path}"

    rebuilt_path = os.path.join(tempfile.gettempdir(), "checker_from_source")
    compile_proc = subprocess.run(
        ["gcc", "-O3", "-std=c11", source_path, "-o", rebuilt_path],
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert compile_proc.returncode == 0, f"checker.c failed to compile:\n{compile_proc.stderr}"

    rng = random.SystemRandom()
    for i in range(100):
        test_input, V, edges, queries = generate_test_case(rng)
        expected = expected_output(V, edges, queries)

        for checker_path in (agent_path, rebuilt_path):
            actual = run_checker(checker_path, test_input, i)
            if actual != expected:
                pytest.fail(
                    f"Mismatch from {checker_path} on test case {i}!\n"
                    f"Input (first 100 chars): {test_input[:100]}...\n"
                    f"Expected output (first 100 chars): {expected[:100]}...\n"
                    f"Actual output (first 100 chars): {actual[:100]}..."
                )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
