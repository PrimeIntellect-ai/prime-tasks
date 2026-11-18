#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import subprocess

SOURCE = "/home/user/knn_cv.c"
DATA = "/home/user/data.csv"
OUTPUT = "/home/user/best_model.json"
BINARY = "/tmp/knn_cv_verified"


def reference_result(path):
    rows = []
    with open(path, "r") as f:
        for line in f:
            if line.strip():
                values = [float(v) for v in line.strip().split(",")]
                assert len(values) == 4, "Each data row must contain four columns."
                rows.append(values)
    assert len(rows) == 100, "The test dataset must contain 100 rows."

    means = [sum(row[j] for row in rows) / 100.0 for j in range(3)]
    stds = []
    for j in range(3):
        variance = sum((row[j] - means[j]) ** 2 for row in rows) / 100.0
        stds.append(math.sqrt(variance))
    assert all(s > 0.0 for s in stds), "Test features must have nonzero variance."

    x = [[(row[j] - means[j]) / stds[j] for j in range(3)] for row in rows]
    y = [row[3] for row in rows]
    maes = {}
    for k in range(1, 6):
        absolute_error = 0.0
        for test_index in range(100):
            fold = test_index // 20
            distances = []
            for train_index in range(100):
                if train_index // 20 == fold:
                    continue
                distance_squared = sum(
                    (x[test_index][j] - x[train_index][j]) ** 2 for j in range(3)
                )
                distances.append((distance_squared, train_index))
            distances.sort()
            prediction = sum(y[index] for _, index in distances[:k]) / k
            absolute_error += abs(prediction - y[test_index])
        maes[k] = absolute_error / 100.0

    best_k = min(range(1, 6), key=lambda k: (maes[k], k))
    return best_k, float(f"{maes[best_k]:.2f}")


def read_output():
    assert os.path.isfile(OUTPUT), f"Output JSON file {OUTPUT} is missing."
    try:
        with open(OUTPUT, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"File {OUTPUT} does not contain valid JSON.") from exc
    assert "best_k" in data, "JSON output is missing 'best_k' key."
    assert "best_mae" in data, "JSON output is missing 'best_mae' key."
    assert isinstance(data["best_mae"], (int, float)), \
        f"Expected best_mae to be a number, got {type(data['best_mae'])}."
    return data


def run_program():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [BINARY], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, \
        f"Compiled program exited with status {result.returncode}: {result.stderr}"
    return read_output()


def assert_matches_reference(data, expected_k, expected_mae):
    assert data["best_k"] == expected_k, \
        f"Expected best_k to be {expected_k}, got {data['best_k']}."
    assert abs(float(data["best_mae"]) - expected_mae) < 1e-9, \
        f"Expected rounded best_mae to be {expected_mae:.2f}, got {data['best_mae']}."


def write_random_dataset(rng, case):
    lines = []
    for i in range(100):
        z0 = rng.uniform(-1.0, 1.0)
        z1 = rng.uniform(-1.0, 1.0)
        z2 = rng.uniform(-1.0, 1.0)
        x0 = 500.0 + 75.0 * z0
        x1 = -3.0 + 0.08 * z1
        x2 = 20.0 + 9.0 * z2
        if case == 0:
            y = 9.0 * math.sin(3.2 * z0) + 4.0 * z1 - 6.0 * z2 * z2 + rng.gauss(0, 0.35)
        else:
            y = 14.0 * z0 * z1 + 7.0 * math.cos(4.0 * z2) + 2.0 * z0 + rng.gauss(0, 1.1)
        lines.append(f"{x0:.4f},{x1:.4f},{x2:.4f},{y:.4f}\n")
    with open(DATA, "w") as f:
        f.writelines(lines)


assert os.path.isfile(SOURCE), f"C source file {SOURCE} is missing."
assert os.path.isfile(DATA), f"Dataset {DATA} is missing."

compile_result = subprocess.run(
    ["gcc", "-std=c11", "-O2", SOURCE, "-lm", "-o", BINARY],
    stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
)
assert compile_result.returncode == 0, f"C source failed to compile: {compile_result.stderr}"

with open(DATA, "rb") as f:
    original_data = f.read()
original_output = None
if os.path.isfile(OUTPUT):
    with open(OUTPUT, "rb") as f:
        original_output = f.read()

try:
    expected_k, expected_mae = reference_result(DATA)
    original_result = run_program()

    # Preserve the original verifier's assertions for the supplied dataset.
    assert original_result["best_k"] == 4, \
        f"Expected best_k to be 4, got {original_result['best_k']}."
    assert abs(float(original_result["best_mae"]) - 1.42) <= 0.02, \
        f"Expected best_mae to be approx 1.42, got {original_result['best_mae']}."
    assert_matches_reference(original_result, expected_k, expected_mae)

    # Exercise the compiled implementation on unpredictable datasets with the
    # same dimensions and derive each answer independently.
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    for case in range(2):
        write_random_dataset(rng, case)
        expected_k, expected_mae = reference_result(DATA)
        result = run_program()
        assert_matches_reference(result, expected_k, expected_mae)
finally:
    with open(DATA, "wb") as f:
        f.write(original_data)
    if original_output is not None:
        with open(OUTPUT, "wb") as f:
            f.write(original_output)
    elif os.path.exists(OUTPUT):
        os.remove(OUTPUT)
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
