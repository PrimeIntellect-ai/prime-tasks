#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import signal
import subprocess
import time
import uuid
import pytest

HOME = "/home/user"
MAIL_FILE = "/home/user/mail/admin"


def root_crontab():
    try:
        return subprocess.check_output("crontab -l", shell=True, text=True)
    except subprocess.CalledProcessError:
        pytest.fail("No crontab found for the user.")


def find_operator():
    cron_output = root_crontab()
    candidates = [p for p in glob.glob("/home/user/operator*") if os.path.isfile(p)]
    referenced = [p for p in candidates if p in cron_output]
    if referenced:
        return sorted(referenced)[0]
    assert candidates, "No operator artifact found under /home/user/operator*"
    return sorted(candidates)[0]


def run_operator():
    path = find_operator()
    assert os.path.isfile(path), f"Operator artifact is not a regular file: {path}"
    if path.endswith(".py"):
        command = ["python3", path]
    elif path.endswith(".sh"):
        command = ["bash", path]
    else:
        assert os.access(path, os.X_OK), f"Operator artifact is not executable: {path}"
        command = [path]
    try:
        result = subprocess.run(command, stdin=subprocess.DEVNULL,
                                stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                                timeout=20)
    except subprocess.TimeoutExpired:
        pytest.fail("Operator did not finish within 20 seconds")
    assert result.returncode == 0, f"Operator exited with status {result.returncode}"


def read_pids(path):
    assert os.path.exists(path), f"PID file not found at {path}"
    with open(path) as f:
        lines = [line.strip() for line in f if line.strip()]
    assert all(line.isdigit() for line in lines), f"PID file contains non-numeric entries: {lines}"
    pids = [int(line) for line in lines]
    assert len(pids) == len(set(pids)), "PID file contains duplicate PIDs"
    return pids


def is_running(pid):
    try:
        os.kill(pid, 0)
        with open(f"/proc/{pid}/stat") as f:
            state = f.read().split()[2]
        return state != "Z"
    except (ProcessLookupError, FileNotFoundError, PermissionError):
        return False


