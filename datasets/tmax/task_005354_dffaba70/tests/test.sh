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
set +e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt

ORIG_RISK="/tmp/risk_calc.original.$$"
cp -p /app/risk_calc "$ORIG_RISK" || exit 0
export ORIG_RISK
SERVER_PID=""

cleanup() {
    cp -p "$ORIG_RISK" /app/risk_calc 2>/dev/null || true
    rm -f "$ORIG_RISK"
    if [ -n "$SERVER_PID" ]; then
        kill "$SERVER_PID" 2>/dev/null || true
    fi
}
trap cleanup EXIT

# Stop anything the agent left on port 9090 so the submitted executable itself
# is what the verifier launches and exercises.
python3 - <<'PY'
import os, signal, time
inodes = set()
for path in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(path) as f:
            next(f)
            for line in f:
                cols = line.split()
                if cols[1].split(':')[-1].upper() == '2382' and cols[3] == '0A':
                    inodes.add(cols[9])
    except OSError:
        pass
pids = set()
for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    fd_dir = f'/proc/{name}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                pids.add(int(name))
    except OSError:
        pass
for pid in pids:
    try:
        os.kill(pid, signal.SIGTERM)
    except OSError:
        pass
time.sleep(0.4)
for pid in pids:
    try:
        os.kill(pid, signal.SIGKILL)
    except OSError:
        pass
PY

/home/user/api_server >/tmp/api_server.verifier.log 2>&1 &
SERVER_PID=$!
sleep 0.8

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import stat
import subprocess
import time
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090/api/v1/calculate"
HEADERS = {"Authorization": "Bearer secret-math-key"}
ORIG_RISK = os.environ["ORIG_RISK"]


def cool_down():
    time.sleep(1.1)


def post(payload=None, *, headers=HEADERS, data=None):
    if data is not None:
        return requests.post(BASE_URL, headers=headers, data=data, timeout=3)
    return requests.post(BASE_URL, headers=headers, json=payload, timeout=3)


def test_00_artifacts_and_server_are_real():
    assert os.path.isfile('/home/user/server.cpp'), 'Missing /home/user/server.cpp'
    assert os.path.getsize('/home/user/server.cpp') > 0, 'server.cpp is empty'
    st = os.stat('/home/user/api_server')
    assert stat.S_ISREG(st.st_mode), 'api_server is not a regular file'
    assert os.access('/home/user/api_server', os.X_OK), 'api_server is not executable'
    with open('/home/user/api_server', 'rb') as f:
        assert f.read(4) == b'\x7fELF', 'api_server is not a compiled Linux executable'


def test_auth_missing():
    cool_down()
    resp = post({"price": 100, "vol": 0.5, "time": 1.0}, headers={})
    assert resp.status_code == 401, f"Expected 401 for missing auth, got {resp.status_code}"


def test_auth_wrong():
    cool_down()
    resp = post({"price": 100, "vol": 0.5, "time": 1.0}, headers={"Authorization": "Bearer wrong-key"})
    assert resp.status_code == 401, f"Expected 401 for wrong auth, got {resp.status_code}"


def test_payload_missing():
    cool_down()
    resp = post({})
    assert resp.status_code == 400, f"Expected 400 for empty payload, got {resp.status_code}"


def test_payload_bad_json():
    cool_down()
    resp = post(data="not json")
    assert resp.status_code == 400, f"Expected 400 for bad JSON, got {resp.status_code}"


def test_validation_price_high():
    cool_down()
    resp = post({"price": 10001, "vol": 0.5, "time": 1.0})
    assert resp.status_code == 400, f"Expected 400 for price > 10000, got {resp.status_code}"


def test_validation_vol_low():
    cool_down()
    resp = post({"price": 100, "vol": -0.1, "time": 1.0})
    assert resp.status_code == 400, f"Expected 400 for vol <= 0, got {resp.status_code}"


def test_validation_time_low():
    cool_down()
    resp = post({"price": 100, "vol": 0.5, "time": 0.05})
    assert resp.status_code == 400, f"Expected 400 for time < 0.1, got {resp.status_code}"


def test_valid_request():
    cool_down()
    price, vol, t = 100.0, 0.5, 1.0
    resp = post({"price": price, "vol": vol, "time": t})
    assert resp.status_code == 200, f"Expected 200 for valid request, got {resp.status_code}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response was not valid JSON: {resp.text}")
    assert "result" in data, "Response JSON missing 'result' key"
    expected = price * math.exp(vol * math.sqrt(t))
    assert math.isclose(data["result"], expected, rel_tol=1e-4), f"Expected result ~{expected}, got {data['result']}"


