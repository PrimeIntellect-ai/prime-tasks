#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import signal
import socket
import stat
import subprocess
import time
import urllib.error
import urllib.request
import uuid

import pytest
import redis

APP_DIR = "/home/user/app"
WAF_PATH = os.path.join(APP_DIR, "waf.py")
NGINX_CONF = os.path.join(APP_DIR, "nginx.conf")
START_SH = os.path.join(APP_DIR, "start_services.sh")
CLEAN_CORPUS = "/home/user/corpus/clean"
EVIL_CORPUS = "/home/user/corpus/evil"


def wait_for_port(port, timeout=10):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return
        except OSError:
            time.sleep(0.1)
    pytest.fail(f"Service on port {port} did not become ready")


@pytest.fixture(scope="session", autouse=True)
def start_services():
    subprocess.run(["pkill", "-f", "nginx"], check=False)
    subprocess.run(["pkill", "-f", "redis-server"], check=False)
    subprocess.run(["pkill", "-f", "api.py"], check=False)
    subprocess.run(["pkill", "-f", "waf.py"], check=False)
    time.sleep(1)

    subprocess.Popen(["bash", START_SH], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for port in (6379, 8080, 8081, 8082):
        wait_for_port(port)
    yield


def listener_inodes(port):
    result = set()
    for path in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(path) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if fields[3] != "0A":
                        continue
                    if int(fields[1].rsplit(":", 1)[1], 16) == port:
                        result.add(fields[9])
        except FileNotFoundError:
            pass
    return result


def listener_processes(port):
    inodes = listener_inodes(port)
    found = []
    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    with open(f"/proc/{entry}/cmdline", "rb") as f:
                        cmdline = f.read().replace(b"\0", b" ").decode("utf-8", "replace")
                    found.append((int(entry), cmdline))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            continue
    return found


def request_raw(raw, headers=None, timeout=3):
    request_headers = {"Content-Type": "application/json"}
    if headers:
        request_headers.update(headers)
    req = urllib.request.Request(
        "http://127.0.0.1:8080/process",
        data=raw,
        headers=request_headers,
        method="POST",
    )
    try:
        with urllib.request.urlopen(req, timeout=timeout) as response:
            return response.getcode(), response.read(), dict(response.headers.items())
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read(), dict(exc.headers.items())
    except Exception:
        return None, b"", {}


def send_request(payload):
    status, _, _ = request_raw(json.dumps(payload).encode("utf-8"))
    return status


def test_waf_permissions():
    assert os.path.exists(WAF_PATH), f"WAF script {WAF_PATH} does not exist."
    st = os.stat(WAF_PATH)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o700, f"Expected {WAF_PATH} to have 700 permissions, got {oct(perms)}."


def test_nginx_config_updated():
    with open(NGINX_CONF, "r") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:8081;" in content, "nginx.conf was not updated to proxy to the WAF on port 8081."


def test_startup_script_updated():
    with open(START_SH, "r") as f:
        content = f.read()
    assert "api.py" in content and "8082" in content, "start_services.sh does not start api.py on the correct port 8082."
    assert "waf.py" in content, "start_services.sh does not start waf.py."


def test_required_services_are_actual_listeners():
    expected = {
        8080: "nginx",
        8081: "waf.py",
        8082: "api.py",
        6379: "redis-server",
    }
    for port, marker in expected.items():
        processes = listener_processes(port)
        assert processes, f"Nothing is listening on required port {port}"
        assert any(marker in cmd for _, cmd in processes), (
            f"Port {port} is not owned by the required {marker} service: {processes}"
        )


def test_generated_clean_request_reaches_api_and_redis():
    client = redis.Redis(host="127.0.0.1", port=6379, db=0)
    before_raw = client.get("processed_count")
    before = int(before_raw) if before_raw is not None else 0
    payload = {
        "username": "client_" + uuid.uuid4().hex,
        "comment": "Routine account update " + uuid.uuid4().hex,
        "request_id": uuid.uuid4().hex,
    }
    status, body, _ = request_raw(json.dumps(payload, separators=(",", ":")).encode("utf-8"))
    assert status == 200, f"Generated clean request returned {status}"
    response = json.loads(body.decode("utf-8"))
    assert response.get("status") == "success", "The response was not the backend API response"
    assert int(response.get("count")) == before + 1, "Backend response did not contain the new Redis count"
    assert int(client.get("processed_count")) == before + 1, "Redis was not reached by the backend API"


def test_clean_corpus():
    clean_files = [f for f in os.listdir(CLEAN_CORPUS) if f.endswith(".json")]
    assert len(clean_files) > 0, "Clean corpus directory is empty."

    failed = []
    for fname in clean_files:
        with open(os.path.join(CLEAN_CORPUS, fname), "r") as f:
            payload = json.load(f)
        status = send_request(payload)
        if status != 200:
            failed.append(fname)

    assert not failed, f"{len(failed)} of {len(clean_files)} clean payloads modified/rejected (expected HTTP 200). Offending files: {', '.join(failed[:10])}"


def test_evil_corpus():
    evil_files = [f for f in os.listdir(EVIL_CORPUS) if f.endswith(".json")]
    assert len(evil_files) > 0, "Evil corpus directory is empty."

    client = redis.Redis(host="127.0.0.1", port=6379, db=0)
    before = client.get("processed_count")
    failed = []
    for fname in evil_files:
        with open(os.path.join(EVIL_CORPUS, fname), "r") as f:
            payload = json.load(f)
        status = send_request(payload)
        if status != 403:
            failed.append(fname)

    assert not failed, f"{len(failed)} of {len(evil_files)} evil payloads bypassed (expected HTTP 403). Offending files: {', '.join(failed[:10])}"
    assert client.get("processed_count") == before, "Blocked corpus requests reached the API/Redis"


def test_dynamic_detection_exact_forwarding_and_backend_response():
    log_path = "/tmp/verifier_backend_requests.log"
    backend_path = "/tmp/verifier_echo_backend.py"
    try:
        os.unlink(log_path)
    except FileNotFoundError:
        pass

    backend_source = r'''from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import base64, hashlib
LOG = "/tmp/verifier_backend_requests.log"
class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        with open(LOG, "ab") as f:
            f.write(base64.b64encode(body) + b"\n")
            f.flush()
        digest = hashlib.sha256(body).hexdigest()
        response = ("BACKEND:" + digest).encode("ascii")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("X-Backend-Proof", digest)
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)
    def log_message(self, *args):
        pass
ThreadingHTTPServer(("127.0.0.1", 8082), Handler).serve_forever()
'''
    with open(backend_path, "w") as f:
        f.write(backend_source)

    api_processes = listener_processes(8082)
    assert api_processes and any("api.py" in cmd for _, cmd in api_processes)
    for pid, _ in api_processes:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass

    deadline = time.time() + 5
    while listener_inodes(8082) and time.time() < deadline:
        time.sleep(0.05)
    assert not listener_inodes(8082), "Could not stop the API for forwarding verification"

    backend = subprocess.Popen(["python3", backend_path], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    try:
        wait_for_port(8082)

        safe_payloads = [
            {
                "username": "member_" + uuid.uuid4().hex,
                "comment": "Project meeting notes " + uuid.uuid4().hex,
                "metadata": {"ticket": uuid.uuid4().hex, "priority": 3},
            },
            {
                "username": "guest_" + uuid.uuid4().hex,
                "comment": "Please archive the quarterly report " + uuid.uuid4().hex,
                "enabled": True,
            },
        ]

        expected_logged = []
        for index, payload in enumerate(safe_payloads):
            if index == 0:
                raw = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            else:
                raw = ("  " + json.dumps(payload, ensure_ascii=False, indent=2) + "\n").encode("utf-8")
            digest = hashlib.sha256(raw).hexdigest()
            status, body, headers = request_raw(raw, {"X-Request-Nonce": uuid.uuid4().hex})
            assert status == 200, f"Generated clean payload returned {status}"
            assert body == ("BACKEND:" + digest).encode("ascii"), "WAF did not return the backend's response body"
            assert headers.get("X-Backend-Proof") == digest, "WAF did not return the backend's proof header"
            expected_logged.append(raw)

        with open(log_path, "rb") as f:
            logged = [base64.b64decode(line.strip()) for line in f if line.strip()]
        assert logged == expected_logged, "Accepted JSON request bodies were not forwarded exactly to port 8082"

        token = uuid.uuid4().hex
        evil_comments = [
            f"review <ScRiPt>alert('{token}')</sCrIpT> now",
            f"image <script src='https://invalid.example/{token}.js'></script>",
            f"lookup UnIoN   SeLeCt password FROM accounts WHERE id='{token}'",
            f"report UNION\tSELECT secret FROM users -- {token}",
            f"open ../../etc/passwd for {token}",
            f"read ../etc/passwd then {token}",
        ]
        before_lines = len(logged)
        for comment in evil_comments:
            payload = {
                "username": "member_" + uuid.uuid4().hex,
                "comment": comment,
            }
            status = send_request(payload)
            assert status == 403, f"Generated malicious payload was not blocked: {comment!r}"

        time.sleep(0.25)
        with open(log_path, "rb") as f:
            after_lines = sum(1 for line in f if line.strip())
        assert after_lines == before_lines, "A generated malicious request was forwarded to the backend"
    finally:
        backend.terminate()
        try:
            backend.wait(timeout=3)
        except subprocess.TimeoutExpired:
            backend.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
