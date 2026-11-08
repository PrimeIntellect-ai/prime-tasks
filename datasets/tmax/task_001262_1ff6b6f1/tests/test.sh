#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import csv
import fcntl
import io
import json
import os
import re
import stat
import subprocess
import time
import uuid
import zipfile

import requests

BASE_URL = "http://127.0.0.1:8080"
JSONL_PATH = "/tmp/video_events.jsonl"
CSV_PATH = "/tmp/video_events.csv"
ZIP_PATH = "/tmp/backup.zip"
VIDEO_PATH = "/app/surveillance.mp4"


def get_expected_frame_count():
    cmd = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-count_frames", "-show_entries", "stream=nb_read_frames",
        "-of", "csv=p=0", VIDEO_PATH,
    ]
    output = subprocess.check_output(cmd, timeout=20).decode().strip()
    return int(output)


def assert_regular_file(path):
    assert os.path.exists(path), f"Required file was not created: {path}"
    assert stat.S_ISREG(os.stat(path).st_mode), f"Expected a regular file: {path}"


def test_server_functionality():
    for path in (JSONL_PATH, CSV_PATH, ZIP_PATH):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    expected_frames = get_expected_frame_count()

    # Hold the actual JSONL inode locked while /analyze is issued. A compliant
    # endpoint cannot finish its append until this lock is released.
    lock_file = open(JSONL_PATH, "a+", encoding="utf-8")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
        analyze_future = executor.submit(requests.post, f"{BASE_URL}/analyze", timeout=30)
        time.sleep(1.5)
        analyze_blocked = not analyze_future.done()
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        assert analyze_blocked, "/analyze completed while another process held an exclusive fcntl lock"
        resp_analyze = analyze_future.result(timeout=25)
    lock_file.close()
    assert resp_analyze.status_code == 200, f"Expected 200 OK from /analyze, got {resp_analyze.status_code}"

    # Use run-specific values that cannot be precomputed by a synthetic server.
    nonce = uuid.uuid4().hex
    payloads = [
        {
            "timestamp": f"{1000 + i}-{nonce}-{uuid.uuid4().hex}",
            "event": f"Concurrent event {i} [{nonce}:{uuid.uuid4().hex}]",
        }
        for i in range(50)
    ]

    # Exercise all 50 requests concurrently while an external process owns the
    # exclusive lock. None may report success before the lock is released.
    lock_file = open(JSONL_PATH, "a+", encoding="utf-8")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)

    def send_log(payload):
        try:
            response = requests.post(f"{BASE_URL}/log", json=payload, timeout=30)
            return response.status_code, payload
        except Exception:
            return 0, payload

    with concurrent.futures.ThreadPoolExecutor(max_workers=50) as executor:
        futures = [executor.submit(send_log, payload) for payload in payloads]
        time.sleep(1.5)
        logs_blocked = not any(future.done() for future in futures)
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        assert logs_blocked, "/log completed while another process held an exclusive fcntl lock"
        results = [future.result(timeout=25) for future in concurrent.futures.as_completed(futures)]
    lock_file.close()

    for status_code, payload in results:
        assert status_code == 200, f"Expected 200 OK from /log for {payload}, got {status_code}"

    # Verify the actual append-only JSONL artifact before requesting a backup.
    assert_regular_file(JSONL_PATH)
    with open(JSONL_PATH, "rb") as f:
        jsonl_bytes = f.read()
    assert jsonl_bytes.endswith(b"\n"), "JSONL file must end each object with a newline"
    raw_lines = jsonl_bytes.decode("utf-8").splitlines()
    assert len(raw_lines) == 51, f"Expected exactly 51 JSONL records, found {len(raw_lines)}"
    try:
        jsonl_objects = [json.loads(line) for line in raw_lines]
    except Exception as exc:
        assert False, f"Invalid JSONL data: {exc}"

    expected_analyze = {"timestamp": "0", "event": f"Video contains {expected_frames} frames"}
    assert jsonl_objects[0] == expected_analyze, f"Incorrect /analyze JSON object: {jsonl_objects[0]}"
    assert all(isinstance(obj, dict) and set(obj) == {"timestamp", "event"} for obj in jsonl_objects), \
        "Each JSONL record must be exactly an object with timestamp and event fields"

    expected_pairs = sorted((p["timestamp"], p["event"]) for p in payloads)
    actual_pairs = sorted((p.get("timestamp"), p.get("event")) for p in jsonl_objects[1:])
    assert actual_pairs == expected_pairs, "On-disk JSONL does not contain the exact submitted log objects"
    for i in range(50):
        assert any(f"Concurrent event {i}" in obj["event"] for obj in jsonl_objects[1:]), \
            f"Missing 'Concurrent event {i}' in JSONL"

    # /backup must also wait for the exclusive lock it is required to acquire.
    lock_file = open(JSONL_PATH, "a+", encoding="utf-8")
    fcntl.flock(lock_file.fileno(), fcntl.LOCK_EX)
    with concurrent.futures.ThreadPoolExecutor(max_workers=1) as executor:
        backup_future = executor.submit(requests.get, f"{BASE_URL}/backup", timeout=30)
        time.sleep(1.5)
        backup_blocked = not backup_future.done()
        fcntl.flock(lock_file.fileno(), fcntl.LOCK_UN)
        assert backup_blocked, "/backup completed while another process held an exclusive fcntl lock"
        resp_backup = backup_future.result(timeout=25)
    lock_file.close()

    assert resp_backup.status_code == 200, f"Expected 200 OK from /backup, got {resp_backup.status_code}"
    assert "zip" in resp_backup.headers.get("Content-Type", "").lower(), \
        "Response Content-Type should indicate a zip file"

    # The required on-disk CSV and ZIP must really have been created, and the
    # response must be the created archive rather than an unrelated synthetic ZIP.
    assert_regular_file(CSV_PATH)
    assert_regular_file(ZIP_PATH)
    with open(CSV_PATH, "rb") as f:
        disk_csv_bytes = f.read()
    with open(ZIP_PATH, "rb") as f:
        disk_zip_bytes = f.read()
    assert disk_zip_bytes == resp_backup.content, "HTTP response does not match /tmp/backup.zip"

    try:
        response_zip = zipfile.ZipFile(io.BytesIO(resp_backup.content))
    except zipfile.BadZipFile:
        assert False, "Response body is not a valid ZIP file"
    assert response_zip.testzip() is None, "Response ZIP failed its integrity check"

    names = response_zip.namelist()
    assert "video_events.csv" in names, "video_events.csv not found at the root of the backup ZIP"
    assert "surveillance.mp4" in names, "surveillance.mp4 not found at the root of the backup ZIP"
    assert names.count("video_events.csv") == 1, "ZIP contains duplicate video_events.csv entries"
    assert names.count("surveillance.mp4") == 1, "ZIP contains duplicate surveillance.mp4 entries"
    assert response_zip.read("video_events.csv") == disk_csv_bytes, \
        "Archived CSV bytes differ from /tmp/video_events.csv"
    with open(VIDEO_PATH, "rb") as f:
        original_video_bytes = f.read()
    assert response_zip.read("surveillance.mp4") == original_video_bytes, \
        "Archived surveillance.mp4 is not the original /app/surveillance.mp4"

    # Verify the exact CSV schema and that every row mirrors JSONL, including
    # timestamps, events, order, and the exact analyze result.
    csv_text = disk_csv_bytes.decode("utf-8")
    reader = csv.DictReader(io.StringIO(csv_text))
    assert reader.fieldnames == ["timestamp", "event"], \
        f"Expected CSV headers timestamp,event; got {reader.fieldnames}"
    rows = list(reader)
    assert len(rows) == 51, f"Expected exactly 51 rows in CSV (1 analyze + 50 logs), found {len(rows)}"
    assert rows == jsonl_objects, "CSV rows do not exactly match the on-disk JSONL records"

    first_row = rows[0]
    assert first_row.get("timestamp") == "0", \
        f"First row timestamp should be '0', got {first_row.get('timestamp')}"
    event_text = first_row.get("event", "")
    assert event_text == f"Video contains {expected_frames} frames", \
        f"Expected exact frame event for {expected_frames} frames, got '{event_text}'"
    assert str(expected_frames) in event_text
    assert re.fullmatch(r"Video contains \d+ frames", event_text)

    events = [row.get("event", "") for row in rows[1:]]
    for i in range(50):
        assert any(f"Concurrent event {i}" in event for event in events), \
            f"Missing 'Concurrent event {i}' in CSV"

    response_zip.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
