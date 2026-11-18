#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import shutil
import subprocess
import tempfile
from collections import defaultdict

CPP_PATH = "/home/user/analyze_graph.cpp"
CSV_PATH = "/home/user/network_events.csv"
OUTPUT_PATH = "/home/user/top_nodes.txt"
BINARY_PATH = "/tmp/analyze_graph_verifier"


def expected_lines(csv_path):
    edge_latest_event = {}
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = int(row["timestamp"])
            n1 = int(row["node1"])
            n2 = int(row["node2"])
            action = row["action"].strip().upper()
            u, v = min(n1, n2), max(n1, n2)
            if (u, v) not in edge_latest_event or ts > edge_latest_event[(u, v)][0]:
                edge_latest_event[(u, v)] = (ts, action)

    degrees = defaultdict(int)
    for (u, v), (_, action) in edge_latest_event.items():
        if action == "CONNECT":
            degrees[u] += 1
            degrees[v] += 1

    top_5 = sorted(degrees.items(), key=lambda x: (-x[1], x[0]))[:5]
    return [f"{node},{degree}" for node, degree in top_5]


def run_and_check(csv_path):
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        [BINARY_PATH], cwd="/home/user", capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}. "
        f"stderr: {result.stderr}"
    )

    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    assert os.path.isfile(OUTPUT_PATH), f"Path {OUTPUT_PATH} is not a file."

    with open(OUTPUT_PATH, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    expected = expected_lines(csv_path)
    assert len(actual_lines) == 5, (
        f"Expected exactly 5 lines in {OUTPUT_PATH}, found {len(actual_lines)}."
    )
    for i, (actual, wanted) in enumerate(zip(actual_lines, expected)):
        assert actual == wanted, (
            f"Mismatch at line {i + 1}: expected '{wanted}', got '{actual}'."
        )


def test_analyze_graph_cpp_exists():
    assert os.path.exists(CPP_PATH), f"C++ source file {CPP_PATH} does not exist."
    assert os.path.isfile(CPP_PATH), f"Path {CPP_PATH} is not a file."


def test_analyze_graph_cpp_compiles():
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_PATH, "-o", BINARY_PATH],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"C++ source failed to compile: {result.stderr}"
    assert os.path.isfile(BINARY_PATH), "Compilation did not produce an executable."


def test_top_nodes_output():
    run_and_check(CSV_PATH)


def test_program_processes_unordered_events():
    synthetic = """timestamp,node1,node2,action
50,1,2,CONNECT
20,3,5,CONNECT
90,4,3,DISCONNECT
40,3,1,CONNECT
30,6,3,CONNECT
100,2,1,DISCONNECT
70,2,3,CONNECT
110,3,4,CONNECT
45,1,4,CONNECT
65,4,2,CONNECT
75,4,5,CONNECT
55,6,5,CONNECT
10,8,7,CONNECT
"""

    fd, backup_path = tempfile.mkstemp(prefix="network_events_backup_", suffix=".csv")
    os.close(fd)
    shutil.copyfile(CSV_PATH, backup_path)
    try:
        with open(CSV_PATH, "w") as f:
            f.write(synthetic)
        run_and_check(CSV_PATH)
    finally:
        shutil.copyfile(backup_path, CSV_PATH)
        os.remove(backup_path)
        # Restore top_nodes.txt for the original supplied data.
        subprocess.run([BINARY_PATH], cwd="/home/user", timeout=10, check=False)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
