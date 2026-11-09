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
import hashlib
import json
import os
import random
import re
import signal
import socket
import string
import subprocess
import threading
import time
import uuid

import pytest
import requests
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

BACKEND_NONCE = uuid.uuid4().hex
BACKEND_REQUESTS = []
BACKEND_LOCK = threading.Lock()


class MockBackendHandler(BaseHTTPRequestHandler):
    def _handle(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length) if length else b""
        record = {
            "method": self.command,
            "path": self.path,
            "trace": self.headers.get("X-Verifier-Trace"),
            "custom": self.headers.get("X-Custom-Value"),
            "body": body,
        }
        with BACKEND_LOCK:
            BACKEND_REQUESTS.append(record)

        if self.command == "GET" and self.path == "/api/test":
            payload = b'{"data": "success"}'
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
            return

        status = int(self.headers.get("X-Backend-Status", "200"))
        payload = json.dumps({
            "backend_nonce": BACKEND_NONCE,
            "method": self.command,
            "path": self.path,
            "custom": self.headers.get("X-Custom-Value"),
            "body_sha256": hashlib.sha256(body).hexdigest(),
        }, sort_keys=True).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("X-Backend-Nonce", BACKEND_NONCE)
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    do_GET = _handle
    do_POST = _handle
    do_PUT = _handle
    do_PATCH = _handle
    do_DELETE = _handle

    def log_message(self, format, *args):
        pass


def listener_pids(address_hex, port):
    wanted = "%s:%04X" % (address_hex, port)
    inodes = set()
    with open("/proc/net/tcp", "r") as f:
        next(f)
        for line in f:
            fields = line.split()
            if fields[1].upper() == wanted and fields[3] == "0A":
                inodes.add(fields[9])
    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        fd_dir = "/proc/%s/fd" % name
        try:
            fds = os.listdir(fd_dir)
        except OSError:
            continue
        for fd in fds:
            try:
                target = os.readlink(os.path.join(fd_dir, fd))
            except OSError:
                continue
            match = re.fullmatch(r"socket:\[(\d+)\]", target)
            if match and match.group(1) in inodes:
                pids.add(int(name))
                break
    return pids


def read_metrics():
    chunks = []
    with socket.create_connection(("127.0.0.1", 8082), timeout=2) as s:
        s.settimeout(2)
        s.sendall(b"STATS\n")
        while True:
            data = s.recv(1024)
            if not data:
                break
            chunks.append(data)
    raw = b"".join(chunks)
    match = re.fullmatch(rb"SUCCESS_COUNT: ([0-9]+)\n", raw)
    assert match, "Metrics response format invalid: %r" % raw
    return int(match.group(1))


def valid_token():
    return hashlib.sha256(b"cloud_migration_2024").hexdigest()


