#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import hashlib
import pytest

def get_expected_data():
    dataset_path = '/home/user/dataset.csv'
    if not os.path.exists(dataset_path):
        return None, None, None

    with open(dataset_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if not rows:
        return None, None, None

    memories = [float(row['memory_usage']) for row in rows]
    min_mem = min(memories)
    max_mem = max(memories)

    train_expected = []
    test_expected = []
    cpu_history = []

    for row in rows:
        ts = row['timestamp']
        role = row['server_role']
        cpu = float(row['cpu_usage'])
        mem = float(row['memory_usage'])
        crashed = int(row['crashed'])

        role_web = 1 if role == 'web' else 0
        role_db = 1 if role == 'db' else 0
        role_cache = 1 if role == 'cache' else 0

        mem_scaled = (mem - min_mem) / (max_mem - min_mem)

        cpu_history.append(cpu)
        if len(cpu_history) > 3:
            cpu_history.pop(0)
        cpu_rolling_avg = sum(cpu_history) / len(cpu_history)

        h = hashlib.md5(ts.encode('utf-8')).digest()
        first_byte = h[0]
        is_train = (first_byte % 10) < 8

        out_row = {
            'timestamp': ts,
            'role_web': str(role_web),
            'role_db': str(role_db),
            'role_cache': str(role_cache),
            'cpu_rolling_avg': f"{cpu_rolling_avg:.4f}",
            'memory_scaled': f"{mem_scaled:.4f}",
            'crashed': str(crashed)
        }

        if is_train:
            train_expected.append(out_row)
        else:
            test_expected.append(out_row)

    correct = 0
    total = len(test_expected)
    for row in test_expected:
        pred = 1 if float(row['cpu_rolling_avg']) > 80.0000 or float(row['memory_scaled']) > 0.8500 else 0
        if pred == int(row['crashed']):
            correct += 1

    accuracy = correct / total if total > 0 else 0.0
    expected_eval = f"Accuracy: {accuracy:.4f}"

    return train_expected, test_expected, expected_eval

def test_train_csv():
    train_path = '/home/user/train.csv'
    assert os.path.exists(train_path), f"File missing: {train_path}"

    train_expected, _, _ = get_expected_data()
    if train_expected is None:
        pytest.skip("dataset.csv not found or empty")

    with open(train_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        train_actual = list(reader)

    assert len(train_actual) == len(train_expected), f"Expected {len(train_expected)} rows in train.csv, got {len(train_actual)}"

    for i, (actual, expected) in enumerate(zip(train_actual, train_expected)):
        assert actual == expected, f"Row {i+1} in train.csv mismatch. Expected {expected}, got {actual}"

def test_test_csv():
    test_path = '/home/user/test.csv'
    assert os.path.exists(test_path), f"File missing: {test_path}"

    _, test_expected, _ = get_expected_data()
    if test_expected is None:
        pytest.skip("dataset.csv not found or empty")

    with open(test_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        test_actual = list(reader)

    assert len(test_actual) == len(test_expected), f"Expected {len(test_expected)} rows in test.csv, got {len(test_actual)}"

    for i, (actual, expected) in enumerate(zip(test_actual, test_expected)):
        assert actual == expected, f"Row {i+1} in test.csv mismatch. Expected {expected}, got {actual}"

def test_model_eval():
    eval_path = '/home/user/model_eval.txt'
    assert os.path.exists(eval_path), f"File missing: {eval_path}"

    _, _, expected_eval = get_expected_data()
    if expected_eval is None:
        pytest.skip("dataset.csv not found or empty")

    with open(eval_path, 'r') as f:
        eval_content = f.read().strip()

    assert eval_content == expected_eval, f"Expected model evaluation to be '{expected_eval}', got '{eval_content}'"
TEST_EOF

if test -f /home/user/pipeline.go \
    && rm -f /home/user/train.csv /home/user/test.csv /home/user/model_eval.txt \
    && (cd /home/user && timeout 60s go run /home/user/pipeline.go) \
    && test -f /home/user/pipeline.go \
    && test -f /home/user/train.csv \
    && test -f /home/user/test.csv \
    && test -f /home/user/model_eval.txt \
    && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
