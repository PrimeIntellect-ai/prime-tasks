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
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

cat << 'TEST_EOF' > /tmp/test_final_state.py
import pytest
import requests
import math

BASE_URL = "http://127.0.0.1:8000"
ENDPOINT = f"{BASE_URL}/process"
AUTH_HEADER = {"Authorization": "Bearer h3x-f0r3ns1cs"}

def test_auth_missing():
    payload = {"sensor_id": "TEST_AUTH", "data": [1.0, 2.0]}
    try:
        response = requests.post(ENDPOINT, json=payload, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 for missing auth, got {response.status_code}"

def test_auth_incorrect():
    payload = {"sensor_id": "TEST_AUTH", "data": [1.0, 2.0]}
    headers = {"Authorization": "Bearer wrong-token"}
    try:
        response = requests.post(ENDPOINT, json=payload, headers=headers, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")
    assert response.status_code == 401, f"Expected HTTP 401 for incorrect auth, got {response.status_code}"

def test_process_zero_variance_with_padding():
    payload = {"sensor_id": "TEST1", "data": [10.0, 10.0, "error", None, 10.0]}
    try:
        response = requests.post(ENDPOINT, json=payload, headers=AUTH_HEADER, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Body: {response.text}"
    data = response.json()
    assert "sensor_id" in data, "Response missing 'sensor_id'"
    assert "final_score" in data, "Response missing 'final_score'"
    assert data["sensor_id"] == "TEST1", f"Expected sensor_id 'TEST1', got {data['sensor_id']}"
    expected_score = 6000000.0
    assert math.isclose(data["final_score"], expected_score, rel_tol=1e-3), f"Expected final_score ~ {expected_score}, got {data['final_score']}"

def test_process_normal_variance_with_truncation():
    payload = {"sensor_id": "TEST2", "data": [1.0, 2.0, 3.0, 4.0, 5.0, 6.0, "invalid"]}
    try:
        response = requests.post(ENDPOINT, json=payload, headers=AUTH_HEADER, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the service: {e}")
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Body: {response.text}"
    data = response.json()
    assert data["sensor_id"] == "TEST2", f"Expected sensor_id 'TEST2', got {data.get('sensor_id')}"
    expected_score = 1.8857136
    assert math.isclose(data["final_score"], expected_score, rel_tol=1e-3), f"Expected final_score ~ {expected_score}, got {data.get('final_score')}"
TEST_EOF

if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    exit 0
fi

REAL_BINARY="/tmp/calc_baseline.real.$$"
CALL_LOG="/tmp/calc_baseline.calls.$$"
if [ ! -x /app/calc_baseline ] || ! cp /app/calc_baseline "$REAL_BINARY"; then
    exit 0
fi
chmod 755 "$REAL_BINARY"
: > "$CALL_LOG"
chmod 666 "$CALL_LOG"

restore_binary() {
    if [ -f "$REAL_BINARY" ]; then
        mv -f "$REAL_BINARY" /app/calc_baseline
        chmod 755 /app/calc_baseline
    fi
    rm -f "$CALL_LOG"
}
trap restore_binary EXIT

FACTOR="1.$((100000 + RANDOM * 7 % 800000))"
OFFSET="0.$((100000 + RANDOM * 11 % 800000))"

cat > /app/calc_baseline << WRAPPER_EOF
#!/bin/bash
{
    printf '%s' "\$#"
    printf '\t%s' "\$@"
    printf '\n'
} >> "$CALL_LOG"
out="\$("$REAL_BINARY" "\$@")" || exit \$?
python3 - "\$out" << 'PY_EOF'
import sys
print(float(sys.argv[1]) * $FACTOR + $OFFSET)
PY_EOF
WRAPPER_EOF
chmod 755 /app/calc_baseline

cat > /tmp/test_dynamic_state.py << TEST_EOF
import math
import os
import random
import secrets
import subprocess
import requests

ENDPOINT = "http://127.0.0.1:8000/process"
AUTH_HEADER = {"Authorization": "Bearer h3x-f0r3ns1cs"}
REAL_BINARY = "$REAL_BINARY"
CALL_LOG = "$CALL_LOG"
FACTOR = $FACTOR
OFFSET = $OFFSET
rng = random.SystemRandom()

def valid_number(value):
    return type(value) in (int, float) and math.isfinite(value)

def expected_for(raw):
    cleaned = [float(x) for x in raw if valid_number(x)]
    assert cleaned
    mean = sum(cleaned) / len(cleaned)
    variance = sum((x - mean) ** 2 for x in cleaned) / len(cleaned)
    args = (cleaned[:5] + [0.0] * 5)[:5]
    baseline_text = subprocess.check_output(
        [REAL_BINARY] + [str(x) for x in args], text=True, timeout=5
    ).strip()
    transformed_baseline = float(baseline_text) * FACTOR + OFFSET
    return transformed_baseline / (variance + 1e-6), args

def assert_binary_called_with(expected_args):
    with open(CALL_LOG, "r", encoding="utf-8") as f:
        lines = [line.rstrip("\n").split("\t") for line in f if line.strip()]
    matching = []
    for fields in lines:
        if not fields or fields[0] != "5" or len(fields) != 6:
            continue
        try:
            actual = [float(x) for x in fields[1:]]
        except ValueError:
            continue
        if all(math.isclose(a, b, rel_tol=1e-12, abs_tol=1e-12) for a, b in zip(actual, expected_args)):
            matching.append(actual)
    assert matching, f"Service did not invoke /app/calc_baseline with exactly five normalized arguments {expected_args}; calls were {lines}"

def dynamic_cases():
    identical = round(rng.uniform(2.0, 30.0), 5)
    many = [round(rng.uniform(-12.0, 18.0), 5) for _ in range(8)]
    short = [round(rng.uniform(-8.0, -1.0), 5), round(rng.uniform(1.0, 9.0), 5)]
    exact = [round(rng.uniform(-20.0, 20.0), 5) for _ in range(5)]
    return [
        [identical, "corrupt", None, identical, {"bad": 1}, identical, True],
        [many[0], "drop", many[1], None, many[2], many[3], [], many[4], many[5], many[6], many[7]],
        [False, short[0], {"x": 2}, "bad", short[1], None],
        [exact[0], exact[1], "noise", exact[2], None, exact[3], exact[4]],
    ]

def test_randomized_processing_and_real_binary_integration():
    for raw in dynamic_cases():
        sensor_id = "DYN-" + secrets.token_hex(10)
        expected, binary_args = expected_for(raw)
        with open(CALL_LOG, "w", encoding="utf-8"):
            pass
        response = requests.post(
            ENDPOINT,
            json={"sensor_id": sensor_id, "data": raw},
            headers=AUTH_HEADER,
            timeout=5,
        )
        assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}: {response.text}"
        body = response.json()
        assert body.get("sensor_id") == sensor_id
        assert "final_score" in body
        assert type(body["final_score"]) in (int, float)
        assert math.isfinite(body["final_score"])
        assert math.isclose(body["final_score"], expected, rel_tol=1e-6, abs_tol=1e-6), \
            f"Expected {expected}, got {body['final_score']} for {raw}"
        assert_binary_called_with(binary_args)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_dynamic_state.py -x --tb=short 2>&1; then
    restore_binary
    trap - EXIT
    echo "1" > /logs/verifier/reward.txt
fi
