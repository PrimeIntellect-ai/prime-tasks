#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess

SCRIPT_PATH = "/home/user/generate_alerts.py"
LOG_PATH = "/home/user/fw_logs.txt"
ALERTS_PATH = "/home/user/alerts.txt"
EXPECTED_INITIAL_IPS = ["10.0.0.7", "10.1.1.1", "192.168.1.100"]


def read_alerts():
    assert os.path.isfile(ALERTS_PATH), f"Alerts file not found at {ALERTS_PATH}"
    with open(ALERTS_PATH, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def run_script():
    return subprocess.run(
        ["python3", SCRIPT_PATH],
        capture_output=True,
        text=True,
        timeout=10,
    )


def test_script_exists():
    """Check if the student created the required Python script."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"


def test_alerts_generated_correctly():
    """Check the initially generated alerts file."""
    lines = read_alerts()
    assert lines == EXPECTED_INITIAL_IPS, (
        f"Contents of {ALERTS_PATH} are incorrect. "
        f"Expected {EXPECTED_INITIAL_IPS}, but got {lines}."
    )


def test_script_processes_existing_log():
    """Execute the script against the supplied log and check its output."""
    result = run_script()
    assert result.returncode == 0, (
        f"Script returned non-zero exit code {result.returncode}. Stderr: {result.stderr}"
    )
    lines = read_alerts()
    assert lines == EXPECTED_INITIAL_IPS, (
        f"After executing the script, expected {EXPECTED_INITIAL_IPS}, but got {lines}."
    )


def test_script_parses_unseen_log_contents():
    """Exercise the parser with unpredictable matching and non-matching entries."""
    with open(LOG_PATH, "rb") as f:
        original_log = f.read()

    used = set()

    def random_ip():
        while True:
            ip = ".".join(str(secrets.randbelow(254) + 1) for _ in range(4))
            if ip not in used:
                used.add(ip)
                return ip

    matching = [random_ip() for _ in range(4)]
    nonmatching = [random_ip() for _ in range(5)]
    entries = [
        f"[2025-04-01 12:00:00] ERROR: Port forwarding failed IP:{matching[0]} PORT:8080 - Rule blocked",
        f"[2025-04-01 12:00:01] ERROR: Port forwarding failed IP:{matching[1]} PORT:8080 - Timeout",
        f"[2025-04-01 12:00:02] ERROR: Port forwarding failed IP:{matching[2]} PORT:8080 - Rule blocked",
        f"[2025-04-01 12:00:03] ERROR: Port forwarding failed IP:{matching[3]} PORT:8080 - Other reason",
        f"[2025-04-01 12:00:04] ERROR: Port forwarding failed IP:{matching[1]} PORT:8080 - Duplicate",
        f"[2025-04-01 12:00:05] INFO: Port forwarding failed IP:{nonmatching[0]} PORT:8080 - Wrong level",
        f"[2025-04-01 12:00:06] WARNING: Port forwarding failed IP:{nonmatching[1]} PORT:8080 - Wrong level",
        f"[2025-04-01 12:00:07] ERROR: Port forwarding succeeded IP:{nonmatching[2]} PORT:8080 - Wrong message",
        f"[2025-04-01 12:00:08] ERROR: Port forwarding failed IP:{nonmatching[3]} PORT:8081 - Wrong port",
        f"[2025-04-01 12:00:09] ERROR: Port forwarding failure IP:{nonmatching[4]} PORT:8080 - Near match",
    ]
    secrets.SystemRandom().shuffle(entries)

    try:
        with open(LOG_PATH, "w") as f:
            f.write("\n".join(entries) + "\n")

        result = run_script()
        assert result.returncode == 0, (
            f"Script returned non-zero exit code {result.returncode} on unseen input. "
            f"Stderr: {result.stderr}"
        )
        expected = sorted(set(matching))
        actual = read_alerts()
        assert actual == expected, (
            f"Script did not correctly parse unseen log contents. "
            f"Expected {expected}, but got {actual}."
        )
    finally:
        with open(LOG_PATH, "wb") as f:
            f.write(original_log)


def test_script_robustness_missing_log():
    """Check if the script handles a missing log file gracefully."""
    assert os.path.isfile(SCRIPT_PATH), f"Script not found at {SCRIPT_PATH}"

    backup_path = "/home/user/fw_logs.txt.bak"
    if os.path.isfile(backup_path):
        os.remove(backup_path)
    if os.path.isfile(LOG_PATH):
        os.rename(LOG_PATH, backup_path)

    try:
        result = run_script()
        assert result.returncode == 0, (
            f"Script crashed or returned non-zero exit code ({result.returncode}) "
            f"when {LOG_PATH} was missing. Stderr: {result.stderr}"
        )
        assert os.path.isfile(ALERTS_PATH), (
            f"Script did not create {ALERTS_PATH} when log file was missing."
        )
        assert os.path.getsize(ALERTS_PATH) == 0, (
            f"{ALERTS_PATH} should be empty when log file is missing."
        )
    finally:
        if os.path.isfile(backup_path):
            os.rename(backup_path, LOG_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
