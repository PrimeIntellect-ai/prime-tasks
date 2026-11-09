#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import signal
import subprocess
import sys
import time

import pytest
import requests

APP = "/home/user/app"
PORTS = (8000, 8001, 8080)


def stop_ports(*ports):
    wanted = set(ports)
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10 or fields[3] != "0A":
                        continue
                    port = int(fields[1].rsplit(":", 1)[1], 16)
                    if port in wanted:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    link = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if link.startswith("socket:[") and link[8:-1] in inodes:
                    victims.add(int(pid))
                    break
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.4)
    for pid in victims:
        try:
            os.kill(pid, 0)
            os.kill(pid, signal.SIGKILL)
        except (ProcessLookupError, PermissionError):
            pass


def wait_for(url, timeout=12):
    deadline = time.time() + timeout
    last_error = None
    while time.time() < deadline:
        try:
            response = requests.get(url, timeout=0.5)
            if response.status_code == 200:
                return response
        except requests.RequestException as exc:
            last_error = exc
        time.sleep(0.15)
    pytest.fail(f"Service did not become ready at {url}: {last_error}")


def process_records():
    records = []
    for pid in os.listdir("/proc"):
        if not pid.isdigit():
            continue
        try:
            with open(f"/proc/{pid}/cmdline", "rb") as f:
                cmd = f.read().replace(b"\0", b" ").decode(errors="replace")
            exe = os.path.realpath(f"/proc/{pid}/exe")
            records.append((int(pid), cmd, exe))
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    return records


@pytest.fixture(scope="module", autouse=True)
def running_stack():
    stop_ports(*PORTS)
    log = open("/tmp/start-sh.log", "w")
    proc = subprocess.Popen(
        ["runuser", "-u", "user", "--", "bash", os.path.join(APP, "start.sh")],
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        wait_for("http://127.0.0.1:8080/status")
        yield proc
    finally:
        try:
            os.killpg(proc.pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
        stop_ports(*PORTS)
        log.close()


def test_files_exist():
    assert os.path.isfile(os.path.join(APP, "nginx.conf")), "nginx.conf is missing"
    assert os.path.isfile(os.path.join(APP, "router.py")), "router.py is missing"
    assert os.path.isfile(os.path.join(APP, "start.sh")), "start.sh is missing"


def test_start_script_started_required_programs():
    records = process_records()
    assert any("nginx: master process" in cmd and "nginx.conf" in cmd for _, cmd, _ in records), \
        "start.sh did not start Nginx with nginx.conf"
    assert any("router.py" in cmd and "python" in cmd.lower() for _, cmd, _ in records), \
        "start.sh did not start router.py"
    builder = os.path.realpath(os.path.join(APP, "builder"))
    assert any(exe == builder for _, _, exe in records), \
        "start.sh did not start the supplied builder executable"


def test_status_endpoint():
    url = "http://127.0.0.1:8080/status"
    try:
        response = requests.get(url, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert response.json() == {"status": "ok"}


def test_build_endpoint_success():
    url = "http://127.0.0.1:8080/build"
    payload = {"version": "1.5.2", "constraint": ">= 1.5.0", "target": "ios"}
    try:
        response = requests.post(url, json=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    assert response.json() == {"triggered": "ios"}


def test_build_endpoint_failure():
    url = "http://127.0.0.1:8080/build"
    payload = {"version": "1.4.9", "constraint": ">= 1.5.0", "target": "android"}
    try:
        response = requests.post(url, json=payload, timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to {url}: {e}")
    assert response.status_code == 400, f"Expected status code 400, got {response.status_code}. Response: {response.text}"
    try:
        json_data = response.json()
        assert json_data.get("error") == "version constraint not met", f"Expected error message 'version constraint not met', got {json_data.get('error')}"
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")


def test_randomized_semver_and_exact_builder_forwarding():
    # Replace only the listening builder process with an unpredictable test double.
    # Its nonce is not present in the client request, so the router can return it only
    # by forwarding the request and relaying the builder's JSON response.
    stop_ports(8001)
    nonce = secrets.token_hex(16)
    log_path = "/tmp/builder-spy-request.json"
    try:
        os.unlink(log_path)
    except FileNotFoundError:
        pass

    spy_source = f'''\
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
NONCE = {nonce!r}
LOG = {log_path!r}
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args):
        pass
    def do_GET(self):
        if self.path != "/status":
            self.send_response(404); self.end_headers(); return
        body = json.dumps({{"status": "ok", "builder_nonce": NONCE}}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
    def do_POST(self):
        length = int(self.headers.get("Content-Length", "0"))
        raw = self.rfile.read(length)
        try:
            payload = json.loads(raw)
        except Exception:
            payload = None
        with open(LOG, "w") as f:
            json.dump({{"path": self.path, "payload": payload}}, f)
        target = payload.get("target") if isinstance(payload, dict) else None
        body = json.dumps({{"triggered": target, "builder_nonce": NONCE}}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body))); self.end_headers(); self.wfile.write(body)
ThreadingHTTPServer(("127.0.0.1", 8001), Handler).serve_forever()
'''
    spy = subprocess.Popen([sys.executable, "-c", spy_source])
    try:
        wait_for("http://127.0.0.1:8001/status", timeout=5)
        major = secrets.randbelow(20) + 3
        patch = secrets.randbelow(50) + 1
        target = "target-" + secrets.token_hex(12)
        payload = {
            "version": f"{major}.2.{patch}-beta",
            "constraint": f">= {major}.1.{patch}",
            "target": target,
        }
        response = requests.post("http://127.0.0.1:8080/build", json=payload, timeout=4)
        assert response.status_code == 200, response.text
        assert response.json() == {"triggered": target, "builder_nonce": nonce}, \
            "The router did not return the builder's JSON response"

        deadline = time.time() + 2
        while time.time() < deadline and not os.path.exists(log_path):
            time.sleep(0.05)
        assert os.path.exists(log_path), "No request reached the builder /trigger endpoint"
        with open(log_path) as f:
            observed = json.load(f)
        assert observed == {"path": "/trigger", "payload": {"target": target}}, \
            "The router did not forward exactly the requested target to /trigger"

        failing = {
            "version": f"{major}.0.{patch}",
            "constraint": f">= {major}.1.{patch}",
            "target": "reject-" + secrets.token_hex(12),
        }
        response = requests.post("http://127.0.0.1:8080/build", json=failing, timeout=4)
        assert response.status_code == 400, response.text
        assert response.json() == {"error": "version constraint not met"}
    finally:
        spy.terminate()
        try:
            spy.wait(timeout=2)
        except subprocess.TimeoutExpired:
            spy.kill()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
