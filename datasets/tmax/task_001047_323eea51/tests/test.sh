#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import stat
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path("/home/user/aggregate_logs.sh")
LOGS = Path("/home/user/server_logs.txt")
OUTPUT = Path("/home/user/hourly_averages.txt")


def run_script():
    result = subprocess.run(
        [str(SCRIPT)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{SCRIPT} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submission_on_original_logs():
    assert SCRIPT.exists(), f"Script {SCRIPT} does not exist."
    assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), f"{SCRIPT} must be a regular file."
    assert os.access(SCRIPT, os.X_OK), f"{SCRIPT} is not executable."

    first_line = SCRIPT.read_text(errors="replace").splitlines()[0]
    assert "bash" in first_line, f"{SCRIPT} must be a Bash script."

    OUTPUT.unlink(missing_ok=True)
    run_script()


def test_hourly_averages_file_exists():
    path = "/home/user/hourly_averages.txt"
    assert os.path.isfile(path), f"File {path} does not exist. Ensure the script was run and generated the output file."


def test_hourly_averages_content():
    path = "/home/user/hourly_averages.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    expected_lines = [
        "Hour: 00, Avg: 100",
        "Hour: 01, Avg: 250",
        "Hour: 02, Avg: 150",
        "Hour: 11, Avg: 120",
        "Hour: 12, Avg: 140",
        "Hour: 17, Avg: 50"
    ]

    with open(path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Content of {path} does not match expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )


def test_script_processes_unseen_logs_correctly():
    original_logs = LOGS.read_bytes()
    original_output = OUTPUT.read_bytes()
    rng = secrets.SystemRandom()

    records = []
    expected_values = {hour: [] for hour in range(24)}
    for utc_hour in range(24):
        for item in range(1 + (utc_hour % 3)):
            response_time = rng.randrange(11, 5000)
            minute = (utc_hour * 7 + item * 13) % 60
            second = (utc_hour * 11 + item * 17) % 60
            records.append(
                f"2024-02-03 {utc_hour:02d}:{minute:02d}:{second:02d} "
                f"[INFO] ResponseTime: {response_time}"
            )
            expected_values[(utc_hour + 3) % 24].append(response_time)

    rng.shuffle(records)
    expected_lines = [
        f"Hour: {hour:02d}, Avg: {sum(expected_values[hour]) // len(expected_values[hour])}"
        for hour in range(24)
    ]

    try:
        LOGS.write_text("\n".join(records) + "\n")
        OUTPUT.unlink(missing_ok=True)
        run_script()
        assert OUTPUT.is_file(), f"{SCRIPT} did not generate {OUTPUT}."
        actual_lines = [line.strip() for line in OUTPUT.read_text().splitlines() if line.strip()]
        assert actual_lines == expected_lines, (
            "The script did not correctly aggregate unseen input, parse zero-padded "
            "hours, and apply UTC+3 with midnight wraparound.\n"
            f"Expected:\n{chr(10).join(expected_lines)}\n\n"
            f"Actual:\n{chr(10).join(actual_lines)}"
        )
    finally:
        LOGS.write_bytes(original_logs)
        OUTPUT.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
