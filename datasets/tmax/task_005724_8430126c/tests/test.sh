#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import http.server
import os
import re
import ssl
import subprocess
import threading
import time
import uuid
import http.client


def get_backdoor_token():
    binary_path = "/home/user/legacy_api"
    assert os.path.isfile(binary_path), f"Backend binary not found at {binary_path}"
    with open(binary_path, "rb") as f:
        content = f.read()
    match = re.search(b"BACKDOOR_TOKEN=([A-Za-z0-9_!@#$%^&*]+)", content)
    assert match is not None, "Could not extract BACKDOOR_TOKEN from legacy_api binary."
    return match.group(1).decode("utf-8")


def request(method, path, headers=None, body=None):
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    conn = http.client.HTTPSConnection("127.0.0.1", 8443, context=ctx, timeout=3)
    conn.request(method, path, body=body, headers=headers or {})
    response = conn.getresponse()
    data = response.read()
    result = (response.status, dict(response.getheaders()), data)
    conn.close()
    return result


def test_final_state():
    crt_path = "/home/user/server.crt"
    key_path = "/home/user/server.key"
    source_path = "/home/user/sec_proxy.go"
    log_path = "/home/user/proxy.log"

    assert os.path.isfile(crt_path), f"TLS certificate not found at {crt_path}"
    assert os.path.isfile(key_path), f"TLS private key not found at {key_path}"
    assert os.path.isfile(source_path), f"Go proxy source not found at {source_path}"
    assert os.path.getsize(source_path) > 0, "Go proxy source is empty"
    subprocess.run(
        ["go", "build", "-o", "/tmp/sec_proxy_verifier_build", source_path],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )

    token = get_backdoor_token()
    proof = uuid.uuid4().hex
    received = []
    lock = threading.Lock()

    class Backend(http.server.BaseHTTPRequestHandler):
        protocol_version = "HTTP/1.1"

        def handle_any(self):
            length = int(self.headers.get("Content-Length", "0"))
            body = self.rfile.read(length) if length else b""
            with lock:
                received.append((self.command, self.path, body))
            payload = f"{proof}|{self.command}|{self.path}|{body.hex()}".encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("X-Backend-Proof", proof)
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(payload)

        do_GET = handle_any
        do_POST = handle_any

        def log_message(self, fmt, *args):
            pass

    # Replace the legacy listener with a verifier-controlled backend. This lets
    # the test prove that successful responses actually traversed port 8080.
    subprocess.run(["pkill", "-x", "legacy_api"], check=False)
    time.sleep(0.3)
    backend = http.server.ThreadingHTTPServer(("127.0.0.1", 8080), Backend)
    thread = threading.Thread(target=backend.serve_forever, daemon=True)
    thread.start()

    try:
        # Truncating an already-open append log is safe and isolates this run.
        with open(log_path, "w"):
            pass

        status, headers, body = request("GET", "/normal_test")
        assert status == 200, f"Expected HTTP 200, got {status}"
        assert headers.get("X-Backend-Proof") == proof
        assert body == f"{proof}|GET|/normal_test|".encode()

        before = len(received)
        status, _, _ = request(
            "GET", "/secret_test", {"Cookie": f"admin_token={token}"}
        )
        assert status == 403, f"Expected HTTP 403 Forbidden, got {status}"
        time.sleep(0.1)
        assert len(received) == before, "Blocked backdoor-token request reached the backend"

        auth_val = "Bearer-" + uuid.uuid4().hex
        session_val = "session-" + uuid.uuid4().hex
        status, headers, body = request(
            "GET",
            "/data_test",
            {
                "Authorization": auth_val,
                "Cookie": f"session_id={session_val}",
            },
        )
        assert status == 200, f"Expected HTTP 200, got {status}"
        assert headers.get("X-Backend-Proof") == proof
        assert body == f"{proof}|GET|/data_test|".encode()

        dynamic_path = "/forward_" + uuid.uuid4().hex
        dynamic_body = os.urandom(24)
        wrong_token = token + "_not_exact"
        dynamic_auth = "Basic-" + uuid.uuid4().hex
        dynamic_session = "sid-" + uuid.uuid4().hex
        status, headers, body = request(
            "POST",
            dynamic_path,
            {
                "Authorization": dynamic_auth,
                "Cookie": f"admin_token={wrong_token}; session_id={dynamic_session}",
                "Content-Type": "application/octet-stream",
            },
            dynamic_body,
        )
        assert status == 200, "A nonmatching admin_token must be forwarded"
        assert headers.get("X-Backend-Proof") == proof
        assert body == f"{proof}|POST|{dynamic_path}|{dynamic_body.hex()}".encode()

        blocked_path = "/blocked_" + uuid.uuid4().hex
        blocked_auth = "Bearer-" + uuid.uuid4().hex
        blocked_session = "sid-" + uuid.uuid4().hex
        before = len(received)
        status, _, _ = request(
            "GET",
            blocked_path,
            {
                "Authorization": blocked_auth,
                "Cookie": f"session_id={blocked_session}; admin_token={token}",
            },
        )
        assert status == 403
        time.sleep(0.1)
        assert len(received) == before, "Dynamically named blocked request reached backend"

        with lock:
            seen = list(received)
        assert ("GET", "/normal_test", b"") in seen
        assert ("GET", "/data_test", b"") in seen
        assert ("POST", dynamic_path, dynamic_body) in seen
        assert all(path not in ("/secret_test", blocked_path) for _, path, _ in seen)

        assert os.path.isfile(log_path), f"Proxy log not found at {log_path}"
        for _ in range(20):
            with open(log_path, "r") as f:
                logs = f.read()
            if blocked_path in logs:
                break
            time.sleep(0.05)

        for secret in (auth_val, session_val, dynamic_auth, dynamic_session,
                       blocked_auth, blocked_session):
            assert secret not in logs, f"Sensitive value leaked into proxy.log: {secret}"

        expected_lines = [
            "GET /normal_test | Auth: NONE | Session: NONE",
            "GET /secret_test | Auth: NONE | Session: NONE",
            "GET /data_test | Auth: [REDACTED] | Session: [REDACTED]",
            f"POST {dynamic_path} | Auth: [REDACTED] | Session: [REDACTED]",
            f"GET {blocked_path} | Auth: [REDACTED] | Session: [REDACTED]",
        ]
        log_lines = logs.splitlines()
        for expected in expected_lines:
            assert expected in log_lines, f"Expected exact log entry not found: {expected}"
    finally:
        backend.shutdown()
        backend.server_close()

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
