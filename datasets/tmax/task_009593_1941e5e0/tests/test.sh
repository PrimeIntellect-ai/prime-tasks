#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import math
import random
import subprocess
import pytest

SENSORS_PATH = '/home/user/sensors.csv'
LABELS_PATH = '/home/user/labels.csv'
JSON_PATH = '/home/user/etl_results.json'
EXECUTABLE = '/tmp/agent_etl'


def get_valid_data():
    assert os.path.exists(SENSORS_PATH), f"Missing {SENSORS_PATH}"
    assert os.path.exists(LABELS_PATH), f"Missing {LABELS_PATH}"

    sensors = {}
    with open(SENSORS_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                s1 = float(row['sensor1'])
                s2 = float(row['sensor2'])
                s3 = float(row['sensor3'])
                sensors[row['id']] = (s1, s2, s3)
            except ValueError:
                continue

    labels = {}
    with open(LABELS_PATH, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            lbl = row['label']
            if lbl in ('0', '1'):
                labels[row['id']] = int(lbl)

    joined_data = []
    for uid in sensors:
        if uid in labels:
            joined_data.append({
                'id': uid,
                's1': sensors[uid][0],
                's2': sensors[uid][1],
                's3': sensors[uid][2],
                'label': labels[uid]
            })

    return joined_data


def compute_expected_metrics(data):
    n = len(data)
    assert n > 1, "Not enough valid rows to compute covariance (N > 1 required)."

    label_1_count = sum(1 for d in data if d['label'] == 1)
    p_label_1 = label_1_count / n

    s1_gt_half_given_1 = sum(1 for d in data if d['label'] == 1 and d['s1'] > 0.5)
    p_s1_gt_half_given_label_1 = s1_gt_half_given_1 / label_1_count if label_1_count > 0 else 0.0

    label_0_count = sum(1 for d in data if d['label'] == 0)
    s1_gt_half_given_0 = sum(1 for d in data if d['label'] == 0 and d['s1'] > 0.5)
    p_s1_gt_half_given_label_0 = s1_gt_half_given_0 / label_0_count if label_0_count > 0 else 0.0

    means = [
        sum(d['s1'] for d in data) / n,
        sum(d['s2'] for d in data) / n,
        sum(d['s3'] for d in data) / n
    ]

    cov = [[0.0] * 3 for _ in range(3)]
    for i in range(3):
        for j in range(3):
            s_i = [d[f's{i+1}'] for d in data]
            s_j = [d[f's{j+1}'] for d in data]
            covar = sum((x - means[i]) * (y - means[j]) for x, y in zip(s_i, s_j)) / (n - 1)
            cov[i][j] = covar

    return {
        "valid_rows": n,
        "p_label_1": p_label_1,
        "p_s1_gt_half_given_label_1": p_s1_gt_half_given_label_1,
        "p_s1_gt_half_given_label_0": p_s1_gt_half_given_label_0,
        "covariance_matrix": cov
    }


@pytest.fixture(scope='session', autouse=True)
def compile_c_program():
    sources = []
    for root, dirs, files in os.walk('/home/user'):
        for name in files:
            path = os.path.join(root, name)
            if name.endswith('.c') and os.path.isfile(path):
                sources.append(path)

    assert sources, "No C source file was found under /home/user."
    command = ['/usr/bin/gcc', '-std=c11', '-O2', '-o', EXECUTABLE] + sorted(sources) + ['-lm']
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=30)
    assert result.returncode == 0, f"C source failed to compile:\n{result.stdout}"
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK), \
        "Compilation did not produce an executable C program."


def run_program():
    if os.path.lexists(JSON_PATH):
        os.unlink(JSON_PATH)
    result = subprocess.run([EXECUTABLE], cwd='/home/user', text=True,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            timeout=30)
    assert result.returncode == 0, f"Compiled C program failed:\n{result.stdout}"
    assert os.path.isfile(JSON_PATH), \
        f"Output file {JSON_PATH} does not exist after running the compiled C program."


