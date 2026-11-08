#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import sys
import time
import pytest
import shlex
import re


def test_config_json_updated():
    config_path = "/home/user/app/config.json"
    assert os.path.isfile(config_path), f"{config_path} is missing"
    with open(config_path, "r") as f:
        data = json.load(f)

    assert data.get("host") == "127.0.0.55", f"Expected host '127.0.0.55', got {data.get('host')}"
    assert str(data.get("port")) == "9090", f"Expected port 9090, got {data.get('port')}"


def test_auth_json_updated():
    auth_path = "/home/user/app/auth.json"
    assert os.path.isfile(auth_path), f"{auth_path} is missing"
    with open(auth_path, "r") as f:
        data = json.load(f)

    users = data.get("users", {})
    assert "svc_ingest" in users, "'svc_ingest' user missing from auth.json"
    groups = users["svc_ingest"].get("groups", [])
    assert "network_admins" in groups, "'svc_ingest' is not in the 'network_admins' group"


def test_daemon_startup_check_optimized():
    daemon_dir = "/home/user/app"
    if daemon_dir not in sys.path:
        sys.path.append(daemon_dir)

    try:
        import daemon
    except ImportError as e:
        pytest.fail(f"Could not import daemon.py: {e}")

    start = time.perf_counter()
    res = daemon.startup_check()
    end = time.perf_counter()

    elapsed = end - start
    assert elapsed <= 0.5, f"Execution too slow: {elapsed}s (Threshold is <= 0.5s)"
    assert res == 4950, f"The optimized function returned an incorrect mathematical result: {res} (Expected 4950)"


def _command_invokes_health_ping(command):
    try:
        tokens = shlex.split(command, posix=True)
    except ValueError:
        return False

    # Permit shell-style environment assignments before the actual command.
    while tokens and re.fullmatch(r"[A-Za-z_][A-Za-z0-9_]*=.*", tokens[0]):
        tokens.pop(0)

    script = "/home/user/app/health_ping.py"
    if tokens and tokens[0] == script:
        return True

    # Also permit explicitly invoking the Python script with a Python interpreter.
    if len(tokens) >= 2 and os.path.basename(tokens[0]) in {"python", "python3"} and tokens[1] == script:
        return True

    # Permit the common portable form: /usr/bin/env python3 SCRIPT.
    if len(tokens) >= 3 and os.path.basename(tokens[0]) == "env" and os.path.basename(tokens[1]) in {"python", "python3"} and tokens[2] == script:
        return True

    return False


def test_cron_job_configured():
    try:
        # Check crontab for the current user
        output = subprocess.check_output(["crontab", "-l"], text=True, stderr=subprocess.STDOUT)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Could not read crontab or no crontab configured. Output: {e.output}")

    found = False
    for raw_line in output.splitlines():
        line = raw_line.strip()
        if not line or line.startswith("#"):
            continue

        # Parse the five cron schedule fields separately from the command.
        fields = line.split(None, 5)
        if len(fields) != 6:
            continue

        minute, hour, day_of_month, month, day_of_week, command = fields
        schedule_is_every_five_minutes = (
            minute == "*/5"
            and hour == "*"
            and day_of_month == "*"
            and month == "*"
            and day_of_week == "*"
        )

        if schedule_is_every_five_minutes and _command_invokes_health_ping(command):
            found = True
            break

    assert found, "Cron job must invoke /home/user/app/health_ping.py exactly every 5 minutes."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