@pytest.fixture(scope="session", autouse=True)
def setup_environment():
    server = ThreadingHTTPServer(("127.0.0.2", 8081), MockBackendHandler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    deploy_script = "/home/user/deploy.sh"
    assert os.path.exists(deploy_script), "Deployment script missing at %s" % deploy_script
    os.chmod(deploy_script, 0o755)
    try:
        proc = subprocess.run([deploy_script], capture_output=True, text=True, timeout=30)
    except subprocess.TimeoutExpired as exc:
        pytest.fail("deploy.sh did not exit after starting the services: %s" % exc)
    assert proc.returncode == 0, (
        "deploy.sh failed with return code %s\nStdout: %s\nStderr: %s"
        % (proc.returncode, proc.stdout, proc.stderr)
    )

    for host, port in [("127.0.0.1", 9000), ("127.0.0.1", 8080), ("127.0.0.1", 8082)]:
        up = False
        for _ in range(30):
            try:
                with socket.create_connection((host, port), timeout=0.5):
                    up = True
                    break
            except OSError:
                time.sleep(0.2)
        assert up, "Port %s did not become ready after running deploy.sh" % port

    env = {"server": server}
    yield env
    server.shutdown()
    server.server_close()


def test_directory_structure_and_symlink():
    secret_path = "/home/user/configs/v2_migrated/secret.txt"
    symlink_path = "/home/user/legacy_system/active"

    assert os.path.exists(secret_path), "Secret file missing at %s" % secret_path
    with open(secret_path, "r") as f:
        content = f.read().strip()
    assert content == "cloud_migration_2024", "Incorrect secret content: %s" % content

    assert os.path.islink(symlink_path), "%s is not a symlink" % symlink_path
    target = os.readlink(symlink_path)
    if not os.path.isabs(target):
        target = os.path.normpath(os.path.join(os.path.dirname(symlink_path), target))
    assert target == "/home/user/configs/v2_migrated", "Symlink points to wrong target: %s" % target


def test_required_artifacts_and_real_listeners():
    main_go = "/home/user/gateway/main.go"
    assert os.path.isfile(main_go), "Go proxy source missing at %s" % main_go
    build = subprocess.run(
        ["go", "build", "-o", "/tmp/verifier_gateway_build", main_go],
        capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, "main.go does not compile:\n%s\n%s" % (build.stdout, build.stderr)

    legacy_pids = listener_pids("0100007F", 9000)
    proxy_pids = listener_pids("00000000", 8080)
    metrics_pids = listener_pids("00000000", 8082)
    assert legacy_pids, "No process is listening on required address 127.0.0.1:9000"
    assert proxy_pids, "No process is listening on required address 0.0.0.0:8080"
    assert metrics_pids, "No process is listening on required address 0.0.0.0:8082"
    assert proxy_pids == metrics_pids and len(proxy_pids) == 1, (
        "HTTP and metrics ports must be served by the same Go proxy process"
    )

    legacy_pid = next(iter(legacy_pids))
    assert os.stat("/proc/%d/exe" % legacy_pid) == os.stat("/app/legacy_auth"), (
        "Port 9000 is not served by /app/legacy_auth"
    )
    gateway_pid = next(iter(proxy_pids))
    info = subprocess.run(
        ["go", "version", "-m", "/proc/%d/exe" % gateway_pid],
        capture_output=True, text=True
    )
    assert info.returncode == 0 and re.search(r"\bgo1\.", info.stdout + info.stderr), (
        "Ports 8080 and 8082 are not served by a compiled Go executable"
    )

    for token, expected in [
        (valid_token(), b"VALID\n"),
        ("invalid-" + uuid.uuid4().hex, b"INVALID\n"),
        (uuid.uuid4().hex + uuid.uuid4().hex, b"INVALID\n"),
    ]:
        with socket.create_connection(("127.0.0.1", 9000), timeout=2) as s:
            s.sendall(token.encode() + b"\n")
            result = s.recv(100)
        assert result == expected, "Unexpected legacy daemon response: %r" % result


def test_proxy_invalid_auth():
    trace = uuid.uuid4().hex
    resp = requests.get(
        "http://127.0.0.1:8080/api/test",
        headers={"X-Auth-Token": "wrong_token", "X-Verifier-Trace": trace}, timeout=2
    )
    assert resp.status_code == 401, "Expected HTTP 401 for invalid auth, got %s" % resp.status_code
    try:
        json_data = resp.json()
    except ValueError:
        pytest.fail("Expected JSON response, got: %s" % resp.text)
    assert json_data == {"error": "unauthorized"}, "Unexpected JSON response: %s" % json_data
    with BACKEND_LOCK:
        assert not any(r["trace"] == trace for r in BACKEND_REQUESTS), (
            "An unauthorized request reached the backend"
        )


def test_proxy_valid_auth():
    trace = uuid.uuid4().hex
    resp = requests.get(
        "http://127.0.0.1:8080/api/test",
        headers={"X-Auth-Token": valid_token(), "X-Verifier-Trace": trace}, timeout=2
    )
    assert resp.status_code == 200, "Expected HTTP 200 for valid auth, got %s" % resp.status_code
    try:
        json_data = resp.json()
    except ValueError:
        pytest.fail("Expected JSON response from backend, got: %s" % resp.text)
    assert json_data == {"data": "success"}, "Unexpected backend response: %s" % json_data
    with BACKEND_LOCK:
        assert any(r["trace"] == trace for r in BACKEND_REQUESTS), (
            "Valid request was not forwarded to the backend"
        )


def test_proxy_metrics_and_varied_forwarding():
    before = read_metrics()

    requests.get(
        "http://127.0.0.1:8080/api/test",
        headers={"X-Auth-Token": valid_token()}, timeout=2
    )
    count = read_metrics()
    assert count >= 2, "Expected SUCCESS_COUNT >= 2, got %s" % count
    assert count == before + 1, "Successful request did not increment metrics exactly once"

    invalid_traces = []
    for method, token in [
        ("GET", "bad-" + uuid.uuid4().hex),
        ("POST", uuid.uuid4().hex),
        ("DELETE", ""),
    ]:
        trace = uuid.uuid4().hex
        invalid_traces.append(trace)
        headers = {"X-Verifier-Trace": trace}
        if token:
            headers["X-Auth-Token"] = token
        resp = requests.request(method, "http://127.0.0.1:8080/random/" + uuid.uuid4().hex,
                                headers=headers, data=os.urandom(17), timeout=2)
        assert resp.status_code == 401
        assert resp.json() == {"error": "unauthorized"}
    assert read_metrics() == count, "Invalid authorizations changed SUCCESS_COUNT"
    with BACKEND_LOCK:
        seen = {r["trace"] for r in BACKEND_REQUESTS}
    assert not (set(invalid_traces) & seen), "Invalid requests reached the backend"

    cases = [("POST", 201), ("PUT", 207), ("PATCH", 202), ("DELETE", 418)]
    successful = 0
    for method, status in cases:
        trace = uuid.uuid4().hex
        custom = "value-" + uuid.uuid4().hex
        body = os.urandom(random.randint(8, 80))
        path = "/v%d/%s?q=%s" % (
            random.randint(2, 99), uuid.uuid4().hex,
            "".join(random.choice(string.ascii_letters) for _ in range(12))
        )
        headers = {
            "X-Auth-Token": valid_token(),
            "X-Verifier-Trace": trace,
            "X-Custom-Value": custom,
            "X-Backend-Status": str(status),
            "Content-Type": "application/octet-stream",
        }
        resp = requests.request(method, "http://127.0.0.1:8080" + path,
                                headers=headers, data=body, timeout=3)
        assert resp.status_code == status
        assert resp.headers.get("X-Backend-Nonce") == BACKEND_NONCE
        assert resp.json() == {
            "backend_nonce": BACKEND_NONCE,
            "method": method,
            "path": path,
            "custom": custom,
            "body_sha256": hashlib.sha256(body).hexdigest(),
        }
        with BACKEND_LOCK:
            matches = [r for r in BACKEND_REQUESTS if r["trace"] == trace]
        assert len(matches) == 1
        assert matches[0]["method"] == method
        assert matches[0]["path"] == path
        assert matches[0]["custom"] == custom
        assert matches[0]["body"] == body
        successful += 1

    assert read_metrics() == count + successful, (
        "SUCCESS_COUNT did not exactly track all successful authorizations"
    )


def test_proxy_returns_401_when_legacy_daemon_is_unavailable():
    legacy_pids = listener_pids("0100007F", 9000)
    assert legacy_pids
    for pid in legacy_pids:
        os.kill(pid, signal.SIGKILL)
    for _ in range(30):
        if not listener_pids("0100007F", 9000):
            break
        time.sleep(0.1)
    assert not listener_pids("0100007F", 9000), "Could not stop legacy daemon for failure test"

    before = read_metrics()
    resp = requests.get(
        "http://127.0.0.1:8080/failure/" + uuid.uuid4().hex,
        headers={"X-Auth-Token": valid_token()}, timeout=3
    )
    assert resp.status_code == 401, "Proxy did not return 401 when legacy daemon was unavailable"
    assert resp.json() == {"error": "unauthorized"}
    assert read_metrics() == before, "Failed legacy connection incremented SUCCESS_COUNT"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
