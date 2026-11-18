#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import signal
import subprocess
import time
import pytest


def test_config_json_fixed():
    path = "/home/user/service/config.json"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        try:
            config = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} does not contain valid JSON.")

    assert "port" in config, f"'port' key missing in {path}."
    assert config["port"] == 8080, f"Expected port to be 8080, got {config['port']}."


def test_expect_script_exists_and_uses_expect():
    path = "/home/user/start_service.exp"
    assert os.path.isfile(path), f"Expect script {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    assert "/home/user/service/daemon.go" in content, "Expect script does not reference the required Go daemon."
    assert re.search(r"(?m)^\s*spawn\b[^\n]*(?:\bgo\b|/go)\s+run\b", content), \
        "Expect script must spawn 'go run'."
    assert re.search(r"(?m)^\s*expect(?:\s|$)", content), \
        "Expect script must use Expect to wait for the interactive prompt."
    assert re.search(r"(?m)^\s*send(?:\s|$)", content), \
        "Expect script must use Expect to send the PIN."


def _descendant_cmdlines(root_pid):
    processes = {}
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/stat", "r") as f:
                stat = f.read()
            close = stat.rfind(")")
            ppid = int(stat[close + 2:].split()[1])
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
            processes[int(entry)] = (ppid, cmdline)
        except (FileNotFoundError, ProcessLookupError, PermissionError, ValueError, IndexError):
            pass

    descendants = {root_pid}
    changed = True
    while changed:
        changed = False
        for pid, (ppid, _) in processes.items():
            if ppid in descendants and pid not in descendants:
                descendants.add(pid)
                changed = True
    return [processes[pid][1] for pid in descendants if pid != root_pid and pid in processes]


def test_expect_script_actually_runs_daemon_and_waits():
    script = "/home/user/start_service.exp"
    log_path = "/home/user/service/daemon.log"
    if os.path.lexists(log_path):
        os.remove(log_path)

    env = os.environ.copy()
    env["TZ"] = "UTC"
    env["LANG"] = "C"

    proc = subprocess.Popen(
        ["/usr/bin/expect", script],
        cwd="/home/user",
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        start_new_session=True,
    )

    deadline = time.monotonic() + 45
    log_seen_at = None
    exit_seen_at = None
    saw_go_run = False
    saw_running_daemon_after_log = False

    try:
        while time.monotonic() < deadline:
            now = time.monotonic()
            cmdlines = _descendant_cmdlines(proc.pid)
            if any("go run" in cmd and "/home/user/service/daemon.go" in cmd for cmd in cmdlines):
                saw_go_run = True

            if os.path.isfile(log_path):
                with open(log_path, "r") as f:
                    log_content = f.read()
                if "Service started successfully on port 8080" in log_content:
                    if log_seen_at is None:
                        log_seen_at = now
                    if any("go-build" in cmd and "/exe/daemon" in cmd for cmd in cmdlines):
                        saw_running_daemon_after_log = True

            if proc.poll() is not None:
                exit_seen_at = now
                break
            time.sleep(0.03)

        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            pytest.fail("Expect script did not finish within 45 seconds.")

        output, _ = proc.communicate(timeout=5)
        assert proc.returncode == 0, f"Expect script failed with exit code {proc.returncode}. Output:\n{output}"
        assert saw_go_run, "The Expect script never executed 'go run /home/user/service/daemon.go'."
        assert log_seen_at is not None, f"The executed service did not create {log_path} with the success message. Output:\n{output}"
        assert saw_running_daemon_after_log, "The success log was not produced while the Go daemon was running."
        assert exit_seen_at - log_seen_at >= 1.5, "The Expect script exited without waiting for the daemon to finish."
    finally:
        if proc.poll() is None:
            os.killpg(proc.pid, signal.SIGKILL)
            proc.wait()


def test_logrotate_conf():
    path = "/home/user/logrotate.conf"
    assert os.path.isfile(path), f"Logrotate config {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    assert "/home/user/service/daemon.log" in content, "Logrotate config does not target /home/user/service/daemon.log."
    assert "daily" in content, "Logrotate config missing 'daily' directive."
    assert "rotate 3" in content, "Logrotate config missing 'rotate 3' directive."
    assert "create" in content, "Logrotate config missing 'create' directive."


def test_daemon_log_success():
    path = "/home/user/service/daemon.log"
    assert os.path.isfile(path), f"Log file {path} does not exist. Did the service run successfully?"
    with open(path, "r") as f:
        content = f.read()

    expected_msg = "Service started successfully on port 8080"
    assert expected_msg in content, f"Expected success message not found in {path}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
