#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import signal
import socket
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest
import requests


def listener_inodes(port, ipv4_address=None):
    results = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path, "r") as f:
                next(f)
                for line in f:
                    fields = line.split()
                    local_address = fields[1]
                    state = fields[3]
                    inode = fields[9]
                    address_hex, port_hex = local_address.rsplit(":", 1)
                    if state != "0A" or int(port_hex, 16) != port:
                        continue
                    if ipv4_address is not None and path == "/proc/net/tcp":
                        expected = "".join(f"{int(part):02X}" for part in reversed(ipv4_address.split(".")))
                        if address_hex != expected:
                            continue
                    elif ipv4_address is not None:
                        continue
                    results.add(inode)
        except FileNotFoundError:
            pass
    return results


def pids_for_inodes(inodes):
    owners = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                match = re.fullmatch(r"socket:\[(\d+)\]", target)
                if match and match.group(1) in inodes:
                    owners.add(int(name))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return owners


def cmdline(pid):
    try:
        with open(f"/proc/{pid}/cmdline", "rb") as f:
            return f.read().replace(b"\0", b" ").decode("utf-8", "replace")
    except OSError:
        return ""


def test_monitor_artifact_and_daemons_running():
    monitor_path = "/home/user/monitor.py"
    assert os.path.isfile(monitor_path), f"File not found or not a regular file: {monitor_path}"

    pids_8080 = pids_for_inodes(listener_inodes(8080))
    pids_8081 = pids_for_inodes(listener_inodes(8081))
    assert pids_8080, "No running process is listening on port 8080"
    assert pids_8081, "No running process is listening on port 8081"
    assert any(monitor_path in cmdline(pid) for pid in pids_8080), \
        "Port 8080 is not served by /home/user/monitor.py"
    assert any(monitor_path in cmdline(pid) for pid in pids_8081), \
        "Port 8081 is not served by /home/user/monitor.py"

    storage_pids = pids_for_inodes(listener_inodes(9999, "127.0.0.1"))
    assert storage_pids, "/app/storage_agent is not listening on 127.0.0.1:9999"
    matching = []
    for pid in storage_pids:
        try:
            if os.path.realpath(f"/proc/{pid}/exe") == "/app/storage_agent":
                matching.append(pid)
        except OSError:
            pass
    assert matching, "The process listening on 127.0.0.1:9999 is not /app/storage_agent"
    for pid in matching:
        with open(f"/proc/{pid}/environ", "rb") as f:
            environment = f.read().split(b"\0")
        assert b"STORAGE_AUTH_TOKEN=7x9_MONITOR_KEY_x99" in environment, \
            "Running storage_agent does not have the required token"


def test_bashrc_contains_token():
    """Verify that the required environment variable is set in .bashrc."""
    bashrc_path = "/home/user/.bashrc"
    assert os.path.exists(bashrc_path), f"File not found: {bashrc_path}"

    with open(bashrc_path, "r") as f:
        content = f.read()

    # Preserve the original checks for the discovered token.
    assert "STORAGE_AUTH_TOKEN" in content, "STORAGE_AUTH_TOKEN not found in .bashrc"
    assert "7x9_MONITOR_KEY_x99" in content, "Correct token value not found in .bashrc"

    # Also verify that sourcing the file actually exports the exact value.
    result = subprocess.run(
        [
            "env", "-i", "HOME=/home/user", "PATH=/usr/bin:/bin",
            "bash", "--noprofile", "--norc", "-c",
            'source "$1"; printf "\\n__TOKEN__=%s\\n" "${STORAGE_AUTH_TOKEN-}"; '
            'env | grep -Fx "STORAGE_AUTH_TOKEN=${STORAGE_AUTH_TOKEN-}"',
            "bash", bashrc_path,
        ],
        text=True,
        capture_output=True,
        timeout=5,
    )
    assert result.returncode == 0, f".bashrc does not export STORAGE_AUTH_TOKEN: {result.stderr}"
    assert "__TOKEN__=7x9_MONITOR_KEY_x99\n" in result.stdout, \
        "Sourcing .bashrc does not set the exact required token"


