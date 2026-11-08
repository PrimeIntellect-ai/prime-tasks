#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import tempfile
import pytest

EVIL_DIR = "/app/corpus/evil"
CLEAN_DIR = "/app/corpus/clean"
SCANNER_PATH = "/home/user/scanner.go"


def run_scanner(filepath):
    try:
        result = subprocess.run(
            ["go", "run", SCANNER_PATH, filepath],
            capture_output=True,
            text=True,
            timeout=5
        )
        if result.returncode != 0:
            return f"ERROR: exit {result.returncode}"
        return result.stdout.strip()
    except subprocess.TimeoutExpired:
        return "TIMEOUT"
    except Exception as e:
        return f"ERROR: {str(e)}"


def test_scanner_exists():
    assert os.path.isfile(SCANNER_PATH), f"Scanner Go program is missing at {SCANNER_PATH}"


def test_adversarial_corpus():
    assert os.path.isdir(EVIL_DIR), f"Evil corpus directory missing at {EVIL_DIR}"
    assert os.path.isdir(CLEAN_DIR), f"Clean corpus directory missing at {CLEAN_DIR}"

    evil_files = [os.path.join(EVIL_DIR, f) for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    clean_files = [os.path.join(CLEAN_DIR, f) for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]

    assert len(evil_files) > 0, f"Evil corpus directory {EVIL_DIR} is empty"
    assert len(clean_files) > 0, f"Clean corpus directory {CLEAN_DIR} is empty"

    evil_bypassed = []
    for f in evil_files:
        output = run_scanner(f)
        if output != "EVIL":
            evil_bypassed.append(os.path.basename(f))

    clean_modified = []
    for f in clean_files:
        output = run_scanner(f)
        if output != "CLEAN":
            clean_modified.append(os.path.basename(f))

    errors = []
    if evil_bypassed:
        errors.append(f"{len(evil_bypassed)} of {len(evil_files)} evil bypassed: {', '.join(evil_bypassed)}")
    if clean_modified:
        errors.append(f"{len(clean_modified)} of {len(clean_files)} clean modified: {', '.join(clean_modified)}")
    if errors:
        pytest.fail("\n".join(errors))


def make_request(method, target, headers=None, body=""):
    headers = list(headers or [])
    if body and not any(k.lower() == "content-length" for k, _ in headers):
        headers.append(("Content-Length", str(len(body.encode("utf-8")))))
    lines = [f"{method} {target} HTTP/1.1", "Host: example.com"]
    lines.extend(f"{key}: {value}" for key, value in headers)
    return ("\r\n".join(lines) + "\r\n\r\n" + body).encode("utf-8")


def test_generated_adversarial_requests():
    token = secrets.token_hex(8)
    cases = [
        (make_request("GET", f"/home/{token}"), "CLEAN"),
        (make_request("POST", "/login", body=f"password={token}"), "CLEAN"),
        (make_request("GET", "/login?password=&pwd=&secret_token="), "CLEAN"),
        (make_request("GET", f"/search?password_hint={token}&mysecret_token={token}"), "CLEAN"),
        (make_request("GET", "/", [("X-Shadow-Protocols", token)]), "CLEAN"),
        (make_request("POST", "/render", body="<img src=logo.png>"), "CLEAN"),
        (make_request("GET", f"/api/{token}", [("X-Shadow-Protocol", token)]), "EVIL"),
        (make_request("POST", "/submit", [("x-shadow-protocol", token)]), "EVIL"),
        (make_request("POST", "/render", body="prefix<img src=x onerror=alert(1)>suffix"), "EVIL"),
        (make_request("GET", f"/login?password={token}"), "EVIL"),
        (make_request("GET", f"/login?a=1&pwd={token}&b=2"), "EVIL"),
        (make_request("GET", f"/api?secret_token={token}"), "EVIL"),
        (make_request("GET", "/search?q=UNION SELECT username,password FROM users"), "EVIL"),
        (make_request("GET", "/search?q=' OR 1=1"), "EVIL"),
        (b"THIS IS NOT AN HTTP REQUEST\r\nHost: example.com\r\n\r\n", "EVIL"),
    ]
    random.SystemRandom().shuffle(cases)

    failures = []
    with tempfile.TemporaryDirectory(prefix="http_eval_") as directory:
        for index, (content, expected) in enumerate(cases):
            filename = secrets.token_hex(12) + ".dat"
            path = os.path.join(directory, filename)
            with open(path, "wb") as request_file:
                request_file.write(content)
            actual = run_scanner(path)
            if actual != expected:
                failures.append(f"case {index}: expected {expected}, got {actual}")

    if failures:
        pytest.fail("\n".join(failures))
TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
