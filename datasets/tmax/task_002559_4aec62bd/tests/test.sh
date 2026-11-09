#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import hmac
import os
import random
import signal
import socket
import ssl
import string
import subprocess
import threading
import time
from http.server import HTTPServer, BaseHTTPRequestHandler

import pytest
import requests

PROXY_BINARY = "/tmp/secure_proxy_submission"
AUTH = {"Authorization": "Bearer 82045"}
UPSTREAM_SECRET = os.urandom(32)
UPSTREAM_REQUESTS = []


def kill_listeners(port):
    inodes = set()
    wanted = f"{port:04X}"
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) > 9 and fields[1].split(":")[-1].upper() == wanted and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    victims = set()
    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(pid))
                    break
        except OSError:
            pass

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


class ReusableHTTPServer(HTTPServer):
    allow_reuse_address = True


class MockUpstreamHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        probe = self.headers.get("X-Verifier-Probe", "")
        UPSTREAM_REQUESTS.append((self.command, self.path, probe))
        message = f"{self.command}|{self.path}|{probe}".encode()
        signature = hmac.new(UPSTREAM_SECRET, message, hashlib.sha256).hexdigest()
        body = ("UPSTREAM:" + signature).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/plain")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass


class TLSUpstream:
    def __init__(self):
        self.httpd = None
        self.thread = None

    def start(self, cert, key):
        self.httpd = ReusableHTTPServer(("127.0.0.1", 8443), MockUpstreamHandler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile=cert, keyfile=key)
        self.httpd.socket = context.wrap_socket(self.httpd.socket, server_side=True)
        self.thread = threading.Thread(target=self.httpd.serve_forever, daemon=True)
        self.thread.start()
        time.sleep(0.25)

    def stop(self):
        if self.httpd is not None:
            self.httpd.shutdown()
            self.httpd.server_close()
            self.thread.join(timeout=2)
            self.httpd = None
            self.thread = None
            time.sleep(0.25)

    def restart_with_untrusted_certificate(self):
        self.stop()
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes",
            "-days", "1", "-keyout", "/tmp/untrusted.key",
            "-out", "/tmp/untrusted.crt", "-subj", "/CN=127.0.0.1",
            "-addext", "subjectAltName=IP:127.0.0.1"
        ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        self.start("/tmp/untrusted.crt", "/tmp/untrusted.key")


@pytest.fixture(scope="module", autouse=True)
def proxy_env():
    kill_listeners(9090)
    kill_listeners(8443)

    upstream = TLSUpstream()
    upstream.start("/app/server.crt", "/app/server.key")
    proc = subprocess.Popen(
        [PROXY_BINARY],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        cwd="/home/user",
    )

    deadline = time.time() + 8
    while time.time() < deadline:
        if proc.poll() is not None:
            upstream.stop()
            pytest.fail(f"compiled proxy exited early with status {proc.returncode}")
        try:
            with socket.create_connection(("127.0.0.1", 9090), timeout=0.2):
                break
        except OSError:
            time.sleep(0.1)
    else:
        proc.kill()
        upstream.stop()
        pytest.fail("compiled proxy did not listen on 127.0.0.1:9090")

    yield upstream

    proc.terminate()
    try:
        proc.wait(timeout=2)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=2)
    upstream.stop()


def test_proxy_valid_relative_redirect():
    url = "http://127.0.0.1:9090/?next=/profile"
    response = requests.get(url, headers=AUTH, timeout=5)
    assert response.status_code == 200, f"Expected 200 OK for valid relative redirect, got {response.status_code}. Response: {response.text}"


def test_proxy_valid_absolute_redirect():
    url = "http://127.0.0.1:9090/?next=https://internal-corp.local/admin"
    response = requests.get(url, headers=AUTH, timeout=5)
    assert response.status_code == 200, f"Expected 200 OK for valid absolute redirect to internal-corp.local, got {response.status_code}. Response: {response.text}"


def test_proxy_invalid_redirect_evil_com():
    url = "http://127.0.0.1:9090/?next=http://evil.com/login"
    response = requests.get(url, headers=AUTH, timeout=5)
    assert response.status_code == 403, f"Expected 403 Forbidden for redirect to evil.com, got {response.status_code}. Response: {response.text}"


def test_proxy_invalid_redirect_protocol_relative():
    url = "http://127.0.0.1:9090/?next=//evil.com/login"
    response = requests.get(url, headers=AUTH, timeout=5)
    assert response.status_code == 403, f"Expected 403 Forbidden for protocol-relative redirect to evil.com, got {response.status_code}. Response: {response.text}"


def test_proxy_invalid_token():
    url = "http://127.0.0.1:9090/?next=/profile"
    response = requests.get(url, headers={"Authorization": "Bearer 99999"}, timeout=5)
    assert response.status_code == 401, f"Expected 401 Unauthorized for incorrect token, got {response.status_code}. Response: {response.text}"


def test_proxy_missing_token():
    url = "http://127.0.0.1:9090/?next=/profile"
    response = requests.get(url, timeout=5)
    assert response.status_code == 401, f"Expected 401 Unauthorized for missing token, got {response.status_code}. Response: {response.text}"


def test_proxy_really_forwards_dynamic_request():
    nonce = os.urandom(16).hex()
    path = f"/?next=/probe-{nonce}&probe={nonce}"
    probe_header = os.urandom(16).hex()
    response = requests.get(
        "http://127.0.0.1:9090" + path,
        headers={**AUTH, "X-Verifier-Probe": probe_header},
        timeout=5,
    )
    expected = "UPSTREAM:" + hmac.new(
        UPSTREAM_SECRET,
        f"GET|{path}|{probe_header}".encode(),
        hashlib.sha256,
    ).hexdigest()
    assert response.status_code == 200
    assert response.text == expected, "proxy did not return the dynamically generated upstream response"
    assert ("GET", path, probe_header) in UPSTREAM_REQUESTS


def test_dynamic_redirect_and_auth_cases_are_enforced():
    suffix = "".join(random.choice(string.ascii_lowercase) for _ in range(14))
    bad_host = f"{suffix}.example.net"
    for target in (f"https://{bad_host}/x", f"//{bad_host}/x"):
        response = requests.get(
            "http://127.0.0.1:9090/",
            params={"next": target},
            headers=AUTH,
            timeout=5,
        )
        assert response.status_code == 403

    wrong = str(random.choice([n for n in range(10000, 100000) if n != 82045]))
    response = requests.get(
        "http://127.0.0.1:9090/?next=/dynamic",
        headers={"Authorization": f"Bearer {wrong}"},
        timeout=5,
    )
    assert response.status_code == 401


def test_z_proxy_rejects_untrusted_upstream_certificate(proxy_env):
    proxy_env.restart_with_untrusted_certificate()
    before = len(UPSTREAM_REQUESTS)
    nonce = os.urandom(16).hex()
    response = requests.get(
        f"http://127.0.0.1:9090/?next=/tls-{nonce}",
        headers={**AUTH, "X-Verifier-Probe": nonce},
        timeout=5,
    )
    assert response.status_code != 200, "proxy accepted an upstream certificate not signed by /app/ca.crt"
    assert len(UPSTREAM_REQUESTS) == before, "request reached the upstream despite its untrusted TLS certificate"
TEST_EOF

if [ -f /home/user/secure_proxy.go ] \
   && go build -o /tmp/secure_proxy_submission /home/user/secure_proxy.go \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
