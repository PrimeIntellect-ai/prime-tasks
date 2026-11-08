#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import re
import string
import subprocess
import time
import urllib.error
import urllib.request
from http.server import HTTPServer, BaseHTTPRequestHandler
from threading import Thread


def test_nginx_routing():
    """Test that Nginx routes /auth/ to 8081 and /data/ to 8082."""

    class AuthHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"AUTH_OK")

        def log_message(self, format, *args):
            pass

    class DataHandler(BaseHTTPRequestHandler):
        def do_GET(self):
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"DATA_OK")

        def log_message(self, format, *args):
            pass

    auth_server = HTTPServer(('127.0.0.1', 8081), AuthHandler)
    data_server = HTTPServer(('127.0.0.1', 8082), DataHandler)

    Thread(target=auth_server.serve_forever, daemon=True).start()
    Thread(target=data_server.serve_forever, daemon=True).start()

    subprocess.run(["nginx", "-s", "reload"], capture_output=True)
    time.sleep(1)

    try:
        req = urllib.request.urlopen("http://127.0.0.1:8080/auth/test", timeout=2)
        assert req.read() == b"AUTH_OK", "Nginx did not correctly proxy /auth/ to Auth Service"

        req = urllib.request.urlopen("http://127.0.0.1:8080/data/test", timeout=2)
        assert req.read() == b"DATA_OK", "Nginx did not correctly proxy /data/ to Data Service"
    except urllib.error.URLError as e:
        assert False, f"Nginx routing failed: {e}"
    finally:
        auth_server.shutdown()
        data_server.shutdown()
        auth_server.server_close()
        data_server.server_close()


def b64url_encode(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b'=').decode('ascii')


def make_jwt(alg, body, header_extra=None):
    header = {"alg": alg, "typ": "JWT"}
    if header_extra:
        header.update(header_extra)
    payload = {"sub": "1234567890"}
    token = ".".join([
        b64url_encode(json.dumps(header, separators=(',', ':')).encode()),
        b64url_encode(json.dumps(payload, separators=(',', ':')).encode()),
        b64url_encode(b"signature"),
    ])
    return json.dumps({"auth_header": "Bearer " + token, "response_body": body})


def strict_b64url_decode(value):
    if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9_-]*", value):
        raise ValueError("invalid base64url")
    padding = "=" * ((4 - len(value) % 4) % 4)
    return base64.b64decode(value + padding, altchars=b'-_', validate=True)


def reference_audit(input_line):
    request = json.loads(input_line)
    auth = request["auth_header"]
    body = request["response_body"]

    try:
        if not isinstance(auth, str) or not auth.startswith("Bearer "):
            raise ValueError("missing bearer")
        token = auth[len("Bearer "):]
        parts = token.split('.')
        if len(parts) != 3 or not all(parts):
            raise ValueError("wrong JWT part count")
        decoded = strict_b64url_decode(parts[0]).decode('utf-8')
        header = json.loads(decoded)
        if not isinstance(header, dict) or "alg" not in header or not isinstance(header["alg"], str):
            raise ValueError("invalid alg")
        alg = header["alg"]
    except (ValueError, UnicodeDecodeError, json.JSONDecodeError, KeyError, TypeError):
        return {"action": "DROP", "reason": "MALFORMED", "body": ""}

    if alg in ("none", "NONE", ""):
        return {"action": "DROP", "reason": "CWE-287", "body": ""}

    sanitized = re.sub(r"[0-9]{3}-[0-9]{2}-[0-9]{4}", "[REDACTED-SSN]", body)
    sanitized = re.sub(r"[0-9]{4}-[0-9]{4}-[0-9]{4}-[0-9]{4}", "[REDACTED-CC]", sanitized)
    return {"action": "ALLOW", "reason": "", "body": sanitized}


