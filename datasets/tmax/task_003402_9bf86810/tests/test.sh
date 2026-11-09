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

# Replace the fixed raw-data process with a controllable fixture so the service
# can be exercised against data that was not available while the agent worked.
pkill -f '^python3 /app/app.py$' 2>/dev/null || true
sleep 1

cat > /tmp/bulk_fixture.json <<'EOF'
[
  {"sensor_id":1,"timestamp":1,"value":10.0},
  {"sensor_id":1,"timestamp":2,"value":10.0},
  {"sensor_id":1,"timestamp":3,"value":100.0},
  {"sensor_id":1,"timestamp":4,"value":12.0},
  {"sensor_id":1,"timestamp":5,"value":200.0},
  {"sensor_id":1,"timestamp":6,"value":20.0},
  {"sensor_id":1,"timestamp":8,"value":5.0}
]
EOF
: > /tmp/bulk_fixture_requests

cat > /tmp/bulk_fixture_server.py <<'PYEOF'
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path != "/bulk_data":
            self.send_response(404)
            self.end_headers()
            return
        with open("/tmp/bulk_fixture.json", "rb") as f:
            body = f.read()
        # Record each actual extraction request before returning the data.
        with open("/tmp/bulk_fixture_requests", "ab") as f:
            f.write(b"1\n")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format, *args):
        pass

ThreadingHTTPServer(("127.0.0.1", 8081), Handler).serve_forever()
PYEOF

python3 /tmp/bulk_fixture_server.py >/tmp/bulk_fixture_server.log 2>&1 &
FIXTURE_PID=$!
trap 'kill "$FIXTURE_PID" 2>/dev/null || true' EXIT

for _ in $(seq 1 30); do
    if curl -fsS http://127.0.0.1:8081/bulk_data >/dev/null 2>&1; then
        break
    fi
    sleep 0.1
done
# Do not count the readiness probe as a pipeline fetch.
: > /tmp/bulk_fixture_requests

cat > /tmp/test_final_state.py <<'PYEOF'
import json
import math
import os
import random
import subprocess
import time

import pytest
import requests

BASE = "http://127.0.0.1:9090"
FIXTURE = "/tmp/bulk_fixture.json"
COUNT_FILE = "/tmp/bulk_fixture_requests"
DB_URL = "postgresql://postgres:password@127.0.0.1:5432/etl_db"


def request_count():
    try:
        with open(COUNT_FILE, "rb") as f:
            return sum(1 for line in f if line.strip())
    except FileNotFoundError:
        return 0


def set_fixture(rows):
    temporary = FIXTURE + ".new"
    with open(temporary, "w") as f:
        json.dump(rows, f)
    os.replace(temporary, FIXTURE)


