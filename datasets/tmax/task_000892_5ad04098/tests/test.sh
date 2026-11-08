#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import secrets
import subprocess
import sys
import time
import urllib.parse
import urllib.request

import pytest

APP_DIR = "/home/user/app/sanitizer-app"
EVIL_DIR = "/home/user/data/evil"
CLEAN_DIR = "/home/user/data/clean"
URL = "http://localhost:8080/sanitize"


def send_request(text):
    data = json.dumps({"text": text}).encode("utf-8")
    req = urllib.request.Request(URL, data=data, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return json.loads(response.read().decode("utf-8"))
    except Exception:
        return None


def encode_variants(text):
    raw = text.encode("utf-8")
    b64 = base64.b64encode(raw).decode("ascii")
    hx = raw.hex()
    hex_b64 = b64.encode("utf-8").hex()
    return [
        text,
        b64,
        hx,
        hex_b64,
        urllib.parse.quote(text, safe=""),
        urllib.parse.quote(hex_b64, safe=""),
    ]


NONCE = secrets.token_hex(12)
MALICIOUS_CLEAR = [
    f"prefix-{NONCE}-<script>alert(1)</script>",
    f"note-{NONCE}-DROP TABLE accounts;",
    f"marker::{NONCE}::evil_payload::end",
]
CLEAN_CLEAR = [
    f"ordinary message {NONCE}",
    f"lowercase drop table is not the exact keyword {NONCE}",
    f"<scr1pt> is harmless {NONCE}",
    f"evil-payload with a hyphen {NONCE}",
]
GENERATED_EVIL = [value for clear in MALICIOUS_CLEAR for value in encode_variants(clear)]
GENERATED_CLEAN = [value for clear in CLEAN_CLEAR for value in encode_variants(clear)]


def test_00_pyproject_is_installable():
    subprocess.run(
        [sys.executable, "-m", "pip", "install", "-e", "."],
        cwd=APP_DIR,
        check=True,
        timeout=120,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
    )
    code = "import flask, redis, sanitizer; print('ok')"
    subprocess.run([sys.executable, "-c", code], cwd=APP_DIR, check=True, timeout=20)


def test_adversarial_corpus():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory {EVIL_DIR} not found."
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory {CLEAN_DIR} not found."

    evil_files = [f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    clean_files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]

    assert len(evil_files) > 0, "No files found in evil corpus."
    assert len(clean_files) > 0, "No files found in clean corpus."

    evil_bypassed = []
    clean_modified = []

    for f in evil_files:
        with open(os.path.join(EVIL_DIR, f), "r", encoding="utf-8") as file:
            content = file.read()
        res = send_request(content)
        if res is None or res.get("safe") is not False:
            evil_bypassed.append(f)

    for f in clean_files:
        with open(os.path.join(CLEAN_DIR, f), "r", encoding="utf-8") as file:
            content = file.read()
        res = send_request(content)
        if res is None or res.get("safe") is not True:
            clean_modified.append(f)

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        error_msgs.append(f"{len(clean_modified)} of {len(clean_files)} clean modified (rejected or failed): {', '.join(clean_modified)}")
    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_generated_detector_cases():
    sys.path.insert(0, APP_DIR)
    from sanitizer.detector import is_malicious

    assert callable(is_malicious)
    for value in GENERATED_EVIL:
        assert is_malicious(value) is True, f"Detector missed generated malicious input: {value!r}"
    for value in GENERATED_CLEAN:
        assert is_malicious(value) is False, f"Detector rejected generated clean input: {value!r}"


def test_generated_endpoint_cases():
    for value in GENERATED_EVIL:
        response = send_request(value)
        assert response is not None and response.get("safe") is False, value
    for value in GENERATED_CLEAN:
        response = send_request(value)
        assert response is not None and response.get("safe") is True, value


def test_redis_request_logging():
    subprocess.run(["redis-cli", "ping"], check=True, timeout=10, stdout=subprocess.PIPE)
    subprocess.run(["redis-cli", "FLUSHALL"], check=True, timeout=10, stdout=subprocess.PIPE)

    token = "redis-log-" + secrets.token_hex(16)
    response = send_request(token)
    assert response is not None and response.get("safe") is True
    time.sleep(0.2)

    keys = subprocess.run(
        ["redis-cli", "--raw", "--scan"], check=True, timeout=10, stdout=subprocess.PIPE
    ).stdout.splitlines()
    assert keys, "The /sanitize request created no Redis log entry"

    needle = token.encode("utf-8")
    found = False
    for key in keys:
        dumped = subprocess.run(
            ["redis-cli", "--raw", "DUMP", key.decode("utf-8", "replace")],
            check=True,
            timeout=10,
            stdout=subprocess.PIPE,
        ).stdout
        if needle in key or needle in dumped:
            found = True
            break
    assert found, "Redis entries did not contain the uniquely generated request text"


def test_submitted_pytest_tests():
    subprocess.run(
        [sys.executable, "-m", "pytest", os.path.join(APP_DIR, "tests", "test_app.py"), "-q"],
        cwd=APP_DIR,
        check=True,
        timeout=60,
    )


def test_pyproject_toml_fixed():
    path = "/home/user/app/sanitizer-app/pyproject.toml"
    assert os.path.isfile(path), f"Expected {path} to exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read().lower()
    assert "flask" in content, "Flask dependency missing from pyproject.toml"
    assert "redis" in content, "Redis dependency missing from pyproject.toml"

    import tomllib
    with open(path, "rb") as f:
        project = tomllib.load(f)["project"]
    dependencies = project.get("dependencies", [])
    names = {re.match(r"[A-Za-z0-9_.-]+", item).group(0).lower() for item in dependencies}
    assert "flask" in names
    assert "redis" in names


def test_detector_py_exists():
    path = "/home/user/app/sanitizer-app/sanitizer/detector.py"
    assert os.path.isfile(path), f"Expected {path} to exist."


def test_app_py_exists():
    path = "/home/user/app/sanitizer-app/sanitizer/app.py"
    assert os.path.isfile(path), f"Expected {path} to exist."


def test_test_app_py_exists():
    path = "/home/user/app/sanitizer-app/tests/test_app.py"
    assert os.path.isfile(path), f"Expected {path} to exist."


def test_nginx_conf_fixed():
    path = "/home/user/app/nginx/nginx.conf"
    assert os.path.isfile(path), f"Expected {path} to exist."
    with open(path, "r", encoding="utf-8") as f:
        content = f.read()
    assert "proxy_pass http://127.0.0.1:5000;" in content or "proxy_pass http://localhost:5000;" in content, "Nginx config does not contain the correct proxy_pass directive."
    assert re.search(r"\blisten\s+8080\s*;", content), "Nginx is not configured to listen on port 8080"
    subprocess.run(["nginx", "-t", "-c", path], check=True, timeout=20, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
