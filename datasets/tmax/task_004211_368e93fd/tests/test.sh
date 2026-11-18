#!/bin/bash
set +e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import random
import secrets
import signal
import socket
import subprocess
import time

import pytest

HANDLER = "/home/user/handler.sh"
LAUNCHER = "/home/user/start_gateway.sh"
FORBIDDEN = b"HTTP/1.1 403 Forbidden\r\n\r\nPolicy Violation\n"
ALLOWED = b"HTTP/1.1 200 OK\r\nX-Policy-ID: 77DF\r\n\r\nAccess Granted\n"


def port_open():
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(0.15)
    try:
        return s.connect_ex(("127.0.0.1", 8080)) == 0
    finally:
        s.close()


def stop_existing_socat():
    pids = []
    for name in os.listdir("/proc"):
        if not name.isdigit():
            continue
        try:
            with open(f"/proc/{name}/comm", "r", encoding="utf-8") as f:
                if f.read().strip() == "socat":
                    pids.append(int(name))
        except (FileNotFoundError, ProcessLookupError, PermissionError):
            pass
    for pid in pids:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    deadline = time.time() + 1.5
    while time.time() < deadline and port_open():
        time.sleep(0.05)
    for pid in pids:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    deadline = time.time() + 1.0
    while time.time() < deadline and port_open():
        time.sleep(0.05)


@pytest.fixture(scope="session", autouse=True)
def validate_artifacts_and_restart_gateway():
    for path in (HANDLER, LAUNCHER):
        assert os.path.isfile(path), f"Missing required script: {path}"
        assert os.path.getsize(path) > 0, f"Required script is empty: {path}"
        syntax = subprocess.run(
            ["bash", "-n", path], capture_output=True, text=True, timeout=3
        )
        assert syntax.returncode == 0, f"Invalid Bash script {path}: {syntax.stderr}"

    stop_existing_socat()
    assert not port_open(), "An existing non-socat process still owns port 8080"
    subprocess.Popen(
        ["bash", LAUNCHER],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        start_new_session=True,
    )
    deadline = time.time() + 4.0
    while time.time() < deadline and not port_open():
        time.sleep(0.05)
    assert port_open(), "start_gateway.sh did not start a listener on 127.0.0.1:8080"
    yield


def send_raw_request_bytes(req):
    s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    s.settimeout(3.0)
    try:
        s.connect(("127.0.0.1", 8080))
        s.sendall(req)
        try:
            s.shutdown(socket.SHUT_WR)
        except OSError:
            pass
        resp = b""
        while True:
            try:
                chunk = s.recv(4096)
                if not chunk:
                    break
                resp += chunk
            except socket.timeout:
                break
        return resp
    finally:
        s.close()


def send_raw_request(req_str):
    return send_raw_request_bytes(req_str.encode("utf-8")).decode(
        "utf-8", errors="replace"
    )


def b64url(data):
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def make_header(alg, target_remainder):
    # Exercise every valid unpadded Base64url length remainder (0, 2, and 3),
    # while making the encoded header unpredictable for each verifier run.
    for _ in range(5000):
        fields = [
            ("nonce", secrets.token_hex(random.randint(5, 25))),
            ("typ", "JWT"),
            ("note", "none" if alg.lower() != "none" else "HS256"),
            ("alg", alg),
        ]
        random.SystemRandom().shuffle(fields)
        separators = (",", ":") if secrets.randbelow(2) else (", ", ": ")
        raw = json.dumps(dict(fields), separators=separators).encode("utf-8")
        encoded = b64url(raw)
        if len(encoded) % 4 == target_remainder:
            return encoded
    raise AssertionError("Could not construct requested Base64url padding case")


def make_request(alg, target_remainder):
    header = make_header(alg, target_remainder)
    payload = b64url(json.dumps({
        "subject": secrets.token_hex(12),
        "request": secrets.token_urlsafe(9),
    }, separators=(",", ":")).encode("utf-8"))
    signature = secrets.token_urlsafe(13)
    token = f"{header}.{payload}.{signature}"
    path = "/" + secrets.token_urlsafe(8)
    return (
        f"GET {path} HTTP/1.1\r\n"
        "Host: 127.0.0.1:8080\r\n"
        f"X-Request-Nonce: {secrets.token_hex(16)}\r\n"
        f"Authorization: Bearer {token}\r\n"
        "Connection: close\r\n"
        "\r\n"
    ).encode("ascii")


def random_none_case():
    return "".join(c.upper() if secrets.randbelow(2) else c for c in "none")


def generated_cases():
    cases = []
    remainders = (0, 2, 3)
    for i in range(9):
        cases.append((make_request(random_none_case(), remainders[i % 3]), FORBIDDEN))
    valid_algs = ["HS256", "RS256", "ES384", "PS512", "noneX", "NONE2", "EdDSA", "A" + secrets.token_hex(6), "custom-" + secrets.token_hex(5)]
    for i, alg in enumerate(valid_algs):
        cases.append((make_request(alg, remainders[i % 3]), ALLOWED))
    random.SystemRandom().shuffle(cases)
    return cases


def test_handler_decodes_random_jwt_headers_and_returns_exact_output():
    for req, expected in generated_cases():
        result = subprocess.run(
            ["bash", HANDLER], input=req, capture_output=True, timeout=3
        )
        assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
        assert result.stdout == expected, (
            f"handler.sh returned incorrect bytes. Expected {expected!r}, got {result.stdout!r}"
        )
        assert result.stderr == b"", f"handler.sh wrote unexpected stderr: {result.stderr!r}"


def test_gateway_decodes_random_jwt_headers_and_returns_exact_output():
    for req, expected in generated_cases():
        resp = send_raw_request_bytes(req)
        assert resp == expected, f"Expected exact response {expected!r}, got {resp!r}"


def test_gateway_alg_none_lowercase():
    req = (
        "GET / HTTP/1.1\r\n"
        "Host: 127.0.0.1:8080\r\n"
        "Authorization: Bearer eyJhbGciOiJub25lIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4ifQ.\r\n"
        "\r\n"
    )
    resp = send_raw_request(req)
    assert "HTTP/1.1 403 Forbidden" in resp, f"Expected 403 Forbidden, got: {resp}"
    assert "Policy Violation\n" in resp, f"Expected 'Policy Violation\\n' in body, got: {resp}"


def test_gateway_alg_none_uppercase():
    req = (
        "GET / HTTP/1.1\r\n"
        "Host: 127.0.0.1:8080\r\n"
        "Authorization: Bearer eyJhbGciOiJOT05FIiwidHlwIjoiSldUIn0.eyJ1c2VyIjoiYWRtaW4ifQ.\r\n"
        "\r\n"
    )
    resp = send_raw_request(req)
    assert "HTTP/1.1 403 Forbidden" in resp, f"Expected 403 Forbidden, got: {resp}"
    assert "Policy Violation\n" in resp, f"Expected 'Policy Violation\\n' in body, got: {resp}"


def test_gateway_alg_valid_hs256():
    req = (
        "GET / HTTP/1.1\r\n"
        "Host: 127.0.0.1:8080\r\n"
        "Authorization: Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJ1c2VyIjoidXNlcjEifQ.signature\r\n"
        "\r\n"
    )
    resp = send_raw_request(req)
    assert "HTTP/1.1 200 OK" in resp, f"Expected 200 OK, got: {resp}"
    assert "X-Policy-ID: 77DF" in resp, f"Expected X-Policy-ID: 77DF header, got: {resp}"
    assert "Access Granted\n" in resp, f"Expected 'Access Granted\\n' in body, got: {resp}"
TEST_EOF

python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
