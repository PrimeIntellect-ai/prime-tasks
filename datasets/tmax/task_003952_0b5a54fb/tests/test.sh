#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv

def test_validation_report_exists():
    """Test that the validation_report.csv file exists."""
    file_path = "/home/user/validation_report.csv"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

def test_validation_report_content():
    """Test that the validation_report.csv contains the correct evaluation results."""
    input_path = "/home/user/pipeline_runs.csv"
    output_path = "/home/user/validation_report.csv"

    assert os.path.exists(input_path), f"Input file {input_path} is missing."

    expected_results = {}
    with open(input_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            run_id = row['run_id']
            alpha = float(row['prior_alpha'])
            beta = float(row['prior_beta'])
            heads = float(row['heads'])
            tails = float(row['tails'])
            est_mean = float(row['estimated_mean'])
            est_var = float(row['estimated_variance'])

            A = alpha + heads
            B = beta + tails

            true_mean = A / (A + B)
            true_var = (A * B) / (((A + B) ** 2) * (A + B + 1))

            mean_diff = abs(est_mean - true_mean)
            var_diff = abs(est_var - true_var)

            if mean_diff <= 0.01 and var_diff <= 0.001:
                expected_results[run_id] = "PASSED"
            else:
                expected_results[run_id] = "FAILED"

    with open(output_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) > 0, f"File {output_path} is empty."
    assert lines[0] == "run_id,status", f"Expected header 'run_id,status', but got '{lines[0]}'."

    actual_results = {}
    for line in lines[1:]:
        parts = line.split(',')
        assert len(parts) == 2, f"Invalid line format in {output_path}: '{line}'"
        actual_results[parts[0]] = parts[1]

    assert len(actual_results) == len(expected_results), \
        f"Expected {len(expected_results)} runs in report, found {len(actual_results)}."

    # Check sorting
    actual_run_ids = list(actual_results.keys())
    assert actual_run_ids == sorted(actual_run_ids), f"The report is not sorted by run_id. Got: {actual_run_ids}"

    for run_id, expected_status in expected_results.items():
        assert run_id in actual_results, f"Run ID '{run_id}' missing from validation report."
        assert actual_results[run_id] == expected_status, \
            f"Expected status '{expected_status}' for {run_id}, but got '{actual_results[run_id]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
