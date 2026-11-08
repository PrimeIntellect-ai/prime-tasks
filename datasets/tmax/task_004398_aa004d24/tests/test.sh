#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest

def test_script_exists():
    """Check if the generate_data.py script exists."""
    script_path = "/home/user/generate_data.py"
    assert os.path.isfile(script_path), f"Script {script_path} is missing."

    with open(script_path, "r") as f:
        content = f.read()
        assert "validate_solver" in content, "The script must define a validate_solver() function."
        assert "Regression Test Passed" in content, "The script must print 'Regression Test Passed'."

def test_csv_output_exists_and_format():
    """Check if training_data.csv exists and has the correct headers."""
    csv_path = "/home/user/training_data.csv"
    assert os.path.isfile(csv_path), f"Output file {csv_path} is missing."

    with open(csv_path, "r") as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail(f"{csv_path} is empty.")

        expected_headers = ["network_id", "node_id", "concentration"]
        assert headers == expected_headers, f"Headers in {csv_path} do not match expected: {expected_headers}"

def test_csv_output_values():
    """Validate the calculated concentrations in the CSV output."""
    csv_path = "/home/user/training_data.csv"
    assert os.path.isfile(csv_path), f"Output file {csv_path} is missing."

    # Compute expected values analytically
    # net1
    # G1(t) = 100 * exp(-0.1*t)
    expected_g1 = 100 * math.exp(-5)
    # G2(t) = 500 * (exp(-0.1*t) - exp(-0.2*t))
    expected_g2 = 500 * (math.exp(-5) - math.exp(-10))

    # net2
    # A(t) = 50 * exp(-0.05*t)
    expected_a = 50 * math.exp(-2.5)
    # B(t) = 200 * exp(-0.05*t) - 190 * exp(-0.1*t)
    expected_b = 200 * math.exp(-2.5) - 190 * math.exp(-5)

    expected_data = [
        ("net1", "G1", f"{expected_g1:.4f}"),
        ("net1", "G2", f"{expected_g2:.4f}"),
        ("net2", "A", f"{expected_a:.4f}"),
        ("net2", "B", f"{expected_b:.4f}")
    ]

    actual_data = []
    with open(csv_path, "r") as f:
        reader = csv.reader(f)
        next(reader)  # skip header
        for row in reader:
            if len(row) == 3:
                actual_data.append(tuple(row))

    # The rows should be sorted alphabetically by network_id, then by node_id
    assert actual_data == expected_data, f"CSV data does not match the expected values or sorting.\nExpected: {expected_data}\nActual: {actual_data}"
TEST_EOF

run_checks() {
    rm -f /home/user/training_data.csv /tmp/generate_data.out
    timeout 60s python3 /home/user/generate_data.py > /tmp/generate_data.out 2>&1 || return 1
    grep -Fxq 'Regression Test Passed' /tmp/generate_data.out || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    # Add an unpredictable network only after the fixed-network assertions pass.
    python3 - << 'PY' || return 1
import json
import os
import secrets

network_id = "verify_" + secrets.token_hex(8)
path = f"/home/user/networks/{network_id}.json"
rng = secrets.SystemRandom()

# Deliberately use nonalphabetical insertion order, a cycle, branching,
# multiple incoming edges, and an isolated node.
names = ["Zeta", "Alpha", "Mu", "Beta", "Omega"]
nodes = {
    name: {
        "init": round(rng.uniform(3.0, 80.0), 6),
        "decay": round(rng.uniform(0.09, 0.22), 6),
    }
    for name in names
}
def rate():
    return round(rng.uniform(0.006, 0.035), 6)

edges = [
    {"source": "Zeta", "target": "Alpha", "rate": rate()},
    {"source": "Alpha", "target": "Mu", "rate": rate()},
    {"source": "Mu", "target": "Beta", "rate": rate()},
    {"source": "Beta", "target": "Zeta", "rate": rate()},
    {"source": "Zeta", "target": "Mu", "rate": rate()},
    {"source": "Alpha", "target": "Beta", "rate": rate()},
]
network = {"nodes": nodes, "edges": edges}
with open(path, "w") as f:
    json.dump(network, f)
with open("/tmp/challenge_path", "w") as f:
    f.write(path)
PY

    rm -f /home/user/training_data.csv /tmp/generate_data_challenge.out
    timeout 60s python3 /home/user/generate_data.py > /tmp/generate_data_challenge.out 2>&1 || return 1
    grep -Fxq 'Regression Test Passed' /tmp/generate_data_challenge.out || return 1

    python3 - << 'PY' || return 1
import csv
import json
import math
import os
import re
import numpy as np
from scipy.linalg import expm

with open("/tmp/challenge_path") as f:
    challenge_path = f.read().strip()
network_id = os.path.splitext(os.path.basename(challenge_path))[0]
with open(challenge_path) as f:
    graph = json.load(f)

node_names = list(graph["nodes"])
index = {name: i for i, name in enumerate(node_names)}
A = np.zeros((len(node_names), len(node_names)), dtype=float)
x0 = np.zeros(len(node_names), dtype=float)
for name, attrs in graph["nodes"].items():
    i = index[name]
    A[i, i] = -float(attrs["decay"])
    x0[i] = float(attrs["init"])
for edge in graph["edges"]:
    A[index[edge["target"]], index[edge["source"]]] += float(edge["rate"])
expected = expm(A * 50.0).dot(x0)
expected_by_node = {name: float(expected[index[name]]) for name in node_names}

csv_path = "/home/user/training_data.csv"
assert os.path.isfile(csv_path), f"Output file {csv_path} is missing after execution"
with open(csv_path, newline="") as f:
    rows = list(csv.reader(f))
assert rows, "training_data.csv is empty"
assert rows[0] == ["network_id", "node_id", "concentration"], "Incorrect CSV header"
data = rows[1:]
assert all(len(row) == 3 for row in data), "Every CSV row must have exactly three columns"
assert data == sorted(data, key=lambda row: (row[0], row[1])), "CSV rows are not sorted"

expected_keys = {
    ("net1", "G1"), ("net1", "G2"),
    ("net2", "A"), ("net2", "B"),
} | {(network_id, name) for name in node_names}
actual_keys = {(row[0], row[1]) for row in data}
assert len(data) == len(expected_keys), "CSV has missing, duplicate, or unexpected rows"
assert actual_keys == expected_keys, "CSV does not contain exactly all network nodes"

challenge_rows = {row[1]: row[2] for row in data if row[0] == network_id}
assert set(challenge_rows) == set(node_names), "Random verification network was not fully simulated"
for name, exact in expected_by_node.items():
    text = challenge_rows[name]
    assert re.fullmatch(r"-?\d+\.\d{4}", text), f"{name} is not formatted to exactly four decimal places"
    actual = float(text)
    tolerance = max(0.03, abs(exact) * 0.002)
    assert math.isfinite(actual) and abs(actual - exact) <= tolerance, \
        f"Incorrect final concentration for {network_id}/{name}: expected {exact}, got {actual}"
PY
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
