#!/bin/bash
mkdir -p /logs/verifier

APP=/home/user/app
PASS=1

# The requested source and vendored-header repairs must be present.
if [ ! -f "$APP/server.cpp" ] || [ ! -f /app/nlohmann_json/single_include/nlohmann/json.hpp ]; then
    PASS=0
fi

if [ "$PASS" -eq 1 ]; then
    python3 - <<'PY' || PASS=0
import re
from pathlib import Path

source = Path('/home/user/app/server.cpp').read_text()
header = Path('/app/nlohmann_json/single_include/nlohmann/json.hpp').read_text()

# Reject the original catastrophic-cancellation implementation.
assert not (
    re.search(r'sum_sq\s*\+=\s*x\s*\*\s*x', source)
    and re.search(r'sum_sq\s*-\s*data\.size\(\)\s*\*\s*mean\s*\*\s*mean', source)
), 'server.cpp still contains the original naive variance calculation'

# Verify that the deliberately altered serializer expression was restored.
assert re.search(
    r'std::numeric_limits\s*<\s*number_float_t\s*>\s*::\s*(?:max_digits10|digits10)',
    header
), 'floating-point serialization precision was not restored in json.hpp'
PY
fi

# Stop anything the agent left listening on 8080 so tests exercise the freshly
# rebuilt artifact rather than an unrelated or hard-coded server.
python3 - <<'PY'
import os
import signal

inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        fields = line.split()
        if len(fields) > 9 and fields[1].split(':')[-1].upper() == '1F90' and fields[3] == '0A':
            inodes.add(fields[9])

for entry in os.listdir('/proc'):
    if not entry.isdigit() or int(entry) == os.getpid():
        continue
    fd_dir = f'/proc/{entry}/fd'
    try:
        links = [os.readlink(f'{fd_dir}/{fd}') for fd in os.listdir(fd_dir)]
    except (OSError, PermissionError):
        continue
    if any(link.startswith('socket:[') and link[8:-1] in inodes for link in links):
        try:
            os.kill(int(entry), signal.SIGKILL)
        except (OSError, ProcessLookupError):
            pass
PY
sleep 0.2

# Recompile through the provided Makefile and execute that resulting artifact.
if [ "$PASS" -eq 1 ]; then
    (cd "$APP" && make clean && make server) >/tmp/verifier_build.log 2>&1 || PASS=0
fi
if [ "$PASS" -eq 1 ]; then
    if [ ! -f "$APP/server" ] || [ ! -x "$APP/server" ] || ! file "$APP/server" | grep -q 'ELF'; then
        PASS=0
    fi
fi

SERVER_PID=""
if [ "$PASS" -eq 1 ]; then
    cd "$APP" || PASS=0
    nohup ./server >/tmp/verifier_server.log 2>&1 &
    SERVER_PID=$!
    cd - >/dev/null || true
    sleep 1
    kill -0 "$SERVER_PID" 2>/dev/null || PASS=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import secrets
import requests
import pytest

SERVER_URL = "http://127.0.0.1:8080/variance"

def post_variance(payload):
    try:
        response = requests.post(SERVER_URL, json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the server at {SERVER_URL}: {e}")
    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        body = response.json()
    except json.JSONDecodeError:
        pytest.fail(f"Server did not return valid JSON. Response: {response.text}")
    assert "variance" in body, f"Response JSON missing 'variance' key. Got: {body}"
    assert isinstance(body["variance"], (int, float)) and not isinstance(body["variance"], bool)
    return response, body["variance"]


def expected_sample_variance(values):
    mean = math.fsum(values) / len(values)
    return math.fsum((x - mean) ** 2 for x in values) / (len(values) - 1)


def test_variance_catastrophic_cancellation():
    payload = {"data": [100000000.1, 100000000.2, 100000000.3]}
    response, variance = post_variance(payload)
    expected_variance = 0.01
    assert math.isclose(variance, expected_variance, rel_tol=1e-5), \
        f"Variance calculation is incorrect. Expected ~{expected_variance}, got {variance}."


def test_variance_precision_serialization():
    payload = {"data": [1.0, 2.0, 4.0]}
    response, variance = post_variance(payload)
    raw_text = response.text
    expected_variance = 7.0 / 3.0
    assert math.isclose(variance, expected_variance, rel_tol=1e-5), \
        f"Variance calculation is incorrect. Expected ~{expected_variance}, got {variance}."
    assert variance != 2.33, \
        f"Variance precision appears to be truncated to 2 decimal places. Raw response: {raw_text}"


def test_secret_general_variance_inputs():
    rng = secrets.SystemRandom()
    cases = []

    # Unpredictable ordinary datasets ensure the endpoint performs the general calculation.
    for _ in range(4):
        n = rng.randrange(4, 15)
        cases.append([rng.uniform(-20000.0, 20000.0) for _ in range(n)])

    # Unpredictable large, tightly clustered values expose the naive E[X^2]-E[X]^2 formula.
    for _ in range(5):
        n = rng.randrange(5, 16)
        base = rng.uniform(50_000_000.0, 900_000_000.0)
        step = rng.choice([0.01, 0.02, 0.05, 0.1, 0.125])
        offsets = list(range(n))
        rng.shuffle(offsets)
        cases.append([base + (k - n // 2) * step for k in offsets])

    for values in cases:
        _, actual = post_variance({"data": values})
        expected = expected_sample_variance(values)
        assert math.isfinite(actual)
        assert math.isclose(actual, expected, rel_tol=5e-5, abs_tol=1e-12), (
            f"Incorrect sample variance for {values}: expected {expected!r}, got {actual!r}"
        )


def test_secret_non_truncated_serialization():
    rng = secrets.SystemRandom()
    for _ in range(5):
        values = [rng.uniform(-25.0, 25.0) for _ in range(rng.randrange(3, 10))]
        response, actual = post_variance({"data": values})
        expected = expected_sample_variance(values)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), (
            f"Floating-point result was rounded or truncated. Raw response: {response.text}"
        )
TEST_EOF

if [ "$PASS" -eq 1 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
