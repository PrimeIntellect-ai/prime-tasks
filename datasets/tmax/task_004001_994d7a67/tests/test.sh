#!/bin/bash
set +e
mkdir -p /logs/verifier

BIN=/app/bin/stat_analyzer
BACKUP="/app/bin/.stat_analyzer.verifier.$$"
TRACE="/tmp/stat_analyzer_invocations.$$"
: > "$TRACE"

restore_binary() {
    if [ -e "$BACKUP" ]; then
        mv -f "$BACKUP" "$BIN"
    fi
}
trap restore_binary EXIT

PREP_OK=1
if [ ! -x "$BIN" ]; then
    PREP_OK=0
else
    mv "$BIN" "$BACKUP" || PREP_OK=0
fi

if [ "$PREP_OK" -eq 1 ]; then
cat > "$BIN" <<SHIM_EOF
#!/usr/bin/env python3
import json
import subprocess
import sys

REAL = ${BACKUP@Q}
TRACE = ${TRACE@Q}
data = sys.stdin.buffer.read()
with open(TRACE, "a", encoding="utf-8") as f:
    f.write(json.dumps({"stdin_hex": data.hex()}) + "\\n")

try:
    p = subprocess.run([REAL], input=data, stdout=subprocess.PIPE,
                       stderr=subprocess.PIPE, timeout=3)
except subprocess.TimeoutExpired:
    sys.exit(124)
sys.stdout.buffer.write(p.stdout)
sys.stderr.buffer.write(p.stderr)
sys.exit(p.returncode)
SHIM_EOF
    chmod 755 "$BIN" || PREP_OK=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import subprocess

import pytest
import requests

URL = "http://127.0.0.1:9000/process"
HEADERS = {"X-Auth-Token": "SecRes2024"}
TRACE = os.environ["VERIFIER_TRACE"]


def trace_events():
    if not os.path.exists(TRACE):
        return []
    events = []
    with open(TRACE, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                events.append(json.loads(line))
    return events


def expected_output(values):
    count = len(values)
    mean = sum(values) / count
    variance = sum(v * v for v in values) / count - mean * mean
    if variance < 0:
        variance = 0
    return f"Mean: {mean:.3f}, Variance: {variance:.3f}\n"


def post(payload, headers=HEADERS):
    try:
        return requests.post(URL, headers=headers, data=payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the service or request timed out: {e}")


def test_regression_files_exist_and_are_meaningful():
    script_path = "/home/user/regression_test.sh"
    log_path = "/home/user/regression_results.log"

    assert os.path.exists(script_path), f"Regression test script {script_path} is missing."
    assert os.path.isfile(script_path), f"{script_path} is not a file."
    assert os.path.exists(log_path), f"Regression results log {log_path} is missing."
    assert os.path.isfile(log_path), f"{log_path} is not a file."

    source = open(script_path, "rb").read()
    lower = source.lower()
    assert b"curl" in lower, "Regression script does not use curl"
    assert b"127.0.0.1:9000/process" in lower, "Regression script does not test /process"
    assert b"x-auth-token" in lower and b"secres2024" in lower
    assert b"regression_results.log" in lower
    assert b"mean:" in lower and b"variance:" in lower, \
        "Regression script does not verify the analyzer output"
    assert any(marker in lower for marker in (
        b"\x1b[d", b"\\x1b", b"\\033", b"\\e[d", b"%1b%5b%44", b"\\u001b"
    )), "Regression script does not contain an intentionally corrupted payload"
    assert any(marker in lower for marker in (
        b"http_code", b"grep", b"expected", b"[[", b"test ", b"status"
    )), "Regression script does not verify request results"

    os.remove(log_path)
    result = subprocess.run(["/bin/bash", script_path], stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=20)
    assert result.returncode == 0, \
        f"Regression script failed: {result.stdout!r} {result.stderr!r}"
    assert os.path.isfile(log_path), "Regression script did not recreate its results log"
    log = open(log_path, "rb").read()
    assert log.strip(), "Regression results log is empty"
    assert b"Mean:" in log and b"Variance:" in log, \
        "Regression results do not contain analyzer output"


def test_valid_request_and_real_subprocess_use():
    # Vary the values so a fixed HTTP response cannot satisfy the verifier.
    base = secrets.randbelow(20) + 4
    values = [float(base), float(base + 3), float(base + 11)]
    payload = b"".join((f"{v:.1f}\n".encode() for v in values))
    before = len(trace_events())
    response = post(payload)

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert response.text == expected_output(values), f"Unexpected response body: {response.text}"
    events = trace_events()[before:]
    assert any(bytes.fromhex(e["stdin_hex"]) == payload for e in events), \
        "The service did not pass the request data to /app/bin/stat_analyzer"


def test_original_valid_request_population_variance():
    payload = b"1.0\n2.0\n3.0\n"
    response = post(payload)
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert "Mean: 2.000" in response.text and "Variance: 0.667" in response.text, \
        f"Unexpected response body: {response.text}"


def test_corrupted_request_recoverable_and_sanitized_before_exec():
    values = [7.0, 12.0, 20.0]
    clean = b"7.0\n12.0\n20.0\n"
    payload = b"7.0\n\x1b\x5b\x4412.0\n20.0\n"
    before = len(trace_events())
    response = post(payload)

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert response.text == expected_output(values), \
        f"Unexpected response body or failed to sanitize payload: {response.text}"
    events = trace_events()[before:]
    submitted = [bytes.fromhex(e["stdin_hex"]) for e in events]
    assert clean in submitted, "The exact deadlocking bytes were not removed before subprocess use"
    assert all(b"\x1b[D" not in data for data in submitted), \
        "Deadlocking bytes were passed to the analyzer"


def test_unrecoverable_payload_returns_400_without_exec():
    # Removing the corrupt sequence leaves no numeric data to process.
    before = len(trace_events())
    response = post(b"\x1b[D")
    assert response.status_code == 400, \
        f"Expected HTTP 400 for an unrecoverable payload, got {response.status_code}"
    assert len(trace_events()) == before, \
        "An unrecoverable payload was passed to the analyzer"


def test_unauthenticated_request():
    payload = b"1.0\n2.0\n3.0\n"
    before = len(trace_events())
    response = post(payload, headers={})
    assert response.status_code == 401, \
        f"Expected HTTP 401 for unauthenticated request, got {response.status_code}"

    response_bad = post(payload, headers={"X-Auth-Token": "InvalidToken"})
    assert response_bad.status_code == 401, \
        f"Expected HTTP 401 for invalid token, got {response_bad.status_code}"
    assert len(trace_events()) == before, "Unauthenticated data was passed to the analyzer"
TEST_EOF

export VERIFIER_TRACE="$TRACE"
RC=1
if [ "$PREP_OK" -eq 1 ]; then
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
    RC=$?
fi

if [ "$RC" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

exit 0