def wait_stopped(pid, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if not is_running(pid):
            return
        time.sleep(0.05)
    pytest.fail(f"Process {pid} did not terminate")


def assert_worker(pid, worker_path):
    assert is_running(pid), f"Tracked PID {pid} is not running"
    with open(f"/proc/{pid}/cmdline", "rb") as f:
        cmdline = f.read().replace(b"\0", b" ").decode(errors="replace")
    assert worker_path in cmdline, f"PID {pid} is not the requested command: {cmdline!r}"


def mail_tail(offset):
    assert os.path.exists(MAIL_FILE), "Mail spool was not created"
    with open(MAIL_FILE, errors="replace") as f:
        f.seek(offset)
        return f.read()


def assert_notice(text, service, action, pid):
    messages = [m for m in re.split(r"(?m)(?=^From )", text) if m.strip()]
    expected = f"{action} PID {pid}"
    matching = [m for m in messages
                if f"Subject: Scaling service {service}" in m
                and re.search(rf"(?m)^{re.escape(expected)}$", m)]
    assert matching, f"Missing valid mbox notice for {expected}"
    message = matching[0]
    assert re.search(r"(?m)^From .+", message), "Missing mbox envelope line"
    assert re.search(r"(?m)^From: operator@localhost$", message), "Missing From header"
    assert re.search(r"(?m)^To: admin@localhost$", message), "Missing To header"


def test_crontab_configured():
    """Verify that a crontab entry exists for the operator."""
    cron_output = root_crontab()
    assert "operator" in cron_output, "Crontab not configured properly with operator script."

    artifact = find_operator()
    active = [line.strip() for line in cron_output.splitlines()
              if line.strip() and not line.lstrip().startswith("#") and "operator" in line]
    assert len(active) == 1, "Expected exactly one active operator cron entry"
    fields = active[0].split()
    assert len(fields) >= 6 and fields[:5] == ["*", "*", "*", "*", "*"], \
        "Operator must be scheduled exactly once every minute"
    assert artifact in active[0], "Cron entry does not execute the submitted operator artifact"


def test_manifest_exists():
    """Verify that the test manifest exists and has correct contents."""
    manifest_path = '/home/user/manifests/test-service.json'
    assert os.path.exists(manifest_path), f"Manifest file not found at {manifest_path}"
    with open(manifest_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Manifest file is not valid JSON.")

    assert data.get("service_name") == "test-service", "Incorrect service_name in manifest."
    assert data.get("command") == "sleep 7200", "Incorrect command in manifest."
    assert data.get("replicas") == 3, "Incorrect replicas in manifest."


def test_pid_file_and_processes():
    """Verify that the PID file exists, contains exactly 3 PIDs, and they correspond to running sleep processes."""
    pid_file = '/home/user/run/test-service.pids'
    assert os.path.exists(pid_file), f"PID file not found at {pid_file}"

    with open(pid_file, 'r') as f:
        pids = [line.strip() for line in f if line.strip().isdigit()]

    assert len(pids) == 3, f"Expected exactly 3 PIDs in {pid_file}, found {len(pids)}"

    for pid in pids:
        try:
            cmd = f"ps -p {pid} -o comm="
            output = subprocess.check_output(cmd, shell=True, text=True).strip()
            assert "sleep" in output, f"Process {pid} is running but is not 'sleep' (found '{output}')"
        except subprocess.CalledProcessError:
            pytest.fail(f"Process with PID {pid} listed in the PID file is not running.")


def test_mail_file():
    """Verify that the mail spool file exists and contains the required mbox headers and body."""
    assert os.path.exists(MAIL_FILE), f"Mail file not found at {MAIL_FILE}"
    with open(MAIL_FILE, 'r') as f:
        content = f.read()

    assert "From: operator@localhost" in content, "Missing 'From: operator@localhost' header in mail file."
    assert "Subject: Scaling service test-service" in content, "Missing 'Subject: Scaling service test-service' header in mail file."
    assert "Started PID" in content, "Missing 'Started PID' action in mail body."


def test_dynamic_reconciliation():
    token = uuid.uuid4().hex
    service = f"audit-{token}"
    manifest = f"/home/user/manifests/{service}.json"
    pid_file = f"/home/user/run/{service}.pids"
    worker = f"/tmp/{service}-worker.py"
    term_log = f"/tmp/{service}-terms"

    worker_source = f'''#!/usr/bin/env python3
import os, signal, time
log = {term_log!r}
def terminate(signum, frame):
    with open(log, "a") as f:
        f.write(str(os.getpid()) + "\\n")
    raise SystemExit(0)
signal.signal(signal.SIGTERM, terminate)
while True:
    time.sleep(0.2)
'''
    with open(worker, "w") as f:
        f.write(worker_source)
    os.chmod(worker, 0o755)

    tracked = []
    try:
        with open(manifest, "w") as f:
            json.dump({"service_name": service, "command": worker, "replicas": 2}, f)

        offset = os.path.getsize(MAIL_FILE) if os.path.exists(MAIL_FILE) else 0
        run_operator()
        tracked = read_pids(pid_file)
        assert len(tracked) == 2, "Operator did not create the requested additional service replicas"
        for pid in tracked:
            assert_worker(pid, worker)
        notices = mail_tail(offset)
        for pid in tracked:
            assert_notice(notices, service, "Started", pid)

        # A dead tracked PID must be removed and replaced.
        dead = tracked[0]
        survivor = tracked[1]
        os.kill(dead, signal.SIGKILL)
        wait_stopped(dead)
        offset = os.path.getsize(MAIL_FILE)
        run_operator()
        after_dead = read_pids(pid_file)
        tracked = after_dead
        assert len(after_dead) == 2
        assert dead not in after_dead, "Dead PID was not cleaned from the PID file"
        assert survivor in after_dead, "Live existing replica was unnecessarily replaced"
        replacement = next(pid for pid in after_dead if pid != survivor)
        assert_worker(replacement, worker)
        assert_notice(mail_tail(offset), service, "Started", replacement)

        # Scale up using the modified manifest.
        with open(manifest, "w") as f:
            json.dump({"service_name": service, "command": worker, "replicas": 3}, f)
        offset = os.path.getsize(MAIL_FILE)
        run_operator()
        scaled_up = read_pids(pid_file)
        tracked = scaled_up
        assert len(scaled_up) == 3, "Operator failed to scale up"
        assert scaled_up[:2] == after_dead, "Scale-up changed existing PID ordering"
        new_pid = scaled_up[2]
        assert_worker(new_pid, worker)
        assert_notice(mail_tail(offset), service, "Started", new_pid)

        # Scale down: the bottom/newest PIDs must receive SIGTERM and be removed.
        with open(manifest, "w") as f:
            json.dump({"service_name": service, "command": worker, "replicas": 1}, f)
        offset = os.path.getsize(MAIL_FILE)
        run_operator()
        remaining = read_pids(pid_file)
        tracked = remaining
        assert remaining == scaled_up[:1], "Scale-down did not retain the oldest PID"
        terminated = scaled_up[1:]
        for pid in terminated:
            wait_stopped(pid)
        deadline = time.time() + 5
        recorded = set()
        while time.time() < deadline:
            if os.path.exists(term_log):
                with open(term_log) as f:
                    recorded = {int(x) for x in f.read().split() if x.isdigit()}
            if set(terminated).issubset(recorded):
                break
            time.sleep(0.05)
        assert set(terminated).issubset(recorded), "Excess processes were not sent SIGTERM"
        notices = mail_tail(offset)
        for pid in terminated:
            assert_notice(notices, service, "Terminated", pid)
    finally:
        for pid in tracked:
            if is_running(pid):
                try:
                    os.kill(pid, signal.SIGTERM)
                except ProcessLookupError:
                    pass
        for path in (manifest, pid_file, worker, term_log):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
TEST_EOF

set +e
python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