def test_http_status_endpoint():
    """Verify that the HTTP proxy /status endpoint returns 'UP'."""
    try:
        response = requests.get("http://127.0.0.1:8080/status", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP proxy on port 8080: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert response.text.strip() == "UP", f"Expected response 'UP', got '{response.text}'"
    assert response.content == b"UP", f"Expected exact plaintext b'UP', got {response.content!r}"


def test_http_metrics_endpoint():
    """Verify that the HTTP proxy /metrics endpoint returns Prometheus formatted metrics."""
    try:
        response = requests.get("http://127.0.0.1:8080/metrics", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP proxy on port 8080: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    text = response.text.strip()
    used_match = re.search(r"^storage_disk_used_mb\s+(\d+(?:\.\d+)?)$", text, re.MULTILINE)
    quota_match = re.search(r"^storage_disk_quota_mb\s+(\d+(?:\.\d+)?)$", text, re.MULTILINE)

    assert used_match is not None, f"Could not find 'storage_disk_used_mb <value>' in response:\n{text}"
    assert quota_match is not None, f"Could not find 'storage_disk_quota_mb <value>' in response:\n{text}"
    assert float(used_match.group(1)) == 460
    assert float(quota_match.group(1)) == 500


def receive_line(sock):
    data = b""
    while not data.endswith(b"\n") and len(data) < 1024:
        part = sock.recv(1024)
        if not part:
            break
        data += part
    return data.decode("utf-8")


def test_tcp_alert_socket():
    """Verify that the TCP alert socket responds correctly to 'CHECK\\n'."""
    try:
        with socket.create_connection(("127.0.0.1", 8081), timeout=5) as sock:
            sock.sendall(b"CHECK\n")
            data = receive_line(sock)
    except Exception as e:
        pytest.fail(f"Failed to connect or communicate with TCP alert socket on port 8081: {e}")

    assert data in ["OK\n", "ALERT\n"], f"Expected 'OK\\n' or 'ALERT\\n', got {repr(data)}"
    assert data == "ALERT\n", f"Expected 'ALERT\\n' since 460/500 > 90%, got {repr(data)}"


class MutableStorageServer(ThreadingHTTPServer):
    allow_reuse_address = True

    def __init__(self, address):
        super().__init__(address, MutableStorageHandler)
        self.value_lock = threading.Lock()
        self.used = 0
        self.quota = 1
        self.raw_requests = 0

    def set_values(self, used, quota):
        with self.value_lock:
            self.used = used
            self.quota = quota

    def snapshot(self):
        with self.value_lock:
            return self.used, self.quota, self.raw_requests


class MutableStorageHandler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def do_GET(self):
        if self.path != "/raw":
            self.send_response(404)
            self.send_header("Content-Length", "0")
            self.end_headers()
            return
        with self.server.value_lock:
            self.server.raw_requests += 1
            used = self.server.used
            quota = self.server.quota
        body = json.dumps({"disk_used_mb": used, "disk_quota_mb": quota}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


def stop_real_storage_agent():
    pids = pids_for_inodes(listener_inodes(9999, "127.0.0.1"))
    real_pids = []
    for pid in pids:
        try:
            if os.path.realpath(f"/proc/{pid}/exe") == "/app/storage_agent":
                real_pids.append(pid)
        except OSError:
            pass
    assert real_pids, "storage_agent stopped before dynamic proxy tests"
    for pid in real_pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 3
    while time.time() < deadline and any(os.path.exists(f"/proc/{pid}") for pid in real_pids):
        time.sleep(0.05)
    for pid in real_pids:
        if os.path.exists(f"/proc/{pid}"):
            os.kill(pid, signal.SIGKILL)
    time.sleep(0.2)


def tcp_check():
    with socket.create_connection(("127.0.0.1", 8081), timeout=5) as sock:
        sock.settimeout(5)
        sock.sendall(b"CHECK\n")
        return receive_line(sock)


def test_metrics_are_proxied_and_alerts_use_current_agent_data():
    stop_real_storage_agent()

    server = None
    last_error = None
    for _ in range(20):
        try:
            server = MutableStorageServer(("127.0.0.1", 9999))
            break
        except OSError as e:
            last_error = e
            time.sleep(0.1)
    assert server is not None, f"Could not replace storage agent with controlled test server: {last_error}"

    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    try:
        rng = random.SystemRandom()

        # Values are generated at verification time, so fixed metric output cannot pass.
        quota = rng.randint(700, 4000)
        used = rng.randint(1, quota - 1)
        if (used, quota) == (460, 500):
            used += 1
        server.set_values(used, quota)
        before = server.snapshot()[2]
        response = requests.get("http://127.0.0.1:8080/metrics", timeout=5)
        assert response.status_code == 200
        lines = [line for line in response.text.splitlines() if line.strip()]
        assert len(lines) == 2, f"Expected exactly two metric lines, got: {response.text!r}"
        parsed = {}
        for line in lines:
            match = re.fullmatch(r"(storage_disk_used_mb|storage_disk_quota_mb)\s+(\d+(?:\.\d+)?)", line)
            assert match, f"Invalid Prometheus metric line: {line!r}"
            assert match.group(1) not in parsed, f"Duplicate metric: {match.group(1)}"
            parsed[match.group(1)] = float(match.group(2))
        assert parsed == {
            "storage_disk_used_mb": float(used),
            "storage_disk_quota_mb": float(quota),
        }
        assert server.snapshot()[2] > before, "/metrics did not request /raw from port 9999"

        # Exercise below, exactly at, and above the strict 90% boundary.
        unit = rng.randint(70, 500)
        cases = [
            (9 * unit - rng.randint(1, unit), 10 * unit, "OK\n"),
            (9 * unit, 10 * unit, "OK\n"),
            (9 * unit + rng.randint(1, unit), 10 * unit, "ALERT\n"),
        ]
        rng.shuffle(cases)
        for case_used, case_quota, expected in cases:
            server.set_values(case_used, case_quota)
            before = server.snapshot()[2]
            actual = tcp_check()
            assert actual == expected, (
                f"For {case_used}/{case_quota}, expected {expected!r}, got {actual!r}"
            )
            assert server.snapshot()[2] > before, \
                "A CHECK request did not query the current /raw data from port 9999"
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
