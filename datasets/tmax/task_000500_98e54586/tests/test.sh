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

cat << 'TEST_EOF' > /tmp/test_final_state.py
import gzip
import json
import os
import random
import struct
import time
import zlib

import requests

LOG_PATH = "/home/user/app/logs/rotating.log.gz"
URL = "http://127.0.0.1:8080/latest-events"


def encode_record(payload):
    encoded = json.dumps(payload, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    return b"EVT\x01" + struct.pack(">I", len(encoded)) + encoded


def replace_log(contents):
    temporary = LOG_PATH + ".verifier-tmp"
    with open(temporary, "wb") as stream:
        stream.write(contents)
        stream.flush()
        os.fsync(stream.fileno())
    os.replace(temporary, LOG_PATH)


def get_json():
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as exc:
        assert False, f"Failed to connect to the server at {URL}. Error: {exc}"

    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, (
        f"Expected Content-Type application/json, got {content_type}"
    )
    try:
        data = response.json()
    except ValueError:
        assert False, "Response body is not valid JSON."
    assert isinstance(data, list), "Expected response JSON to be a list."
    return data


def test_server_script_exists():
    server_script = "/home/user/app/server.py"
    assert os.path.isfile(server_script), f"Server script {server_script} does not exist."


def test_http_endpoint_responses():
    url = "http://127.0.0.1:8080/latest-events"

    # Make multiple requests to ensure stability against race conditions (log rotation)
    for i in range(3):
        try:
            response = requests.get(url, timeout=5)
        except requests.exceptions.RequestException as e:
            assert False, f"Failed to connect to the server at {url}. Error: {e}"

        assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"

        content_type = response.headers.get("Content-Type", "")
        assert "application/json" in content_type, f"Expected Content-Type application/json, got {content_type}"

        try:
            data = response.json()
        except ValueError:
            assert False, "Response body is not valid JSON."

        assert isinstance(data, list), "Expected response JSON to be a list."

        if data:
            # Verify the structure of the parsed items
            last_item = data[-1]
            assert "event_id" in last_item, f"Expected 'event_id' in record, got {last_item}"
            assert "status" in last_item, f"Expected 'status' in record, got {last_item}"

        time.sleep(1.5) # Wait to allow the background writer to write/rotate


def test_parses_valid_gzip_binary_records():
    expected = [
        {"event_id": 101, "status": "started", "nested": {"ok": True}},
        {"event_id": "unicode-事件", "status": "complete", "values": [1, 2, 3]},
        {"event_id": 103, "status": "failed", "message": "disk pressure"},
    ]
    raw = b"".join(encode_record(item) for item in expected)
    replace_log(gzip.compress(raw, mtime=0))
    assert get_json() == expected


def test_ignores_incomplete_binary_record_at_end():
    complete = {"event_id": 201, "status": "complete"}
    incomplete = {"event_id": 202, "status": "must-not-appear", "blob": "x" * 4096}
    incomplete_record = encode_record(incomplete)
    raw = encode_record(complete) + incomplete_record[:37]
    replace_log(gzip.compress(raw, mtime=0))
    assert get_json() == [complete]


def test_recovers_complete_records_from_truncated_gzip_stream():
    complete = {"event_id": 301, "status": "preserved"}
    rng = random.Random(7319)
    large_text = bytes(rng.randrange(256) for _ in range(150000)).hex()
    unfinished = {"event_id": 302, "status": "partial", "blob": large_text}

    first_record = encode_record(complete)
    raw = first_record + encode_record(unfinished)
    compressed = gzip.compress(raw, compresslevel=6, mtime=0)

    truncated = None
    step = max(1, len(compressed) // 20)
    for cut in range(step, len(compressed), step):
        inflater = zlib.decompressobj(16 + zlib.MAX_WBITS)
        produced = inflater.decompress(compressed[:cut])
        if len(produced) > len(first_record) + 8 and len(produced) < len(raw) and not inflater.eof:
            truncated = compressed[:cut]
            break

    assert truncated is not None, "Verifier could not construct a useful truncated gzip stream"
    replace_log(truncated)
    assert get_json() == [complete]


def test_reopens_log_after_rotation_and_handles_empty_truncation():
    before = [{"event_id": 401, "status": "before-rotation"}]
    after = [
        {"event_id": 402, "status": "after-rotation"},
        {"event_id": 403, "status": "latest"},
    ]

    replace_log(gzip.compress(b"".join(encode_record(item) for item in before), mtime=0))
    assert get_json() == before

    replace_log(gzip.compress(b"".join(encode_record(item) for item in after), mtime=0))
    assert get_json() == after

    # A zero-byte file is a possible instant during truncation and must not crash the service.
    replace_log(b"")
    assert get_json() == []
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
