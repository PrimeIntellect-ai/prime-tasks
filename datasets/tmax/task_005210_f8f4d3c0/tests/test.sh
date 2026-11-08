#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080/cgi-bin/upload.sh"
SCRIPT = "/app/cgi-bin/upload.sh"
AUTH_HEADER = "X-Audit-Auth"
AUTH_TOKEN = "reddragon_salty_42"


def wait_for_server():
    for _ in range(10):
        try:
            requests.options(BASE_URL, timeout=1)
            return True
        except requests.exceptions.RequestException:
            pass
        time.sleep(0.5)
    return False


@pytest.fixture(scope="module", autouse=True)
def setup():
    assert os.path.isfile(SCRIPT), f"Missing CGI script: {SCRIPT}"
    assert os.access(SCRIPT, os.X_OK), f"CGI script is not executable: {SCRIPT}"
    with open(SCRIPT, "rb") as f:
        first_line = f.readline(256).decode("utf-8", "replace").strip()
    assert re.match(r"^#!(?:/usr/bin/env\s+)?(?:/bin/)?bash(?:\s|$)", first_line), "upload.sh must be a Bash script"
    syntax = subprocess.run(["bash", "-n", SCRIPT], capture_output=True, text=True)
    assert syntax.returncode == 0, f"Invalid Bash syntax: {syntax.stderr}"
    assert wait_for_server(), "Server is not running on port 8080 or /cgi-bin/upload.sh is not accessible"


def token(n=12):
    return secrets.token_hex(n)


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def post(headers, payload):
    return requests.post(BASE_URL, headers=headers, data=payload, timeout=5)


def run_cgi(payload, headers=None, method="POST"):
    headers = headers or {}
    env = os.environ.copy()
    for key in list(env):
        if key.startswith("HTTP_X_"):
            del env[key]
    env.update({
        "REQUEST_METHOD": method,
        "CONTENT_LENGTH": str(len(payload)),
        "CONTENT_TYPE": "application/octet-stream",
        "GATEWAY_INTERFACE": "CGI/1.1",
        "SERVER_PROTOCOL": "HTTP/1.1",
        "SCRIPT_NAME": "/cgi-bin/upload.sh",
        "SCRIPT_FILENAME": SCRIPT,
    })
    for name, value in headers.items():
        env["HTTP_" + name.upper().replace("-", "_")] = value

    proc = subprocess.run(
        [SCRIPT], input=payload, capture_output=True, env=env,
        cwd="/app", timeout=5
    )
    assert proc.returncode == 0, f"CGI exited {proc.returncode}: {proc.stderr.decode('utf-8', 'replace')}"
    raw = proc.stdout
    if b"\r\n\r\n" in raw:
        head, body = raw.split(b"\r\n\r\n", 1)
        lines = head.split(b"\r\n")
    else:
        assert b"\n\n" in raw, "CGI response must contain a blank line after its headers"
        head, body = raw.split(b"\n\n", 1)
        lines = head.split(b"\n")

    status = 200
    response_headers = {}
    if lines and lines[0].startswith(b"HTTP/"):
        status = int(lines.pop(0).split()[1])
    for line in lines:
        if not line:
            continue
        assert b":" in line, f"Malformed CGI header: {line!r}"
        name, value = line.split(b":", 1)
        response_headers[name.decode("latin1").strip().lower()] = value.decode("latin1").strip()
    if "status" in response_headers:
        status = int(response_headers["status"].split()[0])
    assert response_headers.get("content-type", "").lower().startswith("text/plain"), "CGI must emit Content-Type: text/plain"
    return status, body


# Preserve the original fixed assertions.
def test_missing_auth():
    response = requests.post(BASE_URL, data="test")
    assert response.status_code == 401, f"Expected 401 for missing auth, got {response.status_code}"


def test_incorrect_auth():
    headers = {AUTH_HEADER: "wrong_token"}
    response = requests.post(BASE_URL, headers=headers, data="test")
    assert response.status_code == 401, f"Expected 401 for incorrect auth, got {response.status_code}"


def test_path_traversal():
    headers = {
        AUTH_HEADER: AUTH_TOKEN,
        "X-Filename": "../../../tmp/hack.txt",
        "X-File-Hash": "dummy"
    }
    response = requests.post(BASE_URL, headers=headers, data="test")
    assert response.status_code == 400, f"Expected 400 for path traversal, got {response.status_code}"


def test_invalid_hash():
    headers = {
        AUTH_HEADER: AUTH_TOKEN,
        "X-Filename": "test1.txt",
        "X-File-Hash": "invalidhash"
    }
    response = requests.post(BASE_URL, headers=headers, data="audit payload")
    assert response.status_code == 422, f"Expected 422 for invalid hash, got {response.status_code}"
    assert not os.path.exists("/app/audit_logs/test1.txt"), "File should not be saved if hash is invalid"


