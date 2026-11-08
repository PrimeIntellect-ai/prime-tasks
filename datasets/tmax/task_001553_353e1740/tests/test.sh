#!/bin/bash
set +e
mkdir -p /logs/verifier

kill_ports() {
python3 - "$@" <<'PY'
import os
import signal
import sys

ports = {int(p) for p in sys.argv[1:]}
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        with open(table) as f:
            next(f)
            for line in f:
                cols = line.split()
                if cols[3] != '0A':
                    continue
                port = int(cols[1].split(':')[1], 16)
                if port in ports:
                    inodes.add(cols[9])
    except OSError:
        pass

for entry in os.listdir('/proc'):
    if not entry.isdigit() or int(entry) == os.getpid():
        continue
    fd_dir = f'/proc/{entry}/fd'
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f'{fd_dir}/{fd}')
            except OSError:
                continue
            if target.startswith('socket:[') and target[8:-1] in inodes:
                try:
                    os.kill(int(entry), signal.SIGKILL)
                except (ProcessLookupError, PermissionError):
                    pass
                break
    except OSError:
        pass
PY
}

wait_url() {
    local url="$1"
    local attempts="${2:-120}"
    for ((i=0; i<attempts; i++)); do
        if curl -fsS --max-time 1 "$url" >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.25
    done
    return 1
}

cleanup() {
    [ -n "$INFER_PID" ] && kill "$INFER_PID" >/dev/null 2>&1
    [ -n "$DATA_PID" ] && kill "$DATA_PID" >/dev/null 2>&1
    [ -n "$NGINX_PID" ] && kill "$NGINX_PID" >/dev/null 2>&1
    kill_ports 80 8000 8080 >/dev/null 2>&1
}

