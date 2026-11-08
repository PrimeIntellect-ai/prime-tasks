#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import json
import ctypes
import pytest

def test_scripts_and_executables_exist():
    """Verify that the required source files and executables exist and have correct permissions."""
    run_sh = "/home/user/run.sh"
    process_c = "/home/user/process.c"
    process_bin = "/home/user/process"

    assert os.path.isfile(run_sh), f"Missing bash script at {run_sh}"
    assert os.access(run_sh, os.X_OK), f"Bash script {run_sh} is not executable"

    assert os.path.isfile(process_c), f"Missing C source file at {process_c}"
    assert os.path.isfile(process_bin), f"Missing compiled executable at {process_bin}"
    assert os.access(process_bin, os.X_OK), f"Compiled file {process_bin} is not executable"

def test_output_jsonl_correctness():
    """Verify that the output.jsonl file is generated correctly based on the task rules."""
    output_file = "/home/user/output.jsonl"
    data_file = "/home/user/data/requests.csv"
    target_lib = "/home/user/libs/libmathops-1.12.3.so"

    assert os.path.isfile(output_file), f"Missing output file at {output_file}"
    assert os.path.isfile(data_file), f"Missing input data file at {data_file}"
    assert os.path.isfile(target_lib), f"Missing target library at {target_lib}"

    # Load the library to compute the expected results dynamically
    lib = ctypes.CDLL(target_lib)
    process_value = lib.process_value
    process_value.argtypes = [ctypes.c_int]
    process_value.restype = ctypes.c_int

    expected_records = []
    user_counts = {}

    with open(data_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) != 3:
                continue

            try:
                uid = int(parts[1])
                val = int(parts[2])
            except ValueError:
                continue

            if val > 0:
                if user_counts.get(uid, 0) < 2:
                    res = process_value(val)
                    expected_records.append({"uid": uid, "result": res})
                    user_counts[uid] = user_counts.get(uid, 0) + 1

    actual_records = []
    with open(output_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                actual_records.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON in {output_file}: {line}")

    assert actual_records == expected_records, (
        f"Output in {output_file} does not match expected results.\n"
        f"Expected: {expected_records}\n"
        f"Actual: {actual_records}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
