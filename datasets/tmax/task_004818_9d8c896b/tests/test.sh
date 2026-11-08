#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import hashlib
import http.client
import json
import os
import random
import re
import secrets
import signal
import socket
import string
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

WAF_DIR = "/home/user/waf"
VALIDATOR = os.path.join(WAF_DIR, "validator.py")
PROXY = os.path.join(WAF_DIR, "proxy.py")
NGINX_CONF = "/home/user/gateway/nginx.conf"
EVIL_CORPUS = "/app/corpus/evil"
CLEAN_CORPUS = "/app/corpus/clean"

_backend = None
_proxy_process = None
_backend_bodies = []


def strict_loads(payload):
    return json.loads(payload, parse_constant=lambda value: (_ for _ in ()).throw(ValueError(value)))


def expected_clean(payload):
    try:
        value = strict_loads(payload)
    except Exception:
        return False
    if type(value) is not dict or set(value.keys()) != {"device_id", "readings"}:
        return False
    device_id = value["device_id"]
    if type(device_id) is not str or re.fullmatch(r"[A-Za-z0-9-]+", device_id) is None:
        return False
    readings = value["readings"]
    if type(readings) is not dict:
        return False
    return all(type(item) in (int, float) for item in readings.values())


def load_validator():
    assert os.path.isfile(VALIDATOR), "validator.py is missing"
    sys.path.insert(0, WAF_DIR)
    sys.modules.pop("validator", None)
    try:
        from validator import is_clean
    except Exception as exc:
        pytest.fail(f"Could not import is_clean from {VALIDATOR}: {exc}")
    finally:
        if sys.path and sys.path[0] == WAF_DIR:
            sys.path.pop(0)
    return is_clean


def generated_payloads():
    rng = random.SystemRandom()
    alphabet = string.ascii_letters + string.digits
    payloads = []

    for _ in range(80):
        device = "dev-" + "".join(rng.choice(alphabet) for _ in range(rng.randint(8, 28)))
        readings = {}
        for n in range(rng.randint(0, 8)):
            key = "metric_" + "".join(rng.choice(string.ascii_lowercase) for _ in range(8)) + str(n)
            readings[key] = rng.randint(-10**8, 10**8) if rng.choice([True, False]) else rng.uniform(-100000, 100000)
        payloads.append(json.dumps({"device_id": device, "readings": readings}, separators=(",", ":")))

    bad_ids = [
        "bad id", "x;rm", "quote'", 'quote"', "a/b", "a_b", "$(id)", "line\nbreak",
        "tabs\there", "percent%", "question?", "dot.name", "colon:name", "bracket[1]", "",
    ]
    bad_values = [True, False, None, "12", "NaN", [], {}, [1], {"nested": 2}]
    for _ in range(20):
        suffix = secrets.token_hex(6)
        payloads.extend([
            json.dumps({"device_id": rng.choice(bad_ids) + suffix, "readings": {}}),
            json.dumps({"device_id": "device-" + suffix, "readings": {"m": rng.choice(bad_values)}}),
            json.dumps({"device_id": "device-" + suffix}),
            json.dumps({"device_id": "device-" + suffix, "readings": {}, "extra_" + suffix: 1}),
            json.dumps({"readings": {"m": 1}}),
            json.dumps({"device_id": rng.randint(1, 1000), "readings": {}}),
            json.dumps({"device_id": "device-" + suffix, "readings": [1, 2]}),
            json.dumps(["device-" + suffix, {"m": 1}]),
        ])

    nonce = secrets.token_hex(12)
    payloads.extend([
        "",
        "not-json-" + nonce,
        '{"device_id":"dev-' + nonce + '","readings":',
        '{"device_id":"dev-' + nonce + '","readings":{}} trailing',
        '{"device_id":"dev-' + nonce + '","readings":{"x":NaN}}',
        '{"device_id":"dev-' + nonce + '","readings":{"x":Infinity}}',
        "null", "true", "42", '"string"', "{}",
    ])
    rng.shuffle(payloads)
    return payloads


