#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import subprocess
import tempfile
import time
import pytest

FILTER_SCRIPT = "/home/user/deploy_filter.py"
APPLY_SCRIPT = "/home/user/apply_config.sh"
SERVICE_DIR = "/home/user/deploy_service"
CONFIG_FILE = os.path.join(SERVICE_DIR, "config.ini")
DAEMON_SCRIPT = os.path.join(SERVICE_DIR, "mock_daemon.sh")
PID_FILE = os.path.join(SERVICE_DIR, "daemon.pid")


def run_filter(path):
    return subprocess.run(
        ["python3", FILTER_SCRIPT, path],
        capture_output=True,
        text=True,
        timeout=5,
    )


def process_is_live(pid):
    try:
        os.kill(pid, 0)
        with open(f"/proc/{pid}/stat", "r") as f:
            return f.read().split()[2] != "Z"
    except (OSError, FileNotFoundError, IndexError):
        return False


def read_pid():
    assert os.path.isfile(PID_FILE), f"PID file missing: {PID_FILE}"
    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file does not contain a valid PID: {pid_str}"
    return int(pid_str)


def test_filter_script_behavior():
    """Verify classification of the supplied corpora."""
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script missing: {FILTER_SCRIPT}"

    clean_dir = "/home/user/configs/clean"
    evil_dir = "/home/user/configs/evil"
    clean_files = [os.path.join(clean_dir, f) for f in os.listdir(clean_dir)
                   if os.path.isfile(os.path.join(clean_dir, f))]
    evil_files = [os.path.join(evil_dir, f) for f in os.listdir(evil_dir)
                  if os.path.isfile(os.path.join(evil_dir, f))]

    clean_failed = []
    for cf in clean_files:
        result = run_filter(cf)
        if result.stdout.strip() != "ACCEPT":
            clean_failed.append(os.path.basename(cf))

    evil_failed = []
    for ef in evil_files:
        result = run_filter(ef)
        if result.stdout.strip() != "REJECT":
            evil_failed.append(os.path.basename(ef))

    error_msgs = []
    if evil_failed:
        error_msgs.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        error_msgs.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")
    assert not error_msgs, " | ".join(error_msgs)


def test_filter_on_unseen_mixed_paths():
    """Exercise equivalent unseen inputs at opaque paths so pathname lookup cannot pass."""
    assert os.path.isfile(FILTER_SCRIPT), f"Filter script missing: {FILTER_SCRIPT}"

    with tempfile.TemporaryDirectory(prefix="preflight-") as td:
        cases = []
        for i in range(24):
            quota = secrets.randbelow(1000) + 1
            mount_id = 10000 + secrets.randbelow(900000)
            cases.append((
                "ACCEPT",
                f"IMAGE=ubuntu:latest\nDISK_QUOTA={quota}\nMOUNT_POINT=/var/lib/data{mount_id}\n",
            ))
        for i in range(12):
            mount_id = 10000 + secrets.randbelow(900000)
            cases.append((
                "REJECT",
                f"IMAGE=ubuntu:latest\nDISK_QUOTA=0x7FFFFFFF\nMOUNT_POINT=/var/lib/data{mount_id}\n",
            ))
        for i in range(12):
            quota = secrets.randbelow(1000) + 1
            cases.append((
                "REJECT",
                f"IMAGE=ubuntu:latest\nDISK_QUOTA={quota}\nMOUNT_POINT=/var/lib/data/../../etc/shadow\n",
            ))

        # Labels are deliberately unrelated to directory or filename.
        for expected, content in cases:
            path = os.path.join(td, secrets.token_hex(16))
            with open(path, "w") as f:
                f.write(content)
            result = run_filter(path)
            assert result.returncode == 0, f"Filter failed for an ordinary readable config: {result.stderr}"
            assert result.stdout.strip() == expected, f"Expected {expected} for unseen input at {path}"


def test_integration_script_effects_and_idempotence():
    """Execute apply_config.sh twice and verify creation, restart, and no duplication."""
    assert os.path.isfile(APPLY_SCRIPT), f"Integration script missing: {APPLY_SCRIPT}"

    # Require this script, rather than pre-created state, to produce the integration artifacts.
    shutil.rmtree(SERVICE_DIR, ignore_errors=True)

    first = subprocess.run(
        ["bash", APPLY_SCRIPT], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        text=True, timeout=10,
    )
    assert first.returncode == 0, f"First apply_config.sh run failed: {first.stderr}"

    assert os.path.isdir(SERVICE_DIR), f"Service directory missing: {SERVICE_DIR}/"
    assert os.path.isfile(CONFIG_FILE), f"Config file missing: {CONFIG_FILE}"
    assert os.path.isfile(DAEMON_SCRIPT), f"Mock daemon script missing: {DAEMON_SCRIPT}"

    with open(CONFIG_FILE, "r") as f:
        content = f.read()
    assert "PreflightFilter=/home/user/deploy_filter.py" in content, "PreflightFilter not found in config.ini"
    assert content.splitlines().count("PreflightFilter=/home/user/deploy_filter.py") == 1, "PreflightFilter line is duplicated"

    first_pid = read_pid()
    assert process_is_live(first_pid), f"Daemon process with PID {first_pid} is not running"

    second = subprocess.run(
        ["bash", APPLY_SCRIPT], stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
        text=True, timeout=10,
    )
    assert second.returncode == 0, f"Second apply_config.sh run failed: {second.stderr}"

    assert os.path.isdir(SERVICE_DIR), f"Service directory missing: {SERVICE_DIR}/"
    assert os.path.isfile(CONFIG_FILE), f"Config file missing: {CONFIG_FILE}"
    assert os.path.isfile(DAEMON_SCRIPT), f"Mock daemon script missing: {DAEMON_SCRIPT}"
    with open(CONFIG_FILE, "r") as f:
        content = f.read()
    assert "PreflightFilter=/home/user/deploy_filter.py" in content, "PreflightFilter not found in config.ini"
    assert content.splitlines().count("PreflightFilter=/home/user/deploy_filter.py") == 1, "Repeated application duplicated PreflightFilter"

    second_pid = read_pid()
    assert second_pid != first_pid, "Repeated application did not restart the daemon"
    assert process_is_live(second_pid), f"Daemon process with PID {second_pid} is not running"

    deadline = time.time() + 3
    while time.time() < deadline and process_is_live(first_pid):
        time.sleep(0.05)
    assert not process_is_live(first_pid), f"Old daemon process with PID {first_pid} was not stopped"

    with open(f"/proc/{second_pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\x00", b" ").decode(errors="replace")
    assert DAEMON_SCRIPT in cmdline, f"PID {second_pid} is not the required mock_daemon.sh process"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
