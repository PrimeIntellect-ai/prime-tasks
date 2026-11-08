#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re

def parse_initial_data():
    input_file = "/home/user/server_metrics.csv"
    if not os.path.exists(input_file):
        return [], []

    with open(input_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    if not lines:
        return [], []

    header = lines[0]
    data = lines[1:]
    return header, data

def is_numeric_or_q(val):
    if val == '?':
        return True
    try:
        float(val)
        return True
    except ValueError:
        return False

def get_expected_schema_valid():
    header, data = parse_initial_data()
    valid_rows = []
    for row in data:
        cols = row.split(',')
        if len(cols) != 5:
            continue
        if not all(is_numeric_or_q(c) for c in cols[:4]):
            continue
        if cols[4] not in ('OK', 'FAIL'):
            continue
        valid_rows.append(row)
    return header, valid_rows

def get_expected_cleaned():
    header, valid_rows = get_expected_schema_valid()
    cleaned_rows = []
    for row in valid_rows:
        cols = row.split(',')
        # CPU
        if cols[1] == '?':
            cols[1] = '50.0'
        # RAM
        if cols[2] == '?':
            cols[2] = '50.0'
        else:
            ram = float(cols[2])
            if ram > 100.0:
                # Format to preserve decimal if it was there, but task says exactly 100.0
                cols[2] = '100.0'
        cleaned_rows.append(','.join(cols))
    return header, cleaned_rows

def get_expected_engineered():
    header, cleaned_rows = get_expected_cleaned()
    new_header = header + ",Load_Factor"
    engineered_rows = []
    for row in cleaned_rows:
        cols = row.split(',')
        cpu = float(cols[1])
        ram = float(cols[2])
        load_factor = (cpu * ram) / 100.0
        cols.append(f"{load_factor:.2f}")
        engineered_rows.append(','.join(cols))
    return new_header, engineered_rows

def get_expected_best_model():
    _, engineered_rows = get_expected_engineered()
    if not engineered_rows:
        return ""

    best_t = 1
    best_acc = -1.0

    for t in range(1, 101):
        correct = 0
        total = len(engineered_rows)
        for row in engineered_rows:
            cols = row.split(',')
            status = cols[4]
            lf = float(cols[5])

            pred = 'FAIL' if lf >= t else 'OK'
            if pred == status:
                correct += 1

        acc = correct / total
        if acc > best_acc:
            best_acc = acc
            best_t = t

    return f"Best Threshold: {best_t}, Accuracy: {best_acc:.2f}"

def test_phase1_schema_valid():
    file_path = "/home/user/schema_valid.csv"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = [line.strip() for line in f if line.strip()]

    header, expected_data = get_expected_schema_valid()
    expected_content = [header] + expected_data

    assert content == expected_content, f"Content of {file_path} does not match expected schema-enforced data."

def test_phase2_cleaned():
    file_path = "/home/user/cleaned.csv"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = [line.strip() for line in f if line.strip()]

    header, expected_data = get_expected_cleaned()
    expected_content = [header] + expected_data

    assert content == expected_content, f"Content of {file_path} does not match expected cleaned data."

def test_phase3_engineered():
    file_path = "/home/user/engineered.csv"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = [line.strip() for line in f if line.strip()]

    header, expected_data = get_expected_engineered()
    expected_content = [header] + expected_data

    assert content == expected_content, f"Content of {file_path} does not match expected engineered data."

def test_phase4_best_model():
    file_path = "/home/user/best_model.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_content = get_expected_best_model()

    assert content == expected_content, f"Content of {file_path} does not match expected best model output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