def test_successful_upload():
    payload = b"audit payload"
    payload_hash = hashlib.sha256(payload).hexdigest()
    filename = "test_success.txt"
    headers = {
        AUTH_HEADER: AUTH_TOKEN,
        "X-Filename": filename,
        "X-File-Hash": payload_hash
    }
    response = requests.post(BASE_URL, headers=headers, data=payload)
    assert response.status_code == 200, f"Expected 200 for successful upload, got {response.status_code}"
    assert "SUCCESS" in response.text, f"Expected 'SUCCESS' in response body, got {response.text}"

    file_path = f"/app/audit_logs/{filename}"
    assert os.path.exists(file_path), f"File {file_path} was not saved"
    with open(file_path, "rb") as f:
        assert f.read() == payload, "Saved file content does not match payload"


# Execute the submitted artifact directly with unpredictable inputs, so a separate
# hardcoded HTTP responder cannot stand in for upload.sh.
def test_randomized_direct_cgi_behavior():
    payload = ("direct payload " + token() + "\nsecond line " + token()).encode()
    filename = f"direct-{token()}.log"
    path = os.path.join("/app/audit_logs", filename)

    status, _ = run_cgi(payload, {
        "X-Filename": filename,
        "X-File-Hash": sha256(payload),
    })
    assert status == 401
    assert not os.path.exists(path)

    status, _ = run_cgi(payload, {
        AUTH_HEADER: "wrong-" + token(),
        "X-Filename": filename,
        "X-File-Hash": sha256(payload),
    })
    assert status == 401
    assert not os.path.exists(path)

    status, _ = run_cgi(payload, {
        AUTH_HEADER: AUTH_TOKEN,
        "X-Filename": filename,
        "X-File-Hash": sha256(payload + b"different"),
    })
    assert status == 422
    assert not os.path.exists(path)

    escaped_name = f"escaped-{token()}.txt"
    escaped_path = os.path.join("/app", escaped_name)
    if os.path.exists(escaped_path):
        os.unlink(escaped_path)
    status, _ = run_cgi(payload, {
        AUTH_HEADER: AUTH_TOKEN,
        "X-Filename": "../" + escaped_name,
        "X-File-Hash": sha256(payload),
    })
    assert status == 400
    assert not os.path.exists(escaped_path)

    status, body = run_cgi(payload, {
        AUTH_HEADER: AUTH_TOKEN,
        "X-Filename": filename,
        "X-File-Hash": sha256(payload),
    })
    assert status == 200
    assert b"SUCCESS" in body
    with open(path, "rb") as f:
        assert f.read() == payload


# Exercise the deployed service with names, payloads, hashes, and traversal targets
# that did not exist until verification time.
def test_randomized_deployed_service_behavior():
    auth_payload = ("auth-check-" + token()).encode()
    auth_name = f"auth-{token()}.txt"
    auth_path = os.path.join("/app/audit_logs", auth_name)
    response = post({
        AUTH_HEADER: "invalid-" + token(),
        "X-Filename": auth_name,
        "X-File-Hash": sha256(auth_payload),
    }, auth_payload)
    assert response.status_code == 401
    assert not os.path.exists(auth_path)

    traversal_payload = ("traversal-" + token()).encode()
    outside_app_name = f"outside-{token()}.txt"
    outside_tmp_name = f"outside-{token()}.txt"
    traversal_cases = [
        ("../" + outside_app_name, "/app/" + outside_app_name),
        ("/tmp/" + outside_tmp_name, "/tmp/" + outside_tmp_name),
        ("nested/../../../tmp/" + outside_tmp_name, "/tmp/" + outside_tmp_name),
    ]
    for supplied_name, outside_path in traversal_cases:
        if os.path.exists(outside_path):
            os.unlink(outside_path)
        response = post({
            AUTH_HEADER: AUTH_TOKEN,
            "X-Filename": supplied_name,
            "X-File-Hash": sha256(traversal_payload),
        }, traversal_payload)
        assert response.status_code == 400, f"Traversal filename {supplied_name!r} was not rejected"
        assert not os.path.exists(outside_path), f"Traversal created {outside_path}"

    for _ in range(2):
        payload = ("bad-hash-payload-" + token() + "\n" + token()).encode()
        filename = f"integrity-{token()}.dat"
        path = os.path.join("/app/audit_logs", filename)
        wrong_hash = sha256(payload + secrets.token_bytes(8))
        response = post({
            AUTH_HEADER: AUTH_TOKEN,
            "X-Filename": filename,
            "X-File-Hash": wrong_hash,
        }, payload)
        assert response.status_code == 422
        assert not os.path.exists(path), "Hash-mismatched upload was not deleted"

    for index in range(3):
        payload = (f"random upload {index} {token()}\nline two {token()}\n").encode()
        filename = f"upload-{token()}-{index}.log"
        path = os.path.join("/app/audit_logs", filename)
        response = post({
            AUTH_HEADER: AUTH_TOKEN,
            "X-Filename": filename,
            "X-File-Hash": sha256(payload),
        }, payload)
        assert response.status_code == 200
        assert "SUCCESS" in response.text
        assert os.path.isfile(path)
        with open(path, "rb") as f:
            assert f.read() == payload
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