def assert_etl_results(expected):
    assert os.path.exists(JSON_PATH), f"Output file {JSON_PATH} does not exist. C program may not have run or failed."

    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert "valid_rows" in results, "Missing 'valid_rows' in JSON output."
    assert results["valid_rows"] == expected["valid_rows"], \
        f"Expected {expected['valid_rows']} valid rows, got {results['valid_rows']}."

    keys_to_check = [
        "p_label_1",
        "p_s1_gt_half_given_label_1",
        "p_s1_gt_half_given_label_0"
    ]

    for key in keys_to_check:
        assert key in results, f"Missing '{key}' in JSON output."
        assert isinstance(results[key], (int, float)), f"'{key}' must be a float."
        assert math.isclose(results[key], expected[key], abs_tol=1e-3), \
            f"Expected {key} to be ~{expected[key]:.4f}, got {results[key]}."

    assert "covariance_matrix" in results, "Missing 'covariance_matrix' in JSON output."
    cov_matrix = results["covariance_matrix"]
    assert len(cov_matrix) == 3 and all(len(row) == 3 for row in cov_matrix), \
        "Covariance matrix must be 3x3."

    for i in range(3):
        for j in range(3):
            val = cov_matrix[i][j]
            exp_val = expected["covariance_matrix"][i][j]
            assert isinstance(val, (int, float)), \
                f"Covariance matrix at [{i}][{j}] must be a float."
            assert math.isclose(val, exp_val, abs_tol=1e-3), \
                f"Covariance matrix at [{i}][{j}] expected ~{exp_val:.4f}, got {val}."


def test_generated_fixture():
    with open(SENSORS_PATH, 'rb') as f:
        original_sensors = f.read()
    with open(LABELS_PATH, 'rb') as f:
        original_labels = f.read()

    rng = random.SystemRandom()
    base = rng.randrange(10000, 90000)

    def low():
        return rng.randrange(100, 451) / 1000.0

    def high():
        return rng.randrange(551, 951) / 1000.0

    def other():
        return rng.randrange(-1500, 3501) / 1000.0

    valid = [
        (base + 1, low(), other(), other(), 0),
        (base + 2, high(), other(), other(), 0),
        (base + 3, low(), other(), other(), 1),
        (base + 4, high(), other(), other(), 1),
        (base + 5, high(), other(), other(), 1),
    ]

    sensor_lines = ['id,sensor1,sensor2,sensor3']
    label_lines = ['id,label']
    for uid, s1, s2, s3, label in valid:
        sensor_lines.append(f'{uid},{s1:.3f},{s2:.3f},{s3:.3f}')
        label_lines.append(f'{uid},{label}')

    sensor_lines.extend([
        f'{base + 6},invalid,0.250,1.250',
        f'{base + 7},0.750,0.350,1.750',
        f'{base + 8},0.650,0.450,1.450',
    ])
    label_lines.extend([
        f'{base + 6},1',
        f'{base + 7},2',
        f'{base + 9},1',
    ])

    try:
        with open(SENSORS_PATH, 'w', encoding='utf-8', newline='') as f:
            f.write('\n'.join(sensor_lines) + '\n')
        with open(LABELS_PATH, 'w', encoding='utf-8', newline='') as f:
            f.write('\n'.join(label_lines) + '\n')

        expected = compute_expected_metrics(get_valid_data())
        run_program()
        assert_etl_results(expected)
    finally:
        with open(SENSORS_PATH, 'wb') as f:
            f.write(original_sensors)
        with open(LABELS_PATH, 'wb') as f:
            f.write(original_labels)
        if os.path.lexists(JSON_PATH):
            os.unlink(JSON_PATH)


def test_etl_results():
    expected = compute_expected_metrics(get_valid_data())
    run_program()
    assert_etl_results(expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
