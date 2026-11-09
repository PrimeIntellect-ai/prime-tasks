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
import os
import struct
import socket
import pickle
import json
import time
import uuid
import signal
import subprocess
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import requests
import pytest

_records = []
_records_lock = threading.Lock()
_probe_secret = uuid.uuid4().hex


def _record(method, path, headers, body, response_body):
    with _records_lock:
        _records.append({
            "method": method,
            "path": path,
            "headers": dict(headers),
            "body": body,
            "response_body": response_body,
        })


def _wait_for_record(method, path, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with _records_lock:
            for index, record in enumerate(_records):
                if record["method"] == method and record["path"] == path:
                    return _records.pop(index)
        time.sleep(0.02)
    pytest.fail(f"The backend never received {method} {path}; the listener did not forward the request")


def _listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table, "r") as handle:
                next(handle)
                for line in handle:
                    fields = line.split()
                    if int(fields[1].split(":")[1], 16) == port and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    pids = set()
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
                    pids.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue
    return pids


def _stop_original_backend():
    pids = _listener_pids(8081)
    for pid in pids:
        os.kill(pid, signal.SIGTERM)
    deadline = time.time() + 5
    while time.time() < deadline:
        if not _listener_pids(8081):
            return
        time.sleep(0.05)
    for pid in _listener_pids(8081):
        os.kill(pid, signal.SIGKILL)
    time.sleep(0.2)


