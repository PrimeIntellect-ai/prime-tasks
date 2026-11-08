#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import glob
import socket
import urllib.request
import urllib.error
import pytest
import datetime
import subprocess
import time
import secrets
from pathlib import Path
from zoneinfo import ZoneInfo

TOKEN = secrets.token_hex(24)
REQUEST_LOG = f"/tmp/verifier_backend_requests_{secrets.token_hex(8)}.log"
BACKENDS = {}

BACKEND_SOURCE = r'''
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
import sys

port = int(sys.argv[1])
token = sys.argv[2]
log_path = sys.argv[3]

class ReusableServer(ThreadingHTTPServer):
    allow_reuse_address = True

class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.0"

    def do_GET(self):
        with open(log_path, "a", encoding="utf-8") as log:
            log.write(self.path + "\n")
        proxy_time = self.headers.get("X-Proxy-Time", "MISSING")
        body = (
            f"Backend {port} - Time: {proxy_time}\n"
            f"Verifier-Token: {token}\n"
            f"Request-Target: {self.path}\n"
        ).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass

ReusableServer(("127.0.0.1", port), Handler).serve_forever()
'''


def kill_original_backends():
    for port in (8081, 8082):
        try:
            output = subprocess.check_output(
                ["pgrep", "-f", f"backend.py {port}"], text=True
            ).strip()
        except subprocess.CalledProcessError:
            output = ""
        for value in output.split():
            pid = int(value)
            if pid != os.getpid():
                try:
                    os.kill(pid, 9)
                except ProcessLookupError:
                    pass
    time.sleep(0.4)


def wait_for_port(port, timeout=4):
    deadline = time.time() + timeout
    while time.time() < deadline:
        with socket.socket() as sock:
            sock.settimeout(0.1)
            if sock.connect_ex(("127.0.0.1", port)) == 0:
                return
        time.sleep(0.05)
    raise AssertionError(f"Verifier backend on port {port} did not start")


