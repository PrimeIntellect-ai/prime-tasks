#!/bin/bash
mkdir -p /logs/verifier

if (
    set -e

    cd /home/user/target-api
    rm -rf build
    rm -f auth_ext*.so
    python3 -m pip install --force-reinstall --no-deps .
    python3 setup.py build_ext --inplace

    python3 - <<'PY'
import importlib.machinery
import auth_ext

origin = auth_ext.__spec__.origin or ""
assert any(origin.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES), origin
assert auth_ext.verify_token() == "token_verified_securely"
PY

    cd /home/user/api-emulator
    export PATH="/root/.cargo/bin:${PATH}"
    cargo clean
    cargo build
    test -x /home/user/api-emulator/target/debug/api-emulator

    pkill -f '[p]ython3 .*main.py' 2>/dev/null || true
    cd /home/user/target-api
    python3 main.py >/tmp/target-api.log 2>&1 &
    api_pid=$!
    trap 'kill "$api_pid" 2>/dev/null || true; wait "$api_pid" 2>/dev/null || true' EXIT

    ready=0
    for _ in $(seq 1 30); do
        if response=$(curl -fsS http://localhost:8000/ 2>/dev/null); then
            if [ "$response" = "Status: token_verified_securely" ]; then
                ready=1
                break
            fi
        fi
        sleep 0.2
    done
    test "$ready" -eq 1

    rm -f /home/user/security_report.json
    /home/user/api-emulator/target/debug/api-emulator run \
        /home/user/test_script.dsl \
        http://localhost:8000 \
        /home/user/security_report.json

    cat <<'TEST_EOF' > /tmp/test_final_state.py
import importlib.machinery
import json
import os
import secrets
import subprocess
import tempfile
import threading
from http.server import BaseHTTPRequestHandler, HTTPServer

REPORT_PATH = "/home/user/security_report.json"
EMULATOR = "/home/user/api-emulator/target/debug/api-emulator"


def test_security_report_exists():
    assert os.path.exists(REPORT_PATH), f"The security report was not found at {REPORT_PATH}."


def test_security_report_content():
    assert os.path.exists(REPORT_PATH), f"The security report was not found at {REPORT_PATH}."

    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "The security report does not contain valid JSON."

    assert isinstance(data, list), "The security report JSON should be a list of history events."

    expected_substring = "Status: token_verified_securely"
    found = any(expected_substring in item for item in data if isinstance(item, str))
    assert found, f"The expected string '{expected_substring}' was not found in the security report. This indicates the API or the emulator did not function correctly."
    assert any(item == "Executing: GET /" for item in data if isinstance(item, str))


def test_native_extension_is_loaded():
    import sys
    sys.path.insert(0, "/home/user/target-api")
    import auth_ext

    origin = auth_ext.__spec__.origin or ""
    assert any(origin.endswith(suffix) for suffix in importlib.machinery.EXTENSION_SUFFIXES)
    assert auth_ext.verify_token() == "token_verified_securely"


def test_emulator_really_performs_http_request():
    marker = "probe-" + secrets.token_hex(24)
    requests_seen = []

    class Handler(BaseHTTPRequestHandler):
        def do_GET(self):
            requests_seen.append(self.path)
            body = marker.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def log_message(self, *args):
            pass

    server = HTTPServer(("127.0.0.1", 0), Handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        with tempfile.TemporaryDirectory() as td:
            script = os.path.join(td, "probe.dsl")
            report = os.path.join(td, "probe.json")
            with open(script, "w") as f:
                f.write("GET /\n")

            subprocess.run(
                [EMULATOR, "run", script, f"http://127.0.0.1:{server.server_port}", report],
                check=True,
                timeout=15,
            )

            with open(report, "r") as f:
                data = json.load(f)

        assert isinstance(data, list)
        assert requests_seen == ["/"]
        assert any(item == f"Response: {marker}" for item in data if isinstance(item, str))
    finally:
        server.shutdown()
        server.server_close()
        thread.join(timeout=5)
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
