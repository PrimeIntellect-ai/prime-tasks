#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import hmac
import os
import secrets
import socket
import subprocess
import sys
import time
import urllib.error
import urllib.request

import pytest

TRACE_FILE = "/tmp/waf_backend_trace.jsonl"
PROBE_SECRET = secrets.token_hex(32)

PROBE_CODE = r'''
import hashlib
import hmac
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

secret = os.environ["PROBE_SECRET"].encode()
trace = os.environ["TRACE_FILE"]

class Handler(BaseHTTPRequestHandler):
    def handle_request(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        message = self.command.encode() + b"\n" + self.path.encode() + b"\n" + body
        signature = hmac.new(secret, message, hashlib.sha256).hexdigest()
        with open(trace, "a") as f:
            f.write(json.dumps({"method": self.command, "path": self.path,
                                "body_sha256": hashlib.sha256(body).hexdigest()}) + "\n")
        response = ("BACKEND_PROBE:" + signature).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    do_GET = handle_request
    do_POST = handle_request
    do_PUT = handle_request
    do_DELETE = handle_request

    def log_message(self, fmt, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", 5000), Handler).serve_forever()
'''


def wait_for_port(port, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.2):
                return True
        except OSError:
            time.sleep(0.1)
    return False


@pytest.fixture(scope="session", autouse=True)
def controlled_services():
    config_test = subprocess.run(
        ["nginx", "-t", "-c", "/home/user/nginx.conf"],
        capture_output=True, text=True, timeout=5
    )
    assert config_test.returncode == 0, config_test.stdout + config_test.stderr

    subprocess.run(["pkill", "-f", "/app/backend.py"], capture_output=True)
    deadline = time.time() + 3
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", 5000), timeout=0.1):
                time.sleep(0.1)
        except OSError:
            break

    open(TRACE_FILE, "w").close()
    env = os.environ.copy()
    env["PROBE_SECRET"] = PROBE_SECRET
    env["TRACE_FILE"] = TRACE_FILE
    backend = subprocess.Popen([sys.executable, "-c", PROBE_CODE], env=env)
    assert wait_for_port(5000), "Controlled Flask-backend probe did not start on port 5000"

    subprocess.run(["pkill", "-TERM", "-x", "nginx"], capture_output=True)
    time.sleep(0.5)
    nginx_start = subprocess.run(
        ["nginx", "-c", "/home/user/nginx.conf"],
        capture_output=True, text=True, timeout=5
    )
    assert nginx_start.returncode == 0, nginx_start.stdout + nginx_start.stderr
    assert wait_for_port(8080), "Nginx did not listen on port 8080"

    yield

    subprocess.run(["pkill", "-TERM", "-x", "nginx"], capture_output=True)
    backend.terminate()
    try:
        backend.wait(timeout=2)
    except subprocess.TimeoutExpired:
        backend.kill()


def expected_probe_body(method, path, body):
    message = method.encode() + b"\n" + path.encode() + b"\n" + body
    signature = hmac.new(PROBE_SECRET.encode(), message, hashlib.sha256).hexdigest()
    return "BACKEND_PROBE:" + signature


def trace_size():
    return os.path.getsize(TRACE_FILE) if os.path.exists(TRACE_FILE) else 0


def test_waf_script_exists():
    assert os.path.isfile("/home/user/waf.py"), "WAF script /home/user/waf.py does not exist."


def test_nginx_config_updated():
    conf_path = "/home/user/nginx.conf"
    assert os.path.isfile(conf_path), f"Nginx configuration missing at {conf_path}"

    with open(conf_path, "r") as f:
        conf = f.read()

    assert "127.0.0.1:8000" in conf, "Nginx config does not proxy to the WAF on port 8000."
    assert "/health" in conf, "Nginx config does not contain a /health location block."


def test_health_check_endpoint():
    before = trace_size()
    req = urllib.request.Request("http://127.0.0.1:8080/health")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected 200 OK for /health, got {response.status}"
            body = response.read().decode("utf-8").strip()
            assert "WAF OK" in body, f"Expected 'WAF OK' in body, got {body}"
            assert body == "WAF OK", f"Expected plain text 'WAF OK', got {body}"
    except urllib.error.HTTPError as e:
        pytest.fail(f"Health check failed with HTTP {e.code}")
    except urllib.error.URLError as e:
        pytest.fail(f"Health check failed to connect: {e.reason}")

    with urllib.request.urlopen("http://127.0.0.1:8000/status", timeout=5) as response:
        assert response.status == 200
        assert response.read().decode("utf-8").strip() == "WAF OK"
    time.sleep(0.1)
    assert trace_size() == before, "Health requests were forwarded to the backend instead of handled by the WAF"