def run_pipeline():
    before = request_count()
    try:
        response = requests.post(BASE + "/run_pipeline", timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the Go service or POST /run_pipeline timed out: {e}")
    assert response.status_code in [200, 201, 202, 204], (
        f"Expected success status code for POST /run_pipeline, got "
        f"{response.status_code}. Response: {response.text}"
    )
    deadline = time.time() + 3
    while request_count() <= before and time.time() < deadline:
        time.sleep(0.05)
    assert request_count() > before, "POST /run_pipeline did not fetch /bulk_data"
    time.sleep(1)


def get_anomalies(sensor_id):
    try:
        response = requests.get(
            BASE + "/anomalies", params={"sensor_id": sensor_id}, timeout=5
        )
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to GET /anomalies from the Go service: {e}")
    assert response.status_code == 200, (
        f"Expected 200 OK for GET /anomalies, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"GET /anomalies did not return valid JSON: {response.text}")
    assert isinstance(data, list), f"Expected a JSON array, got {type(data).__name__}"
    return data


def psql(query):
    result = subprocess.run(
        ["psql", DB_URL, "-t", "-A", "-c", query],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Postgres query failed: {result.stderr}"
    return result.stdout.strip()


def derive_expected(rows):
    groups = {}
    for row in rows:
        if int(row["timestamp"]) % 2 == 0:
            groups.setdefault(int(row["sensor_id"]), []).append(row)

    expected = []
    for sensor_id, samples in groups.items():
        samples.sort(key=lambda r: int(r["timestamp"]))
        previous = []
        for row in samples:
            value = float(row["value"])
            rolling = sum(previous[-2:]) / len(previous[-2:]) if previous else 0.0
            if previous and value > 1.5 * rolling:
                expected.append({
                    "sensor_id": sensor_id,
                    "timestamp": int(row["timestamp"]),
                    "value": value,
                    "rolling_avg": rolling,
                })
            previous.append(value)
    return sorted(expected, key=lambda r: (r["sensor_id"], r["timestamp"]))


def assert_records(actual, expected):
    assert len(actual) == len(expected), f"Expected {expected}, got {actual}"
    for got, want in zip(actual, expected):
        assert int(got.get("sensor_id")) == want["sensor_id"]
        assert int(got.get("timestamp")) == want["timestamp"]
        assert math.isclose(float(got.get("value")), want["value"], rel_tol=1e-9, abs_tol=1e-9)
        assert math.isclose(
            float(got.get("rolling_avg")), want["rolling_avg"], rel_tol=1e-9, abs_tol=1e-9
        )


def database_records():
    output = psql(
        "SELECT sensor_id, timestamp, value, rolling_avg "
        "FROM anomalies ORDER BY sensor_id ASC, timestamp ASC;"
    )
    if not output:
        return []
    records = []
    for line in output.splitlines():
        columns = line.split("|")
        assert len(columns) == 4, f"Unexpected database output: {line}"
        records.append({
            "sensor_id": int(columns[0]),
            "timestamp": int(columns[1]),
            "value": float(columns[2]),
            "rolling_avg": float(columns[3]),
        })
    return records


def verify_dynamic_case(rows):
    expected = derive_expected(rows)
    set_fixture(rows)

    # A correct run must clear stale data before loading the new result.
    psql(
        "INSERT INTO anomalies(sensor_id,timestamp,value,rolling_avg) "
        "VALUES (987654,987654,987654,987654);"
    )
    run_pipeline()

    sensor_ids = sorted({int(row["sensor_id"]) for row in rows})
    for sensor_id in sensor_ids:
        wanted = [r for r in expected if r["sensor_id"] == sensor_id]
        actual = get_anomalies(sensor_id)
        assert [int(r["timestamp"]) for r in actual] == sorted(
            int(r["timestamp"]) for r in actual
        ), "GET /anomalies results are not ordered by timestamp"
        assert_records(actual, wanted)

    assert get_anomalies(987654) == [], "Stale rows were not cleared"
    assert_records(database_records(), expected)


def test_original_pipeline_execution_and_anomalies():
    # Preserve the original fixed-fixture assertions.
    run_pipeline()
    data = get_anomalies(1)
    assert len(data) == 1, f"Expected exactly 1 anomaly, got {len(data)}. Data: {data}"
    anomaly = data[0]
    assert anomaly.get("sensor_id") == 1
    assert anomaly.get("timestamp") == 6
    assert float(anomaly.get("value")) == 20.0
    assert float(anomaly.get("rolling_avg")) == 11.0

    output = psql(
        "SELECT sensor_id, timestamp, value, rolling_avg FROM anomalies "
        "WHERE sensor_id = 1 ORDER BY timestamp ASC;"
    )
    assert output, "The anomalies table is empty or missing expected records"
    rows = output.split("\n")
    assert len(rows) == 1, f"Expected exactly 1 row, got {len(rows)}: {output}"
    columns = rows[0].split("|")
    assert len(columns) == 4
    assert int(columns[0]) == 1
    assert int(columns[1]) == 6
    assert float(columns[2]) == 20.0
    assert float(columns[3]) == 11.0


def test_pipeline_on_unseen_inputs_and_repeated_runs():
    rng = random.SystemRandom()
    ids = rng.sample(range(100, 900), 5)
    bases = rng.sample(range(10, 80), 5)
    offset = 2 * rng.randrange(20, 100)

    # This case covers multiple sensors, unsorted input, ignored odd timestamps,
    # one-value rolling averages, two-value windows, and strict boundaries.
    rows1 = []
    patterns = [
        [bases[0], bases[0] * 1.1, bases[0] * 3, bases[0] * 0.8, bases[0] * 4],
        [bases[1], bases[1] * 2, bases[1] * 0.1],
        [bases[2], bases[2] * 1.5],
    ]
    for sensor_id, values in zip(ids[:3], patterns):
        for index, value in enumerate(values):
            timestamp = offset + index * 2
            rows1.append({"sensor_id": sensor_id, "timestamp": timestamp, "value": value})
            rows1.append({
                "sensor_id": sensor_id,
                "timestamp": timestamp + 1,
                "value": bases[3] * 1000 + index,
            })
    rng.shuffle(rows1)
    verify_dynamic_case(rows1)

    # A different latest dataset verifies that results are recomputed and old
    # anomalies are removed rather than accumulated or returned as constants.
    offset2 = offset + 200
    rows2 = [
        {"sensor_id": ids[3], "timestamp": offset2 + 4, "value": bases[3]},
        {"sensor_id": ids[3], "timestamp": offset2, "value": bases[3]},
        {"sensor_id": ids[3], "timestamp": offset2 + 2, "value": bases[3]},
        {"sensor_id": ids[4], "timestamp": offset2, "value": bases[4]},
        {"sensor_id": ids[4], "timestamp": offset2 + 2, "value": bases[4] * 2},
        {"sensor_id": ids[4], "timestamp": offset2 + 3, "value": bases[4] * 1000},
    ]
    rng.shuffle(rows2)
    verify_dynamic_case(rows2)
PYEOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
