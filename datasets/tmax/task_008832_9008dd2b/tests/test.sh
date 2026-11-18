#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import string
import subprocess
import time

import pytest

API_DIR = "/home/user/session-api"
SCRIPT_PATH = "/home/user/pbt.sh"
LOG_PATH = "/home/user/bug_report.log"
URL = "http://127.0.0.1:8080/validate"


def post_token(token):
    payload = json.dumps({
        "request_type": "validate",
        "payload": {"token": token, "metadata": {"len": len(token)}},
    })
    result = subprocess.run(
        [
            "curl", "-sS", "--max-time", "3", "-o", "/tmp/api_response_body",
            "-w", "%{http_code}", "-H", "Content-Type: application/json",
            "-X", "POST", "--data-binary", payload, URL,
        ],
        capture_output=True,
        text=True,
        timeout=5,
    )
    body = ""
    if os.path.exists("/tmp/api_response_body"):
        with open("/tmp/api_response_body", "r", errors="replace") as f:
            body = f.read()
    return result.returncode, result.stdout.strip(), body


def wait_for_api():
    deadline = time.time() + 10
    while time.time() < deadline:
        rc, status, _ = post_token("lowercase7")
        if rc == 0 and status == "200":
            return
        time.sleep(0.25)
    pytest.fail("The API was not running and accepting POST requests on 127.0.0.1:8080.")


def load_and_validate_report():
    assert os.path.isfile(LOG_PATH), f"Bug report {LOG_PATH} does not exist."
    with open(LOG_PATH, "r") as f:
        lines = f.readlines()
    assert len(lines) > 0, "Bug report is empty."
    assert len(lines) == 1, "Bug report must contain exactly one line with the raw JSON string."

    content = lines[0].strip()
    try:
        data = json.loads(content)
    except json.JSONDecodeError:
        pytest.fail("Bug report does not contain a valid JSON string.")

    assert data.get("request_type") == "validate", "JSON missing or incorrect 'request_type'."
    assert "payload" in data, "JSON missing 'payload' object."
    payload = data["payload"]
    assert "token" in payload, "Payload missing 'token'."
    assert "metadata" in payload, "Payload missing 'metadata'."
    assert "len" in payload["metadata"], "Metadata missing 'len'."

    assert set(data) == {"request_type", "payload"}, "Bug report has unexpected top-level fields."
    assert isinstance(payload, dict) and set(payload) == {"token", "metadata"}, \
        "Payload must contain exactly token and metadata."
    assert isinstance(payload["metadata"], dict) and set(payload["metadata"]) == {"len"}, \
        "Metadata must contain exactly len."
    token = payload["token"]
    assert isinstance(token, str), "Token must be a string."
    assert 5 <= len(token) <= 15, "Generated token length must be between 5 and 15."
    assert token.isascii() and token.isalnum(), "Generated token must be ASCII alphanumeric."
    assert payload["metadata"]["len"] == len(token), "Metadata len does not match token length."
    return content, token


def token_has_panic_property(token):
    upper_count = 0
    for c in token:
        if c.isupper() and c.isascii():
            upper_count += 1
        elif c.isdigit() and c.isascii() and upper_count == 3:
            return True
        else:
            upper_count = 0
    return False


def test_rust_api_compiles():
    assert os.path.isdir(API_DIR), f"Directory {API_DIR} does not exist."
    try:
        result = subprocess.run(
            ["cargo", "check"], cwd=API_DIR, capture_output=True, text=True, timeout=30
        )
        assert result.returncode == 0, f"Rust project failed to compile:\n{result.stderr}"
    except FileNotFoundError:
        main_rs_path = os.path.join(API_DIR, "src/main.rs")
        with open(main_rs_path, "r") as f:
            content = f.read()
        assert "let result = process_token(token_ref);" not in content, \
            "The borrow checker error in src/main.rs has not been fixed."


def test_pbt_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Fuzzer script {SCRIPT_PATH} does not exist."


