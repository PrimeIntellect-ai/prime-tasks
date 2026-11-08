#!/bin/bash
mkdir -p /logs/verifier

# Replace the dummy services with deterministic test doubles.
if command -v fuser >/dev/null 2>&1; then
    fuser -k 5001/tcp >/dev/null 2>&1 || true
    fuser -k 5002/tcp >/dev/null 2>&1 || true
fi
pkill -f '[s]ensor_api.py' >/dev/null 2>&1 || true
pkill -f '[d]ata_warehouse.py' >/dev/null 2>&1 || true
sleep 1

rm -f /tmp/etl_capture.b64
rm -rf /tmp/etl_verifier_work
mkdir -p /tmp/etl_verifier_work
rm -f /home/user/temp_data.jsonl /home/user/processed_data.jsonl
redis-cli FLUSHALL >/dev/null 2>&1 || true

cat <<'PY' > /tmp/etl_mock_services.py
import base64
import json
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

ROWS = [
    {"timestamp": "2024-01-01T11:59:55Z", "msg": "OUTSIDE_BEFORE", "value": -1},
    {"timestamp": "2024-01-01T12:00:40Z", "msg": "LATE_IN_MINUTE", "value": 40},
    {"timestamp": "2024-01-01T12:00:05Z", "msg": "FIRST", "value": 5},
    {"timestamp": "2024-01-01T12:01:15Z", "msg": "温度センサー正常", "value": 42},
    {"timestamp": "2024-01-01T12:01:15Z", "msg": "温度センサー正常", "value": 42},
    {"timestamp": "2024-01-01T12:02:10Z", "msg": "あいうえおかきくけこさしすせそた", "value": 2},
    {"timestamp": "2024-01-01T12:03:54Z", "msg": "درجة الحرارة", "value": 33},
    {"timestamp": "2024-01-01T12:03:58Z", "msg": "LATER", "value": 34},
    {"timestamp": "2024-01-01T12:59:59Z", "msg": "END", "value": 59},
    {"timestamp": "2024-01-01T13:00:00Z", "msg": "OUTSIDE_AFTER", "value": 60},
]
FULL = b"".join((json.dumps(row, ensure_ascii=False) + "\n").encode("utf-8") for row in ROWS)
PREFIX = b"".join((json.dumps(row, ensure_ascii=False) + "\n").encode("utf-8") for row in ROWS[:4])
state_lock = threading.Lock()
log_requests = 0
capture_lock = threading.Lock()

