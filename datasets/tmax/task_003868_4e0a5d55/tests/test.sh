#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import csv

def test_pipeline_source_exists():
    assert os.path.isfile("/home/user/pipeline.c"), "Source file /home/user/pipeline.c is missing."

def test_pipeline_binary_exists():
    assert os.path.isfile("/home/user/pipeline"), "Compiled binary /home/user/pipeline is missing."
    assert os.access("/home/user/pipeline", os.X_OK), "/home/user/pipeline is not executable."

def compute_ground_truth():
    rows = []
    valid_vals = []

    with open('/home/user/raw_data.csv', 'r', newline='') as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            id_val = int(row[0])
            sensor_val = row[1]
            text_note = row[2]

            if sensor_val != "":
                val = float(sensor_val)
                valid_vals.append(val)
            else:
                val = None

            rows.append((id_val, val, text_note))

    mean = sum(valid_vals) / len(valid_vals)

    imputed_vals = []
    for r in rows:
        if r[1] is None:
            imputed_vals.append(mean)
        else:
            imputed_vals.append(r[1])

    variance = sum((x - mean) ** 2 for x in imputed_vals) / len(imputed_vals)
    std_dev = math.sqrt(variance)

    surviving_rows = 0
    out_rows = []
    for r, imp_val in zip(rows, imputed_vals):
        if abs(imp_val - mean) <= 2.0 * std_dev:
            surviving_rows += 1
            tokens = len(r[2].split()) if r[2] else 0
            fold = r[0] % 3
            out_rows.append(f"{r[0]},{imp_val:.4f},{tokens},{fold}")

    log_content = (
        f"Original Rows: {len(rows)}\n"
        f"Mean: {mean:.4f}\n"
        f"StdDev: {std_dev:.4f}\n"
        f"Surviving Rows: {surviving_rows}\n"
    )

    csv_content = "id,imputed_sensor_val,token_count,fold\n" + "\n".join(out_rows) + "\n"

    return log_content, csv_content

def test_experiment_log():
    log_path = "/home/user/experiment_log.txt"
    assert os.path.isfile(log_path), f"Output file {log_path} is missing."

    expected_log, _ = compute_ground_truth()

    with open(log_path, 'r') as f:
        actual_log = f.read()

    assert actual_log.strip() == expected_log.strip(), (
        f"Content of {log_path} does not match expected output.\n"
        f"Expected:\n{expected_log.strip()}\n\n"
        f"Actual:\n{actual_log.strip()}"
    )

def test_clean_features_csv():
    csv_path = "/home/user/clean_features.csv"
    assert os.path.isfile(csv_path), f"Output file {csv_path} is missing."

    _, expected_csv = compute_ground_truth()

    with open(csv_path, 'r') as f:
        actual_csv = f.read()

    assert actual_csv.strip() == expected_csv.strip(), (
        f"Content of {csv_path} does not match expected output."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