class ProbeBackend(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def log_message(self, format, *args):
        pass

    def _send(self, body, status=200):
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("X-Backend-Probe", _probe_secret)
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/status":
            body = b'{"status": "ok"}'
        else:
            body = json.dumps({"status": "ok", "probe": _probe_secret}, separators=(",", ":")).encode()
        _record("GET", self.path, self.headers, b"", body)
        self._send(body)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        request_body = self.rfile.read(length)
        try:
            decoded = json.loads(request_body.decode("utf-8"))
        except Exception:
            decoded = None
        body = json.dumps(
            {"status": "ok", "echo": decoded, "probe": _probe_secret},
            separators=(",", ":"),
        ).encode("utf-8")
        _record("POST", self.path, self.headers, request_body, body)
        self._send(body)


@pytest.fixture(scope="session", autouse=True)
def probe_backend():
    _stop_original_backend()
    server = ThreadingHTTPServer(("127.0.0.1", 8081), ProbeBackend)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    yield
    server.shutdown()
    server.server_close()


def test_migrated_artifact_is_running_under_python3():
    server_path = "/home/user/app/proxy/server.py"
    assert os.path.isfile(server_path), f"Missing required proxy artifact: {server_path}"
    subprocess.run(["python3", "-m", "py_compile", server_path], check=True)

    for port in (8080, 9090):
        pids = _listener_pids(port)
        assert pids, f"No process is listening on required port {port}"
        valid = False
        for pid in pids:
            try:
                cmdline = open(f"/proc/{pid}/cmdline", "rb").read().replace(b"\0", b" ").decode("utf-8", "replace")
            except OSError:
                continue
            if "python3" in cmdline and server_path in cmdline:
                valid = True
                break
        assert valid, f"Port {port} is not served by the migrated server.py under Python 3"


def test_http_proxy_status_and_headers():
    """
    Test the HTTP proxy on port 8080.
    It should forward the request to the Go backend and inject the X-Migrated-By header.
    """
    try:
        response = requests.get("http://127.0.0.1:8080/status", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the HTTP proxy on 127.0.0.1:8080: {e}")

    assert response.status_code == 200, f"Expected 200 OK from proxy, got {response.status_code}"
    status_record = _wait_for_record("GET", "/status")
    assert status_record["headers"].get("X-Migrated-By") == "Python3", "Proxy did not inject X-Migrated-By: Python3"
    assert response.content == status_record["response_body"], "Proxy did not return the exact backend response body"
    assert response.headers.get("X-Backend-Probe") == _probe_secret, "Proxy did not return the backend response headers"

    try:
        post_resp = requests.post("http://127.0.0.1:8080/test_header", json={"test": "data"}, timeout=5)
        if post_resp.status_code == 200:
            data = post_resp.json()
            assert data.get("status") == "ok", "Expected status 'ok' in backend response"
            assert data.get("echo") == {"test": "data"}, "Expected echoed data to match"
    except Exception as e:
        pytest.fail(f"Proxy POST request failed: {e}")

    assert post_resp.status_code == 200
    fixed_record = _wait_for_record("POST", "/test_header")
    assert fixed_record["headers"].get("X-Migrated-By") == "Python3", "Injected migration header did not reach the backend"
    assert json.loads(fixed_record["body"].decode("utf-8")) == {"test": "data"}
    assert post_resp.content == fixed_record["response_body"], "Proxy altered the backend response body"

    token = uuid.uuid4().hex
    dynamic_path = "/http_" + token
    dynamic_payload = {"token": token, "values": [uuid.uuid4().hex, 17]}
    dynamic_resp = requests.post(
        "http://127.0.0.1:8080" + dynamic_path,
        json=dynamic_payload,
        headers={"X-Client-Challenge": token},
        timeout=5,
    )
    dynamic_record = _wait_for_record("POST", dynamic_path)
    assert dynamic_record["headers"].get("X-Migrated-By") == "Python3"
    assert dynamic_record["headers"].get("X-Client-Challenge") == token
    assert json.loads(dynamic_record["body"].decode("utf-8")) == dynamic_payload
    assert dynamic_resp.content == dynamic_record["response_body"]
    assert dynamic_resp.headers.get("X-Backend-Probe") == _probe_secret


def _tcp_exchange(payload_dict):
    payload = pickle.dumps(payload_dict, protocol=2)
    msg = struct.pack(">I", len(payload)) + payload
    s = socket.create_connection(("127.0.0.1", 9090), timeout=5)
    try:
        s.sendall(msg)
        length_data = b""
        while len(length_data) < 4:
            chunk = s.recv(4 - len(length_data))
            if not chunk:
                break
            length_data += chunk
        assert len(length_data) == 4, "Failed to read 4-byte length prefix from TCP proxy"
        response_length = struct.unpack(">I", length_data)[0]
        response_payload = b""
        while len(response_payload) < response_length:
            chunk = s.recv(response_length - len(response_payload))
            if not chunk:
                break
            response_payload += chunk
        assert len(response_payload) == response_length, "Failed to read complete response payload"
        try:
            return pickle.loads(response_payload)
        except Exception as e:
            pytest.fail(f"Failed to unpickle response from TCP proxy: {e}")
    finally:
        s.close()


def test_tcp_translator():
    """
    Test the TCP translator on port 9090.
    It should accept a length-prefixed pickled dict, forward it as JSON to the Go backend,
    and return a length-prefixed pickled response.
    """
    payload_dict = {"route": "/test_tcp", "data": {"key": "value"}}
    try:
        payload = pickle.dumps(payload_dict, protocol=2)
    except Exception as e:
        pytest.fail(f"Failed to pickle payload: {e}")

    response_dict = _tcp_exchange(payload_dict)
    assert isinstance(response_dict, dict), "Expected unpickled response to be a dictionary"
    assert response_dict.get("status") == "ok", f"Expected status 'ok', got {response_dict.get('status')}"
    assert response_dict.get("echo") == {"key": "value"}, f"Expected echo {{'key': 'value'}}, got {response_dict.get('echo')}"

    fixed_record = _wait_for_record("POST", "/test_tcp")
    assert json.loads(fixed_record["body"].decode("utf-8")) == {"key": "value"}
    assert response_dict.get("probe") == _probe_secret, "TCP response was not obtained from the backend"

    token = uuid.uuid4().hex
    dynamic_path = "/tcp_" + token
    dynamic_data = {"token": token, "nested": {"number": 314159, "flag": True}}
    dynamic_response = _tcp_exchange({"route": dynamic_path, "data": dynamic_data})
    dynamic_record = _wait_for_record("POST", dynamic_path)
    assert json.loads(dynamic_record["body"].decode("utf-8")) == dynamic_data
    assert dynamic_response.get("status") == "ok"
    assert dynamic_response.get("echo") == dynamic_data
    assert dynamic_response.get("probe") == _probe_secret, "TCP translator returned a canned response instead of forwarding"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