class SensorHandler(BaseHTTPRequestHandler):
    def do_GET(self):
        global log_requests
        if self.path.split("?", 1)[0] != "/api/v1/logs":
            self.send_error(404)
            return
        with state_lock:
            log_requests += 1
            request_number = log_requests
        # The first response is retryable and contains a valid partial batch. A
        # pipeline which appends retry bodies will therefore see duplicates.
        body = PREFIX if request_number == 1 else FULL
        self.send_response(500 if request_number == 1 else 200)
        self.send_header("Content-Type", "application/x-ndjson; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, *args):
        pass

class WarehouseHandler(BaseHTTPRequestHandler):
    def do_POST(self):
        if self.path.split("?", 1)[0] != "/api/v1/load":
            self.send_error(404)
            return
        length = int(self.headers.get("Content-Length", "0"))
        body = self.rfile.read(length)
        with capture_lock:
            with open("/tmp/etl_capture.b64", "ab") as fh:
                fh.write(base64.b64encode(body) + b"\n")
        payload = json.dumps({"status": "success"}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_GET(self):
        if self.path.split("?", 1)[0] != "/api/v1/stats":
            self.send_error(404)
            return
        payload = json.dumps({"accuracy": 0.983}).encode()
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def log_message(self, *args):
        pass

sensor = ThreadingHTTPServer(("127.0.0.1", 5001), SensorHandler)
warehouse = ThreadingHTTPServer(("127.0.0.1", 5002), WarehouseHandler)
threading.Thread(target=sensor.serve_forever, daemon=True).start()
warehouse.serve_forever()
PY

python3 /tmp/etl_mock_services.py >/tmp/etl_mock_services.log 2>&1 &
MOCK_PID=$!
trap 'kill "$MOCK_PID" >/dev/null 2>&1 || true' EXIT
sleep 1

cat <<'PY' > /tmp/test_final_state.py
import base64
import datetime
import json
import os
import stat
import subprocess
import urllib.request
import pytest

SCRIPT = "/home/user/etl_pipeline.sh"
CAPTURE = "/tmp/etl_capture.b64"


def parse_post_body(body):
    text = body.decode("utf-8").strip()
    assert text, "The warehouse received an empty POST body."
    try:
        value = json.loads(text)
        if isinstance(value, list):
            return value
        if isinstance(value, dict):
            return [value]
    except json.JSONDecodeError:
        pass

    records = []
    for number, line in enumerate(text.splitlines(), 1):
        if not line.strip():
            continue
        try:
            value = json.loads(line)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Warehouse POST contains invalid JSON on line {number}: {exc}")
        assert isinstance(value, dict), "Each JSON-lines item must be an object."
        records.append(value)
    return records


def test_pipeline_artifact_and_behavior():
    assert os.path.lexists(SCRIPT), f"Required pipeline does not exist: {SCRIPT}"
    info = os.lstat(SCRIPT)
    assert stat.S_ISREG(info.st_mode), "The pipeline path must be a regular file, not a symlink or directory."
    assert os.access(SCRIPT, os.X_OK), "The pipeline script is not executable."

    result = subprocess.run(
        [SCRIPT],
        cwd="/tmp/etl_verifier_work",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(CAPTURE), "The pipeline never POSTed data to /api/v1/load."

    records = []
    with open(CAPTURE, "rb") as fh:
        for line in fh:
            if line.strip():
                records.extend(parse_post_body(base64.b64decode(line.strip())))

    assert len(records) == 60, f"Expected exactly 60 loaded records, received {len(records)}."
    for record in records:
        assert isinstance(record, dict), "Every loaded record must be a JSON object."
        assert isinstance(record.get("timestamp"), str), "Every record must have a string timestamp."
        assert "msg" in record, "Every record must contain the msg field."

    by_timestamp = {record["timestamp"]: record for record in records}
    assert len(by_timestamp) == 60, "Loaded timestamps are not unique."

    start = datetime.datetime(2024, 1, 1, 12, 0, tzinfo=datetime.timezone.utc)
    expected_timestamps = [
        (start + datetime.timedelta(minutes=i)).strftime("%Y-%m-%dT%H:%M:00Z")
        for i in range(60)
    ]
    assert set(by_timestamp) == set(expected_timestamps), (
        "Output must contain exactly one bucket for every minute from 12:00 through 12:59 UTC."
    )

    expected_real = {
        "2024-01-01T12:00:00Z": ("FIRST", 5),
        "2024-01-01T12:01:00Z": ("温度センサー正常", 42),
        "2024-01-01T12:03:00Z": ("درجة الحرارة", 33),
        "2024-01-01T12:59:00Z": ("END", 59),
    }
    for timestamp, (message, value) in expected_real.items():
        record = by_timestamp[timestamp]
        assert record["msg"] == message, f"Wrong source record selected for {timestamp}."
        assert record.get("value") == value, f"Wrong value selected for {timestamp}."

    for timestamp in expected_timestamps:
        if timestamp not in expected_real:
            assert by_timestamp[timestamp]["msg"] == "GAP_DETECTED", (
                f"Missing minute {timestamp} was not gap-filled correctly."
            )

    all_messages = [record["msg"] for record in records]
    assert "あいうえおかきくけこさしすせそた" not in all_messages, (
        "A message longer than 15 Unicode characters passed validation."
    )


def test_pipeline_accuracy():
    url = "http://localhost:5002/api/v1/stats"
    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode('utf-8'))
    except Exception as e:
        pytest.fail(f"Failed to fetch stats from Data Warehouse API at {url}: {e}")

    assert "accuracy" in data, "Response from Data Warehouse API is missing the 'accuracy' key."
    accuracy = data["accuracy"]
    threshold = 0.95

    assert accuracy >= threshold, f"Pipeline accuracy {accuracy} is below the required threshold of {threshold}."
PY

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
