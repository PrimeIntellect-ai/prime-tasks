#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import base64
import secrets
import pytest

REPORT_PATH = "/home/user/uptime_report.txt"
SCRIPT_PATH = "/home/user/uptime_monitor.sh"
LOG_PATH = "/home/user/logs/ping_data.b64"


def run_script():
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=10)
    assert result.returncode == 0, f"Script failed to run. stderr: {result.stderr}"
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} was not created"
    with open(REPORT_PATH, "r") as f:
        return f.read().strip()


def test_uptime_report_exists():
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} does not exist. Did you run the script?"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist"
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable"


def test_uptime_report_content():
    with open(REPORT_PATH, 'r') as f:
        content = f.read().strip()
    assert content == "Uptime: 75%", f"Expected 'Uptime: 75%', but got '{content}'"


def test_script_dynamic_calculation():
    # Preserve the original fixed dynamic check.
    new_log_data = b"1600000000,1\r\n1600000060,0\r\n1600000120,0\r\n1600000180,1\r\n"
    encoded_log = base64.b64encode(new_log_data)

    with open(LOG_PATH, 'rb') as f:
        original_log = f.read()

    try:
        with open(LOG_PATH, 'wb') as f:
            f.write(encoded_log)

        result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True, timeout=10)
        assert result.returncode == 0, f"Script failed to run with new data. stderr: {result.stderr}"

        with open(REPORT_PATH, 'r') as f:
            content = f.read().strip()
        assert content == "Uptime: 50%", f"Script appears to have hardcoded output or failed to calculate correctly. Expected 'Uptime: 50%', got '{content}'"
    finally:
        with open(LOG_PATH, 'wb') as f:
            f.write(original_log)
        subprocess.run([SCRIPT_PATH], capture_output=True, timeout=10)


def test_script_on_runtime_generated_logs():
    rng = secrets.SystemRandom()
    with open(LOG_PATH, "rb") as f:
        original_log = f.read()

    tested_percentages = set()
    try:
        for _ in range(7):
            while True:
                total = rng.randint(3, 25)
                successes = rng.randint(0, total)
                expected = successes * 100 // total
                if expected not in {50, 75} and expected not in tested_percentages:
                    tested_percentages.add(expected)
                    break

            statuses = [1] * successes + [0] * (total - successes)
            rng.shuffle(statuses)
            start = rng.randint(1500000000, 1900000000)
            decoded = b"".join(
                f"{start + index * 60},{status}\r\n".encode("ascii")
                for index, status in enumerate(statuses)
            )
            with open(LOG_PATH, "wb") as f:
                f.write(base64.b64encode(decoded))

            content = run_script()
            assert content == f"Uptime: {expected}%", (
                f"For {successes} successful pings out of {total}, expected "
                f"'Uptime: {expected}%', got '{content}'"
            )
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)
        subprocess.run([SCRIPT_PATH], capture_output=True, timeout=10)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
