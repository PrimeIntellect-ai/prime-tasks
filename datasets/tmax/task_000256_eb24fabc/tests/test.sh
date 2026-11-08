#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import datetime
import os
import re
import stat
import subprocess
import threading
import time

import requests

HEALTH_SCRIPT = "/home/user/health_check.sh"
HEALTH_LOG = "/home/user/health.log"
HEALTH_PATTERN = re.compile(r"^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] STATUS: 200$")


def health_script_processes():
    matches = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        try:
            with open(f"/proc/{entry}/cmdline", "rb") as f:
                args = [arg.decode(errors="replace") for arg in f.read().split(b"\0") if arg]
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
        if HEALTH_SCRIPT in args:
            matches.append(int(entry))
    return matches


def connections_to_router():
    endpoints = set()
    try:
        with open("/proc/net/tcp", "r") as f:
            rows = f.readlines()[1:]
    except OSError:
        return endpoints

    for row in rows:
        fields = row.split()
        if len(fields) < 3:
            continue
        local, remote = fields[1], fields[2]
        try:
            remote_addr, remote_port = remote.split(":")
            _, local_port = local.split(":")
        except ValueError:
            continue
        # 0100007F is 127.0.0.1 and 1F90 is port 8080 in /proc/net/tcp.
        if remote_addr == "0100007F" and remote_port.upper() == "1F90":
            endpoints.add(local_port.upper())
    return endpoints


def test_authorized_keys_permissions():
    path = "/home/user/.ssh/authorized_keys"
    assert os.path.exists(path), f"{path} does not exist"
    st = os.stat(path)
    assert not bool(st.st_mode & stat.S_IWOTH), "authorized_keys is still world-writable"
    assert not bool(st.st_mode & stat.S_IWGRP), "authorized_keys is still group-writable"


def test_strict_modes_remains_enabled():
    config = "/home/user/app/ssh/sshd_config"
    assert os.path.isfile(config), f"{config} does not exist"
    result = subprocess.run(
        [
            "/usr/sbin/sshd", "-T", "-f", config,
            "-C", "user=user,host=localhost,addr=127.0.0.1",
        ],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, f"Unable to validate sshd_config: {result.stderr}"
    settings = {}
    for line in result.stdout.splitlines():
        parts = line.split(None, 1)
        if len(parts) == 2:
            settings[parts[0].lower()] = parts[1].strip().lower()
    assert settings.get("strictmodes") == "yes", "StrictModes must remain enabled"


def test_router_config_fixed():
    path = "/home/user/app/router/routes.conf"
    assert os.path.exists(path), f"{path} does not exist"
    with open(path, "r") as f:
        content = f.read()
    assert "backend=127.0.0.1:9090" in content, "The routing bug in routes.conf has not been fixed to point to 127.0.0.1:9090"


def test_health_log_exists_and_format():
    path = HEALTH_LOG
    assert os.path.exists(path), f"{path} does not exist. Health check script may not be running."

    with open(path, "r") as f:
        lines = f.readlines()

    assert len(lines) > 0, "health.log is empty"

    last_line = lines[-1].strip()
    pattern = r"^\[\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\] STATUS: 200$"
    assert re.match(pattern, last_line), f"Log entry '{last_line}' does not match expected format or status is not 200"


def test_health_script_is_running_and_polls_every_five_seconds():
    assert os.path.isfile(HEALTH_SCRIPT), f"{HEALTH_SCRIPT} does not exist"
    with open(HEALTH_SCRIPT, "r", errors="replace") as f:
        script = f.read()
    assert "http://127.0.0.1:8080/api/status" in script, "Health script does not target the required router URL"

    initial_pids = health_script_processes()
    assert initial_pids, "health_check.sh is not running in the background"

    with open(HEALTH_LOG, "rb") as f:
        f.seek(0, os.SEEK_END)
        initial_size = f.tell()

    baseline_connections = connections_to_router()
    observed_connections = set()
    stop_monitor = threading.Event()

    def monitor_router_connections():
        while not stop_monitor.is_set():
            observed_connections.update(connections_to_router() - baseline_connections)
            time.sleep(0.02)

    monitor = threading.Thread(target=monitor_router_connections, daemon=True)
    monitor.start()
    try:
        time.sleep(12)
    finally:
        stop_monitor.set()
        monitor.join(timeout=1)

    assert health_script_processes(), "health_check.sh did not continue running"
    assert len(observed_connections) >= 2, "Health check did not repeatedly connect to 127.0.0.1:8080"

    with open(HEALTH_LOG, "rb") as f:
        f.seek(initial_size)
        appended = f.read().decode(errors="replace")

    new_lines = [line.strip() for line in appended.splitlines() if line.strip()]
    assert len(new_lines) >= 2, "health_check.sh did not append repeated health results"

    timestamps = []
    for line in new_lines:
        match = HEALTH_PATTERN.match(line)
        assert match, f"New health log entry '{line}' has the wrong format or status"
        timestamps.append(datetime.datetime.strptime(match.group(1), "%Y-%m-%d %H:%M:%S"))

    intervals = [(b - a).total_seconds() for a, b in zip(timestamps, timestamps[1:])]
    assert any(4 <= interval <= 6 for interval in intervals), f"Health checks are not occurring every 5 seconds: {intervals}"


def test_e2e_ssh_tunnel_and_http():
    # Establish SSH tunnel
    tunnel_cmd = [
        "ssh", "-i", "/home/user/test_key",
        "-o", "StrictHostKeyChecking=no",
        "-o", "UserKnownHostsFile=/dev/null",
        "-p", "2222",
        "-N", "-L", "8888:127.0.0.1:8080",
        "user@127.0.0.1"
    ]

    proc = subprocess.Popen(tunnel_cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE)

    try:
        # Wait for the tunnel to be established
        time.sleep(2)

        # Check if SSH process died early (e.g., auth failure)
        if proc.poll() is not None:
            _, stderr = proc.communicate()
            assert False, f"SSH tunnel failed to start. stderr: {stderr.decode()}"

        # Make the HTTP request through the tunnel
        try:
            resp = requests.get("http://127.0.0.1:8888/api/status", timeout=5)
        except requests.exceptions.RequestException as e:
            assert False, f"Failed to connect to backend via SSH tunnel: {e}"

        assert resp.status_code == 200, f"Expected HTTP 200, got {resp.status_code}"

        try:
            data = resp.json()
            assert data == {"status": "ok", "service": "backend"}, f"Unexpected response body: {data}"
        except ValueError:
            assert False, f"Response is not valid JSON: {resp.text}"

    finally:
        proc.terminate()
        proc.wait()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
