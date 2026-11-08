#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import subprocess
import time
import uuid
import pytest

START_SERVICES_SCRIPT = "/home/user/start_services.py"
MIGRATION_LOG = "/home/user/migration.log"
MOCK_QEMU = "/home/user/mock_qemu.py"
EXPECTED_LOG_CONTENT = "STATUS: [SUCCESS] VM state exported"
PROBE_TOKEN = uuid.uuid4().hex
PROBE_LOG = f"/tmp/mock_qemu_probe_{uuid.uuid4().hex}.log"

PROBE_SOURCE = f'''#!/usr/bin/env python3
import select
import sys
import time

TOKEN = {PROBE_TOKEN!r}
EVENT_LOG = {PROBE_LOG!r}

def event(value):
    with open(EVENT_LOG, "a", encoding="utf-8") as f:
        f.write(TOKEN + ":" + value + "\\n")
        f.flush()

def wait_without_input(seconds):
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        remaining = deadline - time.monotonic()
        readable, _, _ = select.select([sys.stdin], [], [], min(0.05, remaining))
        if readable:
            value = sys.stdin.readline().rstrip("\\n")
            event("EARLY:" + value)
            print("[ERROR] Command received before VNC readiness", flush=True)
            sys.exit(1)

event("LAUNCHED")
print("[INFO] Booting VM...", flush=True)
wait_without_input(1.0)
print("[INFO] Loading drivers...", flush=True)
wait_without_input(1.0)
print("[INFO] VNC server running on 127.0.0.1:5900", flush=True)
event("READY")
readable, _, _ = select.select([sys.stdin], [], [], 5.0)
if not readable:
    event("NO_COMMAND")
    print("[ERROR] Timed out waiting for command", flush=True)
    sys.exit(1)
cmd = sys.stdin.readline().strip()
event("COMMAND:" + cmd)
if cmd != "MIGRATE":
    print("[ERROR] Unknown command: " + cmd, flush=True)
    sys.exit(1)
time.sleep(0.5)
print("[SUCCESS] VM state exported", flush=True)
event("SUCCESS")
'''

@pytest.fixture(scope="session", autouse=True)
def instrument_mock_qemu():
    with open(MOCK_QEMU, "rb") as f:
        original = f.read()
    original_mode = stat.S_IMODE(os.stat(MOCK_QEMU).st_mode)
    with open(MOCK_QEMU, "w", encoding="utf-8") as f:
        f.write(PROBE_SOURCE)
    os.chmod(MOCK_QEMU, 0o755)
    try:
        yield
    finally:
        with open(MOCK_QEMU, "wb") as f:
            f.write(original)
        os.chmod(MOCK_QEMU, original_mode)
        if os.path.exists(PROBE_LOG):
            os.remove(PROBE_LOG)

def test_start_services_script_exists():
    """Test that the start_services.py script exists."""
    assert os.path.isfile(START_SERVICES_SCRIPT), f"Missing file: {START_SERVICES_SCRIPT}"

def test_migration_log_exists_and_correct():
    """Test that the migration.log exists and contains the correct status."""
    assert os.path.isfile(MIGRATION_LOG), f"Missing file: {MIGRATION_LOG}. The script may not have been run or failed to create the log."
    with open(MIGRATION_LOG, "r") as f:
        content = f.read().strip()
    assert EXPECTED_LOG_CONTENT in content, f"Log content incorrect. Expected to find '{EXPECTED_LOG_CONTENT}' in {MIGRATION_LOG}"

def test_idempotency():
    """Test that the script is idempotent, exits quickly, and does not launch the VM."""
    if os.path.exists(PROBE_LOG):
        os.remove(PROBE_LOG)
    with open(MIGRATION_LOG, "w") as f:
        f.write(EXPECTED_LOG_CONTENT + "\n")

    start_time = time.time()
    result = subprocess.run(
        ["python3", START_SERVICES_SCRIPT],
        capture_output=True,
        text=True,
        timeout=3
    )
    duration = time.time() - start_time

    assert result.returncode == 0, f"Script failed during idempotency check. Stderr: {result.stderr}"
    assert duration < 1.0, "Script took too long during idempotency check. It should exit immediately."
    assert not os.path.exists(PROBE_LOG), "The mock VM was launched despite an existing success log."

def test_full_execution():
    """Test actual process supervision, readiness synchronization, and command delivery."""
    if os.path.exists(MIGRATION_LOG):
        os.remove(MIGRATION_LOG)
    if os.path.exists(PROBE_LOG):
        os.remove(PROBE_LOG)

    start_time = time.time()
    result = subprocess.run(
        ["python3", START_SERVICES_SCRIPT],
        capture_output=True,
        text=True,
        timeout=10
    )
    duration = time.time() - start_time

    assert result.returncode == 0, f"Script failed during full execution. Stderr: {result.stderr}"
    assert duration >= 2.0, "Script finished too quickly. It must wait for the VNC server to initialize before sending the command."

    assert os.path.isfile(MIGRATION_LOG), "Script failed to create migration.log after full execution."
    with open(MIGRATION_LOG, "r") as f:
        content = f.read().strip()
    assert EXPECTED_LOG_CONTENT in content, f"Log content incorrect after full execution. Expected to find '{EXPECTED_LOG_CONTENT}'"
    assert content == EXPECTED_LOG_CONTENT, "migration.log must contain exactly the captured final status line in STATUS: <line> format."

    assert os.path.isfile(PROBE_LOG), "The required /home/user/mock_qemu.py process was not launched."
    with open(PROBE_LOG, "r", encoding="utf-8") as f:
        events = [line.strip() for line in f if line.strip()]
    expected_events = [
        PROBE_TOKEN + ":LAUNCHED",
        PROBE_TOKEN + ":READY",
        PROBE_TOKEN + ":COMMAND:MIGRATE",
        PROBE_TOKEN + ":SUCCESS",
    ]
    assert events == expected_events, (
        "Incorrect VM interaction. The script must launch mock_qemu.py, send no input "
        "before the VNC readiness line, then send exactly MIGRATE. Events: " + repr(events)
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
