#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
import subprocess

import numpy as np
import pytest
from scipy.optimize import curve_fit

SCRIPT_PATH = "/home/user/pcr_model.py"
SOLUTION_PATH = "/home/user/solution.json"


def logistic(t, r, K):
    y0 = 2.0
    return (K * y0 * np.exp(r * t)) / (K + y0 * (np.exp(r * t) - 1.0))


def load_solution(path=SOLUTION_PATH):
    assert os.path.isfile(path), f"Solution file not found at {path}"
    with open(path, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} is not a valid JSON file.")


def parse_fasta(path):
    records = []
    name = None
    chunks = []
    with open(path) as f:
        for raw_line in f:
            line = raw_line.strip()
            if not line:
                continue
            if line.startswith(">"):
                if name is not None:
                    records.append((name, "".join(chunks)))
                name = line[1:].split()[0]
                chunks = []
            else:
                assert name is not None, "FASTA sequence appeared before a header"
                chunks.append(line)
    if name is not None:
        records.append((name, "".join(chunks)))
    return records


def test_pcr_model_regression_test_passes():
    """Retain the script's own regression check."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    result = subprocess.run(
        ["python3", SCRIPT_PATH, "--test"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )

    assert result.returncode == 0, (
        f"pcr_model.py --test failed with exit code {result.returncode}.\n"
        f"Stdout: {result.stdout}\nStderr: {result.stderr}"
    )
    assert "Test passed!" in result.stdout, "Expected 'Test passed!' in stdout."


def test_simulator_independently_against_analytic_solution():
    """Import and exercise the actual numerical integration on unseen cases."""
    spec = importlib.util.spec_from_file_location("submitted_pcr_model", SCRIPT_PATH)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "simulate_pcr", None)), "simulate_pcr is missing or not callable"

    cases = [
        (0.37, 73.0, np.array([0.0, 0.17, 0.9, 2.35, 5.1, 9.7, 14.2])),
        (0.91, 146.0, np.array([0.0, 0.08, 0.63, 1.8, 3.4, 6.25, 10.0])),
    ]
    for r, K, times in cases:
        actual = np.asarray(module.simulate_pcr(r, K, times), dtype=float)
        expected = logistic(times, r, K)
        assert actual.shape == expected.shape
        assert np.all(np.isfinite(actual)), "Simulation returned non-finite values"
        mse = float(np.mean((actual - expected) ** 2))
        assert mse < 1.0, f"Independent regression failed for r={r}, K={K}: MSE={mse}"


def test_solution_json_exists_and_correct():
    """Retain the checks for the supplied dataset's required result."""
    data = load_solution()

    assert "fitted_r" in data, "Missing 'fitted_r' in solution.json"
    assert "fitted_K" in data, "Missing 'fitted_K' in solution.json"
    assert "primer_id" in data, "Missing 'primer_id' in solution.json"

    fitted_r = float(data["fitted_r"])
    fitted_K = float(data["fitted_K"])
    primer_id = str(data["primer_id"])

    assert abs(fitted_r - 0.85) <= 0.02, f"fitted_r {fitted_r} is not within tolerance of 0.85"
    assert abs(fitted_K - 120.0) <= 0.02, f"fitted_K {fitted_K} is not within tolerance of 120.0"
    assert primer_id == "primer2", f"Expected primer_id 'primer2', but got '{primer_id}'"


def test_fitting_and_primer_selection_are_computed_end_to_end():
    """Run the submitted program on an unseen logistic dataset and primer set."""
    paths = [
        "/home/user/reference_yield.csv",
        "/home/user/candidates.fasta",
        "/home/user/gene_sequence.txt",
        SOLUTION_PATH,
    ]
    backups = {}
    for path in paths:
        if os.path.exists(path):
            with open(path, "rb") as f:
                backups[path] = f.read()
        else:
            backups[path] = None

    times = np.arange(0.0, 19.0, 1.0)
    hidden_yields = logistic(times, 0.67, 87.0)
    target = "TTGACGTGCAATGCCAGGCTTACCGGATC"
    fasta = (
        ">decoy_same_length\nTTTTTTTTTTTTT\n"
        ">hidden_match\nACGTGCAATGCCA\n"
        ">matching_wrong_length\nGACGTGCAAT\n"
        ">another_decoy\nAACCGGTTAACCG\n"
    )

    try:
        with open("/home/user/reference_yield.csv", "w") as f:
            f.write("time,yield\n")
            for t, y in zip(times, hidden_yields):
                f.write(f"{t:.8f},{y:.10f}\n")
        with open("/home/user/gene_sequence.txt", "w") as f:
            f.write(target + "\n")
        with open("/home/user/candidates.fasta", "w") as f:
            f.write(fasta)
        if os.path.exists(SOLUTION_PATH):
            os.remove(SOLUTION_PATH)

        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60,
        )
        assert result.returncode == 0, (
            f"pcr_model.py failed on the independent dataset.\n"
            f"Stdout: {result.stdout}\nStderr: {result.stderr}"
        )
        data = load_solution()
        assert "fitted_r" in data and "fitted_K" in data and "primer_id" in data

        fitted, _ = curve_fit(
            logistic,
            times,
            hidden_yields,
            p0=(0.5, float(np.max(hidden_yields))),
            bounds=([0.0, 2.01], [5.0, 10000.0]),
            maxfev=20000,
        )
        expected_r = round(float(fitted[0]), 2)
        expected_K = round(float(fitted[1]), 2)
        required_length = int(float(fitted[0]) * 20)
        matches = [
            primer_id
            for primer_id, sequence in parse_fasta("/home/user/candidates.fasta")
            if len(sequence) == required_length and sequence in target
        ]
        assert len(matches) == 1, "Verifier fixture must have exactly one valid primer"

        assert float(data["fitted_r"]) == expected_r, (
            f"Independent fitted_r should be {expected_r}, got {data['fitted_r']}"
        )
        assert float(data["fitted_K"]) == expected_K, (
            f"Independent fitted_K should be {expected_K}, got {data['fitted_K']}"
        )
        assert str(data["primer_id"]) == matches[0], (
            f"Independent primer should be {matches[0]}, got {data['primer_id']}"
        )
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
