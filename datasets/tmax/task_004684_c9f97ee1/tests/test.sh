#!/bin/bash
mkdir -p /logs/verifier

run_verifier() (
    set -e
    pkill -x vuln_server 2>/dev/null || true

    WORKDIR="$(mktemp -d)"
    trap 'rm -rf "$WORKDIR"' EXIT

    openssl req -x509 -newkey rsa:2048 -days 2 -nodes \
        -keyout "$WORKDIR/ca.key" -out "$WORKDIR/ca.crt" \
        -subj "/CN=Verifier Internal CA" >/dev/null 2>&1
    openssl req -newkey rsa:2048 -nodes \
        -keyout "$WORKDIR/server.key" -out "$WORKDIR/server.csr" \
        -subj "/CN=127.0.0.1" >/dev/null 2>&1
    printf 'subjectAltName=IP:127.0.0.1\n' > "$WORKDIR/ext.cnf"
    openssl x509 -req -in "$WORKDIR/server.csr" \
        -CA "$WORKDIR/ca.crt" -CAkey "$WORKDIR/ca.key" -CAcreateserial \
        -out "$WORKDIR/server.crt" -days 2 -extfile "$WORKDIR/ext.cnf" \
        >/dev/null 2>&1

    openssl req -x509 -newkey rsa:2048 -days 2 -nodes \
        -keyout "$WORKDIR/wrong-ca.key" -out "$WORKDIR/wrong-ca.crt" \
        -subj "/CN=Untrusted Verifier CA" >/dev/null 2>&1

    cat > "$WORKDIR/mock_server.py" <<'PY_EOF'
import base64
import json
import os
import ssl
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

scenario = json.loads(os.environ["AUDIT_SCENARIO"])
request_log = os.environ["AUDIT_REQUEST_LOG"]


def decode_segment(segment):
    segment += "=" * (-len(segment) % 4)
    return json.loads(base64.urlsafe_b64decode(segment.encode("ascii")))


class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/api/ssh-config":
            self.send_error(404)
            return

        auth = self.headers.get("Authorization", "")
        if not auth.startswith("Bearer "):
            self.send_error(401)
            return
        token = auth[len("Bearer "):]
        parts = token.split(".")
        try:
            header = decode_segment(parts[0]) if len(parts) == 3 else None
            payload = decode_segment(parts[1]) if len(parts) == 3 else None
        except Exception:
            self.send_error(401)
            return

        if len(parts) != 3 or parts[2] != "" or not isinstance(header, dict):
            self.send_error(401)
            return
        if header.get("alg") != "none" or payload != {"role": "admin"}:
            self.send_error(403)
            return

        with open(request_log, "w", encoding="utf-8") as f:
            json.dump({"header": header, "payload": payload}, f)

        cookie = "session_id=verifier_session; Path=/"
        if scenario["secure"]:
            cookie += "; Secure"
        if scenario["httponly"]:
            cookie += "; HttpOnly"

        config = (
            "# verifier-generated configuration\n"
            "Port 22\n"
            f"PermitRootLogin {'yes' if scenario['root'] else 'no'}\n"
            f"PasswordAuthentication {'yes' if scenario['password'] else 'no'}\n"
            "AllowTcpForwarding no\n"
        )
        body = json.dumps({"sshd_config": config, "status": "success"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Set-Cookie", cookie)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args):
        pass


class Server(ThreadingHTTPServer):
    allow_reuse_address = True


server = Server(("127.0.0.1", 8443), Handler)
ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
ctx.load_cert_chain(sys.argv[1], sys.argv[2])
server.socket = ctx.wrap_socket(server.socket, server_side=True)
with open(os.environ["AUDIT_READY_FILE"], "w", encoding="utf-8") as f:
    f.write("ready")
server.serve_forever()
PY_EOF

    cat > "$WORKDIR/test_final_state.py" <<'PY_EOF'
import json
import os
import random
import stat
import subprocess
import time
from pathlib import Path

import pytest

WORKDIR = Path(os.environ["AUDIT_TEST_TMP"])
REPORT = Path("/home/user/audit_report.json")
SOURCE = Path("/home/user/audit.go")
BINARY = WORKDIR / "submitted-audit"
KEYS = [
    "jwt_alg_none_vulnerable",
    "cookie_secure_flag_missing",
    "cookie_httponly_flag_missing",
    "ssh_root_login_permitted",
    "ssh_password_auth_permitted",
]
ALL_TRUE = {key: True for key in KEYS}


def load_report():
    assert REPORT.exists(), f"Audit report not found at {REPORT}"
    assert REPORT.is_file(), f"Path {REPORT} is not a file"
    try:
        with REPORT.open("r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse {REPORT} as JSON: {e}")


def start_server(scenario, tag):
    ready = WORKDIR / f"ready-{tag}"
    request_log = WORKDIR / f"request-{tag}.json"
    ready.unlink(missing_ok=True)
    request_log.unlink(missing_ok=True)
    env = os.environ.copy()
    env.update({
        "AUDIT_SCENARIO": json.dumps(scenario),
        "AUDIT_READY_FILE": str(ready),
        "AUDIT_REQUEST_LOG": str(request_log),
    })
    proc = subprocess.Popen(
        ["python3", str(WORKDIR / "mock_server.py"),
         str(WORKDIR / "server.crt"), str(WORKDIR / "server.key")],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    deadline = time.time() + 5
    while time.time() < deadline and not ready.exists():
        if proc.poll() is not None:
            out, err = proc.communicate()
            pytest.fail(f"Mock server failed to start: {out}\n{err}")
        time.sleep(0.05)
    assert ready.exists(), "Timed out starting verifier mock server"
    return proc, request_log


def stop_server(proc):
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait(timeout=3)


def execute(scenario, tag):
    REPORT.unlink(missing_ok=True)
    proc, request_log = start_server(scenario, tag)
    try:
        result = subprocess.run(
            [str(BINARY)], cwd="/home/user", capture_output=True, text=True,
            timeout=20,
        )
    finally:
        stop_server(proc)
    assert result.returncode == 0, (
        f"audit program exited with {result.returncode}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert request_log.exists(), "Program did not make an authenticated alg:none request"
    return load_report()


def test_00_program_executes_and_audits_live_state():
    assert SOURCE.exists(), f"Go source not found at {SOURCE}"
    mode = SOURCE.lstat().st_mode
    assert stat.S_ISREG(mode), f"{SOURCE} must be a regular Go source file"

    build = subprocess.run(
        ["go", "build", "-o", str(BINARY), str(SOURCE)],
        cwd="/home/user", capture_output=True, text=True, timeout=60,
    )
    assert build.returncode == 0, f"audit.go did not compile:\n{build.stderr}"

    # A certificate not signed by the CA supplied at the required path must not
    # yield a successful audit, which catches disabled or bypassed verification.
    Path("/home/user/ca.crt").write_bytes((WORKDIR / "wrong-ca.crt").read_bytes())
    REPORT.unlink(missing_ok=True)
    proc, _ = start_server(
        {"secure": False, "httponly": False, "root": True, "password": True},
        "wrong-ca",
    )
    try:
        try:
            subprocess.run([str(BINARY)], cwd="/home/user", capture_output=True,
                           text=True, timeout=20)
        except subprocess.TimeoutExpired:
            pass
    finally:
        stop_server(proc)
    if REPORT.exists():
        try:
            wrong_ca_report = json.loads(REPORT.read_text(encoding="utf-8"))
        except Exception:
            wrong_ca_report = None
        assert wrong_ca_report != ALL_TRUE, (
            "Program reported a successful audit with a server certificate "
            "not signed by /home/user/ca.crt"
        )

    Path("/home/user/ca.crt").write_bytes((WORKDIR / "ca.crt").read_bytes())

    scenarios = [
        {"secure": True,  "httponly": True,  "root": False, "password": False},
        {"secure": True,  "httponly": False, "root": False, "password": True},
        {"secure": False, "httponly": True,  "root": True,  "password": False},
    ]
    random.SystemRandom().shuffle(scenarios)
    # Leave the original all-true appliance state last for the original checks.
    scenarios.append(
        {"secure": False, "httponly": False, "root": True, "password": True}
    )

    for index, scenario in enumerate(scenarios):
        expected = {
            "jwt_alg_none_vulnerable": True,
            "cookie_secure_flag_missing": not scenario["secure"],
            "cookie_httponly_flag_missing": not scenario["httponly"],
            "ssh_root_login_permitted": scenario["root"],
            "ssh_password_auth_permitted": scenario["password"],
        }
        data = execute(scenario, f"scenario-{index}")
        assert set(data) == set(KEYS), "Report must contain exactly the required keys"
        assert data == expected, f"Expected live audit result {expected}, got {data}"


# Preserve the original verifier's report assertions.
def test_audit_report_exists():
    assert REPORT.exists(), f"Audit report not found at {REPORT}"
    assert REPORT.is_file(), f"Path {REPORT} is not a file"


def test_audit_report_content():
    data = load_report()
    for key in KEYS:
        assert key in data, f"Missing expected key '{key}' in audit report"
        assert data[key] is True, f"Expected key '{key}' to be true, but got {data[key]}"
PY_EOF

    export AUDIT_TEST_TMP="$WORKDIR"
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider "$WORKDIR/test_final_state.py" -x --tb=short
)

if run_verifier 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
