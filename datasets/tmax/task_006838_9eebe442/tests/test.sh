#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import subprocess

SOURCE = "/home/user/predictor.cpp"
BINARY = "/tmp/predictor_verifier"
HYPER = "/home/user/hyperparameters.csv"
RESULTS = "/home/user/results.csv"
PREDICTIONS = "/home/user/predictions.txt"

ORIGINAL_HYPER = """exp_id,param_a,param_b,param_c
1,10,20,30
2,12,20,30
3,10,25,30
4,15,20,30
5,10,20,35
6,11,21,31
7,20,30,40
8,10,20,29
"""

ORIGINAL_RESULTS = """exp_id,accuracy
1,80.0
2,82.0
3,85.0
4,78.0
5,NaN
6,81.0
7,NaN
8,79.0
"""

ALTERNATE_HYPER = """exp_id,param_a,param_b,param_c
108,10,0,0
103,0,2,0
101,0,0,0
109,3,3,3
106,1,1,0
104,5,0,0
107,1,0,0
102,2,0,0
105,0,0,5
"""

ALTERNATE_RESULTS = """exp_id,accuracy
105,50.0
999,99.0
102,20.0
107,NaN
101,10.0
104,40.0
108,NaN
106,25.0
103,30.0
"""


def derive_expected(hyper_text, results_text):
    hyper = {}
    for line in hyper_text.strip().splitlines()[1:]:
        fields = line.split(',')
        exp_id = int(fields[0])
        hyper[exp_id] = tuple(float(x) for x in fields[1:4])

    results = {}
    for line in results_text.strip().splitlines()[1:]:
        exp_id_text, accuracy_text = line.split(',')
        results[int(exp_id_text)] = accuracy_text

    labeled = []
    unlabeled = []
    for exp_id in sorted(set(hyper) & set(results)):
        if results[exp_id] == "NaN":
            unlabeled.append((exp_id, hyper[exp_id]))
        else:
            labeled.append((exp_id, hyper[exp_id], float(results[exp_id])))

    def distance_sq(a, b):
        return sum((x - y) ** 2 for x, y in zip(a, b))

    best_k = None
    best_mse = math.inf
    for k in (1, 2, 3):
        squared_errors = []
        for held_id, held_features, held_accuracy in labeled:
            neighbors = [
                (distance_sq(held_features, features), exp_id, accuracy)
                for exp_id, features, accuracy in labeled
                if exp_id != held_id
            ]
            neighbors.sort(key=lambda item: (item[0], item[1]))
            prediction = sum(item[2] for item in neighbors[:k]) / k
            squared_errors.append((prediction - held_accuracy) ** 2)
        mse = sum(squared_errors) / len(squared_errors)
        if mse < best_mse:
            best_mse = mse
            best_k = k

    lines = [f"Best K: {best_k}"]
    for exp_id, features in sorted(unlabeled):
        neighbors = [
            (distance_sq(features, train_features), train_id, accuracy)
            for train_id, train_features, accuracy in labeled
        ]
        neighbors.sort(key=lambda item: (item[0], item[1]))
        prediction = sum(item[2] for item in neighbors[:best_k]) / best_k
        lines.append(f"{exp_id},{prediction:.2f}")
    return lines


def run_case(hyper_text, results_text):
    with open(HYPER, "w") as f:
        f.write(hyper_text)
    with open(RESULTS, "w") as f:
        f.write(results_text)

    if os.path.exists(PREDICTIONS):
        os.remove(PREDICTIONS)

    completed = subprocess.run(
        [BINARY], cwd="/home/user", capture_output=True, text=True, timeout=10
    )
    assert completed.returncode == 0, (
        f"predictor exited with code {completed.returncode}\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(PREDICTIONS), (
        f"Predictions file missing: {PREDICTIONS}. Did the C++ program run and generate it?"
    )
    with open(PREDICTIONS, "r") as f:
        return [line.strip() for line in f if line.strip()]


def test_predictor_compiles_runs_and_is_correct():
    assert os.path.isfile(SOURCE), f"C++ source file missing: {SOURCE}"

    compilation = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", BINARY],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compilation.returncode == 0, (
        f"predictor.cpp failed to compile\nstdout:\n{compilation.stdout}\n"
        f"stderr:\n{compilation.stderr}"
    )

    try:
        original_lines = run_case(ORIGINAL_HYPER, ORIGINAL_RESULTS)
        assert len(original_lines) == 3, (
            f"Expected exactly 3 non-empty lines in predictions.txt, found {len(original_lines)}"
        )
        assert original_lines[0] == "Best K: 1", original_lines
        assert original_lines[1] == "5,81.00", original_lines
        assert original_lines[2] == "7,85.00", original_lines
        assert original_lines == derive_expected(ORIGINAL_HYPER, ORIGINAL_RESULTS)

        alternate_lines = run_case(ALTERNATE_HYPER, ALTERNATE_RESULTS)
        assert alternate_lines == derive_expected(ALTERNATE_HYPER, ALTERNATE_RESULTS), (
            f"Incorrect output for alternate joined input: {alternate_lines}"
        )
    finally:
        with open(HYPER, "w") as f:
            f.write(ORIGINAL_HYPER)
        with open(RESULTS, "w") as f:
            f.write(ORIGINAL_RESULTS)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
