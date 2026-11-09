#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import stat
import subprocess
from pathlib import Path
import pytest

TRACKER = "/home/user/tracker.cpp"
BINARY = "/tmp/tracker_submission"
SUMMARY = "/home/user/summary.txt"
SOURCE_A = "/home/user/source_a.csv"
SOURCE_B = "/home/user/source_b.csv"


def compute_expected_results():
    source_a_path = SOURCE_A
    source_b_path = SOURCE_B

    assert os.path.exists(source_a_path), f"{source_a_path} is missing."
    assert os.path.exists(source_b_path), f"{source_b_path} is missing."

    data = {}
    with open(source_a_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            exp_id = int(row["ExperimentID"])
            data[exp_id] = {
                "M1": float(row["Metric1"]),
                "M2": float(row["Metric2"])
            }

    with open(source_b_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            exp_id = int(row["ExperimentID"])
            if exp_id in data:
                data[exp_id]["M3"] = float(row["Metric3"])
                data[exp_id]["Prior"] = float(row["PriorProb"])

    # Impute missing values (-999.0)
    for metric in ["M1", "M2", "M3"]:
        valid_values = [d[metric] for d in data.values() if d[metric] != -999.0]
        mean_val = sum(valid_values) / len(valid_values) if valid_values else 0.0
        for exp_id in data:
            if data[exp_id][metric] == -999.0:
                data[exp_id][metric] = mean_val

    # Calculate population variance
    total_variance = 0.0
    for metric in ["M1", "M2", "M3"]:
        values = [d[metric] for d in data.values()]
        mean_val = sum(values) / len(values)
        variance = sum((x - mean_val) ** 2 for x in values) / len(values)
        total_variance += variance

    # Calculate Bayesian Posterior
    max_posterior = -1.0
    best_exp_id = -1

    for exp_id, d in data.items():
        metric_sum = d["M1"] + d["M2"] + d["M3"]
        prior = d["Prior"]

        if metric_sum > 20.0:
            l_success = 0.8
            l_fail = 0.3
        else:
            l_success = 0.4
            l_fail = 0.7

        marginal = (l_success * prior) + (l_fail * (1.0 - prior))
        posterior = (l_success * prior) / marginal

        if posterior > max_posterior:
            max_posterior = posterior
            best_exp_id = exp_id

    return best_exp_id, total_variance


def read_summary():
    assert os.path.exists(SUMMARY), "The summary.txt file was not found."
    with open(SUMMARY, "r") as f:
        content = f.read().strip()

    lines = content.split('\n')
    assert len(lines) >= 2, "summary.txt does not contain enough lines."

    exp_id_line = lines[0].strip()
    variance_line = lines[1].strip()
    assert exp_id_line.startswith("Highest_Posterior_Exp_ID:"), "First line format is incorrect."
    assert variance_line.startswith("Total_Variance:"), "Second line format is incorrect."

    return (
        int(exp_id_line.split(":", 1)[1].strip()),
        float(variance_line.split(":", 1)[1].strip()),
    )


def assert_summary_matches(expected_exp_id, expected_total_variance):
    actual_exp_id, actual_variance = read_summary()
    assert actual_exp_id == expected_exp_id, (
        f"Expected Highest_Posterior_Exp_ID to be {expected_exp_id}, "
        f"but got {actual_exp_id}."
    )

    expected_variance_str = f"{expected_total_variance:.2f}"
    actual_variance_str = f"{actual_variance:.2f}"
    assert actual_variance_str == expected_variance_str, (
        f"Expected Total_Variance to be {expected_variance_str}, "
        f"but got {actual_variance_str}."
    )


def run_tracker():
    if os.path.exists(SUMMARY):
        os.remove(SUMMARY)
    result = subprocess.run(
        [BINARY], cwd="/home/user", capture_output=True, text=True, timeout=10
    )
    assert result.returncode == 0, (
        f"Compiled tracker exited with code {result.returncode}. "
        f"stdout: {result.stdout} stderr: {result.stderr}"
    )
    assert os.path.exists(SUMMARY), "Running tracker did not create summary.txt."


def test_summary_file_exists():
    assert os.path.exists(SUMMARY), "The summary.txt file was not found."


def test_cpp_file_exists():
    assert os.path.exists(TRACKER), "The tracker.cpp file was not found."


def test_summary_content():
    expected_exp_id, expected_total_variance = compute_expected_results()

    with open(SUMMARY, "r") as f:
        content = f.read().strip()

    lines = content.split('\n')
    assert len(lines) >= 2, "summary.txt does not contain enough lines."

    exp_id_line = lines[0].strip()
    variance_line = lines[1].strip()

    assert exp_id_line.startswith("Highest_Posterior_Exp_ID:"), "First line format is incorrect."
    assert variance_line.startswith("Total_Variance:"), "Second line format is incorrect."

    actual_exp_id = int(exp_id_line.split(":")[1].strip())
    actual_variance = float(variance_line.split(":")[1].strip())

    assert actual_exp_id == expected_exp_id, f"Expected Highest_Posterior_Exp_ID to be {expected_exp_id}, but got {actual_exp_id}."

    expected_variance_str = f"{expected_total_variance:.2f}"
    actual_variance_str = f"{actual_variance:.2f}"

    assert actual_variance_str == expected_variance_str, f"Expected Total_Variance to be {expected_variance_str}, but got {actual_variance_str}."


def test_tracker_compiles_and_runs_on_original_inputs():
    mode = os.stat(TRACKER).st_mode
    assert stat.S_ISREG(mode), "tracker.cpp is not a regular file."

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", TRACKER, "-o", BINARY],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "tracker.cpp did not compile as C++17. "
        f"stdout: {compile_result.stdout} stderr: {compile_result.stderr}"
    )

    expected = compute_expected_results()
    run_tracker()
    assert_summary_matches(*expected)


def test_tracker_processes_unseen_csv_inputs():
    original_a = Path(SOURCE_A).read_bytes()
    original_b = Path(SOURCE_B).read_bytes()
    original_summary = Path(SUMMARY).read_bytes() if Path(SUMMARY).exists() else None

    cases = [
        (
            """ExperimentID,Metric1,Metric2
101,-999.0,4.0
102,10.0,-999.0
103,30.0,8.0
999,500.0,500.0
""",
            """ExperimentID,Metric3,PriorProb
101,6.0,0.9
102,-999.0,0.2
103,2.0,0.5
777,900.0,0.99
""",
        ),
        (
            """ExperimentID,Metric1,Metric2
7,1.0,2.0
8,3.0,4.0
9,-999.0,6.0
10,40.0,-999.0
""",
            """ExperimentID,Metric3,PriorProb
7,1.0,0.95
8,3.0,0.5
9,-999.0,0.7
10,40.0,0.1
""",
        ),
    ]

    try:
        for source_a, source_b in cases:
            Path(SOURCE_A).write_text(source_a)
            Path(SOURCE_B).write_text(source_b)
            expected = compute_expected_results()
            run_tracker()
            assert_summary_matches(*expected)
    finally:
        Path(SOURCE_A).write_bytes(original_a)
        Path(SOURCE_B).write_bytes(original_b)
        if original_summary is None:
            if Path(SUMMARY).exists():
                Path(SUMMARY).unlink()
        else:
            Path(SUMMARY).write_bytes(original_summary)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
