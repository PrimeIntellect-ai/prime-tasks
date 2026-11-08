#!/bin/bash
mkdir -p /logs/verifier

# Stop the agent-facing server and replace it with a fresh, unpredictable
# verification instance so a precomputed hash cannot pass.
pkill -f '^python3 /usr/local/libexec/traffic-auditor-server.py$' 2>/dev/null || true
sleep 1

TOKEN="$(python3 -c 'import secrets; print(secrets.token_urlsafe(32))')"
cat > /tmp/verifier_https_server.py <<'SERVER_EOF'
from http.server import HTTPServer, BaseHTTPRequestHandler
import os
import ssl

TOKEN = os.environ["VERIFIER_TOKEN"]

class SecureHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/secure-endpoint":
            self.send_response(200)
            self.send_header("Set-Cookie", f"session_token={TOKEN}; Secure; HttpOnly")
            self.send_header("Content-type", "text/plain")
            self.end_headers()
            self.wfile.write(b"Success")
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, format, *args):
        pass

httpd = HTTPServer(("127.0.0.1", 8443), SecureHandler)
context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
context.load_cert_chain(certfile="/home/user/server.crt", keyfile="/home/user/server.key")
httpd.socket = context.wrap_socket(httpd.socket, server_side=True)
httpd.serve_forever()
SERVER_EOF

VERIFIER_TOKEN="$TOKEN" python3 /tmp/verifier_https_server.py >/dev/null 2>&1 &
SERVER_PID=$!
sleep 1

cat > /tmp/test_final_state.py <<'TEST_EOF'
import hashlib
import os
import stat
import subprocess
import ssl
import urllib.request

import pytest

PROJECT = "/home/user/traffic-auditor"
OUTPUT = "/home/user/cookie_hash.txt"


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    if os.path.lexists(OUTPUT):
        os.remove(OUTPUT)

    subprocess.run(
        ["cargo", "build", "--manifest-path", f"{PROJECT}/Cargo.toml"],
        cwd=PROJECT,
        check=True,
        timeout=240,
    )

    binary = f"{PROJECT}/target/debug/traffic-auditor"
    assert os.path.isfile(binary), f"Cargo did not produce the expected Rust executable at {binary}"
    assert os.access(binary, os.X_OK), f"Built artifact is not executable: {binary}"

    subprocess.run(
        ["runuser", "-u", "user", "--", "sh", "-c", f"umask 022; exec {binary}"],
        cwd=PROJECT,
        check=True,
        timeout=30,
    )


def test_rust_code_fixed_cwe295():
    main_rs = "/home/user/traffic-auditor/src/main.rs"
    assert os.path.isfile(main_rs), f"Missing main.rs at {main_rs}"

    with open(main_rs, "r", encoding="utf-8") as f:
        content = f.read()

    assert "danger_accept_invalid_certs(true)" not in content, \
        "The Rust code still contains 'danger_accept_invalid_certs(true)', meaning CWE-295 is not fixed."


def test_cookie_hash_file_exists_and_permissions():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} was not created."

    file_stat = os.stat(OUTPUT)
    mode = file_stat.st_mode
    assert stat.S_IMODE(mode) == 0o600, \
        f"File permissions for {OUTPUT} are not 0600. Current mode: {oct(stat.S_IMODE(mode))}"


def test_cookie_hash_content():
    ctx = ssl.create_default_context(cafile="/home/user/ca.crt")
    req = urllib.request.Request("https://127.0.0.1:8443/secure-endpoint")
    with urllib.request.urlopen(req, context=ctx, timeout=3) as response:
        cookie_header = response.getheader("Set-Cookie")

    assert cookie_header, "Verification server did not return a Set-Cookie header"
    expected_token = None
    for part in cookie_header.split(";"):
        part = part.strip()
        if part.startswith("session_token="):
            expected_token = part.split("=", 1)[1]
            break

    assert expected_token is not None, "Verification server did not return a session_token cookie"
    expected_hash = hashlib.sha256(expected_token.encode("utf-8")).hexdigest()

    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} was not created."
    with open(OUTPUT, "r", encoding="utf-8") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_hash, \
        f"The content of {OUTPUT} does not match the expected SHA-256 hash of the cookie."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

kill "$SERVER_PID" 2>/dev/null || true
wait "$SERVER_PID" 2>/dev/null || true
