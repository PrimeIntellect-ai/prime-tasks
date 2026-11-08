#!/bin/bash
set +e
mkdir -p /logs/verifier

RAW=/home/user/raw_data.csv
BACKUP=/tmp/raw_data.csv.verifier_backup
BIN=/tmp/submission_pipeline
cp "$RAW" "$BACKUP"

cleanup() {
    cp "$BACKUP" "$RAW" 2>/dev/null || true
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_clean_data_exists_and_content():
    clean_data_path = "/home/user/clean_data.csv"
    assert os.path.isfile(clean_data_path), f"File not found: {clean_data_path}"

    with open(clean_data_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "ID,X1,X2,X3,Y",
        "1,12,2,24,0",
        "2,14,3,42,100",
        "3,14,1,14,0",
        "4,18,2,36,100",
        "5,10,1,10,0",
        "6,14,4,56,100",
        "7,20,2,40,100",
        "8,15,3,45,100",
        "9,11,1,11,0",
        "10,25,2,50,100"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} rows in clean_data.csv, found {len(lines)}"

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Row {i} mismatch in clean_data.csv. Expected: {expected}, Got: {actual}"

def test_result_txt_exists_and_content():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"File not found: {result_path}"

    with open(result_path, 'r') as f:
        content = f.read().strip()

    expected_content = "Optimal T: 30\nBest MSE: 0.00"

    assert content == expected_content, f"Content of {result_path} is incorrect.\nExpected:\n{expected_content}\nGot:\n{content}"
TEST_EOF

cat << 'DYNAMIC_TEST_EOF' > /tmp/test_dynamic_state.py
import os


def test_dynamic_clean_data():
    assert os.path.isfile('/home/user/clean_data.csv')
    with open('/home/user/clean_data.csv', 'r') as actual_file:
        actual = [line.strip() for line in actual_file if line.strip()]
    with open('/tmp/expected_clean_data.csv', 'r') as expected_file:
        expected = [line.strip() for line in expected_file if line.strip()]
    assert actual == expected


def test_dynamic_result():
    assert os.path.isfile('/home/user/result.txt')
    with open('/home/user/result.txt', 'r') as actual_file:
        actual = actual_file.read().strip()
    with open('/tmp/expected_result.txt', 'r') as expected_file:
        expected = expected_file.read().strip()
    assert actual == expected
DYNAMIC_TEST_EOF

score=0

if python3 - << 'PY'
import os
import stat
p = '/home/user/pipeline.go'
assert os.path.exists(p), f'Missing {p}'
assert not os.path.islink(p), f'{p} must be a regular Go source file, not a symlink'
assert stat.S_ISREG(os.stat(p).st_mode), f'{p} is not a regular file'
PY
then
    if go build -o "$BIN" /home/user/pipeline.go; then
        rm -f /home/user/clean_data.csv /home/user/result.txt
        if timeout 20s "$BIN" && python3 -m pytest /tmp/test_final_state.py -x --tb=short; then
            if python3 - << 'PY'
import csv
import secrets

candidates = [10, 20, 30, 40, 50]
chosen = secrets.choice(candidates)
base_id = 1000 + secrets.randbelow(8000)

# Eight valid X1 values have sorted middle values 12 and 13, so the
# floor-median used for both missing entries is 12. Products cover every
# interval between adjacent candidate thresholds.
spec = [
    ('3', 2),
    ('7', 2),
    ('12', 2),
    ('17', 2),
    ('22', 2),
    ('27', 2),
    ('13', 3),
    ('8', 4),
    ('', 2),
    ('', 4),
]

valid_x1 = sorted(int(x1) for x1, _ in spec if x1 != '')
n = len(valid_x1)
median = valid_x1[n // 2] if n % 2 else (valid_x1[n // 2 - 1] + valid_x1[n // 2]) // 2

rows = []
for index, (raw_x1, x2) in enumerate(spec):
    x1 = int(raw_x1) if raw_x1 else median
    x3 = x1 * x2
    y = 100 if x3 >= chosen else 0
    # This point is below every candidate threshold, adding a common,
    # nonzero error so MSE calculation and formatting are exercised.
    if index == 0:
        y = 100
    rows.append((base_id + index, raw_x1, x1, x2, x3, y))

with open('/home/user/raw_data.csv', 'w', newline='') as f:
    writer = csv.writer(f, lineterminator='\n')
    writer.writerow(['ID', 'X1', 'X2', 'Y'])
    for row_id, raw_x1, _, x2, _, y in rows:
        writer.writerow([row_id, raw_x1, x2, y])

with open('/tmp/expected_clean_data.csv', 'w', newline='') as f:
    writer = csv.writer(f, lineterminator='\n')
    writer.writerow(['ID', 'X1', 'X2', 'X3', 'Y'])
    for row_id, _, x1, x2, x3, y in rows:
        writer.writerow([row_id, x1, x2, x3, y])

fold_size = len(rows) // 5
scores = {}
for threshold in candidates:
    fold_mses = []
    for fold in range(5):
        validation = rows[fold * fold_size:(fold + 1) * fold_size]
        squared_errors = []
        for _, _, _, _, x3, y in validation:
            prediction = 100 if x3 >= threshold else 0
            squared_errors.append((prediction - y) ** 2)
        fold_mses.append(sum(squared_errors) / len(squared_errors))
    scores[threshold] = sum(fold_mses) / len(fold_mses)

best_threshold = min(candidates, key=lambda threshold: scores[threshold])
with open('/tmp/expected_result.txt', 'w') as f:
    f.write(f'Optimal T: {best_threshold}\nBest MSE: {scores[best_threshold]:.2f}\n')
PY
            then
                rm -f /home/user/clean_data.csv /home/user/result.txt
                if timeout 20s "$BIN" && python3 -m pytest /tmp/test_dynamic_state.py -x --tb=short; then
                    score=1
                fi
            fi
        fi
    fi
fi

cleanup
trap - EXIT
if [ "$score" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
