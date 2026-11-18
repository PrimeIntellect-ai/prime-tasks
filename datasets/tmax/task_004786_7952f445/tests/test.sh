#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import signal
import socket
import subprocess
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest


def socket_inodes_for_port(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local_port = int(fields[1].rsplit(":", 1)[1], 16)
                    state = fields[3]
                    if local_port == port and state == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass
    return inodes


def pids_owning_port(port):
    inodes = socket_inodes_for_port(port)
    owners = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    owners.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return owners


def test_nginx_listening_and_proxying():
    """Check that Nginx owns port 8080 and correctly proxies to the mock server."""
    config_path = "/home/user/nginx.conf"
    assert os.path.isfile(config_path), f"Nginx configuration not found at {config_path}"

    check = subprocess.run(
        ["/usr/sbin/nginx", "-t", "-c", config_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
    )
    assert check.returncode == 0, f"Nginx configuration is invalid: {check.stderr}"

    owners = pids_owning_port(8080)
    assert owners, "No process is listening on port 8080"
    nginx_owners = []
    for pid in owners:
        try:
            if os.path.basename(os.readlink(f"/proc/{pid}/exe")) == "nginx":
                nginx_owners.append(pid)
        except OSError:
            pass
    assert nginx_owners, f"Port 8080 is not owned by Nginx; listener PIDs: {sorted(owners)}"

    url = "http://127.0.0.1:8080/v2/import"
    payload = json.dumps({
        "identifier": 999,
        "display_name": "Test User",
        "is_admin": False
    }).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=payload,
        headers={"Content-Type": "application/json"},
        method="POST",
    )

    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 201, f"Expected HTTP 201 Created from proxy, got {response.status}"
            body = response.read().decode("utf-8")
            assert body == "Created", "Proxy did not return the expected response body from the mock server."
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to Nginx proxy at {url} or proxy failed: {e}")


def test_migrate_script_exists():
    """Check if the bash script was created."""
    script_path = "/home/user/migrate.sh"
    assert os.path.isfile(script_path), f"Migration script not found at {script_path}"


def test_migration_results_log():
    """Check if the migration results log contains the expected output."""
    log_path = "/home/user/migration_results.log"
    assert os.path.isfile(log_path), f"Migration results log not found at {log_path}"

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "ID 1: HTTP 201",
        "ID 2: HTTP 201",
        "ID 3: HTTP 201",
        "ID 4: HTTP 201"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in log, found {len(lines)}"
    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, f"Line {i+1} in log mismatch. Expected '{expected}', got '{lines[i]}'"


def test_script_processes_dynamic_csv_and_sends_exact_payloads():
    """Execute the submitted script against unpredictable rows and inspect backend requests."""
    csv_path = "/home/user/legacy_data.csv"
    log_path = "/home/user/migration_results.log"
    script_path = "/home/user/migrate.sh"

    stamp = int.from_bytes(os.urandom(3), "big") + 10000
    rows = [
        (stamp, "Verifier Alpha", "admin"),
        (stamp + 7, "Verifier Beta", "user"),
        (stamp + 19, "Verifier Gamma", "Admin"),
        (stamp + 31, "Verifier Delta", "admin"),
    ]
    statuses = {
        rows[0][0]: 201,
        rows[1][0]: 202,
        rows[2][0]: 207,
        rows[3][0]: 418,
    }
    expected_payloads = [
        {"identifier": row_id, "display_name": name, "is_admin": role == "admin"}
        for row_id, name, role in rows
    ]

    old_csv = open(csv_path, "rb").read() if os.path.exists(csv_path) else None
    old_log = open(log_path, "rb").read() if os.path.exists(log_path) else None

    # Vacate the real backend port so a capturing backend can inspect what Nginx forwards.
    current_pid = os.getpid()
    backend_pids = pids_owning_port(9000) - {current_pid}
    for pid in backend_pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 3
    while pids_owning_port(9000) - {current_pid} and time.time() < deadline:
        time.sleep(0.05)
    for pid in pids_owning_port(9000) - {current_pid}:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.1)

    received = []

    class CaptureHandler(BaseHTTPRequestHandler):
        def do_POST(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length)
            try:
                parsed = json.loads(body.decode("utf-8"))
            except Exception:
                parsed = None
            received.append({
                "path": self.path,
                "content_type": self.headers.get("Content-Type", ""),
                "payload": parsed,
            })
            identifier = parsed.get("identifier") if isinstance(parsed, dict) else None
            status = statuses.get(identifier, 422)
            self.send_response(status)
            self.end_headers()
            self.wfile.write(f"status-{status}".encode("ascii"))

        def log_message(self, fmt, *args):
            pass

    server = None
    thread = None
    try:
        server = HTTPServer(("127.0.0.1", 9000), CaptureHandler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        csv_text = "id,full_name,role\n" + "".join(
            f"{row_id},{name},{role}\n" for row_id, name, role in rows
        )
        with open(csv_path, "w") as f:
            f.write(csv_text)
        os.chown(csv_path, 1000, 1000)
        if os.path.exists(log_path):
            os.remove(log_path)

        proc = subprocess.run(
            ["runuser", "-u", "user", "--", "/bin/bash", script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert proc.returncode == 0, (
            f"migrate.sh failed on dynamic CSV with exit code {proc.returncode}. "
            f"stdout={proc.stdout!r}, stderr={proc.stderr!r}"
        )

        assert len(received) == len(rows), f"Expected {len(rows)} backend requests, received {len(received)}"
        for index, request in enumerate(received):
            assert request["path"] == "/import", (
                f"Request {index + 1} reached backend path {request['path']!r}; /v2/ was not stripped correctly"
            )
            assert request["content_type"].lower().startswith("application/json"), (
                f"Request {index + 1} did not use Content-Type application/json"
            )
            assert request["payload"] == expected_payloads[index], (
                f"Request {index + 1} payload mismatch: expected {expected_payloads[index]!r}, "
                f"got {request['payload']!r}"
            )
            assert type(request["payload"]["identifier"]) is int
            assert type(request["payload"]["display_name"]) is str
            assert type(request["payload"]["is_admin"]) is bool

        assert os.path.isfile(log_path), "migrate.sh did not create migration_results.log"
        with open(log_path, "r") as f:
            actual_log = [line.strip() for line in f if line.strip()]
        expected_log = [f"ID {row_id}: HTTP {statuses[row_id]}" for row_id, _, _ in rows]
        assert actual_log == expected_log, f"Dynamic migration log mismatch: expected {expected_log}, got {actual_log}"
    finally:
        if server is not None:
            server.shutdown()
            server.server_close()
        if thread is not None:
            thread.join(timeout=2)
        if old_csv is not None:
            with open(csv_path, "wb") as f:
                f.write(old_csv)
            os.chown(csv_path, 1000, 1000)
        if old_log is None:
            try:
                os.remove(log_path)
            except FileNotFoundError:
                pass
        else:
            with open(log_path, "wb") as f:
                f.write(old_log)
            os.chown(log_path, 1000, 1000)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
