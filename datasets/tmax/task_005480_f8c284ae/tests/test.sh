#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import re
import stat
import subprocess
import time


def test_cleaned_dataset():
    path = '/home/user/cleaned_dataset.csv'
    assert os.path.isfile(path), f"File missing: {path}"

    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "id,value1,value2,value3",
        "1,0.5,2.0,1.0",
        "-1,1.0,1.0,1.0",
        "3,0.0,3.0,0.0",
        "4,2.0,-1.0,-2.0"
    ]

    assert lines == expected_lines, f"Content of {path} does not match expected."


def test_inference_script_exists():
    path = '/home/user/inference.py'
    assert os.path.isfile(path), f"File missing: {path}"
    assert stat.S_ISREG(os.stat(path).st_mode), f"Not a regular file: {path}"


def test_predictions():
    path = '/home/user/predictions.csv'
    assert os.path.isfile(path), f"File missing: {path}"

    with open(path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "id,prediction",
        "1,0",
        "-1,1",
        "3,0",
        "4,1"
    ]

    assert lines == expected_lines, f"Content of {path} does not match expected."


def test_accuracy_txt():
    path = '/home/user/accuracy.txt'
    assert os.path.isfile(path), f"File missing: {path}"

    with open(path, 'r') as f:
        content = f.read().strip()

    assert content == "2.0798", f"Content of {path} is '{content}', expected '2.0798'."


def test_benchmark_txt():
    path = '/home/user/benchmark.txt'
    assert os.path.isfile(path), f"File missing: {path}"

    with open(path, 'r') as f:
        content = f.read().strip()

    lines = content.split('\n')
    found = False
    for line in lines:
        if re.search(r'Average:\s+\d+\.\d+\s+seconds', line):
            found = True
            break

    assert found, f"Could not find required format 'Average: X.XXXX seconds' in {path}."


def _save(paths):
    saved = {}
    for path in paths:
        saved[path] = open(path, 'rb').read() if os.path.exists(path) else None
    return saved


def _restore(saved):
    for path, data in saved.items():
        if data is None:
            if os.path.exists(path):
                os.remove(path)
        else:
            with open(path, 'wb') as f:
                f.write(data)


def test_inference_executes_on_runtime_generated_inputs():
    script = '/home/user/inference.py'
    cleaned = '/home/user/cleaned_dataset.csv'
    weights_path = '/home/user/model_weights.json'
    predictions = '/home/user/predictions.csv'
    accuracy = '/home/user/accuracy.txt'
    saved = _save([cleaned, weights_path, predictions, accuracy])

    rng = random.SystemRandom()
    weights = {
        'w1': rng.uniform(-1.7, 1.7),
        'w2': rng.uniform(-1.7, 1.7),
        'w3': rng.uniform(-0.8, 0.8),
        'b': rng.uniform(-0.9, 0.9),
    }
    ids = rng.sample(range(-50000, 50000), 7)
    rows = []
    for row_id in ids:
        value1 = rng.uniform(-5.0, 5.0)
        value2 = rng.uniform(-5.0, 5.0)
        value3 = value1 * value2
        rows.append((row_id, value1, value2, value3))

    expected_predictions = []
    probability_sum = 0.0
    for row_id, value1, value2, value3 in rows:
        z = (weights['w1'] * value1 + weights['w2'] * value2 +
             weights['w3'] * value3 + weights['b'])
        p = 1.0 / (1.0 + math.exp(-z))
        probability_sum += p
        expected_predictions.append([str(row_id), str(1 if p >= 0.5 else 0)])

    try:
        with open(cleaned, 'w', newline='') as f:
            writer = csv.writer(f)
            writer.writerow(['id', 'value1', 'value2', 'value3'])
            for row in rows:
                writer.writerow([str(row[0]), repr(row[1]), repr(row[2]), repr(row[3])])
        with open(weights_path, 'w') as f:
            json.dump(weights, f)

        result = subprocess.run(
            ['python3', script], cwd='/home/user', text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
        )
        assert result.returncode == 0, (
            f"inference.py failed with exit code {result.returncode}: {result.stderr}"
        )
        assert os.path.isfile(predictions), "inference.py did not create predictions.csv"
        assert os.path.isfile(accuracy), "inference.py did not create accuracy.txt"

        with open(predictions, newline='') as f:
            actual_predictions = list(csv.reader(f))
        assert actual_predictions == [['id', 'prediction']] + expected_predictions, (
            "inference.py produced incorrect predictions for runtime-generated inputs"
        )

        with open(accuracy) as f:
            actual_accuracy = f.read().strip()
        expected_accuracy = f"{probability_sum:.4f}"
        assert actual_accuracy == expected_accuracy, (
            f"accuracy.txt is '{actual_accuracy}', expected '{expected_accuracy}' "
            "for runtime-generated inputs"
        )
    finally:
        _restore(saved)


def test_reported_benchmark_is_plausible_for_100_real_invocations():
    script = '/home/user/inference.py'
    start = time.perf_counter()
    for i in range(100):
        result = subprocess.run(
            ['python3', script], cwd='/home/user',
            stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
            text=True, timeout=20
        )
        assert result.returncode == 0, (
            f"inference.py failed during benchmark invocation {i + 1}: {result.stderr}"
        )
    measured_average = (time.perf_counter() - start) / 100.0

    path = '/home/user/benchmark.txt'
    assert os.path.isfile(path), f"File missing: {path}"
    with open(path) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines, f"No benchmark result in {path}"
    match = re.fullmatch(r'Average:\s+(\d+\.\d{4})\s+seconds', lines[-1])
    assert match, "The final benchmark line must have format 'Average: X.XXXX seconds'"
    reported_average = float(match.group(1))
    assert reported_average > 0.0, "The benchmark average must be a positive measurement"
    ratio = reported_average / measured_average
    assert 0.2 <= ratio <= 5.0, (
        f"Reported average {reported_average:.4f}s is not plausible compared with "
        f"100 measured command-line runs averaging {measured_average:.4f}s"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
