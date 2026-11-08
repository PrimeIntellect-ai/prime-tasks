#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
from scipy.fft import fft


def test_executable_compiled():
    exe_path = "/home/user/filter_seqs"
    assert os.path.isfile(exe_path), f"Executable {exe_path} was not found. Did you compile the C program?"
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."


def test_filtered_output():
    out_path = "/home/user/filtered.txt"
    assert os.path.isfile(out_path), f"Filtered output file {out_path} was not found."

    with open(out_path, "r") as f:
        content = f.read().strip().split('\n')

    # Check that TARGET_SEQ is in the output and properly formatted
    target_found = False
    for line in content:
        if line.startswith("TARGET_SEQ,"):
            target_found = True
            seq = line.split(",")[1]
            assert len(seq) >= 30, "TARGET_SEQ length in filtered.txt is incorrect."
            break

    assert target_found, "TARGET_SEQ was not found in the filtered output."


def test_analyze_script_exists():
    script_path = "/home/user/analyze.py"
    assert os.path.isfile(script_path), f"Python script {script_path} was not found."


def test_spectral_results_json():
    json_path = "/home/user/spectral_results.json"
    assert os.path.isfile(json_path), f"JSON results file {json_path} was not found."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} is not valid JSON."

    assert "TARGET_SEQ" in data, "Key 'TARGET_SEQ' is missing from the JSON output."

    weights = data["TARGET_SEQ"]
    expected_keys = {"w_A", "w_C", "w_G", "w_T"}
    assert set(weights.keys()) == expected_keys, f"JSON weights keys must be exactly {expected_keys}."

    # Check bounds and sum
    w_sum = sum(weights.values())
    assert abs(w_sum - 1.0) < 1e-3, f"Weights must sum to 1.0, but got {w_sum}."

    for k, v in weights.items():
        assert 0.0 <= v <= 1.0, f"Weight {k} is out of bounds [0, 1]: {v}"

    # Recompute the period-3 objective from the filtered TARGET_SEQ. The DFT
    # coefficient is linear in the weights, and the maximum magnitude over the
    # simplex is attained at a vertex, so all tied global optima are accepted.
    target_seq = None
    with open("/home/user/filtered.txt", "r") as f:
        for line in f:
            name, sep, seq = line.strip().partition(",")
            if name == "TARGET_SEQ" and sep:
                target_seq = seq
                break

    assert target_seq is not None, "TARGET_SEQ was not found in the filtered output."
    n = len(target_seq)
    assert n % 3 == 0, "TARGET_SEQ length must be a multiple of 3."

    bases = ("A", "C", "G", "T")
    coefficients = {}
    for base in bases:
        indicator = [1.0 if char == base else 0.0 for char in target_seq]
        coefficients[base] = fft(indicator)[n // 3]

    achieved = abs(sum(weights[f"w_{base}"] * coefficients[base] for base in bases))
    optimum = max(abs(coefficients[base]) for base in bases)

    # Preserve the original verifier's roughly two-percent objective tolerance
    # while accepting every weight vector that reaches an equivalent optimum.
    tolerance = max(1e-6, 0.020001 * optimum)
    assert achieved >= optimum - tolerance, (
        f"Weights are not optimal for TARGET_SEQ: achieved magnitude {achieved}, "
        f"but the optimum is {optimum}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