@pytest.fixture(scope="session", autouse=True)
def verifier_backends():
    kill_original_backends()
    Path(REQUEST_LOG).write_text("", encoding="utf-8")
    script = "/tmp/verifier_backend.py"
    Path(script).write_text(BACKEND_SOURCE, encoding="utf-8")
    for port in (8081, 8082):
        proc = subprocess.Popen(
            ["python3", script, str(port), TOKEN, REQUEST_LOG],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        BACKENDS[port] = proc
    for port in (8081, 8082):
        wait_for_port(port)
    yield
    for proc in BACKENDS.values():
        if proc.poll() is None:
            proc.kill()
            proc.wait(timeout=2)


def listening_socket_inodes(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            lines = Path(table).read_text().splitlines()[1:]
        except OSError:
            continue
        for line in lines:
            fields = line.split()
            local = fields[1]
            state = fields[3]
            if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                inodes.add(fields[9])
    return inodes


def assert_pid_owns_listener(pid, port):
    wanted = listening_socket_inodes(port)
    assert wanted, f"Nothing is listening on port {port}"
    owned = set()
    try:
        for fd in os.listdir(f"/proc/{pid}/fd"):
            try:
                target = os.readlink(f"/proc/{pid}/fd/{fd}")
            except OSError:
                continue
            if target.startswith("socket:["):
                owned.add(target[8:-1])
    except FileNotFoundError:
        pytest.fail(f"PID {pid} is not alive")
    assert wanted & owned, f"PID {pid} does not own the listener on port {port}"


def extract_time(body):
    first_line = body.splitlines()[0]
    assert "Time: " in first_line and "MISSING" not in first_line
    time_str = first_line.split("Time: ", 1)[1].strip()
    parsed = datetime.datetime.strptime(time_str, "%Y-%m-%d %H:%M:%S")
    berlin = ZoneInfo("Europe/Berlin")
    now_utc = datetime.datetime.now(datetime.timezone.utc)
    differences = []
    for fold in (0, 1):
        candidate = parsed.replace(tzinfo=berlin, fold=fold).astimezone(datetime.timezone.utc)
        differences.append(abs((now_utc - candidate).total_seconds()))
    assert min(differences) <= 15, f"X-Proxy-Time is not the current Europe/Berlin time: {time_str}"
    return time_str


def fetch(uri, timeout=3):
    req = urllib.request.Request(f"http://127.0.0.1:8080{uri}")
    response = urllib.request.urlopen(req, timeout=timeout)
    body = response.read().decode("utf-8")
    return response, body


def assert_genuine_backend_response(body, expected_target=None):
    assert f"Verifier-Token: {TOKEN}" in body, "Response was not returned by a verifier backend"
    if expected_target is not None:
        assert f"Request-Target: {expected_target}" in body, "Proxy did not forward the original request target"
    extract_time(body)


def test_proxy_pid_file():
    proxy_file = "/home/user/proxy.py"
    assert os.path.isfile(proxy_file), f"{proxy_file} does not exist or is not a regular file"
    assert os.path.getsize(proxy_file) > 0, f"{proxy_file} is empty"
    subprocess.run(["python3", "-m", "py_compile", proxy_file], check=True)

    pid_file = "/home/user/proxy.pid"
    assert os.path.exists(pid_file), f"{pid_file} does not exist"
    with open(pid_file, "r") as f:
        pid_text = f.read().strip()
    assert pid_text.isdigit(), f"{pid_file} does not contain a valid PID"
    pid = int(pid_text)
    try:
        os.kill(pid, 0)
    except OSError as exc:
        pytest.fail(f"Proxy PID {pid} is not alive: {exc}")
    cmdline = Path(f"/proc/{pid}/cmdline").read_bytes().replace(b"\0", b" ").decode("utf-8", "replace")
    assert "proxy.py" in cmdline, f"PID {pid} is not running the proxy script"
    assert_pid_owns_listener(pid, 8080)


def test_evil_corpus():
    evil_files = glob.glob("/home/user/corpus/evil/*.txt")
    assert len(evil_files) > 0, "No evil corpus files found in /home/user/corpus/evil"
    bypassed = []
    for filename in evil_files:
        with open(filename, "r") as file:
            uri = file.read().strip()
        uri = uri.replace(" ", "%20")
        try:
            urllib.request.urlopen(urllib.request.Request(f"http://127.0.0.1:8080{uri}"), timeout=2)
            bypassed.append(os.path.basename(filename))
        except urllib.error.HTTPError as exc:
            if exc.code != 403:
                bypassed.append(os.path.basename(filename))
        except Exception:
            bypassed.append(os.path.basename(filename))
    assert not bypassed, f"{len(bypassed)} of {len(evil_files)} evil bypassed: {', '.join(bypassed)}"


def test_dynamic_waf_patterns_are_blocked_without_forwarding():
    nonce = secrets.token_hex(10)
    evil_uris = [
        f"/waf/{nonce}?q=uNiOn+SeLeCt+value",
        f"/waf/{nonce}/../private",
        f"/waf/{nonce}?q=<ScRiPt>alert(1)</sCrIpT>",
        f"/waf/{nonce}?q=EvAl(test)",
    ]
    for uri in evil_uris:
        with pytest.raises(urllib.error.HTTPError) as caught:
            urllib.request.urlopen(
                urllib.request.Request(f"http://127.0.0.1:8080{uri}"), timeout=2
            )
        assert caught.value.code == 403, f"Dynamic malicious URI was not rejected: {uri}"
    time.sleep(0.15)
    backend_log = Path(REQUEST_LOG).read_text(encoding="utf-8")
    assert nonce not in backend_log, "A WAF-blocked request was forwarded to a backend"


def test_clean_corpus_and_timezone():
    clean_files = glob.glob("/home/user/corpus/clean/*.txt")
    assert len(clean_files) > 0, "No clean corpus files found in /home/user/corpus/clean"
    modified = []
    for filename in clean_files:
        with open(filename, "r") as file:
            uri = file.read().strip()
        uri = uri.replace(" ", "%20")
        try:
            response, body = fetch(uri, timeout=2)
            if response.status != 200:
                modified.append(os.path.basename(filename))
                continue
            assert_genuine_backend_response(body, uri)
        except Exception:
            modified.append(os.path.basename(filename))
    assert not modified, f"{len(modified)} of {len(clean_files)} clean modified or failed: {', '.join(modified)}"


def test_dynamic_forwarding_and_round_robin():
    nonce = secrets.token_hex(12)
    ports = []
    for index in range(6):
        uri = f"/verify/{nonce}/{index}?value={nonce}{index}"
        response, body = fetch(uri)
        assert response.status == 200
        assert_genuine_backend_response(body, uri)
        if "Backend 8081" in body:
            ports.append(8081)
        elif "Backend 8082" in body:
            ports.append(8082)
        else:
            pytest.fail("Response did not identify either configured backend")
    assert set(ports) == {8081, 8082}, f"Requests did not reach both backends: {ports}"
    assert all(a != b for a, b in zip(ports, ports[1:])), f"Backends were not selected round-robin: {ports}"


def test_failover():
    try:
        pids = subprocess.check_output(["pgrep", "-f", "backend.py 8081"]).decode().strip().split()
        for pid in pids:
            subprocess.run(["kill", "-9", pid])
    except subprocess.CalledProcessError:
        pass
    time.sleep(1)

    url = "http://127.0.0.1:8080/api/v1/status"
    try:
        req = urllib.request.Request(url)
        response = urllib.request.urlopen(req, timeout=3)
        assert response.status == 200
        body = response.read().decode("utf-8")
        assert "Backend 8082" in body, "Failover to Backend B failed, response did not indicate Backend 8082"
        assert_genuine_backend_response(body, "/api/v1/status")
    except Exception as exc:
        pytest.fail(f"Failover test failed: {exc}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