def run_case(agent_bin, input_line, case_number):
    try:
        proc = subprocess.run(
            [agent_bin],
            input=(input_line + "\n").encode('utf-8'),
            capture_output=True,
            timeout=1,
        )
    except subprocess.TimeoutExpired:
        assert False, f"Auditor timed out on case {case_number}: {input_line}"

    assert proc.returncode == 0, (
        f"Auditor exited with {proc.returncode} on case {case_number}; stderr={proc.stderr!r}"
    )
    assert proc.stdout.endswith(b"\n") and proc.stdout.count(b"\n") == 1, (
        f"Auditor must emit exactly one newline-terminated JSON line on case {case_number}: {proc.stdout!r}"
    )
    try:
        actual = json.loads(proc.stdout.decode('utf-8'))
    except (UnicodeDecodeError, json.JSONDecodeError) as e:
        assert False, f"Auditor emitted invalid JSON on case {case_number}: {e}; output={proc.stdout!r}"

    expected = reference_audit(input_line)
    assert isinstance(actual, dict), f"Output is not a JSON object on case {case_number}"
    assert set(actual) == {"action", "reason", "body"}, f"Incorrect output fields on case {case_number}: {actual}"
    assert actual == expected, (
        f"Mismatch on case {case_number}:\nInput: {input_line}\nExpected: {expected}\nActual: {actual}"
    )


def generate_cases(n=5000):
    cases = [
        make_jwt("none", "SSN 123-45-6789 and 1111-2222-3333-4444"),
        make_jwt("NONE", "secret 987-65-4321"),
        make_jwt("", "secret 9876-5432-1098-7654"),
        make_jwt("HS256", "SSN 123-45-6789; CC 1111-2222-3333-4444"),
        make_jwt("RS256", "adjacent: x123-45-6789y and 91111-2222-3333-44449"),
        make_jwt("invalid", "quotes \" and unicode café; unchanged"),
    ]

    payload = b64url_encode(b'{"sub":"1"}')
    signature = b64url_encode(b"sig")
    malformed_headers = [
        "%%%",
        b64url_encode(b'{"alg":"HS256"'),
        b64url_encode(b'not json'),
        b64url_encode(b'{"typ":"JWT"}'),
        b64url_encode(b'{"alg":null}'),
    ]
    for header in malformed_headers:
        cases.append(json.dumps({
            "auth_header": f"Bearer {header}.{payload}.{signature}",
            "response_body": "123-45-6789",
        }))

    valid_header = b64url_encode(b'{"alg":"HS256"}')
    cases.extend([
        json.dumps({"auth_header": f"Bearer {valid_header}.{payload}", "response_body": "123-45-6789"}),
        json.dumps({"auth_header": f"Bearer {valid_header}.{payload}.{signature}.extra", "response_body": "123-45-6789"}),
        json.dumps({"auth_header": f"{valid_header}.{payload}.{signature}", "response_body": "123-45-6789"}),
        json.dumps({"auth_header": "Bearer ", "response_body": "123-45-6789"}),
    ])

    random.seed(42)
    while len(cases) < n:
        alg = random.choice(["none", "NONE", "", "HS256", "RS256", "ES256", "invalid"])
        parts = []
        for _ in range(random.randint(1, 6)):
            choice = random.random()
            if choice < 0.3:
                parts.append(f"{random.randint(0,999):03d}-{random.randint(0,99):02d}-{random.randint(0,9999):04d}")
            elif choice < 0.6:
                parts.append("-".join(f"{random.randint(0,9999):04d}" for _ in range(4)))
            else:
                parts.append(''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(1, 15))))
        separator = random.choice([" ", ",", "|", ":"])
        cases.append(make_jwt(alg, separator.join(parts)))
    return cases


def test_auditor_behavior():
    agent_source = "/app/auditor.go"
    agent_bin = "/app/auditor"

    assert os.path.isfile(agent_source), f"Go source not found at {agent_source}"
    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary at {agent_bin} is not executable"
    with open(agent_bin, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The compiled auditor must be an ELF executable"

    go_info = subprocess.run(["go", "version", "-m", agent_bin], capture_output=True, text=True)
    assert go_info.returncode == 0 and "go1" in go_info.stdout, "The auditor must be compiled as a Go executable"

    for i, input_line in enumerate(generate_cases(5000)):
        run_case(agent_bin, input_line, i)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
