#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import secrets
import subprocess

import pytest

FAST_BIN = "/home/user/fast_resolver"
LEGACY_BIN = "/app/legacy_resolver"
C_SOURCE = "/home/user/resolver.c"
GO_SOURCE = "/home/user/fuzzer.go"
BUILT_FROM_SOURCE = "/tmp/resolver_from_source"


def run_program(path, data, timeout=30):
    return subprocess.run(
        [path], input=data, capture_output=True, timeout=timeout, check=False
    )


@pytest.fixture(scope="session", autouse=True)
def validate_and_build_artifacts():
    assert os.path.isfile(C_SOURCE), f"Missing C source: {C_SOURCE}"
    assert os.path.getsize(C_SOURCE) > 0, f"Empty C source: {C_SOURCE}"
    assert os.path.isfile(GO_SOURCE), f"Missing Go harness: {GO_SOURCE}"
    assert os.path.getsize(GO_SOURCE) > 0, f"Empty Go harness: {GO_SOURCE}"

    assert os.path.isfile(FAST_BIN), f"Missing binary: {FAST_BIN}"
    assert os.access(FAST_BIN, os.X_OK), f"Binary is not executable: {FAST_BIN}"
    with open(FAST_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast_resolver is not a compiled native executable"

    c_build = subprocess.run(
        ["gcc", "-O2", "-pthread", C_SOURCE, "-o", BUILT_FROM_SOURCE],
        capture_output=True,
        text=True,
        timeout=60,
    )
    assert c_build.returncode == 0, f"resolver.c does not compile:\n{c_build.stderr}"

    go_build = subprocess.run(
        ["go", "build", "-o", "/tmp/fuzzer_check", GO_SOURCE],
        capture_output=True,
        text=True,
        timeout=90,
    )
    assert go_build.returncode == 0, f"fuzzer.go does not compile:\n{go_build.stderr}"

    with open(GO_SOURCE, "r", encoding="utf-8", errors="replace") as f:
        go_text = f.read()
    uncommented = re.sub(r"//.*?$|/\*.*?\*/", "", go_text, flags=re.MULTILINE | re.DOTALL)
    assert re.search(r"\bgo\s+(?:func\s*\(|[A-Za-z_][A-Za-z0-9_.]*\s*\()", uncommented), \
        "fuzzer.go must launch goroutines"
    assert re.search(r"\bchan\b", uncommented), "fuzzer.go must use channels"


def assert_matches_oracle(graph_bytes):
    oracle = run_program(LEGACY_BIN, graph_bytes)
    assert oracle.returncode == 0, oracle.stderr.decode(errors="replace")

    for candidate in (FAST_BIN, BUILT_FROM_SOURCE):
        result = run_program(candidate, graph_bytes)
        assert result.returncode == 0, \
            f"{candidate} failed: {result.stderr.decode(errors='replace')}"
        assert result.stdout == oracle.stdout, \
            f"Output mismatch for {candidate} on input:\n{graph_bytes.decode(errors='replace')}"


def test_randomized_property_cases():
    seed = secrets.randbits(128)
    rng = random.Random(seed)

    cases = [
        b"",
        b"ignored\nonly one token\n",
        b"z a\nz a\na b\n",
        b"node10 node2\nnode1 node2\n",
    ]

    # Random DAGs with labels whose lexical order is independent of topological rank.
    for case_no in range(12):
        n = rng.randint(4, 45)
        labels = [f"svc_{case_no}_{rng.getrandbits(40):010x}_{i}" for i in range(n)]
        rank = list(range(n))
        rng.shuffle(rank)
        edges = set()
        target = rng.randint(n - 1, min(n * (n - 1) // 2, n * 4))
        while len(edges) < target:
            a, b = sorted(rng.sample(range(n), 2))
            edges.add((rank[a], rank[b]))
        lines = [f"{labels[u]} {labels[v]}\n" for u, v in edges]
        rng.shuffle(lines)
        cases.append("".join(lines).encode())

    # Random cyclic graphs, including cycles with acyclic prefixes and suffixes.
    for case_no in range(8):
        n = rng.randint(4, 30)
        labels = [f"cyc_{case_no}_{rng.getrandbits(36):09x}_{i}" for i in range(n)]
        cycle_nodes = rng.sample(range(n), rng.randint(2, min(8, n)))
        edges = [(cycle_nodes[i], cycle_nodes[(i + 1) % len(cycle_nodes)])
                 for i in range(len(cycle_nodes))]
        for _ in range(rng.randint(n, n * 3)):
            u, v = rng.sample(range(n), 2)
            edges.append((u, v))
        lines = [f"{labels[u]} {labels[v]}\n" for u, v in edges]
        rng.shuffle(lines)
        cases.append("".join(lines).encode())

    for graph in cases:
        try:
            assert_matches_oracle(graph)
        except AssertionError as exc:
            raise AssertionError(f"Random property test failed with seed {seed}: {exc}") from exc


def test_fast_resolver_performance_and_correctness():
    # Preserve the original 5,000-node/20,000-edge benchmark, but generate an
    # unpredictable DAG whose lexical labels do not reveal its topological ranks.
    num_nodes = 5000
    num_edges = 20000
    rng = random.Random(secrets.randbits(128))
    salt = secrets.token_hex(6)
    labels = [f"S_{salt}_{i:04d}" for i in range(num_nodes)]
    topo = list(range(num_nodes))
    rng.shuffle(topo)

    edges = set()
    while len(edges) < num_edges:
        a = rng.randrange(num_nodes - 1)
        b = rng.randrange(a + 1, num_nodes)
        edges.add((topo[a], topo[b]))
    edge_list = list(edges)
    rng.shuffle(edge_list)
    graph_bytes = "".join(f"{labels[u]} {labels[v]}\n" for u, v in edge_list).encode()

    import time
    t0 = time.monotonic()
    p_legacy = run_program(LEGACY_BIN, graph_bytes, timeout=90)
    t_legacy = time.monotonic() - t0
    assert p_legacy.returncode == 0, \
        f"Legacy resolver failed: {p_legacy.stderr.decode(errors='replace')}"

    t0 = time.monotonic()
    p_fast = run_program(FAST_BIN, graph_bytes, timeout=90)
    t_fast = time.monotonic() - t0
    assert p_fast.returncode == 0, \
        f"Fast resolver failed: {p_fast.stderr.decode(errors='replace')}"

    assert p_fast.stdout == p_legacy.stdout, \
        "Output mismatch between fast_resolver and legacy_resolver on DAG"

    speedup = t_legacy / t_fast if t_fast > 0 else float("inf")
    assert speedup >= 4.0, \
        f"Speedup is {speedup:.2f}x (Legacy: {t_legacy:.4f}s, Fast: {t_fast:.4f}s), which is less than the required 4.0x"


def test_fast_resolver_cycle_handling():
    graph_input = b"A B\nB C\nC D\nD B\n"
    p_legacy = run_program(LEGACY_BIN, graph_input)
    p_fast = run_program(FAST_BIN, graph_input)
    assert p_fast.stdout == p_legacy.stdout, \
        "Output mismatch between fast_resolver and legacy_resolver on cyclic graph"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
