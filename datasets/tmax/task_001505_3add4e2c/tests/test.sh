#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import subprocess
import urllib.request

import pytest

EXPECTED_EVALUATOR = '''import redis, requests, numpy as np

r = redis.Redis(host='localhost', port=6379, db=0)
r.delete('telemetry_stream')

np.random.seed(42)
t_base = 1700000000
t = np.linspace(t_base, t_base + 1000, 100)
y = 2.5 * ((t - t_base)/1000)**2 + 1.2 * ((t - t_base)/1000) + 0.5 + np.random.normal(0, 0.01, 100)

for i in range(len(t)):
    r.rpush('telemetry_stream', f"{t[i]},{y[i]}")

try:
    resp = requests.post('http://localhost:8080/fit_and_predict', json={"predict_timestamps": t.tolist()})
    preds = resp.json()['predictions']
    mse = np.mean((y - np.array(preds))**2)
    print(f"FINAL_MSE={mse}")
except Exception as e:
    print(f"FINAL_MSE=999.0")
'''


def redis_cli(*args):
    return subprocess.run(
        ["redis-cli", "--raw", *map(str, args)],
        check=True,
        capture_output=True,
        text=True,
    ).stdout


def request_predictions(timestamps):
    body = json.dumps({"predict_timestamps": timestamps}).encode()
    req = urllib.request.Request(
        "http://127.0.0.1:8080/fit_and_predict",
        data=body,
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=10) as response:
        payload = json.loads(response.read().decode())
    predictions = payload.get("predictions")
    assert isinstance(predictions, list)
    assert len(predictions) == len(timestamps)
    assert all(isinstance(v, (int, float)) and math.isfinite(v) for v in predictions)
    return [float(v) for v in predictions]


def test_required_files_and_evaluator_unchanged():
    regression = "/app/telemetry_system/analyzer/src/regression.rs"
    assert os.path.isfile(regression), "regression.rs is missing"
    assert not os.path.islink(regression), "regression.rs must be a real source file"
    with open("/app/telemetry_system/evaluate.py", "r", encoding="utf-8") as f:
        assert f.read() == EXPECTED_EVALUATOR, "evaluate.py was modified"


def test_hidden_regression_cases():
    rng = random.SystemRandom()
    for _ in range(4):
        base = rng.uniform(1_500_000_000.0, 1_900_000_000.0)
        span = rng.uniform(250.0, 5000.0)
        c0 = rng.uniform(-1.0, 2.0)
        c1 = rng.uniform(-2.5, 2.5)
        c2 = rng.uniform(0.4, 4.0)

        train_u = sorted(rng.uniform(0.0, 1.0) for _ in range(80))
        train_t = [base + span * u for u in train_u]
        train_y = [c0 + c1 * u + c2 * u * u + rng.gauss(0.0, 0.002) for u in train_u]

        redis_cli("DEL", "telemetry_stream")
        for x, y in zip(train_t, train_y):
            redis_cli("RPUSH", "telemetry_stream", f"{x:.17g},{y:.17g}")

        query_u = [-0.15 + 1.30 * i / 32.0 for i in range(33)]
        query_t = [base + span * u for u in query_u]
        expected = [c0 + c1 * u + c2 * u * u for u in query_u]
        predictions = request_predictions(query_t)
        mse = sum((a - b) ** 2 for a, b in zip(predictions, expected)) / len(expected)
        assert mse < 0.001, f"hidden large-timestamp regression MSE was {mse}"


def test_evaluate_mse():
    result = subprocess.run(
        ["python3", "/app/telemetry_system/evaluate.py"],
        capture_output=True,
        text=True,
        check=True,
    )
    match = re.search(r"FINAL_MSE=([0-9eE.-]+)", result.stdout)
    assert match, f"Could not find FINAL_MSE in evaluate.py output. Output was:\n{result.stdout}"
    mse = float(match.group(1))
    assert mse < 0.05, f"FINAL_MSE is {mse}, which is not strictly less than the threshold of 0.05"
TEST_EOF

if (
    set -e

    # Stop any agent-controlled listener and launch a freshly built analyzer artifact.
    python3 - <<'PY'
import os
import signal

port_hex = format(8080, '04X')
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
                os.kill(int(pid), signal.SIGKILL)
                break
    except OSError:
        pass
PY

    redis-cli shutdown nosave >/dev/null 2>&1 || true
    /usr/bin/redis-server --daemonize yes --save '' --appendonly no
    for i in $(seq 1 50); do
        [ "$(redis-cli ping 2>/dev/null)" = "PONG" ] && break
        sleep 0.1
    done
    [ "$(redis-cli ping 2>/dev/null)" = "PONG" ]

    cd /app/telemetry_system/analyzer
    cargo build --release
    ./target/release/analyzer >/tmp/verifier-analyzer.log 2>&1 &
    ANALYZER_PID=$!
    trap 'kill "$ANALYZER_PID" >/dev/null 2>&1 || true' EXIT

    for i in $(seq 1 100); do
        if curl -sS -o /dev/null -X POST \
            -H 'Content-Type: application/json' \
            -d '{"predict_timestamps":[]}' \
            http://127.0.0.1:8080/fit_and_predict; then
            break
        fi
        kill -0 "$ANALYZER_PID"
        sleep 0.1
    done
    kill -0 "$ANALYZER_PID"

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short
) 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
