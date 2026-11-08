#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import subprocess
import pytest

PCAP_FILE = "/home/user/pcap_summary.log"
SCRIPT_FILE = "/home/user/network_analyzer.sh"
RESULT_FILE = "/home/user/result.txt"
SOLUTION_FILE = "/home/user/solution.txt"
TRACE_FILE = "/home/user/trace.log"


def calculate_expected(pcap_file):
    expected_total = 0
    with open(pcap_file, 'r') as f:
        lines = f.read().strip().split('\n')

    for line in lines:
        parts = line.split()
        if not parts or parts[0] == "session_id":
            continue

        try:
            bytes_transferred = int(parts[1])
            start_time = int(parts[2])
            end_time = int(parts[3])
        except ValueError:
            continue

        duration = end_time - start_time
        if duration == 0:
            duration = 1

        throughput = bytes_transferred // duration
        expected_total += throughput

    return expected_total


def test_solution_file_contains_correct_value():
    pcap_file = "/home/user/pcap_summary.log"
    solution_file = "/home/user/solution.txt"

    assert os.path.isfile(pcap_file), f"Missing file: {pcap_file}"
    assert os.path.isfile(solution_file), f"Missing solution file: {solution_file}"

    expected_total = 0
    with open(pcap_file, 'r') as f:
        lines = f.read().strip().split('\n')

    for line in lines:
        parts = line.split()
        if not parts or parts[0] == "session_id":
            continue

        try:
            bytes_transferred = int(parts[1])
            start_time = int(parts[2])
            end_time = int(parts[3])
        except ValueError:
            continue

        duration = end_time - start_time
        if duration == 0:
            duration = 1

        throughput = bytes_transferred // duration
        expected_total += throughput

    with open(solution_file, 'r') as f:
        solution_content = f.read().strip()

    assert solution_content == str(expected_total), (
        f"Expected solution to be {expected_total}, but found '{solution_content}'"
    )


def test_script_is_executable():
    script_path = "/home/user/network_analyzer.sh"
    assert os.path.isfile(script_path), f"Missing script: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_existing_result_contains_correct_value():
    assert os.path.isfile(RESULT_FILE), f"Missing result file: {RESULT_FILE}"
    expected = calculate_expected(PCAP_FILE)
    with open(RESULT_FILE, "r") as f:
        result_content = f.read().strip()
    assert result_content == str(expected), (
        f"Expected result to be {expected}, but found '{result_content}'"
    )


def test_script_runs_on_supplied_input_and_recreates_result():
    expected = calculate_expected(PCAP_FILE)
    if os.path.exists(RESULT_FILE):
        os.remove(RESULT_FILE)

    completed = subprocess.run(
        [SCRIPT_FILE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"Analyzer failed with exit code {completed.returncode}: {completed.stderr}"
    )
    assert os.path.isfile(RESULT_FILE), "Analyzer did not create /home/user/result.txt"
    with open(RESULT_FILE, "r") as f:
        result_content = f.read().strip()
    assert result_content == str(expected), (
        f"Analyzer produced '{result_content}', expected '{expected}'"
    )

    with open(SOLUTION_FILE, "r") as f:
        solution_content = f.read().strip()
    assert solution_content == str(expected), (
        f"Solution contains '{solution_content}', expected '{expected}'"
    )


def test_script_handles_unseen_zero_duration_sessions():
    paths_to_restore = [PCAP_FILE, RESULT_FILE, TRACE_FILE, SOLUTION_FILE]
    snapshots = {}
    for path in paths_to_restore:
        if os.path.exists(path):
            with open(path, "rb") as f:
                snapshots[path] = (True, f.read())
        else:
            snapshots[path] = (False, b"")

    try:
        for trial in range(2):
            rows = []
            expected = 0
            for index in range(7):
                start = 1000 + secrets.randbelow(50000)
                duration = 0 if index in (1, 4) else 1 + secrets.randbelow(19)
                byte_count = secrets.randbelow(900000) + index + trial + 1
                end = start + duration
                rows.append(f"T{trial}_{index} {byte_count} {start} {end}")
                divisor = 1 if duration == 0 else duration
                expected += byte_count // divisor

            with open(PCAP_FILE, "w") as f:
                f.write("session_id bytes start_time end_time\n")
                f.write("\n".join(rows) + "\n")

            if os.path.exists(RESULT_FILE):
                os.remove(RESULT_FILE)

            completed = subprocess.run(
                [SCRIPT_FILE],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert completed.returncode == 0, (
                f"Analyzer failed on generated input with exit code "
                f"{completed.returncode}: {completed.stderr}"
            )
            assert os.path.isfile(RESULT_FILE), (
                "Analyzer did not create result.txt for generated input"
            )
            with open(RESULT_FILE, "r") as f:
                actual = f.read().strip()
            assert actual == str(expected), (
                f"Analyzer produced '{actual}' for generated input; expected '{expected}'"
            )
    finally:
        for path, (existed, content) in snapshots.items():
            if existed:
                with open(path, "wb") as f:
                    f.write(content)
            elif os.path.exists(path):
                os.remove(path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
