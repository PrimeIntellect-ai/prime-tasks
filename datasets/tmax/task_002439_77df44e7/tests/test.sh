#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import stat
import pytest

def test_source_code_exists():
    path = "/home/user/config_tracker.c"
    assert os.path.isfile(path), f"Source code file {path} does not exist."

def test_executable_exists():
    path = "/home/user/config_tracker"
    assert os.path.isfile(path), f"Executable file {path} does not exist."
    st = os.stat(path)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {path} is not executable."

def test_output_file_exists():
    path = "/home/user/config_delta.csv"
    assert os.path.isfile(path), f"Output file {path} does not exist."

def test_delta_correctness():
    day1_path = "/home/user/configs/day1.csv"
    day2_path = "/home/user/configs/day2.csv"
    output_path = "/home/user/config_delta.csv"

    assert os.path.isfile(day1_path), f"Input file {day1_path} missing."
    assert os.path.isfile(day2_path), f"Input file {day2_path} missing."
    assert os.path.isfile(output_path), f"Output file {output_path} missing."

    day1_data = {}
    with open(day1_path, 'r', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) == 3:
                day1_data[(row[0], row[1])] = row[2]

    day2_data = {}
    with open(day2_path, 'r', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) == 3:
                day2_data[(row[0], row[1])] = row[2]

    expected_output = []
    all_keys = set(day1_data.keys()).union(set(day2_data.keys()))

    for (srv, key) in all_keys:
        val1 = day1_data.get((srv, key))
        val2 = day2_data.get((srv, key))

        if val1 is not None and val2 is None:
            expected_output.append([srv, key, 'DELETED', val1, ''])
        elif val1 is None and val2 is not None:
            expected_output.append([srv, key, 'ADDED', '', val2])
        elif val1 is not None and val2 is not None and val1 != val2:
            expected_output.append([srv, key, 'MODIFIED', val1, val2])

    expected_output.sort(key=lambda x: (x[0], x[1]))

    actual_output = []
    with open(output_path, 'r', newline='') as f:
        reader = csv.reader(f)
        for row in reader:
            actual_output.append(row)

    assert len(actual_output) == len(expected_output), \
        f"Expected {len(expected_output)} rows in {output_path}, but got {len(actual_output)}."

    for i, (actual, expected) in enumerate(zip(actual_output, expected_output)):
        assert actual == expected, \
            f"Row {i+1} mismatch. Expected {expected}, but got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
