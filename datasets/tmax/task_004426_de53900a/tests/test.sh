#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import http.client
import http.server
import os
import secrets
import signal
import socket
import subprocess
import threading
import time
import urllib.parse

import pytest

BACKEND_SECRET = secrets.token_hex(24)
DYNAMIC_POST_PATH = "/probe-" + secrets.token_hex(8)
DYNAMIC_POST_BODY = "body-" + secrets.token_hex(20)
DYNAMIC_HEADER = "header-" + secrets.token_hex(20)
ABS_HTTP_PATH = "/absolute-http-" + secrets.token_hex(8)
ABS_HTTPS_PATH = "/absolute-https-" + secrets.token_hex(8)
ABS_HTTP_LOCATION = "http://" + secrets.token_hex(10) + ".invalid/landing"
ABS_HTTPS_LOCATION = "https://" + secrets.token_hex(10) + ".invalid/landing"
RELATIVE_PATH = "/relative-" + secrets.token_hex(8)
RELATIVE_LOCATION = "/dashboard/" + secrets.token_hex(12)
FIREWALL_PATH = "/blocked-" + secrets.token_hex(8)
FIREWALL_MARKER = secrets.token_hex(20)
BACKEND_SEEN = set()
BACKEND_LOCK = threading.Lock()


def wait_for_port(port, timeout=5):
    start = time.time()
    while time.time() - start < timeout:
        with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
            if s.connect_ex(("127.0.0.1", port)) == 0:
                return True
        time.sleep(0.05)
    return False


def kill_port_listeners(port):
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) < 10:
                        continue
                    local = fields[1]
                    state = fields[3]
                    if state == "0A" and int(local.rsplit(":", 1)[1], 16) == port:
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = os.path.join("/proc", entry, "fd")
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 2
    while time.time() < deadline and any(wait_for_port(p, 0.05) for p in (port,)):
        time.sleep(0.05)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass


class ControlledBackend(http.server.ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True


class BackendHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):
        pass

    def reply(self, status, body=b"", headers=()):
        self.send_response(status)
        for name, value in headers:
            self.send_header(name, value)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        parsed = urllib.parse.urlsplit(self.path)
        marker = self.headers.get("X-Request-Marker")
        if marker:
            with BACKEND_LOCK:
                BACKEND_SEEN.add(marker)

        if parsed.path == "/login":
            self.reply(200, b"Login page", [("Set-Cookie", "session=12345ABC")])
        elif parsed.path == "/redirect":
            target = urllib.parse.parse_qs(parsed.query).get("url", [""])[0]
            self.reply(302, b"redirect", [("Location", target or "/dashboard")])
        elif parsed.path == ABS_HTTP_PATH:
            self.reply(302, b"absolute", [
                ("Location", ABS_HTTP_LOCATION),
                ("Set-Cookie", "alpha=" + secrets.token_hex(8)),
                ("Set-Cookie", "beta=" + secrets.token_hex(8) + "; HttpOnly"),
            ])
        elif parsed.path == ABS_HTTPS_PATH:
            self.reply(307, b"absolute", [("Location", ABS_HTTPS_LOCATION)])
        elif parsed.path == RELATIVE_PATH:
            self.reply(302, b"relative", [("Location", RELATIVE_LOCATION)])
        else:
            self.reply(404, b"not found")

    def do_POST(self):
        parsed = urllib.parse.urlsplit(self.path)
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length).decode("utf-8", "replace")
        if (parsed.path == DYNAMIC_POST_PATH and
                urllib.parse.parse_qs(parsed.query).get("nonce") == [DYNAMIC_HEADER] and
                self.headers.get("X-Dynamic-Probe") == DYNAMIC_HEADER and
                body == DYNAMIC_POST_BODY):
            self.reply(200, BACKEND_SECRET.encode(), [
                ("X-Backend-Secret", BACKEND_SECRET),
                ("Set-Cookie", "dynamic=" + secrets.token_hex(8)),
            ])
        else:
            self.reply(418, b"request was not forwarded intact")


@pytest.fixture(scope="module", autouse=True)
def setup_services():
    kill_port_listeners(9000)
    kill_port_listeners(8080)

    backend = ControlledBackend(("127.0.0.1", 8080), BackendHandler)
    backend_thread = threading.Thread(target=backend.serve_forever, daemon=True)
    backend_thread.start()
    assert wait_for_port(8080), "Controlled backend did not start."

    proxy = None
    if os.path.exists("/home/user/proxy_worker.sh"):
        proxy = subprocess.Popen([
            "socat",
            "TCP-LISTEN:9000,reuseaddr,fork",
            "EXEC:/home/user/proxy_worker.sh",
        ])
        wait_for_port(9000)

    yield

    if proxy is not None:
        proxy.terminate()
        try:
            proxy.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proxy.kill()
    backend.shutdown()
    backend.server_close()


