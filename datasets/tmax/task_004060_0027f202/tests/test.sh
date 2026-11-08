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
import json
import os
import secrets
import socket
import subprocess
import threading
import time

import pytest
import requests

APP = "/app/bash-uptime-monitor-v2.1"
STATE = "/home/user/dashboard_state.json"
URL = "http://127.0.0.1:8080/state"
AUTH = {"Authorization": "Bearer sre-secret-77x"}
EXPECTED = {"target1", "target2", "target3"}


class RequestCollector:
    def __init__(self, expected_count):
        self.expected_count = expected_count
        self.requests = []
        self.errors = []
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("127.0.0.1", 80))
        self.sock.listen(expected_count)
        self.sock.settimeout(5)
        self.thread = threading.Thread(target=self._run, daemon=True)

    def start(self):
        self.thread.start()
        return self

    def _run(self):
        try:
            for _ in range(self.expected_count):
                conn, _ = self.sock.accept()
                conn.settimeout(2)
                data = b""
                try:
                    while len(data) < 65536:
                        chunk = conn.recv(4096)
                        if not chunk:
                            break
                        data += chunk
                        if b"\r\n\r\n" in data:
                            break
                    self.requests.append(data)
                    conn.sendall(b"HTTP/1.1 200 OK\r\nContent-Length: 0\r\nConnection: close\r\n\r\n")
                finally:
                    conn.close()
        except Exception as exc:
            self.errors.append(exc)
        finally:
            self.sock.close()

    def finish(self):
        self.thread.join(7)
        assert not self.thread.is_alive(), "Timed out waiting for HTTP probe connections"
        assert not self.errors, f"HTTP collector failed: {self.errors}"
        assert len(self.requests) == self.expected_count, (
            f"Expected {self.expected_count} probes, got {len(self.requests)}"
        )
        return self.requests


def assert_valid_probe(raw, expected_host):
    assert raw.endswith(b"\r\n\r\n"), f"Probe lacks CRLF/CRLF termination: {raw!r}"
    head = raw[:-4]
    assert b"\n" not in head.replace(b"\r\n", b""), f"Probe contains bare LF: {raw!r}"
    lines = head.split(b"\r\n")
    assert lines[0] == b"GET / HTTP/1.1", f"Bad request line: {lines[0]!r}"
    headers = {}
    for line in lines[1:]:
        assert b":" in line, f"Malformed HTTP header: {line!r}"
        name, value = line.split(b":", 1)
        headers[name.strip().lower()] = value.strip()
    assert headers.get(b"host") == expected_host.encode(), (
        f"Expected Host: {expected_host}, got {headers.get(b'host')!r}"
    )


def assert_complete_state(data):
    assert isinstance(data, dict), f"Unexpected JSON structure: {data}"
    targets = data.get("targets")
    assert isinstance(targets, dict), f"Expected a targets mapping, got: {data}"
    assert set(targets) == EXPECTED, f"Missing or unexpected targets: {targets}"
    for target, status in targets.items():
        if isinstance(status, dict):
            assert status.get("status") == "UP", f"Target {target} is not UP: {status}"
        else:
            assert status == "UP", f"Target {target} is not UP: {status}"


def test_required_artifacts_exist():
    for name in ("http_probe.sh", "monitor.sh", "serve.sh"):
        path = os.path.join(APP, name)
        assert os.path.isfile(path), f"Required artifact is missing: {path}"
        assert os.access(path, os.X_OK), f"Required artifact is not executable: {path}"


def test_http_probe_generates_valid_request():
    target = "verify-" + secrets.token_hex(8)
    collector = RequestCollector(1).start()
    result = subprocess.run(
        [os.path.join(APP, "http_probe.sh"), target, "localhost"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=6,
    )
    requests_seen = collector.finish()
    assert result.returncode == 0, result.stderr.decode(errors="replace")
    assert_valid_probe(requests_seen[0], target)


def test_monitor_probes_all_targets_and_never_leaves_corrupt_state():
    monitor = os.path.join(APP, "monitor.sh")
    for _ in range(15):
        collector = RequestCollector(3).start()
        proc = subprocess.Popen([monitor], stdout=subprocess.PIPE, stderr=subprocess.PIPE)

        while proc.poll() is None:
            try:
                with open(STATE, "r", encoding="utf-8") as state_file:
                    json.load(state_file)
            except json.JSONDecodeError as exc:
                proc.kill()
                pytest.fail(f"Monitor exposed invalid intermediate JSON: {exc}")
            time.sleep(0.002)

        stdout, stderr = proc.communicate(timeout=2)
        captured = collector.finish()
        assert proc.returncode == 0, (
            f"monitor.sh failed\nstdout={stdout.decode(errors='replace')}\n"
            f"stderr={stderr.decode(errors='replace')}"
        )

        hosts = []
        for raw in captured:
            assert raw.endswith(b"\r\n\r\n"), f"Malformed monitor probe: {raw!r}"
            lines = raw[:-4].split(b"\r\n")
            assert lines[0] == b"GET / HTTP/1.1"
            host_lines = [line for line in lines[1:] if line.lower().startswith(b"host:")]
            assert len(host_lines) == 1, f"Expected one Host header: {raw!r}"
            hosts.append(host_lines[0].split(b":", 1)[1].strip().decode())
        assert set(hosts) == EXPECTED, f"Monitor probed wrong targets: {hosts}"

        with open(STATE, "r", encoding="utf-8") as state_file:
            assert_complete_state(json.load(state_file))


def test_dashboard_service():
    """
    Test that the dashboard service is running on 127.0.0.1:8080,
    accepts the correct authentication token, and returns valid JSON
    with all targets marked as UP.
    """
    try:
        response = requests.get(URL, headers=AUTH, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the dashboard service at {URL}: {e}")

    assert response.status_code == 200, f"Expected status code 200, but got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except json.JSONDecodeError as e:
        pytest.fail(f"Dashboard response is not valid JSON. Response body: {response.text}\nError: {e}")

    # Preserve the original status assertions.
    if isinstance(data, dict):
        targets = data.get("targets", data)
        if isinstance(targets, dict):
            for target, status in targets.items():
                if isinstance(status, dict):
                    assert status.get("status") == "UP", f"Target {target} is not UP: {status}"
                else:
                    assert status == "UP", f"Target {target} is not UP: {status}"
        elif isinstance(targets, list):
            for item in targets:
                assert item.get("status") == "UP", f"Target {item} is not UP"
    elif isinstance(data, list):
        for item in data:
            assert item.get("status") == "UP", f"Target {item} is not UP"
    else:
        pytest.fail(f"Unexpected JSON structure: {data}")

    assert_complete_state(data)

    unauth = requests.get(URL, headers={"Authorization": "Bearer wrong-token"}, timeout=5)
    assert unauth.status_code == 401, "Dashboard did not enforce the configured ADMIN_TOKEN"

    listeners = []
    with open("/proc/net/tcp", "r", encoding="ascii") as tcp:
        for line in tcp.readlines()[1:]:
            fields = line.split()
            if fields[1].endswith(":1F90") and fields[3] == "0A":
                listeners.append(fields[1])
    assert "0100007F:1F90" in listeners, f"No listener on exactly 127.0.0.1:8080: {listeners}"
    assert "00000000:1F90" not in listeners, "Dashboard is exposed on 0.0.0.0:8080"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