def test_01_validator_corpus_and_generated_suite():
    is_clean = load_validator()

    evil_files = glob.glob(os.path.join(EVIL_CORPUS, "*.json"))
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS, "*.json"))
    if not evil_files or not clean_files:
        pytest.fail("Corpus files are missing. Cannot validate.")

    evil_bypassed = []
    for fpath in evil_files:
        payload = open(fpath, "r").read()
        try:
            if is_clean(payload) is not False:
                evil_bypassed.append(os.path.basename(fpath))
        except Exception:
            evil_bypassed.append(os.path.basename(fpath) + " (raised exception)")

    clean_modified = []
    for fpath in clean_files:
        payload = open(fpath, "r").read()
        try:
            if is_clean(payload) is not True:
                clean_modified.append(os.path.basename(fpath))
        except Exception:
            clean_modified.append(os.path.basename(fpath) + " (raised exception)")

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_modified)}")
    if errors:
        pytest.fail(" | ".join(errors))

    failures = []
    cases = generated_payloads()
    for index, payload in enumerate(cases):
        expected = expected_clean(payload)
        try:
            actual = is_clean(payload)
        except Exception as exc:
            failures.append(f"case {index} raised {type(exc).__name__}")
            continue
        if actual is not expected:
            failures.append(f"case {index}: expected {expected}, got {actual!r}; payload={payload[:160]!r}")
    assert not failures, "Validator failed generated cases:\n" + "\n".join(failures[:20])


def test_02_nginx_config_updated_and_valid():
    assert os.path.exists(NGINX_CONF), "nginx.conf missing"
    with open(NGINX_CONF, "r") as f:
        content = f.read()
    assert "127.0.0.1:8081" in content, "Nginx config not updated to point to WAF proxy on port 8081"
    assert "127.0.0.1:5000" not in content, "Nginx config still points to Flask backend on port 5000"
    result = subprocess.run(["nginx", "-t", "-c", NGINX_CONF], text=True, capture_output=True)
    assert result.returncode == 0, f"nginx.conf is not valid:\n{result.stdout}\n{result.stderr}"


def git_command(*args, timeout=15):
    return subprocess.run(
        ["git", "-c", f"safe.directory={WAF_DIR}", "-C", WAF_DIR, *args],
        text=True, capture_output=True, timeout=timeout,
    )


def test_03_git_repo_commit_and_hook():
    git_dir = os.path.join(WAF_DIR, ".git")
    assert os.path.isdir(git_dir), f"Git repository not initialized in {WAF_DIR}"

    hook_path = os.path.join(git_dir, "hooks", "post-commit")
    assert os.path.isfile(hook_path), "post-commit hook not found"
    assert os.access(hook_path, os.X_OK), "post-commit hook is not executable"

    count = git_command("rev-list", "--count", "HEAD")
    assert count.returncode == 0 and int(count.stdout.strip()) >= 1, "WAF repository has no initial commit"
    tracked = git_command("ls-files", "validator.py", "proxy.py")
    assert tracked.returncode == 0, tracked.stderr
    assert set(tracked.stdout.splitlines()) == {"validator.py", "proxy.py"}, "validator.py and proxy.py must be tracked by Git"


def listener_pids(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = open(table).read().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                inodes.add(fields[9])
    pids = set()
    for name in os.listdir("/proc"):
        if not name.isdigit() or int(name) == os.getpid():
            continue
        fd_dir = f"/proc/{name}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    pids.add(int(name))
        except OSError:
            pass
    return pids


def kill_listeners(port):
    pids = listener_pids(port)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and listener_pids(port):
        time.sleep(0.05)
    for pid in listener_pids(port):
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.15)


def wait_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=0.25):
                return True
        except OSError:
            time.sleep(0.1)
    return False


class RecordingBackend(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        _backend_bodies.append((self.path, body))
        response = b"backend-ack:" + hashlib.sha256(body).hexdigest().encode("ascii")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(response)))
        self.end_headers()
        self.wfile.write(response)

    def log_message(self, *args):
        pass


def start_backend():
    global _backend
    kill_listeners(5000)
    _backend_bodies.clear()
    _backend = ThreadingHTTPServer(("127.0.0.1", 5000), RecordingBackend)
    threading.Thread(target=_backend.serve_forever, daemon=True).start()
    assert wait_port(5000), "Could not start verification backend"


