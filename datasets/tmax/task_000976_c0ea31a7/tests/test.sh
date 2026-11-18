#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math
import glob
import random
import secrets
import subprocess

NAMES = ["exp_alpha", "exp_beta", "exp_gamma"]
EXPERIMENT_DIR = "/home/user/experiments"
TRACKER_PATH = "/home/user/tracker.json"


def get_matrix_from_csv(filepath):
    matrix = []
    with open(filepath, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            row = [float(x) for x in line.strip().split(',')]
            matrix.append(row)
    return matrix


def compute_covariance(matrix):
    n = len(matrix)
    m = len(matrix[0])
    means = [sum(matrix[i][j] for i in range(n)) / n for j in range(m)]

    cov = [[0.0 for _ in range(m)] for _ in range(m)]
    for j in range(m):
        for k in range(m):
            s = sum((matrix[i][j] - means[j]) * (matrix[i][k] - means[k]) for i in range(n))
            cov[j][k] = s / (n - 1)
    return cov


def compute_determinant_3x3(mat):
    a, b, c = mat[0]
    d, e, f = mat[1]
    g, h, i = mat[2]
    return a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g)


def expected_results_from_csvs():
    expected_results = {}
    for name in NAMES:
        matrix = get_matrix_from_csv(f"{EXPERIMENT_DIR}/{name}.csv")
        cov = compute_covariance(matrix)
        for i in range(3):
            cov[i][i] += 0.1
        expected_results[name] = round(compute_determinant_3x3(cov), 4)
    return expected_results


def tracker_matches_expected():
    if not os.path.isfile(TRACKER_PATH):
        return False
    try:
        with open(TRACKER_PATH, 'r') as f:
            tracker = json.load(f)
    except (OSError, json.JSONDecodeError):
        return False

    expected = expected_results_from_csvs()
    best = min(NAMES, key=lambda k: expected[k])
    for name in NAMES:
        if name not in tracker or not isinstance(tracker[name], (int, float)):
            return False
        if not math.isclose(tracker[name], expected[name], abs_tol=0.0002):
            return False
    return tracker.get("best") == best


def run_binary(binary):
    if os.path.exists(TRACKER_PATH):
        os.remove(TRACKER_PATH)
    try:
        result = subprocess.run(
            [binary], cwd="/home/user", stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True, timeout=10
        )
    except (OSError, subprocess.TimeoutExpired):
        return False
    return result.returncode == 0 and tracker_matches_expected()


def test_compiled_cpp_generates_tracker_on_fresh_inputs():
    cpp_files = glob.glob("/home/user/*.cpp")
    assert cpp_files, "No C++ (.cpp) file found in /home/user/"

    original_csvs = {
        name: open(f"{EXPERIMENT_DIR}/{name}.csv", "rb").read()
        for name in NAMES
    }

    rng = random.Random(secrets.randbits(64))
    scales = {"exp_alpha": 0.45, "exp_beta": 1.05, "exp_gamma": 1.75}
    chosen_binary = None
    diagnostics = []

    try:
        for name in NAMES:
            scale = scales[name]
            with open(f"{EXPERIMENT_DIR}/{name}.csv", "w") as f:
                for _ in range(10):
                    x = rng.gauss(0.0, scale)
                    y = 0.25 * x + rng.gauss(0.0, scale * 0.8)
                    z = -0.15 * x + 0.2 * y + rng.gauss(0.0, scale * 1.1)
                    f.write(f"{x:.9f},{y:.9f},{z:.9f}\n")

        for index, source in enumerate(cpp_files):
            binary = f"/tmp/submission_{index}"
            try:
                compiled = subprocess.run(
                    ["g++", "-std=c++17", "-O2", source, "-o", binary],
                    stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                    text=True, timeout=30
                )
            except (OSError, subprocess.TimeoutExpired) as exc:
                diagnostics.append(f"{source}: compilation failed: {exc}")
                continue
            if compiled.returncode != 0:
                diagnostics.append(f"{source}: compilation failed: {compiled.stderr[-1000:]}")
                continue
            if run_binary(binary):
                chosen_binary = binary
                break
            diagnostics.append(f"{source}: compiled program did not generate correct tracker.json")
    finally:
        for name, contents in original_csvs.items():
            with open(f"{EXPERIMENT_DIR}/{name}.csv", "wb") as f:
                f.write(contents)

    assert chosen_binary is not None, "No submitted C++ program passed execution checks. " + " | ".join(diagnostics)
    assert run_binary(chosen_binary), "The compiled C++ program failed to generate tracker.json for the original CSV files."


def test_cpp_file_exists():
    cpp_files = glob.glob("/home/user/*.cpp")
    assert len(cpp_files) > 0, "No C++ (.cpp) file found in /home/user/"


def test_tracker_json_exists():
    assert os.path.isfile("/home/user/tracker.json"), "/home/user/tracker.json does not exist."


def test_tracker_json_contents():
    tracker_path = "/home/user/tracker.json"
    with open(tracker_path, 'r') as f:
        try:
            tracker = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/tracker.json is not valid JSON."

    expected_results = {}
    for name in ["exp_alpha", "exp_beta", "exp_gamma"]:
        csv_path = f"/home/user/experiments/{name}.csv"
        matrix = get_matrix_from_csv(csv_path)
        cov = compute_covariance(matrix)
        # Regularize
        for i in range(3):
            cov[i][i] += 0.1

        det = compute_determinant_3x3(cov)
        expected_results[name] = round(det, 4)

    best_exp = min(["exp_alpha", "exp_beta", "exp_gamma"], key=lambda k: expected_results[k])

    for name in ["exp_alpha", "exp_beta", "exp_gamma"]:
        assert name in tracker, f"Missing key '{name}' in tracker.json"
        assert isinstance(tracker[name], (int, float)), f"Value for '{name}' must be a number."
        assert math.isclose(tracker[name], expected_results[name], abs_tol=0.0002), \
            f"Value for '{name}' is {tracker[name]}, expected {expected_results[name]} (±0.0001)."

    assert "best" in tracker, "Missing key 'best' in tracker.json"
    assert tracker["best"] == best_exp, f"Expected 'best' to be '{best_exp}', got '{tracker['best']}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