verify() {
    kill_ports 80 8000 8080 || return 1
    sleep 0.5

    test -f /app/inference_service/src/main.rs || return 1
    test -f /app/inference_service/Cargo.toml || return 1
    nginx -t -c /app/nginx.conf >/tmp/nginx-test.log 2>&1 || return 1
    cargo build --manifest-path /app/inference_service/Cargo.toml >/tmp/cargo-build.log 2>&1 || return 1

    BIN=/app/inference_service/target/debug/inference_service
    test -f "$BIN" && test -x "$BIN" || return 1

    python3 /app/data_server.py >/tmp/data-server.log 2>&1 &
    DATA_PID=$!
    wait_url 'http://127.0.0.1:8000/data.csv' || return 1

    "$BIN" >/tmp/inference-fixed.log 2>&1 &
    INFER_PID=$!

    nginx -c /app/nginx.conf >/tmp/nginx.log 2>&1 &
    NGINX_PID=$!
    wait_url 'http://127.0.0.1:80/api/predict?x=3.0' || return 1

    cat <<'TEST_EOF' > /tmp/test_fixed_state.py
import math
import requests

def test_nginx_proxy_and_inference_math():
    url = "http://127.0.0.1:80/api/predict?x=3.0"

    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        raise AssertionError(f"Failed to connect to Nginx at {url}: {e}")

    assert response.status_code == 200, f"Expected status 200, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        raise AssertionError(f"Expected JSON response, got: {response.text}")

    assert "mean" in data, f"Response JSON missing 'mean' field: {data}"
    assert "variance" in data, f"Response JSON missing 'variance' field: {data}"

    x_vals = [1.0, 2.0, 1.5, 3.0]
    y_vals = [2.1, 3.9, 3.2, 6.0]
    noise_var = 2.0
    prior_var = 1.0

    sum_xx = sum(x**2 / noise_var for x in x_vals)
    sum_xy = sum(x*y / noise_var for x, y in zip(x_vals, y_vals))
    post_var = 1.0 / ((1.0 / prior_var) + sum_xx)
    post_mean = post_var * sum_xy

    x_star = 3.0
    expected_mean = post_mean * x_star
    expected_var = (x_star**2 * post_var) + noise_var
    actual_mean = data["mean"]
    actual_var = data["variance"]

    assert math.isclose(actual_mean, expected_mean, rel_tol=1e-4), \
        f"Predictive mean is incorrect. Expected ~{expected_mean:.5f}, got {actual_mean}"
    assert math.isclose(actual_var, expected_var, rel_tol=1e-4), \
        f"Predictive variance is incorrect. Expected ~{expected_var:.5f}, got {actual_var}"
TEST_EOF
    python3 -m pytest /tmp/test_fixed_state.py -x --tb=short || return 1

    kill "$INFER_PID" >/dev/null 2>&1
    kill "$DATA_PID" >/dev/null 2>&1
    wait "$INFER_PID" >/dev/null 2>&1
    wait "$DATA_PID" >/dev/null 2>&1
    INFER_PID=
    DATA_PID=
    kill_ports 8000 8080 || return 1
    sleep 0.5

    python3 <<'PY' || return 1
import json
import random
import secrets

rng = random.Random(secrets.randbits(128))
rows = []
for _ in range(7):
    x = rng.uniform(-4.5, 4.5)
    if abs(x) < 0.35:
        x += 0.8 if x >= 0 else -0.8
    y = rng.uniform(-8.0, 8.0)
    rows.append((x, y))

queries = []
while len(queries) < 7:
    x = rng.uniform(-7.0, 7.0)
    if abs(x) > 0.2 and abs(x - 3.0) > 0.1:
        queries.append(x)

with open('/tmp/verifier-data.csv', 'w') as f:
    f.write('x,y\n')
    for x, y in rows:
        f.write(f'{x:.17g},{y:.17g}\n')
with open('/tmp/verifier-queries.json', 'w') as f:
    json.dump(queries, f)
PY

    cat <<'PY' > /tmp/dynamic_data_server.py
from http.server import BaseHTTPRequestHandler, HTTPServer

with open('/tmp/verifier-data.csv', 'rb') as f:
    payload = f.read()

class Server(HTTPServer):
    allow_reuse_address = True

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == '/data.csv':
            self.send_response(200)
            self.send_header('Content-Type', 'text/csv')
            self.send_header('Content-Length', str(len(payload)))
            self.end_headers()
            self.wfile.write(payload)
        else:
            self.send_response(404)
            self.end_headers()
    def log_message(self, *args):
        pass

Server(('127.0.0.1', 8000), Handler).serve_forever()
PY

    python3 /tmp/dynamic_data_server.py >/tmp/dynamic-data.log 2>&1 &
    DATA_PID=$!
    wait_url 'http://127.0.0.1:8000/data.csv' || return 1

    "$BIN" >/tmp/inference-dynamic.log 2>&1 &
    INFER_PID=$!
    wait_url 'http://127.0.0.1:80/api/predict?x=1.23456789' || return 1

    cat <<'TEST_EOF' > /tmp/test_dynamic_state.py
import csv
import json
import math
import requests


def test_runtime_dataset_and_unpredictable_inputs():
    with open('/tmp/verifier-data.csv', newline='') as f:
        rows = list(csv.DictReader(f))
    xs = [float(r['x']) for r in rows]
    ys = [float(r['y']) for r in rows]
    with open('/tmp/verifier-queries.json') as f:
        queries = json.load(f)

    noise_var = 2.0
    prior_var = 1.0
    sum_xx = sum(x * x / noise_var for x in xs)
    sum_xy = sum(x * y / noise_var for x, y in zip(xs, ys))
    post_var = 1.0 / ((1.0 / prior_var) + sum_xx)
    post_mean = post_var * sum_xy

    for x_star in queries:
        response = requests.get(
            'http://127.0.0.1:80/api/predict', params={'x': repr(x_star)}, timeout=5
        )
        assert response.status_code == 200, response.text
        try:
            data = response.json()
        except ValueError:
            raise AssertionError(f'Expected JSON response, got: {response.text}')
        assert 'mean' in data, f"Response JSON missing 'mean' field: {data}"
        assert 'variance' in data, f"Response JSON missing 'variance' field: {data}"

        expected_mean = post_mean * x_star
        expected_var = x_star * x_star * post_var + noise_var
        assert math.isclose(data['mean'], expected_mean, rel_tol=1e-5, abs_tol=1e-7), \
            f"Incorrect mean for x={x_star}: expected {expected_mean}, got {data['mean']}"
        assert math.isclose(data['variance'], expected_var, rel_tol=1e-5, abs_tol=1e-7), \
            f"Incorrect variance for x={x_star}: expected {expected_var}, got {data['variance']}"
TEST_EOF
    python3 -m pytest /tmp/test_dynamic_state.py -x --tb=short || return 1
    return 0
}

INFER_PID=
DATA_PID=
NGINX_PID=
if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
cleanup
exit 0
