#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import re

def test_results_json_exists_and_valid():
    results_file = "/home/user/results.json"
    assert os.path.exists(results_file), "The file /home/user/results.json does not exist."
    assert os.path.isfile(results_file), "/home/user/results.json is not a file."

    with open(results_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "/home/user/results.json is not valid JSON."

    assert isinstance(data, dict), "The top-level JSON structure in results.json must be an object (dictionary)."

def test_results_match_truth():
    results_file = "/home/user/results.json"
    data_dir = "/home/user/data"

    with open(results_file, 'r') as f:
        student_results = json.load(f)

    # Recompute truth from actual files
    expected_results = {}
    for i in range(1, 21):
        filename = f"sensor_{i}.csv"
        filepath = os.path.join(data_dir, filename)

        sum_of_squares = 0
        if os.path.exists(filepath):
            with open(filepath, 'r', newline='') as f:
                reader = csv.DictReader(f)
                for row in reader:
                    reading = int(row['reading'])
                    if reading % 2 != 0:
                        sum_of_squares += reading * reading
        expected_results[filename] = sum_of_squares

    assert len(student_results) == len(expected_results), f"Expected {len(expected_results)} entries in results.json, found {len(student_results)}."

    for filename, expected_sum in expected_results.items():
        assert filename in student_results, f"Missing result for {filename} in results.json."
        assert student_results[filename] == expected_sum, f"Incorrect sum for {filename}. Expected {expected_sum}, got {student_results[filename]}."

def test_pipeline_log_exists_and_format():
    log_file = "/home/user/pipeline.log"
    assert os.path.exists(log_file), "The file /home/user/pipeline.log does not exist."

    start_count = 0
    done_count = 0

    with open(log_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if re.match(r"^\[START\] Processing sensor_\d+\.csv$", line):
                start_count += 1
            elif re.match(r"^\[DONE\] sensor_\d+\.csv - Result: \d+$", line):
                done_count += 1

    assert start_count == 20, f"Expected 20 [START] lines in pipeline.log, found {start_count}."
    assert done_count == 20, f"Expected 20 [DONE] lines in pipeline.log, found {done_count}."

def test_process_script_exists_and_parallel():
    script_file = "/home/user/process.sh"
    assert os.path.exists(script_file), "The file /home/user/process.sh does not exist."
    assert os.access(script_file, os.X_OK), "The script /home/user/process.sh is not executable."

    with open(script_file, 'r') as f:
        content = f.read()

    # Check for parallel constructs
    has_parallel = bool(re.search(r'(&|xargs\s+-P|parallel)', content))
    assert has_parallel, "The script /home/user/process.sh does not appear to use parallel constructs (&, xargs -P, or parallel)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