def test_bug_report_exists_and_format():
    load_and_validate_report()


def test_bug_report_token_triggers_crash():
    _, token = load_and_validate_report()
    assert token_has_panic_property(token), (
        f"The token '{token}' found in the bug report does not trigger the API panic. "
        "It must contain exactly three consecutive uppercase letters followed immediately by a digit."
    )


def test_live_api_and_executed_bash_fuzzer():
    with open(SCRIPT_PATH, "r", errors="replace") as f:
        script = f.read()
    assert script.strip(), "The Bash property-based tester is empty."
    syntax = subprocess.run(["bash", "-n", SCRIPT_PATH], capture_output=True, text=True)
    assert syntax.returncode == 0, f"pbt.sh is not valid Bash:\n{syntax.stderr}"

    lowered = script.lower()
    assert "curl" in lowered, "pbt.sh does not invoke curl."
    assert "http://127.0.0.1:8080/validate" in script, "pbt.sh does not target the required endpoint."
    assert "content-type" in lowered and "application/json" in lowered, \
        "pbt.sh does not send the required JSON Content-Type header."
    assert re.search(r"/dev/(u)?random|\$\{?random\}?|\bshuf\b", lowered), \
        "pbt.sh has no random data source."
    assert re.search(r"\b(while|until|for)\b", lowered), "pbt.sh does not contain a fuzzing loop."
    assert "5" in script and "15" in script, "pbt.sh does not implement the required 5-15 length range."
    assert "request_type" in script and "metadata" in script and "token" in script, \
        "pbt.sh does not build the required JSON payload structure."

    # Confirm the submitted server is already running on the mandated port and
    # preserves both normal handling and the precise panic behavior.
    wait_for_api()
    for safe_token in ("abc12", "abAB7cd", "abWXYZ7cd"):
        rc, status, _ = post_token(safe_token)
        assert rc == 0 and status == "200", \
            f"API did not return 200 for non-triggering alphanumeric token {safe_token!r}."

    nonce = os.urandom(3)
    uppers = "".join(string.ascii_uppercase[b % 26] for b in nonce)
    digit = str(os.urandom(1)[0] % 10)
    trigger = "ab" + uppers + digit + "cd"
    assert trigger not in script, "The live-test trigger was unexpectedly embedded in pbt.sh."
    rc, status, body = post_token(trigger)
    assert rc != 0 or status == "500" or (status in ("", "000") and body == ""), \
        f"API did not panic/drop the connection for derived trigger token {trigger!r}; status={status!r}."

    # A panic is handled in a worker thread in the supplied API, so it should
    # remain available for the actual fuzzer runs.
    wait_for_api()

    discovered = []
    for attempt in range(2):
        if os.path.lexists(LOG_PATH):
            os.remove(LOG_PATH)
        started = time.time_ns()
        try:
            subprocess.run(
                ["bash", SCRIPT_PATH], cwd="/home/user", capture_output=True,
                text=True, timeout=45,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("pbt.sh did not stop after finding a crashing input within 45 seconds.")

        assert os.path.isfile(LOG_PATH), "Executing pbt.sh did not create bug_report.log."
        assert os.stat(LOG_PATH).st_mtime_ns >= started, \
            "bug_report.log was not freshly written by this pbt.sh execution."
        raw, token = load_and_validate_report()
        assert token_has_panic_property(token), \
            f"pbt.sh reported non-crashing token {token!r}."
        assert token not in script, \
            "pbt.sh contains its reported crash token literally instead of discovering it."

        # Exercise the report against the live artifact rather than trusting a
        # recomputation of the disclosed pattern.
        rc, status, body = post_token(token)
        assert rc != 0 or status == "500" or (status in ("", "000") and body == ""), \
            f"Reported payload did not actually crash the API; status={status!r}, body={body!r}."
        discovered.append((raw, token))
        wait_for_api()

    assert discovered[0][1] != discovered[1][1], \
        "Repeated pbt.sh executions produced the identical token; the tester appears hard-coded rather than random."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
