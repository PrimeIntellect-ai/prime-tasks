#!/bin/bash
set +e
mkdir -p /logs/verifier

MOCK_PID=""
NGINX_STOPPED=0

cleanup() {
    if [ -n "$MOCK_PID" ] && kill -0 "$MOCK_PID" 2>/dev/null; then
        kill "$MOCK_PID" 2>/dev/null || true
        wait "$MOCK_PID" 2>/dev/null || true
    fi
    if [ "$NGINX_STOPPED" -eq 1 ]; then
        nginx -c /home/user/nginx/nginx.conf >/dev/null 2>&1 || true
    fi
}

run_checks() {
    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import urllib.request
import urllib.error
import pytest


def test_success_log_content():
    log_path = "/home/user/success.log"
    assert os.path.isfile(log_path), f"File {log_path} does not exist. The verify script may not have run or failed to create it."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_text = "Backend Service Operational"
    assert expected_text in content, f"Expected '{expected_text}' in {log_path}, but found: {content}"


def test_verify_script_exists():
    script_path = "/home/user/verify.py"
    assert os.path.isfile(script_path), f"File {script_path} does not exist. You must create the verification script."


def test_nginx_and_backend_running():
    url = "http://127.0.0.1:8080"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            status = response.getcode()
            body = response.read().decode("utf-8").strip()

            assert status == 200, f"Expected HTTP status 200, got {status}."
            assert "Backend Service Operational" in body, f"Unexpected response body: {body}"
    except urllib.error.HTTPError as e:
        pytest.fail(f"HTTP request failed with status {e.code}. Nginx might still be returning a 502 Bad Gateway.")
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to {url}: {e.reason}. Nginx might not be running or listening on port 8080.")
    except Exception as e:
        pytest.fail(f"Unexpected error when connecting to {url}: {e}")


def test_server_file_exists():
    server_path = "/home/user/app/server.py"
    assert os.path.isfile(server_path), f"File {server_path} is missing."
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    test -f /home/user/cicd/deploy.sh || return 1
    timeout 15 bash /home/user/cicd/deploy.sh >/tmp/deploy-verifier.out 2>&1 || return 1

    python3 - <<'PY' || return 1
import time
import urllib.request

last_error = None
for _ in range(30):
    try:
        with urllib.request.urlopen("http://127.0.0.1:8080", timeout=2) as response:
            body = response.read().decode("utf-8")
            if response.status == 200 and "Backend Service Operational" in body:
                raise SystemExit(0)
    except Exception as exc:
        last_error = exc
    time.sleep(0.2)
raise SystemExit(f"Deployment did not produce a working proxied service: {last_error}")
PY

    NGINX_PID=""
    if [ -f /home/user/nginx/nginx.pid ]; then
        NGINX_PID="$(cat /home/user/nginx/nginx.pid 2>/dev/null)"
    fi
    test -n "$NGINX_PID" || return 1
    kill -0 "$NGINX_PID" 2>/dev/null || return 1
    kill -QUIT "$NGINX_PID" 2>/dev/null || return 1
    NGINX_STOPPED=1

    for _ in $(seq 1 50); do
        kill -0 "$NGINX_PID" 2>/dev/null || break
        sleep 0.1
    done
    kill -0 "$NGINX_PID" 2>/dev/null && return 1

    NONCE="VerifierResponse-$(cat /proc/sys/kernel/random/uuid)"
    rm -f /tmp/verify-request.txt /tmp/verify-mock-ready /home/user/success.log

    cat <<'PY' > /tmp/verify_mock.py
import http.server
import sys

response_text = sys.argv[1]

class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        with open("/tmp/verify-request.txt", "w") as f:
            f.write(f"{self.command} {self.path}")
        data = response_text.encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def log_message(self, format, *args):
        pass

server = http.server.HTTPServer(("127.0.0.1", 8080), Handler)
open("/tmp/verify-mock-ready", "w").close()
server.handle_request()
server.server_close()
PY

    python3 /tmp/verify_mock.py "$NONCE" >/tmp/verify-mock.out 2>&1 &
    MOCK_PID=$!
    for _ in $(seq 1 50); do
        [ -f /tmp/verify-mock-ready ] && break
        kill -0 "$MOCK_PID" 2>/dev/null || return 1
        sleep 0.1
    done
    [ -f /tmp/verify-mock-ready ] || return 1

    timeout 15 python3 /home/user/verify.py >/tmp/verify-script.out 2>&1 || return 1
    wait "$MOCK_PID" || return 1
    MOCK_PID=""

    [ "$(cat /tmp/verify-request.txt 2>/dev/null)" = "GET /" ] || return 1
    python3 - "$NONCE" <<'PY' || return 1
import pathlib
import sys

expected = sys.argv[1]
path = pathlib.Path("/home/user/success.log")
assert path.is_file(), "verify.py did not create success.log"
assert path.read_text() == expected, "verify.py did not write the exact HTTP response text"
PY

    nginx -c /home/user/nginx/nginx.conf >/tmp/nginx-restart.out 2>&1 || return 1
    NGINX_STOPPED=0

    python3 - <<'PY' || return 1
import time
import urllib.request

for _ in range(30):
    try:
        with urllib.request.urlopen("http://127.0.0.1:8080", timeout=2) as response:
            if response.status == 200 and response.read().decode("utf-8") == "Backend Service Operational":
                raise SystemExit(0)
    except Exception:
        pass
    time.sleep(0.2)
raise SystemExit("Nginx did not return after verification-script testing")
PY

    timeout 15 python3 /home/user/verify.py >/tmp/verify-script-final.out 2>&1 || return 1
    python3 - <<'PY' || return 1
from pathlib import Path
assert Path("/home/user/success.log").read_text() == "Backend Service Operational"
PY
}

STATUS=0
run_checks || STATUS=1
cleanup

if [ "$STATUS" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
