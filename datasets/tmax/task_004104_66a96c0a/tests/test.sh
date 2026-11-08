#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

CYCLIC_JOBS_FILE = "/home/user/cyclic_jobs.txt"
JOB_STATS_FILE = "/home/user/job_stats.csv"

def test_cyclic_jobs_file_exists_and_correct():
    """Verify that cyclic_jobs.txt exists and contains the correct cyclic jobs."""
    assert os.path.isfile(CYCLIC_JOBS_FILE), f"File {CYCLIC_JOBS_FILE} does not exist."

    with open(CYCLIC_JOBS_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_cyclic = [
        "Update_Metrics_A",
        "Update_Metrics_B",
        "Update_Metrics_C"
    ]

    assert lines == expected_cyclic, (
        f"Contents of {CYCLIC_JOBS_FILE} are incorrect.\n"
        f"Expected: {expected_cyclic}\n"
        f"Got: {lines}"
    )

def test_job_stats_csv_exists_and_correct():
    """Verify that job_stats.csv exists and contains the correct statistics and hierarchy levels."""
    assert os.path.isfile(JOB_STATS_FILE), f"File {JOB_STATS_FILE} does not exist."

    with open(JOB_STATS_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_csv = [
        "job_name,avg_duration_seconds,hierarchy_level",
        "Extract_Sales,333,0",
        "Extract_Users,90,0",
        "Transform_Sales,0,1",
        "Transform_Users,300,1",
        "Load_DW,450,2"
    ]

    assert lines == expected_csv, (
        f"Contents of {JOB_STATS_FILE} are incorrect.\n"
        f"Expected:\n{chr(10).join(expected_csv)}\n\n"
        f"Got:\n{chr(10).join(lines)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
