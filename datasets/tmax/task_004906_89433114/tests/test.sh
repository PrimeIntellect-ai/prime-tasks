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
set -e
mkdir -p /logs/verifier
all_ok=1

cat << 'TEST_EOF' > /tmp/test_original_state.py
import os
import pytest
import requests
import time

def test_serve_model_script_exists():
    """Verify that the agent created the required script."""
    script_path = "/home/user/serve_model.py"
    assert os.path.exists(script_path), f"Expected script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."

def test_flask_service_predict_endpoint():
    """Verify the Flask service is running and returns the correct prediction."""
    url = "http://127.0.0.1:5050/predict"
    params = {"views": 1000}

    max_retries = 5
    for i in range(max_retries):
        try:
            response = requests.get(url, params=params, timeout=2)
            break
        except requests.exceptions.RequestException:
            if i == max_retries - 1:
                pytest.fail("Failed to connect to the Flask service on 127.0.0.1:5050. Is it running?")
            time.sleep(1)

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    assert "expected_clicks" in data, f"JSON response missing 'expected_clicks' key. Got: {data}"

    expected_clicks = data["expected_clicks"]
    assert isinstance(expected_clicks, (int, float)), f"'expected_clicks' should be a number, got {type(expected_clicks)}"

    assert 149.0 <= expected_clicks <= 151.0, f"Expected prediction around 150.0, but got {expected_clicks}"
TEST_EOF

if ! python3 -m pytest /tmp/test_original_state.py -x --tb=short 2>&1; then
    all_ok=0
fi

# Stop whichever process currently owns the listening socket on port 5050 so the
# submitted artifact itself must be executed against a fresh, unpredictable dataset.
python3 << 'PY'
import os
import signal
import time

port_hex = format(5050, '04X')
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                fields = line.split()
                if fields[1].split(':')[-1].upper() == port_hex and fields[3] == '0A':
                    inodes.add(fields[9])
    except OSError:
        pass

victims = set()
for name in os.listdir('/proc'):
    if not name.isdigit() or int(name) == os.getpid():
        continue
    fd_dir = f'/proc/{name}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                victims.add(int(name))
                break
    except OSError:
        pass

for pid in victims:
    try:
        os.kill(pid, signal.SIGTERM)
    except ProcessLookupError:
        pass
time.sleep(1)
for pid in victims:
    try:
        os.kill(pid, signal.SIGKILL)
    except ProcessLookupError:
        pass
PY

cat << 'TEST_EOF' > /tmp/test_fresh_execution.py
import json
import math
import os
import random
import re
import signal
import subprocess
import time

import pytest
import redis
import requests

SCRIPT = "/home/user/serve_model.py"


def build_fresh_dataset():
    rng = random.SystemRandom()
    records = []
    points = []

    # Include repeated actions and users missing one action, so correct aggregation
    # and zero-filling are both exercised. Values vary on every verifier run.
    xs = [0] + rng.sample(range(7, 350), 13)
    base_slope = rng.randint(2, 8)
    intercept = rng.randint(9, 45)
    for i, x in enumerate(xs):
        y = max(0, base_slope * x + intercept + rng.randint(-30, 30))
        uid = f"fresh_{i}_{rng.randrange(1 << 30)}"
        points.append((float(x), float(y)))
        if x:
            first = rng.randint(0, x)
            records.append({"user_id": uid, "action": "view", "count": first})
            records.append({"user_id": uid, "action": "view", "count": x - first})
        if y:
            first = rng.randint(0, y)
            records.append({"user_id": uid, "action": "click", "count": first})
            records.append({"user_id": uid, "action": "click", "count": y - first})

    # A view-only user has an implicit click total of zero.
    x = rng.randint(360, 500)
    uid = f"view_only_{rng.randrange(1 << 30)}"
    records.extend([
        {"user_id": uid, "action": "view", "count": x // 3},
        {"user_id": uid, "action": "view", "count": x - x // 3},
    ])
    points.append((float(x), 0.0))
    rng.shuffle(records)

    client = redis.Redis(host="127.0.0.1", port=6379, db=0)
    client.ping()
    pipe = client.pipeline()
    pipe.delete("raw_logs")
    for record in records:
        pipe.rpush("raw_logs", json.dumps(record))
    pipe.execute()

    mean_x = sum(x for x, _ in points) / len(points)
    mean_y = sum(y for _, y in points) / len(points)
    slope = sum((x - mean_x) * (y - mean_y) for x, y in points) / sum((x - mean_x) ** 2 for x, _ in points)
    intercept_fit = mean_y - slope * mean_x
    queries = rng.sample(range(-100, 1200), 6) + [1000]
    return {q: slope * q + intercept_fit for q in queries}


def test_submitted_script_on_fresh_redis_data():
    assert os.path.exists(SCRIPT), f"Expected script {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"{SCRIPT} is not a file."

    with open(SCRIPT, "r", encoding="utf-8") as f:
        source = f.read()
    assert "raw_logs" in source, "The script does not reference the required Redis list raw_logs."
    assert re.search(r"LinearRegression\s*\(", source), "The script must instantiate scikit-learn LinearRegression."
    assert re.search(r"\b(redis|Redis)\b", source), "The script must connect to Redis."

    expected = build_fresh_dataset()
    log = open("/tmp/submitted_service.log", "w+")
    process = subprocess.Popen(
        ["python3", SCRIPT],
        stdout=log,
        stderr=subprocess.STDOUT,
        start_new_session=True,
    )
    try:
        url = "http://127.0.0.1:5050/predict"
        for attempt in range(30):
            if process.poll() is not None:
                log.seek(0)
                pytest.fail(f"Submitted script exited before serving requests:\n{log.read()}")
            try:
                response = requests.get(url, params={"views": next(iter(expected))}, timeout=1)
                if response.status_code == 200:
                    break
            except requests.RequestException:
                pass
            time.sleep(0.5)
        else:
            log.seek(0)
            pytest.fail(f"Submitted script did not listen on port 5050:\n{log.read()}")

        for views, wanted in expected.items():
            response = requests.get(url, params={"views": views}, timeout=2)
            assert response.status_code == 200, f"Expected HTTP 200 for views={views}, got {response.status_code}: {response.text}"
            try:
                data = response.json()
            except ValueError:
                pytest.fail(f"Response is not valid JSON for views={views}: {response.text}")
            assert set(data) == {"expected_clicks"}, f"Unexpected JSON response for views={views}: {data}"
            prediction = data["expected_clicks"]
            assert isinstance(prediction, (int, float)) and not isinstance(prediction, bool), f"Prediction is not numeric: {prediction!r}"
            assert math.isfinite(float(prediction)), f"Prediction is not finite: {prediction!r}"
            assert float(prediction) == pytest.approx(wanted, rel=1e-6, abs=1e-6), (
                f"Incorrect prediction for views={views}: expected {wanted}, got {prediction}"
            )
    finally:
        try:
            os.killpg(process.pid, signal.SIGTERM)
            process.wait(timeout=3)
        except (ProcessLookupError, subprocess.TimeoutExpired):
            try:
                os.killpg(process.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
        log.close()
TEST_EOF

if ! python3 -m pytest /tmp/test_fresh_execution.py -x --tb=short 2>&1; then
    all_ok=0
fi

if [ "$all_ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