def test_additional_numeric_validation_and_boundaries():
    bad_payloads = [
        {"price": -0.0001, "vol": 0.5, "time": 1.0},
        {"price": 100, "vol": 2.0001, "time": 1.0},
        {"price": 100, "vol": 0.5, "time": 30.0001},
        {"price": "100", "vol": 0.5, "time": 1.0},
        {"price": 100, "vol": True, "time": 1.0},
        {"price": 100, "vol": 0.5, "time": None},
    ]
    for payload in bad_payloads:
        cool_down()
        resp = post(payload)
        assert resp.status_code == 400, f"Expected 400 for invalid payload {payload}, got {resp.status_code}"

    for raw in (
        '{"price": NaN, "vol": 0.5, "time": 1.0}',
        '{"price": 100, "vol": Infinity, "time": 1.0}',
    ):
        cool_down()
        resp = requests.post(BASE_URL, headers={**HEADERS, "Content-Type": "application/json"}, data=raw, timeout=3)
        assert resp.status_code == 400, f"Expected 400 for non-finite/nonstandard JSON number, got {resp.status_code}"


def test_exactly_one_endpoint_is_exposed():
    paths = ['/', '/health', '/api/v1/status', '/api/v1/' + uuid.uuid4().hex]
    for path in paths:
        cool_down()
        resp = requests.post('http://127.0.0.1:9090' + path, headers=HEADERS,
                             json={"price": 100, "vol": 0.5, "time": 1.0}, timeout=3)
        assert resp.status_code == 404, f"Unexpected POST endpoint {path}: HTTP {resp.status_code}"
    cool_down()
    resp = requests.get(BASE_URL, headers=HEADERS, timeout=3)
    assert resp.status_code in (404, 405), f"GET unexpectedly handled by calculation endpoint: HTTP {resp.status_code}"


def test_dynamic_inputs_are_obtained_from_risk_calc():
    # Replace the oracle only after preserving the original fixed-result assertion.
    # A correct wrapper follows this executable; a hardcoded mathematical server does not.
    offset = secrets.SystemRandom().uniform(137.0, 913.0)
    wrapper = f'''#!/bin/bash
out=$("{ORIG_RISK}" "$@") || exit $?
python3 - "$out" <<'PY'
import sys
print(f"{{float(sys.argv[1]) + {offset!r}:.6f}}")
PY
'''
    tmp = '/app/.risk_calc.verifier.' + uuid.uuid4().hex
    with open(tmp, 'w') as f:
        f.write(wrapper)
    os.chmod(tmp, 0o755)
    os.replace(tmp, '/app/risk_calc')

    rng = secrets.SystemRandom()
    cases = [
        (0.0, rng.uniform(0.01, 2.0), rng.uniform(0.1, 30.0)),
        (10000.0, 2.0, 0.1),
        (rng.uniform(0.01, 9999.99), rng.uniform(0.001, 1.999), 30.0),
    ]
    for price, vol, duration in cases:
        cool_down()
        expected_text = subprocess.check_output(
            ['/app/risk_calc', format(price, '.17g'), format(vol, '.17g'), format(duration, '.17g')],
            text=True, timeout=3).strip()
        expected = float(expected_text)
        resp = post({"price": price, "vol": vol, "time": duration})
        assert resp.status_code == 200, f"Dynamic valid request returned {resp.status_code}: {resp.text}"
        data = resp.json()
        assert isinstance(data.get('result'), (int, float)) and not isinstance(data.get('result'), bool)
        assert math.isfinite(data['result'])
        assert math.isclose(data['result'], expected, rel_tol=1e-6, abs_tol=1e-5), \
            f"Server did not return the current /app/risk_calc result: expected {expected}, got {data['result']}"


def test_rate_limiting():
    cool_down()
    payload = {"price": 100, "vol": 0.5, "time": 1.0}
    for i in range(3):
        resp = post(payload)
        assert resp.status_code == 200, f"Request {i+1}/3 failed with {resp.status_code}, expected 200"
    resp4 = post(payload)
    assert resp4.status_code == 429, f"Expected 429 for 4th request, got {resp4.status_code}"
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0
