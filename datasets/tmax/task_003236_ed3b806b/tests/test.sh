#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import subprocess
import tempfile
from datetime import datetime, timedelta

DETECTOR = "/home/user/detector.py"
ETL = "/home/user/etl.py"
TIMELINE = "/home/user/timeline.csv"
SALT = "k9#xP2m"


def run_detector(path):
    return subprocess.run(["python3", DETECTOR, path], capture_output=True, timeout=10).returncode


def write_json(path, value):
    with open(path, "w") as f:
        json.dump(value, f)


def payload_hash(payload):
    compact = json.dumps(payload, separators=(",", ":"), sort_keys=True)
    return hashlib.sha256((compact + SALT).encode()).hexdigest()


def expected_timeline(records):
    servers = sorted({r["server_id"] for r in records})
    # Deduplicate immediate consecutive payload hashes after chronological grouping.
    changes = {}
    for server in servers:
        ordered = sorted((r for r in records if r["server_id"] == server), key=lambda r: r["timestamp"])
        kept = []
        previous = None
        for record in ordered:
            digest = payload_hash(record["payload"])
            if digest != previous:
                kept.append((datetime.strptime(record["timestamp"], "%Y-%m-%dT%H:%M:%SZ"), digest))
            previous = digest
        changes[server] = kept

    rows = []
    start = datetime(2024, 1, 1)
    for i in range(48):
        bucket = start + timedelta(minutes=30 * i)
        bucket_text = bucket.strftime("%Y-%m-%dT%H:%M:%SZ")
        # A record becomes active in the bucket containing its timestamp.
        bucket_end = bucket + timedelta(minutes=30)
        for server in servers:
            active = "EMPTY"
            for timestamp, digest in changes[server]:
                if timestamp < bucket_end:
                    active = digest
                else:
                    break
            rows.append([bucket_text, server, active])
    return rows


def test_detector_clean_corpus():
    assert os.path.isfile(DETECTOR), "detector.py not found"
    clean_dir = "/app/corpora/clean"
    failures = []
    for name in os.listdir(clean_dir):
        if name.endswith(".json") and run_detector(os.path.join(clean_dir, name)) != 0:
            failures.append(name)
    assert not failures, f"clean corpus rejected: {failures}"


def test_detector_evil_corpus():
    assert os.path.isfile(DETECTOR), "detector.py not found"
    evil_dir = "/app/corpora/evil"
    failures = []
    for name in os.listdir(evil_dir):
        if name.endswith(".json") and run_detector(os.path.join(evil_dir, name)) != 1:
            failures.append(name)
    assert not failures, f"evil corpus bypassed: {failures}"


def test_detector_generated_nested_cases():
    assert os.path.isfile(DETECTOR), "detector.py not found"
    with tempfile.TemporaryDirectory() as directory:
        cases = [
            ("ordinary.json", {"meta": {"note": "LD-PRELOAD", "paths": ["/tmp", "/var/tmp"]}}, 0),
            ("deep_a.json", {"a": [1, {"b": [False, {"c": "prefix LD_PRELOAD=something"}]}]}, 1),
            ("deep_b.json", {"a": {"b": [{"c": "copy to /tmp/generated-name.bin now"}]}}, 1),
            ("deep_c.json", ["safe", {"x": [3, {"y": "/var/tmp/random-dir/file"}]}], 1),
            # Matching text in a key is not a string value and must remain clean.
            ("key_only.json", {"LD_PRELOAD /tmp/key": {"value": "safe"}}, 0),
        ]
        for name, document, expected in cases:
            path = os.path.join(directory, name)
            write_json(path, document)
            assert run_detector(path) == expected, f"wrong result for generated case {name}"


def test_etl_timeline_existing_assertions():
    # Preserve the original assertions against the requested output location.
    assert os.path.isfile(TIMELINE), f"{TIMELINE} not found"
    with open(TIMELINE, newline="") as f:
        rows = list(csv.reader(f))
    assert len(rows) > 0, "timeline.csv is empty"
    assert rows[0] == ["bucket_start", "server_id", "config_hash"], "Invalid CSV header"

    hash_srv1 = payload_hash({"path": "/var/www/html", "service": "web", "workers": 4})
    hash_srv2 = payload_hash({"options": ["--bind", "0.0.0.0"], "service": "db"})
    buckets = [(datetime(2024, 1, 1) + timedelta(minutes=30 * i)).strftime("%Y-%m-%dT%H:%M:%SZ") for i in range(48)]
    expected = []
    for bucket in buckets:
        expected.append([bucket, "srv1", "EMPTY" if bucket == "2024-01-01T00:00:00Z" else hash_srv1])
        expected.append([bucket, "srv2", "EMPTY" if bucket < "2024-01-01T02:00:00Z" else hash_srv2])
    expected.sort(key=lambda row: (row[0], row[1]))
    data = rows[1:]
    assert len(data) == len(expected), f"Expected {len(expected)} rows, got {len(data)}"
    for i, wanted in enumerate(expected):
        assert data[i] == wanted, f"Mismatch at row {i+1}: expected {wanted}, got {data[i]}"


def test_etl_executes_on_generated_input():
    assert os.path.isfile(ETL), "etl.py not found"
    records = [
        {"server_id": "node-z", "timestamp": "2024-01-01T00:07:00Z", "payload": {"z": 2, "a": "first"}},
        {"server_id": "node-z", "timestamp": "2024-01-01T00:20:00Z", "payload": {"a": "first", "z": 2}},
        {"server_id": "node-a", "timestamp": "2024-01-01T01:02:00Z", "payload": {"mode": "alpha", "items": [3, 1]}},
        {"server_id": "node-z", "timestamp": "2024-01-01T01:41:00Z", "payload": {"a": "second", "nested": {"q": True}}},
        {"server_id": "node-a", "timestamp": "2024-01-01T03:29:59Z", "payload": {"items": [3, 1], "mode": "alpha"}},
        {"server_id": "node-a", "timestamp": "2024-01-01T04:00:00Z", "payload": {"mode": "beta", "n": 17}},
    ]
    with tempfile.TemporaryDirectory() as input_dir:
        # Deliberately make filenames and insertion order unrelated to chronology.
        for i, record in enumerate(reversed(records)):
            write_json(os.path.join(input_dir, f"sample_{i * 7 + 3}.json"), record)
        result = subprocess.run(["python3", ETL, input_dir, TIMELINE], capture_output=True, text=True, timeout=60)
        assert result.returncode == 0, f"etl.py failed: stdout={result.stdout!r} stderr={result.stderr!r}"
        assert os.path.isfile(TIMELINE), "etl.py did not create timeline.csv"
        with open(TIMELINE, newline="") as f:
            rows = list(csv.reader(f))
        assert rows and rows[0] == ["bucket_start", "server_id", "config_hash"], "Invalid CSV header"
        expected = expected_timeline(records)
        assert rows[1:] == expected, "ETL output is incorrect for generated records"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
