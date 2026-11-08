#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess

REPORT_FILE = "/home/user/profiler_report.txt"
RUN_SCRIPT = "/home/user/profiler_repo/run_analysis.sh"

def test_profiler_report_exists():
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} does not exist."

def test_profiler_report_content():
    with open(REPORT_FILE, "r") as f:
        lines = [line.strip() for line in f.read().strip().splitlines()]

    assert len(lines) == 3, f"Expected exactly 3 lines in {REPORT_FILE}, found {len(lines)}."

    assert lines[0] == "a9f8b7c6d5e4", f"Line 1 is incorrect. Expected 'a9f8b7c6d5e4', got '{lines[0]}'."
    assert lines[1] == "--dev-xc92k1l8m4n5", f"Line 2 is incorrect. Expected '--dev-xc92k1l8m4n5', got '{lines[1]}'."
    assert lines[2] == "90", f"Line 3 is incorrect. Expected '90', got '{lines[2]}'."

def run_analysis(requests, time_sec):
    result = subprocess.run(
        [RUN_SCRIPT, str(requests), str(time_sec)],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"Script {RUN_SCRIPT} failed for inputs {requests} {time_sec}: "
        f"{result.stderr.strip()}"
    )
    return result.stdout.strip()

def test_run_analysis_script_fixed():
    assert os.path.isfile(RUN_SCRIPT), f"Script {RUN_SCRIPT} is missing."

    # Run the script with 150 and 100
    output = run_analysis(150, 100)
    assert output == "90", f"Script {RUN_SCRIPT} did not output the correct value. Expected '90', got '{output}'."

def test_run_analysis_general_formula():
    # Include truncation-sensitive edge cases, then add unpredictable cases so a
    # fixed lookup or constant-output script cannot satisfy the required formula.
    cases = [(1, 2), (2, 3), (7, 4), (99, 100), (100, 99), (1001, 60)]
    rng = secrets.SystemRandom()
    while len(cases) < 30:
        requests = rng.randint(1, 1_000_000)
        time_sec = rng.randint(1, 10_000)
        if requests % time_sec != 0:
            cases.append((requests, time_sec))

    for requests, time_sec in cases:
        expected = str((requests * 60) // time_sec)
        output = run_analysis(requests, time_sec)
        assert output == expected, (
            f"Script {RUN_SCRIPT} produced '{output}' for {requests} requests "
            f"in {time_sec} seconds; expected '{expected}'."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
