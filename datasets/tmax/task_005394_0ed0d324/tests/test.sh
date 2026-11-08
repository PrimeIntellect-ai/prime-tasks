#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import random
import secrets
import subprocess

SOURCE = "/home/user/analyze_backups.rs"
BINARY = "/home/user/analyze_backups"
GRAPH = "/home/user/replication_graph.csv"
SIZES = "/home/user/backup_sizes.csv"
REPORT = "/home/user/report.csv"
RECOMPILED = "/tmp/analyze_backups_recompiled"


def test_rust_source_exists():
    assert os.path.isfile(SOURCE), f"Rust source file not found: {SOURCE}"


def test_rust_binary_exists():
    assert os.path.isfile(BINARY), f"Compiled Rust binary not found: {BINARY}"
    assert os.access(BINARY, os.X_OK), f"File is not executable: {BINARY}"
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compiled binary is not an ELF executable"


def test_report_csv_content():
    assert os.path.isfile(REPORT), f"Report file not found: {REPORT}"
    with open(REPORT, "r") as f:
        content = f.read().strip()

    expected_content = """instance_id,shortest_latency_ms,backup_size_gb
db-05,37,45
db-06,40,30
db-02,15,12"""
    assert content == expected_content, (
        f"Content mismatch in {REPORT}. Expected:\n{expected_content}\nGot:\n{content}"
    )


def make_fixture():
    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    nodes = [f"db-{i:02d}" for i in range(1, 11)]

    edges = []
    for i in range(len(nodes) - 1):
        edges.append((nodes[i], nodes[i + 1], rng.randint(4, 35)))

    for target in range(2, len(nodes)):
        edges.append(("db-01", nodes[target], rng.randint(18, 110)))
    for _ in range(15):
        a = rng.randrange(len(nodes))
        b = rng.randrange(len(nodes))
        if a != b:
            edges.append((nodes[a], nodes[b], rng.randint(3, 70)))

    # These graph components are unreachable from db-01 and must not be joined.
    edges.extend([
        ("db-11", "db-12", 1),
        ("db-12", "db-11", 1),
    ])

    sizes = {node: rng.randint(15, 140) for node in nodes}
    sizes["db-02"] = 9                 # Strictly below the filter threshold.
    sizes["db-03"] = 75                # Exercise the instance_id tie-breaker.
    sizes["db-07"] = 75
    sizes["db-11"] = 900               # Unreachable despite a large size.
    sizes["db-12"] = 800
    sizes["db-13"] = 1000              # No graph entry at all.

    graph_text = "source_instance,target_instance,latency_ms\n" + "".join(
        f"{a},{b},{w}\n" for a, b, w in edges
    )
    sizes_text = "instance_id,backup_size_gb\n" + "".join(
        f"{node},{size}\n" for node, size in sizes.items()
    )

    adjacency = {}
    for a, b, weight in edges:
        adjacency.setdefault(a, []).append((b, weight))

    distances = {"db-01": 0}
    queue = [(0, "db-01")]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances.get(node):
            continue
        for neighbor, weight in adjacency.get(node, []):
            candidate = distance + weight
            if candidate < distances.get(neighbor, 10**30):
                distances[neighbor] = candidate
                heapq.heappush(queue, (candidate, neighbor))

    rows = [
        (node, distance, sizes[node])
        for node, distance in distances.items()
        if node in sizes and sizes[node] >= 10
    ]
    rows.sort(key=lambda row: (-row[2], row[0]))
    page = rows[3:6]
    expected = "instance_id,shortest_latency_ms,backup_size_gb\n" + "\n".join(
        f"{node},{distance},{size}" for node, distance, size in page
    )
    return graph_text, sizes_text, expected


def run_and_check(executable):
    graph_text, sizes_text, expected = make_fixture()
    with open(GRAPH, "w") as f:
        f.write(graph_text)
    with open(SIZES, "w") as f:
        f.write(sizes_text)
    if os.path.exists(REPORT):
        os.unlink(REPORT)

    result = subprocess.run(
        [executable], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f"{executable} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT), f"{executable} did not generate {REPORT}"
    with open(REPORT, "r") as f:
        actual = f.read().strip()
    assert actual == expected.strip(), (
        f"Incorrect report from {executable}.\nExpected:\n{expected}\nGot:\n{actual}"
    )


def test_program_implements_required_processing():
    original_graph = open(GRAPH, "rb").read()
    original_sizes = open(SIZES, "rb").read()
    original_report = open(REPORT, "rb").read() if os.path.exists(REPORT) else None
    try:
        compile_result = subprocess.run(
            ["rustc", SOURCE, "-o", RECOMPILED], cwd="/home/user", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=60
        )
        assert compile_result.returncode == 0, (
            f"Rust source does not compile.\nstdout:\n{compile_result.stdout}\n"
            f"stderr:\n{compile_result.stderr}"
        )
        with open(RECOMPILED, "rb") as f:
            assert f.read(4) == b"\x7fELF", "rustc did not produce an ELF executable"

        # Exercise both the submitted compiled artifact and a fresh build of its source
        # on independently generated inputs whose answers are computed by the verifier.
        run_and_check(BINARY)
        run_and_check(RECOMPILED)
    finally:
        with open(GRAPH, "wb") as f:
            f.write(original_graph)
        with open(SIZES, "wb") as f:
            f.write(original_sizes)
        if original_report is None:
            if os.path.exists(REPORT):
                os.unlink(REPORT)
        else:
            with open(REPORT, "wb") as f:
                f.write(original_report)
        if os.path.exists(RECOMPILED):
            os.unlink(RECOMPILED)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
