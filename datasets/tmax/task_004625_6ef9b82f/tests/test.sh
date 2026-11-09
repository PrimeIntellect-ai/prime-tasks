#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def compute_expected_values():
    # 1. Compute L
    fasta_path = "/home/user/kinetics/sequence.fasta"
    assert os.path.exists(fasta_path), f"Input file missing: {fasta_path}"

    L = 0
    with open(fasta_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith(">"):
                continue
            L += len(line.replace(" ", ""))

    # 2. Compute S using Kahan summation
    sim_data_path = "/home/user/kinetics/sim_data.txt"
    assert os.path.exists(sim_data_path), f"Input file missing: {sim_data_path}"

    S = 0.0
    c = 0.0
    with open(sim_data_path, 'r') as f:
        for line in f:
            val = float(line.strip())
            y = val - c
            t = S + y
            c = (t - S) - y
            S = t

    # 3. Compute Newton-Raphson steps and root
    x = 1.0
    diffs = []
    while True:
        f_val = x**3 + L * x - S
        df_val = 3 * x**2 + L
        x_new = x - f_val / df_val
        diff = abs(x_new - x)
        diffs.append(diff)
        x = x_new
        if diff < 1e-7:
            break

    return L, S, x, diffs

@pytest.fixture(scope="module")
def expected_data():
    L, S, root, diffs = compute_expected_values()
    return {
        "L": L,
        "S": S,
        "root": root,
        "diffs": diffs
    }

def test_solution_json(expected_data):
    json_path = "/home/user/kinetics/solution.json"
    assert os.path.exists(json_path), f"Output file missing: {json_path}"

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    assert "L" in data, "Key 'L' missing in solution.json"
    assert "kahan_sum" in data, "Key 'kahan_sum' missing in solution.json"
    assert "root" in data, "Key 'root' missing in solution.json"

    assert data["L"] == expected_data["L"], f"Expected L={expected_data['L']}, got {data['L']}"

    expected_S_rounded = round(expected_data["S"], 4)
    assert math.isclose(data["kahan_sum"], expected_S_rounded, rel_tol=1e-5), \
        f"Expected kahan_sum={expected_S_rounded}, got {data['kahan_sum']}"

    expected_root_rounded = round(expected_data["root"], 6)
    assert math.isclose(data["root"], expected_root_rounded, rel_tol=1e-5), \
        f"Expected root={expected_root_rounded}, got {data['root']}"

def test_convergence_txt(expected_data):
    conv_path = "/home/user/kinetics/convergence.txt"
    assert os.path.exists(conv_path), f"Output file missing: {conv_path}"

    with open(conv_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_diffs = expected_data["diffs"]

    assert len(lines) == len(expected_diffs), \
        f"Expected {len(expected_diffs)} convergence steps, got {len(lines)}"

    for i, (actual_str, expected_val) in enumerate(zip(lines, expected_diffs)):
        try:
            actual_val = float(actual_str)
        except ValueError:
            pytest.fail(f"Non-numeric value in convergence.txt at line {i+1}: {actual_str}")

        assert math.isclose(actual_val, expected_val, rel_tol=1e-5, abs_tol=1e-9), \
            f"Convergence step {i+1} mismatch: expected {expected_val}, got {actual_val}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
