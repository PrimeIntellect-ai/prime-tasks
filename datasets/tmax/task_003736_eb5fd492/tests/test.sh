#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest

def get_data():
    x_data = {}
    with open('/home/user/data_X.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            x_data[int(row['ID'])] = float(row['X'])

    y_data = {}
    with open('/home/user/data_Y.csv', 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            y_data[int(row['ID'])] = float(row['Y'])

    joined = []
    for uid in x_data:
        joined.append((uid, x_data[uid], y_data[uid]))

    return joined

def compute_stats(data):
    n = len(data)
    sum_x = sum(d[1] for d in data)
    sum_y = sum(d[2] for d in data)

    mean_x = sum_x / n
    mean_y = sum_y / n

    sum_sq_x = sum((d[1] - mean_x) ** 2 for d in data)
    sum_sq_y = sum((d[2] - mean_y) ** 2 for d in data)
    sum_coproduct = sum((d[1] - mean_x) * (d[2] - mean_y) for d in data)

    r = sum_coproduct / math.sqrt(sum_sq_x * sum_sq_y)
    m = sum_coproduct / sum_sq_x
    c = mean_y - m * mean_x

    return r, m, c

def test_correlation_output():
    corr_file = '/home/user/correlation.txt'
    assert os.path.exists(corr_file), f"File {corr_file} does not exist."

    data = get_data()
    expected_r, _, _ = compute_stats(data)
    expected_r_str = f"{expected_r:.4f}"

    with open(corr_file, 'r') as f:
        actual_r_str = f.read().strip()

    assert actual_r_str == expected_r_str, f"Expected correlation {expected_r_str}, got {actual_r_str}."

def test_cleaned_output():
    cleaned_file = '/home/user/cleaned.csv'
    assert os.path.exists(cleaned_file), f"File {cleaned_file} does not exist."

    data = get_data()
    _, m, c = compute_stats(data)

    expected_cleaned = []
    for d in data:
        uid, x, y = d
        residual = abs(y - (m * x + c))
        if residual < 1.5:
            expected_cleaned.append(d)

    expected_cleaned.sort(key=lambda item: item[0])

    with open(cleaned_file, 'r') as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, "Cleaned CSV is empty."
    assert reader[0] == ['ID', 'X', 'Y'], f"Expected header ['ID', 'X', 'Y'], got {reader[0]}."

    actual_rows = reader[1:]
    assert len(actual_rows) == len(expected_cleaned), f"Expected {len(expected_cleaned)} cleaned rows, got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_cleaned)):
        e_id, e_x, e_y = expected
        a_id, a_x, a_y = actual

        assert int(a_id) == e_id, f"Row {i+1}: Expected ID {e_id}, got {a_id}."
        assert a_x == f"{e_x:.4f}", f"Row {i+1}: Expected X {e_x:.4f}, got {a_x}."
        assert a_y == f"{e_y:.4f}", f"Row {i+1}: Expected Y {e_y:.4f}, got {a_y}."
TEST_EOF

verify_submission() {
    test -f /home/user/processor.c || return 1
    test -s /home/user/processor.c || return 1

    rm -f /home/user/processor || return 1
    gcc /home/user/processor.c -lm -o /home/user/processor || return 1
    test -f /home/user/processor || return 1
    test -x /home/user/processor || return 1

    rm -f /home/user/correlation.txt /home/user/cleaned.csv || return 1
    timeout 10s /home/user/processor || return 1

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
}

if verify_submission; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
