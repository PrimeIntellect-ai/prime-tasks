#!/bin/bash
set +e
mkdir -p /logs/verifier

run_verification() {
    test -f /home/user/clean_data.cpp || return 1
    test -s /home/user/clean_data.cpp || return 1

    g++ -std=c++17 -O2 -Wall -Wextra /home/user/clean_data.cpp -o /tmp/clean_data_submission || return 1
    test -x /tmp/clean_data_submission || return 1

    cat << 'EOF' > /home/user/users.csv
user_id,age,region
1,25,NA
2,17,EU
3,45,AS
4,130,NA
5,50,EU
6,30,SA
8,40,AF
9,22,NA
EOF

    cat << 'EOF' > /home/user/predictions.csv
user_id,score,class_label
1,0.85,1
2,0.90,1
3,1.20,0
4,0.50,0
5,0.45,2
6,0.30,0
7,0.99,1
9,0.77,1
EOF

    rm -f /home/user/cleaned_output.csv /home/user/validation_errors.txt
    runuser -u user -- bash -c 'cd /home/user && timeout 10 /tmp/clean_data_submission' || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_cleaned_output_csv():
    file_path = "/home/user/cleaned_output.csv"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 1, "cleaned_output.csv is empty or missing header."
    assert lines[0] == "user_id,age,region,score,class_label", "Header is incorrect or missing."

    expected_data = [
        (1, 25, "NA", 0.85, 1),
        (6, 30, "SA", 0.3, 0),
        (9, 22, "NA", 0.77, 1)
    ]

    assert len(lines) - 1 == len(expected_data), f"Expected {len(expected_data)} data rows, found {len(lines) - 1}."

    for i, expected_row in enumerate(expected_data):
        actual_parts = lines[i + 1].split(',')
        assert len(actual_parts) == 5, f"Row {i + 1} does not have 5 columns."

        user_id, age, region, score, class_label = actual_parts
        assert int(user_id) == expected_row[0], f"Row {i + 1} user_id mismatch."
        assert int(age) == expected_row[1], f"Row {i + 1} age mismatch."
        assert region == expected_row[2], f"Row {i + 1} region mismatch."
        assert abs(float(score) - expected_row[3]) < 1e-6, f"Row {i + 1} score mismatch."
        assert int(class_label) == expected_row[4], f"Row {i + 1} class_label mismatch."

def test_validation_errors_txt():
    file_path = "/home/user/validation_errors.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_errors = ["2", "3", "4", "5"]
    assert lines == expected_errors, f"validation_errors.txt content mismatch. Expected {expected_errors}, got {lines}."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    python3 << 'PY_EOF' || return 1
import json
import random
import secrets

base = 100000 + secrets.randbelow(800000)
ids = [base + n for n in (41, 3, 88, 12, 67, 25, 99, 54, 76, 130, 7)]
users = [
    (ids[0], 18, "R18"),
    (ids[1], 120, "R120"),
    (ids[2], 17, "YOUNG"),
    (ids[3], 121, "OLD"),
    (ids[4], 35, "NEG"),
    (ids[5], 44, "HIGH"),
    (ids[6], 52, "CLASS2"),
    (ids[7], 29, "CLASSNEG"),
    (ids[8], 63, "VALID"),
    (ids[9], 40, "USER_ONLY"),
]
predictions = [
    (ids[0], "0.0", 0),
    (ids[1], "1.0", 1),
    (ids[2], "0.25", 1),
    (ids[3], "0.75", 0),
    (ids[4], "-0.01", 0),
    (ids[5], "1.01", 1),
    (ids[6], "0.5", 2),
    (ids[7], "0.6", -1),
    (ids[8], "0.314159", 1),
    (ids[10], "0.9", 1),
]
random.SystemRandom().shuffle(users)
random.SystemRandom().shuffle(predictions)

with open('/home/user/users.csv', 'w', newline='') as f:
    f.write('user_id,age,region\n')
    for uid, age, region in users:
        f.write(f'{uid},{age},{region}\n')

with open('/home/user/predictions.csv', 'w', newline='') as f:
    f.write('user_id,score,class_label\n')
    for uid, score, label in predictions:
        f.write(f'{uid},{score},{label}\n')

expected = {
    'valid': sorted([
        [ids[0], 18, 'R18', 0.0, 0],
        [ids[1], 120, 'R120', 1.0, 1],
        [ids[8], 63, 'VALID', 0.314159, 1],
    ]),
    'errors': sorted([ids[2], ids[3], ids[4], ids[5], ids[6], ids[7]])
}
with open('/tmp/dynamic_expected.json', 'w') as f:
    json.dump(expected, f)
PY_EOF
    chmod 600 /tmp/dynamic_expected.json

    rm -f /home/user/cleaned_output.csv /home/user/validation_errors.txt
    runuser -u user -- bash -c 'cd /home/user && timeout 10 /tmp/clean_data_submission' || return 1

    cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_state.py
import csv
import json
import os

with open('/tmp/dynamic_expected.json') as f:
    EXPECTED = json.load(f)

def test_dynamic_cleaned_output():
    path = '/home/user/cleaned_output.csv'
    assert os.path.isfile(path), f'File {path} is missing.'
    with open(path, newline='') as f:
        rows = list(csv.reader(f))
    assert rows, 'cleaned_output.csv is empty.'
    assert rows[0] == ['user_id', 'age', 'region', 'score', 'class_label']
    assert len(rows) - 1 == len(EXPECTED['valid'])
    for actual, expected in zip(rows[1:], EXPECTED['valid']):
        assert len(actual) == 5
        assert int(actual[0]) == expected[0]
        assert int(actual[1]) == expected[1]
        assert actual[2] == expected[2]
        assert abs(float(actual[3]) - expected[3]) < 1e-6
        assert int(actual[4]) == expected[4]

def test_dynamic_validation_errors():
    path = '/home/user/validation_errors.txt'
    assert os.path.isfile(path), f'File {path} is missing.'
    with open(path) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert lines == [str(value) for value in EXPECTED['errors']]
DYNAMIC_EOF

    python3 -m pytest /tmp/test_dynamic_state.py -x --tb=short || return 1
    return 0
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
