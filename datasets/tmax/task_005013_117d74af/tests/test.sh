#!/bin/bash
set -e
mkdir -p /logs/verifier

restore_dir=$(mktemp -d)
cp -a /home/user/backup/edges.csv "$restore_dir/edges.csv"
if [ -e /home/user/index_priority.json ]; then
    cp -a /home/user/index_priority.json "$restore_dir/index_priority.json"
    touch "$restore_dir/had_json"
fi
restore_files() {
    cp -a "$restore_dir/edges.csv" /home/user/backup/edges.csv
    if [ -e "$restore_dir/had_json" ]; then
        cp -a "$restore_dir/index_priority.json" /home/user/index_priority.json
    else
        rm -f /home/user/index_priority.json
    fi
    rm -rf "$restore_dir"
}
trap restore_files EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import random
import subprocess
import pytest

C_FILE = "/home/user/analyze_graph.c"
CSV_FILE = "/home/user/backup/edges.csv"
JSON_FILE = "/home/user/index_priority.json"
BINARY = "/tmp/analyze_graph_verifier"


def test_c_program_exists():
    """Verify that the C program was created."""
    c_file = "/home/user/analyze_graph.c"
    assert os.path.isfile(c_file), f"The C program {c_file} does not exist."


def test_json_output_exists():
    """Verify that the JSON output file was created."""
    json_file = "/home/user/index_priority.json"
    assert os.path.isfile(json_file), f"The JSON output file {json_file} does not exist."


def test_json_output_content():
    """Verify that the JSON output contains the correct top 3 nodes."""
    json_file = "/home/user/index_priority.json"

    with open(json_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_file} does not contain valid JSON.")

    expected = [
        {"node_id": 3, "degree": 6},
        {"node_id": 6, "degree": 6},
        {"node_id": 1, "degree": 5}
    ]

    assert isinstance(data, list), "The JSON output must be a list of objects."
    assert len(data) == 3, f"Expected exactly 3 items in the JSON array, got {len(data)}."

    for i in range(3):
        assert data[i] == expected[i], f"Mismatch at index {i}. Expected {expected[i]}, got {data[i]}."


def expected_top_three(edges):
    degrees = {}
    for source, target in edges:
        degrees[source] = degrees.get(source, 0) + 1
        degrees[target] = degrees.get(target, 0) + 1
    ranked = sorted(degrees.items(), key=lambda item: (-item[1], item[0]))[:3]
    return [{"node_id": node_id, "degree": degree} for node_id, degree in ranked]


def run_case(edges):
    with open(CSV_FILE, "w", encoding="utf-8") as f:
        for source, target in edges:
            f.write(f"{source},{target}\n")

    if os.path.lexists(JSON_FILE):
        os.unlink(JSON_FILE)

    result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Compiled program exited with status {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert os.path.isfile(JSON_FILE), "The executed C program did not create index_priority.json."

    try:
        with open(JSON_FILE, "r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The executed C program produced invalid JSON: {exc}")

    expected = expected_top_three(edges)
    assert isinstance(data, list), "The generated JSON must be an array."
    assert len(data) == 3, "The generated JSON must contain exactly three objects."
    for item in data:
        assert isinstance(item, dict), "Each array entry must be an object."
        assert set(item) == {"node_id", "degree"}, "Each object must contain only node_id and degree."
        assert type(item["node_id"]) is int, "node_id must be a JSON integer."
        assert type(item["degree"]) is int, "degree must be a JSON integer."
    assert data == expected, f"Expected {expected}, got {data}."


def test_c_program_compiles_and_computes_graph_analytics():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", C_FILE, "-o", BINARY],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"C program did not compile: {compile_result.stderr}"
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK)

    original_edges = [
        (1, 2), (1, 3), (1, 4), (1, 5), (2, 3), (3, 1), (4, 3),
        (5, 3), (3, 6), (6, 4), (6, 7), (6, 8), (6, 9), (6, 10),
    ]
    run_case(original_edges)

    run_case([
        (-10, -10), (-10, 4), (4, -10), (4, 8), (8, 4),
        (8, 12), (12, 8), (12, 4), (99, 4), (99, 12),
        (7, 99), (7, 99), (-3, 7),
    ])

    rng = random.SystemRandom()
    nodes = rng.sample(range(-2000000000, 2000000001), 14)
    random_edges = [(rng.choice(nodes), rng.choice(nodes)) for _ in range(180)]
    run_case(random_edges)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