def start_proxy_artifact():
    global _proxy_process
    assert os.path.isfile(PROXY), "proxy.py is missing"
    kill_listeners(8081)
    _proxy_process = subprocess.Popen(
        [sys.executable, PROXY], cwd=WAF_DIR,
        stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True,
    )
    if not wait_port(8081):
        error = ""
        if _proxy_process.poll() is not None and _proxy_process.stderr:
            error = _proxy_process.stderr.read()
        pytest.fail(f"proxy.py did not listen on 127.0.0.1:8081: {error}")


def restart_nginx_from_submission():
    kill_listeners(8080)
    try:
        os.remove("/tmp/nginx.pid")
    except FileNotFoundError:
        pass
    result = subprocess.run(["nginx", "-c", NGINX_CONF], text=True, capture_output=True)
    assert result.returncode == 0, f"Could not start Nginx with submitted config: {result.stderr}"
    assert wait_port(8080), "Nginx did not listen on port 8080"


def request_through_nginx(body):
    request = urllib.request.Request(
        "http://127.0.0.1:8080/telemetry", data=body, method="POST",
        headers={"Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=4) as response:
            return response.status, response.read()
    except urllib.error.HTTPError as exc:
        return exc.code, exc.read()
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to route payload through Nginx: {exc}")


def clean_body():
    token = secrets.token_hex(10)
    return json.dumps({
        "device_id": "sensor-" + token,
        "readings": {"temperature": random.uniform(-30, 80), "sequence": random.randint(1, 10**7)},
    }, separators=(",", ":")).encode()


def evil_bodies():
    token = secrets.token_hex(8)
    return [
        json.dumps({"device_id": "bad id " + token, "readings": {"x": 1}}).encode(),
        json.dumps({"device_id": "dev-" + token, "readings": {"x": "12"}}).encode(),
        json.dumps({"device_id": "dev-" + token, "readings": {"x": True}}).encode(),
        json.dumps({"device_id": "dev-" + token, "readings": {}, "extra": token}).encode(),
        b'{"device_id":"dev-' + token.encode() + b'","readings":',
    ]


def assert_clean_forwarded(body):
    before = len(_backend_bodies)
    status, response = request_through_nginx(body)
    assert status == 200, f"Clean payload returned {status}, not 200"
    expected_response = b"backend-ack:" + hashlib.sha256(body).hexdigest().encode("ascii")
    assert response == expected_response, "Proxy did not return the backend response unchanged"
    assert len(_backend_bodies) == before + 1, "Clean payload was not forwarded exactly once"
    assert _backend_bodies[-1] == ("/telemetry", body), "Proxy did not forward the exact body to /telemetry"


def assert_evil_blocked(body):
    before = len(_backend_bodies)
    status, _ = request_through_nginx(body)
    assert status == 403, f"Malicious or malformed payload returned {status}, not 403"
    time.sleep(0.05)
    assert len(_backend_bodies) == before, "Blocked payload was forwarded to the Flask backend"


def test_04_execute_proxy_and_end_to_end_randomized():
    start_backend()
    start_proxy_artifact()
    restart_nginx_from_submission()

    for _ in range(8):
        assert_clean_forwarded(clean_body())
    for body in evil_bodies():
        assert_evil_blocked(body)


def test_05_post_commit_hook_restarts_working_proxy():
    global _proxy_process
    kill_listeners(8081)
    if _proxy_process is not None:
        try:
            _proxy_process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            _proxy_process.kill()

    marker = "verifier-hook-" + secrets.token_hex(8)
    commit = git_command(
        "-c", "user.name=Verifier",
        "-c", "user.email=verifier@localhost",
        "commit", "--allow-empty", "-m", marker,
        timeout=20,
    )
    assert commit.returncode == 0, f"Creating a commit to exercise post-commit failed:\n{commit.stdout}\n{commit.stderr}"
    assert wait_port(8081, timeout=10), "post-commit hook did not restart proxy.py on port 8081"

    assert_clean_forwarded(clean_body())
    for body in evil_bodies():
        assert_evil_blocked(body)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
