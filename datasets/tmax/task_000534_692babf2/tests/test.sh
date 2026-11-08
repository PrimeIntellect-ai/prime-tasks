#!/bin/bash
set -e
mkdir -p /logs/verifier

REWARD=0
SERVER_PID=""
cleanup() {
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
        wait "$SERVER_PID" 2>/dev/null || true
    fi
    echo "$REWARD" > /logs/verifier/reward.txt
}
trap cleanup EXIT

PROJECT=/home/user/pricing_service
SOURCE="$PROJECT/server.cpp"
HEADER="$PROJECT/httplib.h"
VERIFIER_BIN=/tmp/pricing_service_verified

# Compile the submitted source so the service under test is the demanded artifact.
g++ -O2 "$SOURCE" -o "$VERIFIER_BIN" -lpthread

# Stop any process currently listening on 127.0.0.1:8080, then run the freshly
# compiled submission instead of trusting an arbitrary pre-existing server.
python3 - <<'PY'
import os
import signal
import time

inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) >= 10 and fields[1].split(':')[-1].upper() == '1F90' and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass

for pid in os.listdir('/proc'):
    if not pid.isdigit():
        continue
    fd_dir = f'/proc/{pid}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                os.kill(int(pid), signal.SIGTERM)
                break
    except OSError:
        pass

time.sleep(0.3)
PY

"$VERIFIER_BIN" >/tmp/pricing_service.log 2>&1 &
SERVER_PID=$!
sleep 0.5

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import random
import re
import stat
import time

import pytest
import requests

PROJECT = "/home/user/pricing_service"
SOURCE = os.path.join(PROJECT, "server.cpp")
HEADER = os.path.join(PROJECT, "httplib.h")
URL = "http://127.0.0.1:8080/price"


def _regular_file(path):
    try:
        return stat.S_ISREG(os.lstat(path).st_mode)
    except OSError:
        return False


def _without_comments_and_strings(text):
    pattern = r'//[^\n]*|/\*.*?\*/|"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\''
    return re.sub(pattern, " ", text, flags=re.S)


def test_required_cpp_artifacts_and_configuration():
    assert _regular_file(SOURCE), f"Missing regular C++ source file: {SOURCE}"
    assert _regular_file(HEADER), f"Missing regular cpp-httplib header: {HEADER}"
    assert os.path.getsize(HEADER) > 1000, "httplib.h is not a plausible cpp-httplib header"

    text = open(SOURCE, encoding="utf-8").read()
    code = _without_comments_and_strings(text)

    assert re.search(r'#\s*include\s*[<\"]httplib\.h[>\"]', text), "server.cpp must include httplib.h"
    assert "httplib::Server" in code and ".Get" in code and ".listen" in code, "server.cpp must implement the cpp-httplib server"

    epsilon = re.search(r'\bconst(?:expr)?\s+double\s+EPSILON\s*=\s*([0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?\s*;', code)
    assert epsilon, "EPSILON must be declared as a double constant"
    literal = re.search(r'\bconst(?:expr)?\s+double\s+EPSILON\s*=\s*([^;]+);', code).group(1).strip()
    assert re.fullmatch(r'(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?', literal), "EPSILON must use the OCR-derived numeric value"
    assert float(literal) == 1e-9, f"Expected EPSILON=1e-9, found {literal}"

    maximum = re.search(r'\bconst(?:expr)?\s+int\s+MAX_ITERATIONS\s*=\s*([0-9]+)\s*;', code)
    assert maximum and int(maximum.group(1)) == 1000, "MAX_ITERATIONS must be 1000"

    assert not re.search(r'\bfloat\b', code), "Pricing logic must be upgraded from float to double"
    assert re.search(r'\bdouble\s+calculate_pricing_model\s*\(\s*(?:const\s+)?double\b', code), "calculate_pricing_model must accept and return double"
    assert "std::stod" in code, "The HTTP parameter must be parsed as a double"
    assert "EPSILON" in code and "MAX_ITERATIONS" in code, "The recovered constants must control convergence"
    assert re.search(r'\bS\s*/\s*x\b', code), "The Newton-Raphson update is missing"


def _get(params=None):
    last = None
    for _ in range(20):
        try:
            return requests.get(URL, params=params, timeout=5)
        except requests.exceptions.RequestException as exc:
            last = exc
            time.sleep(0.1)
    pytest.fail(f"Failed to connect to the pricing service at {URL}: {last}")


def _newton_expected(s):
    if s <= 0.0:
        return 0.0
    x = s
    prev_x = 0.0
    iterations = 0
    while abs(x - prev_x) >= 1e-9 and iterations < 1000:
        prev_x = x
        x = 0.5 * (x + s / x)
        iterations += 1
    return x


def _assert_price(s):
    response = _get({"s": format(s, ".17g")})
    assert response.status_code == 200, f"Expected HTTP 200 for s={s}, got {response.status_code}: {response.text}"
    body = response.text.strip()
    try:
        result = float(body)
    except ValueError:
        pytest.fail(f"Failed to parse response body as a float for s={s}: {response.text}")
    assert math.isfinite(result), f"Non-finite result for s={s}: {body}"

    expected = _newton_expected(s)
    tolerance = max(1e-18, 2e-14 * max(abs(expected), 1e-9))
    assert abs(result - expected) <= tolerance, (
        f"For s={s}, expected Newton-Raphson result {expected:.17g}, got {body}. "
        "Check double precision, EPSILON=1e-9, MAX_ITERATIONS=1000, and response precision."
    )


def test_pricing_service_success():
    """Preserve the original double-precision regression assertion."""
    response = _get({"s": "123456789.0"})
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    try:
        result = float(response.text)
    except ValueError:
        pytest.fail(f"Failed to parse response body as a float: {response.text}")

    expected = 11111.111060555555
    assert abs(result - expected) < 1e-7, (
        f"Expected result close to {expected}, but got {result}. "
        "This likely means the algorithm is still using single-precision floats "
        "or the EPSILON/MAX_ITERATIONS values were not correctly extracted and applied."
    )


def test_pricing_service_varied_inputs():
    # Tiny values expose the specified absolute stopping criterion and cannot be
    # answered correctly by simply returning sqrt(s).
    values = [1e-18, 1e-12, 1e-9, 1e-8, 2.0, 10.0, 1e6, 987654321.1234567]
    rng = random.SystemRandom()
    values.extend(10.0 ** rng.uniform(-14.0, 14.0) for _ in range(8))
    values.extend(rng.uniform(0.01, 1e10) for _ in range(5))
    for value in values:
        _assert_price(value)


def test_pricing_service_missing_param():
    """Preserve the original missing-parameter status assertion."""
    response = _get()
    assert response.status_code == 400, f"Expected HTTP 400 for missing parameter, got {response.status_code}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    REWARD=1
fi
