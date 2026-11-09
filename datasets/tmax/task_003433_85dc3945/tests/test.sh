#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'DATA_EOF' > /tmp/reference_sensor_data.csv
id,timestamp,sensor_value,is_anomaly
1,1000,45.5,0
2,1001,-5.0,0
3,1002,NA,1
4,1003,85.2,1
5,1004,12.0,0
6,1005,,1
7,1006,55.0,1
8,1007,22.1,0
9,1008,91.0,1
10,1009,10.0,0
11,1010,48.0,0
12,1011,75.0,1
13,1012,33.3,0
14,1013,62.5,1
15,1014,18.9,0
DATA_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import pytest


def compute_expected_best_model(data_path):
    if not os.path.exists(data_path):
        pytest.fail(f"Input data file {data_path} is missing.")

    cleaned_data = []
    with open(data_path, 'r') as f:
        reader = csv.reader(f)
        next(reader, None)
        for row in reader:
            if len(row) < 4:
                continue
            sensor_value_str = row[2].strip()
            if sensor_value_str == "" or sensor_value_str == "NA":
                continue
            try:
                sensor_value = float(sensor_value_str)
            except ValueError:
                continue
            if sensor_value < 0:
                continue

            is_anomaly = int(row[3].strip())
            cleaned_data.append((sensor_value, is_anomaly))

    folds = {0: [], 1: [], 2: []}
    for idx, row in enumerate(cleaned_data):
        folds[idx % 3].append(row)

    thresholds = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100]
    best_t = None
    best_acc = -1.0

    for t in thresholds:
        fold_accuracies = []
        for i in range(3):
            val_set = folds[i]
            if not val_set:
                continue
            correct = 0
            for val, true_label in val_set:
                pred = 1 if val >= t else 0
                if pred == true_label:
                    correct += 1
            fold_accuracies.append(correct / len(val_set))

        if len(fold_accuracies) == 3:
            avg_acc = sum(fold_accuracies) / 3.0
        else:
            avg_acc = 0.0

        if avg_acc > best_acc:
            best_acc = avg_acc
            best_t = t
        elif avg_acc == best_acc and (best_t is None or t < best_t):
            best_t = t

    return best_t, best_acc


def test_best_model_output():
    data_path = "/home/user/sensor_data.csv"
    trusted_data_path = "/tmp/reference_sensor_data.csv"
    output_path = "/home/user/best_model.csv"

    assert os.path.isfile(data_path), f"Input data file {data_path} is missing."
    with open(data_path, "rb") as actual, open(trusted_data_path, "rb") as trusted:
        assert actual.read() == trusted.read(), f"Input data file {data_path} was modified."

    expected_t, expected_acc = compute_expected_best_model(trusted_data_path)
    expected_line = f"{expected_t},{expected_acc:.4f}"

    assert os.path.isfile(output_path), f"Output file {output_path} is missing."
    with open(output_path, 'r') as f:
        content = f.read().strip()

    assert content == expected_line, f"Expected '{expected_line}' in {output_path}, but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
