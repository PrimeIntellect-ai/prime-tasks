#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import socket
import subprocess
import tempfile
import time
import uuid

import pytest

REPO = "/home/user/dashboards.git"
HOOK = REPO + "/hooks/post-receive"
LOG = "/home/user/dashboard_alerts.log"
PID_FILE = "/home/user/alert_service.pid"
PROJECT = "/home/user/alert_service"
BINARY = PROJECT + "/target/release/alert_service"
EXPECTED_ALERT = "ALERT: Dashboards updated\n"


def read_log():
    if not os.path.isfile(LOG):
        return ""
    with open(LOG, "r", encoding="utf-8") as f:
        return f.read()


def wait_for_log_tail(before, expected, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        content = read_log()
        if content.startswith(before) and content[len(before):] == expected:
            return
        time.sleep(0.05)
    content = read_log()
    assert content.startswith(before), "Alert log was unexpectedly rewritten."
    assert content[len(before):] == expected, (
        f"Expected newly appended log data {expected!r}, got {content[len(before):]!r}."
    )


def run_git(args, cwd=None):
    return subprocess.run(
        ["git"] + args,
        cwd=cwd,
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )


def test_bare_repo_exists():
    """Verify the bare git repository exists."""
    assert os.path.isdir(REPO + "/objects"), "Bare Git repository at /home/user/dashboards.git does not exist or is not a bare repo."


def test_hook_executable():
    """Verify the post-receive hook exists, is executable, and is a bash hook."""
    assert os.path.isfile(HOOK), f"Hook file {HOOK} does not exist."
    assert os.access(HOOK, os.X_OK), f"Hook file {HOOK} is not executable."
    with open(HOOK, "r", encoding="utf-8") as f:
        hook_text = f.read()
    first_line = hook_text.splitlines()[0] if hook_text.splitlines() else ""
    assert re.match(r"^#!.*(?:/|\s)bash(?:\s|$)", first_line), "post-receive is not a bash script."
    assert "git diff-tree" in hook_text, "post-receive does not use git diff-tree."


def test_alert_service_running():
    """Verify the Rust release service is the recorded process and owns the TCP listener."""
    assert os.path.isfile(PROJECT + "/Cargo.toml"), "Rust project Cargo.toml is missing."
    assert os.path.isfile(PROJECT + "/src/main.rs"), "Rust project src/main.rs is missing."
    assert os.path.isfile(BINARY), "Built release alert_service binary is missing."
    assert os.access(BINARY, os.X_OK), "Built release alert_service binary is not executable."
    assert os.path.isfile(PID_FILE), f"PID file {PID_FILE} does not exist."

    with open(PID_FILE, "r") as f:
        pid_str = f.read().strip()
    assert pid_str.isdigit(), f"PID file {PID_FILE} does not contain a valid numeric PID."
    pid = int(pid_str)

    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail(f"Process with PID {pid} from {PID_FILE} is not running.")

    try:
        assert os.path.samefile(f"/proc/{pid}/exe", BINARY), (
            "The PID file does not identify the built release alert_service binary."
        )
    except FileNotFoundError:
        pytest.fail("The recorded alert service process or release binary is missing.")

    listener_inodes = set()
    with open("/proc/net/tcp", "r") as f:
        for line in f.readlines()[1:]:
            fields = line.split()
            local, state, inode = fields[1], fields[3], fields[9]
            if local.upper() == "0100007F:09DD" and state == "0A":
                listener_inodes.add(inode)
    assert listener_inodes, "No process is listening on 127.0.0.1:2525."

    owned = set()
    for fd in os.listdir(f"/proc/{pid}/fd"):
        try:
            target = os.readlink(f"/proc/{pid}/fd/{fd}")
        except OSError:
            continue
        match = re.fullmatch(r"socket:\[(\d+)\]", target)
        if match:
            owned.add(match.group(1))
    assert listener_inodes & owned, "The recorded alert service process does not own the 127.0.0.1:2525 listener."


def test_alert_log_content():
    """Verify the dashboard commit triggered the alert log."""
    assert os.path.isfile(LOG), f"Log file {LOG} does not exist."
    content = read_log()
    assert "ALERT: Dashboards updated" in content, f"Log file {LOG} does not contain the expected alert string."


def test_work_repo_content():
    """Verify the clone exists and contains the correct dashboard."""
    dashboard_file = "/home/user/dashboards_work/network_dashboard.json"
    assert os.path.isfile(dashboard_file), f"Dashboard file {dashboard_file} does not exist."
    with open(dashboard_file, "r") as f:
        content = f.read()
    assert "Network Metrics" in content, f"Dashboard file {dashboard_file} does not contain 'Network Metrics'."
    try:
        data = json.loads(content)
        assert data.get("title") == "Network Metrics", "JSON title is not 'Network Metrics'."
    except json.JSONDecodeError:
        pytest.fail(f"Dashboard file {dashboard_file} does not contain valid JSON.")


def test_service_tcp_behavior():
    """Exercise the service with verifier-generated non-alert and alert messages."""
    token = uuid.uuid4().hex
    before = read_log()

    with socket.create_connection(("127.0.0.1", 2525), timeout=2) as sock:
        sock.sendall(f"NOTICE: {token}\n".encode("utf-8"))
        sock.shutdown(socket.SHUT_WR)
    time.sleep(0.4)
    assert read_log() == before, "The service logged a string that did not start with 'ALERT: '."

    message = f"ALERT: verifier-{token}"
    with socket.create_connection(("127.0.0.1", 2525), timeout=2) as sock:
        sock.sendall((message + "\n\n").encode("utf-8"))
        sock.shutdown(socket.SHUT_WR)
    wait_for_log_tail(before, message + "\n")


def test_post_receive_pipeline_on_real_pushes():
    """Push non-JSON and JSON changes and verify the hook's actual behavior."""
    with tempfile.TemporaryDirectory(prefix="dashboard-verifier-") as tmp:
        work = os.path.join(tmp, "work")
        run_git(["clone", REPO, work])
        run_git(["checkout", "master"], cwd=work)
        run_git(["config", "user.email", "verifier@example.invalid"], cwd=work)
        run_git(["config", "user.name", "Pipeline Verifier"], cwd=work)

        token = uuid.uuid4().hex

        # A non-JSON-only push must not produce an alert.
        with open(os.path.join(work, f"notes-{token}.txt"), "w") as f:
            f.write(token + "\n")
        run_git(["add", "."], cwd=work)
        run_git(["commit", "-m", f"verifier non-json {token}"], cwd=work)
        before = read_log()
        run_git(["push", "origin", "HEAD:master"], cwd=work)
        time.sleep(0.75)
        assert read_log() == before, "A push containing only a non-JSON change incorrectly produced an alert."

        # Adding a JSON file must produce exactly the required alert.
        dashboard = os.path.join(work, f"verifier-{token}.json")
        with open(dashboard, "w") as f:
            json.dump({"title": token, "revision": 1}, f)
        run_git(["add", "."], cwd=work)
        run_git(["commit", "-m", f"verifier json add {token}"], cwd=work)
        before = read_log()
        run_git(["push", "origin", "HEAD:master"], cwd=work)
        wait_for_log_tail(before, EXPECTED_ALERT)

        # Modifying an existing JSON file must also produce exactly one alert.
        with open(dashboard, "w") as f:
            json.dump({"title": token, "revision": 2}, f)
        run_git(["add", "."], cwd=work)
        run_git(["commit", "-m", f"verifier json modify {token}"], cwd=work)
        before = read_log()
        run_git(["push", "origin", "HEAD:master"], cwd=work)
        wait_for_log_tail(before, EXPECTED_ALERT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