def request(method, path, body=None, headers=None):
    conn = http.client.HTTPConnection("127.0.0.1", 9000, timeout=7)
    conn.request(method, path, body=body, headers=headers or {})
    response = conn.getresponse()
    data = response.read()
    return conn, response, data


def test_script_exists_and_executable():
    script_path = "/home/user/proxy_worker.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."


def test_firewall_rule():
    assert wait_for_port(9000, timeout=2), "Proxy is not listening on port 9000."
    conn, res, _ = request("GET", "/login", headers={"X-Block-Me": "true"})
    assert res.status == 403, f"Firewall rule failed: Expected 403 Forbidden, got {res.status}"
    conn.close()


def test_csp_and_cookies():
    assert wait_for_port(9000, timeout=2), "Proxy is not listening on port 9000."
    conn, res, _ = request("GET", "/login")
    assert res.status == 200, f"Expected 200 OK, got {res.status}"
    csp = res.getheader("Content-Security-Policy", "")
    assert "default-src 'self'" in csp, f"CSP enforcement failed: Header missing or incorrect. Got: {csp}"
    cookie = res.getheader("Set-Cookie", "")
    assert "HttpOnly" in cookie and "Secure" in cookie, f"Cookie inspection failed: Missing HttpOnly or Secure. Got: {cookie}"
    conn.close()


def test_open_redirect_mitigation():
    assert wait_for_port(9000, timeout=2), "Proxy is not listening on port 9000."
    conn, res, _ = request("GET", "/redirect?url=http://evil.com")
    assert res.status == 302, f"Expected 302 Found, got {res.status}"
    loc = res.getheader("Location", "")
    assert loc == "/error", f"Open redirect mitigation failed: Expected Location: /error, got {loc}"
    conn.close()


def test_relative_redirect_allowed():
    assert wait_for_port(9000, timeout=2), "Proxy is not listening on port 9000."
    conn, res, _ = request("GET", "/redirect")
    assert res.status == 302, f"Expected 302 Found, got {res.status}"
    loc = res.getheader("Location", "")
    assert loc == "/dashboard", f"Relative redirect failed: Expected Location: /dashboard, got {loc}"
    conn.close()


def test_arbitrary_request_is_forwarded_raw_to_backend():
    path = DYNAMIC_POST_PATH + "?nonce=" + urllib.parse.quote(DYNAMIC_HEADER)
    conn, res, data = request("POST", path, body=DYNAMIC_POST_BODY, headers={
        "Content-Type": "text/plain",
        "X-Dynamic-Probe": DYNAMIC_HEADER,
    })
    assert res.status == 200, f"Backend rejected the forwarded request with {res.status}"
    assert data.decode() == BACKEND_SECRET, "Response did not come from the controlled backend."
    assert res.getheader("X-Backend-Secret") == BACKEND_SECRET, "Backend response headers were not proxied."
    assert "default-src 'self'" in res.getheader("Content-Security-Policy", "")
    cookie = res.getheader("Set-Cookie", "")
    assert "HttpOnly" in cookie and "Secure" in cookie
    conn.close()


def test_firewall_blocks_arbitrary_request_without_forwarding():
    conn, res, _ = request("GET", FIREWALL_PATH, headers={
        "X-Block-Me": "true",
        "X-Request-Marker": FIREWALL_MARKER,
    })
    assert res.status == 403
    conn.close()
    time.sleep(0.2)
    with BACKEND_LOCK:
        assert FIREWALL_MARKER not in BACKEND_SEEN, "Blocked request was forwarded to the backend."


@pytest.mark.parametrize("path,expected_status", [
    (ABS_HTTP_PATH, 302),
    (ABS_HTTPS_PATH, 307),
])
def test_arbitrary_absolute_locations_are_rewritten(path, expected_status):
    conn, res, _ = request("GET", path)
    assert res.status == expected_status
    assert res.getheader("Location", "") == "/error"
    assert "default-src 'self'" in res.getheader("Content-Security-Policy", "")
    if path == ABS_HTTP_PATH:
        cookies = [v for k, v in res.getheaders() if k.lower() == "set-cookie"]
        assert len(cookies) == 2, "All Set-Cookie headers must be preserved."
        for cookie in cookies:
            assert "httponly" in cookie.lower() and "secure" in cookie.lower(), cookie
    conn.close()


def test_arbitrary_relative_location_is_preserved():
    conn, res, _ = request("GET", RELATIVE_PATH)
    assert res.status == 302
    assert res.getheader("Location", "") == RELATIVE_LOCATION
    assert "default-src 'self'" in res.getheader("Content-Security-Policy", "")
    conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