def test_adversarial_corpus_filtering():
    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.json"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.json"))

    assert clean_files, f"No files found in clean corpus directory {clean_dir}"
    assert evil_files, f"No files found in evil corpus directory {evil_dir}"

    failed_clean = []
    for fpath in clean_files:
        with open(fpath, "rb") as f:
            data = f.read()
        req = urllib.request.Request("http://127.0.0.1:8080/api", data=data, method="POST")
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status != 200:
                    failed_clean.append(os.path.basename(fpath))
        except urllib.error.HTTPError as e:
            if e.code != 200:
                failed_clean.append(os.path.basename(fpath))
        except Exception:
            failed_clean.append(os.path.basename(fpath))

    failed_evil = []
    for fpath in evil_files:
        with open(fpath, "rb") as f:
            data = f.read()
        req = urllib.request.Request("http://127.0.0.1:8080/api", data=data, method="POST")
        req.add_header("Content-Type", "application/json")
        try:
            with urllib.request.urlopen(req, timeout=5) as response:
                if response.status != 403:
                    failed_evil.append(os.path.basename(fpath))
        except urllib.error.HTTPError as e:
            if e.code != 403:
                failed_evil.append(os.path.basename(fpath))
        except Exception:
            failed_evil.append(os.path.basename(fpath))

    err_msgs = []
    if failed_clean:
        err_msgs.append(f"{len(failed_clean)} of {len(clean_files)} clean modified/rejected: {', '.join(failed_clean)}")
    if failed_evil:
        err_msgs.append(f"{len(failed_evil)} of {len(evil_files)} evil bypassed: {', '.join(failed_evil)}")

    if err_msgs:
        pytest.fail(" | ".join(err_msgs))


def test_dynamic_forwarding_filtering_and_rejection_logging():
    nonce = secrets.token_hex(12)
    path = "/api?probe=" + nonce
    clean = ('{"data":"clean_payload_' + nonce + '"}').encode()
    clean_req = urllib.request.Request(
        "http://127.0.0.1:8080" + path, data=clean, method="POST",
        headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(clean_req, timeout=5) as response:
        assert response.status == 200
        body = response.read().decode()
    assert body == expected_probe_body("POST", path, clean), \
        "Accepted request did not return the controlled backend's derived response"

    log_file = "/home/user/waf_rejects.log"
    with open(log_file, "w"):
        pass
    with open(TRACE_FILE, "w"):
        pass

    evil = ('{"data":"eval(\'malicious_' + nonce + '\')"}').encode()
    evil_req = urllib.request.Request(
        "http://127.0.0.1:8080/api", data=evil, method="POST",
        headers={"Content-Type": "application/json"}
    )
    with pytest.raises(urllib.error.HTTPError) as exc:
        urllib.request.urlopen(evil_req, timeout=5)
    assert exc.value.code == 403

    deadline = time.time() + 2
    while time.time() < deadline and (not os.path.exists(log_file) or os.path.getsize(log_file) == 0):
        time.sleep(0.05)
    assert os.path.isfile(log_file), "WAF did not create the rejection log"
    assert os.path.getsize(log_file) > 0, "WAF did not append a log entry for the rejected request"
    time.sleep(0.1)
    assert trace_size() == 0, "Rejected request was forwarded to the backend"


def test_storage_monitoring():
    log_file = "/home/user/waf_rejects.log"
    bash_script = "/home/user/monitor_quota.sh"
    py_script = "/home/user/monitor_quota.py"

    if os.path.exists(bash_script):
        cmd = ["bash", bash_script]
    elif os.path.exists(py_script):
        cmd = ["python3", py_script]
    else:
        pytest.fail("Monitor script not found. Expected monitor_quota.sh or monitor_quota.py")

    # Artificially pad the log file to 2048 bytes
    with open(log_file, "w") as f:
        f.write("A" * 2048)

    try:
        res = subprocess.run(cmd, capture_output=True, text=True, timeout=5)
        assert "Quota exceeded, log truncated" in res.stdout, f"Monitor script did not print expected output. Got: {res.stdout}"
        assert os.path.getsize(log_file) == 0, f"Log file was not truncated to 0 bytes. Size is {os.path.getsize(log_file)}"
    finally:
        if os.path.exists(log_file):
            os.remove(log_file)
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
