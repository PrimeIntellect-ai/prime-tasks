#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
import uuid

import pytest

SCRIPT_PATH = "/home/user/analyze_auth.py"
LOG_PATH = "/home/user/auth.log"
ROUTES_PATH = "/home/user/block_routes.sh"


def test_block_routes_script_exists_and_executable():
    assert os.path.isfile(ROUTES_PATH), f"File {ROUTES_PATH} does not exist."

    st = os.stat(ROUTES_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"File {ROUTES_PATH} is not executable."


def test_block_routes_content():
    assert os.path.isfile(ROUTES_PATH), f"File {ROUTES_PATH} does not exist."

    with open(ROUTES_PATH, "r") as f:
        content = f.read()

    expected_lines = [
        "ip route add blackhole 192.168.1.50",
        "ip route add blackhole 172.16.0.10",
    ]

    for line in expected_lines:
        assert line in content, f"Expected command '{line}' not found in {ROUTES_PATH}."

    unexpected_line = "ip route add blackhole 10.0.0.5"
    assert unexpected_line not in content, f"Unexpected command '{unexpected_line}' found in {ROUTES_PATH}."


def test_cron_job_configured():
    try:
        output = subprocess.check_output(
            ["crontab", "-l"], stderr=subprocess.STDOUT, text=True
        )
    except subprocess.CalledProcessError:
        pytest.fail("crontab -l failed, cron job might not be configured.")

    pattern = r"^\s*(?:\*/5|0-59/5)\s+\*\s+\*\s+\*\s+\*\s+/usr/bin/python3\s+/home/user/analyze_auth\.py\s*$"
    assert any(re.match(pattern, line) for line in output.splitlines()), (
        "Cron job for analyze_auth.py every 5 minutes was not found in crontab."
    )


def test_python_script_processes_dynamic_sessions():
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} does not exist."

    token = uuid.uuid4().hex
    log_backup = f"/tmp/auth.log.{token}"
    routes_backup = f"/tmp/block_routes.sh.{token}"
    had_log = os.path.exists(LOG_PATH)
    had_routes = os.path.exists(ROUTES_PATH)

    if had_log:
        os.rename(LOG_PATH, log_backup)
    if had_routes:
        os.rename(ROUTES_PATH, routes_backup)

    base = secrets.randbelow(180) + 20
    ips = [f"198.18.{base}.{n}" for n in range(31, 36)]
    rejected, accepted, accepted_then_closed, no_offer, wrong_pid_accept = ips
    pid = secrets.randbelow(20000) + 20000

    fixture = "\n".join([
        f"12:00:01 sshd[{pid}]: Connection from {rejected}",
        f"12:00:02 sshd[{pid + 1}]: Connection from {accepted}",
        f"12:00:03 sshd[{pid}]: Offering public key: RSA SHA256:random-a",
        f"12:00:04 sshd[{pid + 1}]: Offering public key: RSA SHA256:random-b",
        f"12:00:05 sshd[{pid + 1}]: Accepted publickey for user from {accepted}",
        f"12:00:06 sshd[{pid}]: Connection closed by {rejected}",
        f"12:00:07 sshd[{pid + 2}]: Connection from {accepted_then_closed}",
        f"12:00:08 sshd[{pid + 2}]: Offering public key: RSA SHA256:random-c",
        f"12:00:09 sshd[{pid + 2}]: Accepted publickey for user from {accepted_then_closed}",
        f"12:00:10 sshd[{pid + 2}]: Connection closed by {accepted_then_closed}",
        f"12:00:11 sshd[{pid + 3}]: Connection from {no_offer}",
        f"12:00:12 sshd[{pid + 3}]: Connection closed by {no_offer}",
        f"12:00:13 sshd[{pid + 4}]: Connection from {wrong_pid_accept}",
        f"12:00:14 sshd[{pid + 4}]: Offering public key: RSA SHA256:random-d",
        f"12:00:15 sshd[{pid + 5}]: Accepted publickey for user from {wrong_pid_accept}",
        f"12:00:16 sshd[{pid + 4}]: Connection closed by {wrong_pid_accept}",
        f"12:00:17 sshd[{pid + 6}]: Connection from {rejected}",
        f"12:00:18 sshd[{pid + 6}]: Offering public key: RSA SHA256:random-e",
        f"12:00:19 sshd[{pid + 6}]: Connection closed by {rejected}",
        "",
    ])

    try:
        with open(LOG_PATH, "w") as f:
            f.write(fixture)

        result = subprocess.run(
            ["/usr/bin/python3", SCRIPT_PATH],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Script failed on a valid dynamic log: {result.stdout}{result.stderr}"
        )
        assert os.path.isfile(ROUTES_PATH), "Script did not create block_routes.sh."
        assert os.stat(ROUTES_PATH).st_mode & stat.S_IXUSR, (
            "Dynamically created block_routes.sh is not executable."
        )

        with open(ROUTES_PATH, "r") as f:
            command_lines = [
                line.strip()
                for line in f
                if line.strip().startswith("ip route add blackhole ")
            ]

        expected = {
            f"ip route add blackhole {rejected}",
            f"ip route add blackhole {wrong_pid_accept}",
        }
        assert set(command_lines) == expected, (
            f"Incorrect routes for dynamic sessions: {command_lines!r}"
        )
        assert len(command_lines) == len(expected), (
            "Each silently rejected IP must be emitted only once."
        )
    finally:
        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)
        if os.path.exists(ROUTES_PATH):
            os.remove(ROUTES_PATH)
        if had_log:
            os.rename(log_backup, LOG_PATH)
        if had_routes:
            os.rename(routes_backup, ROUTES_PATH)


def test_python_script_missing_log_handling():
    assert os.path.isfile(SCRIPT_PATH), f"Python script {SCRIPT_PATH} does not exist."

    token = uuid.uuid4().hex
    log_backup = f"/tmp/auth.log.missing.{token}"
    routes_backup = f"/tmp/block_routes.sh.missing.{token}"
    had_log = os.path.exists(LOG_PATH)
    had_routes = os.path.exists(ROUTES_PATH)

    if had_log:
        os.rename(LOG_PATH, log_backup)
    if had_routes:
        os.rename(ROUTES_PATH, routes_backup)

    try:
        result = subprocess.run(
            ["/usr/bin/python3", SCRIPT_PATH],
            capture_output=True,
            text=True,
            timeout=15,
        )

        assert result.returncode == 0, (
            f"Script exited with non-zero code {result.returncode} when log is missing."
        )
        assert "Log not found" in result.stdout, (
            "Script did not print 'Log not found' when log is missing."
        )
        assert not os.path.exists(ROUTES_PATH), (
            "Script created block_routes.sh even though auth.log was missing."
        )
    finally:
        if os.path.exists(LOG_PATH):
            os.remove(LOG_PATH)
        if os.path.exists(ROUTES_PATH):
            os.remove(ROUTES_PATH)
        if had_log:
            os.rename(log_backup, LOG_PATH)
        if had_routes:
            os.rename(routes_backup, ROUTES_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
