#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import subprocess
import time
from datetime import datetime, timedelta, timezone

import pytest

CSV_PATH = "/home/user/data/configs.csv"
JSON_PATH = "/home/user/data/configs.json"
SCRIPT_PATH = "/home/user/process.py"
OUTPUT_PATH = "/home/user/output/aggregated.json"
THRESHOLD = 5.0


def compute_hash(config_val: str) -> str:
    h = 0x5A5A5A5A
    for c in config_val:
        h = ((h * 33) ^ ord(c)) & 0xFFFFFFFF
    return f"{h:08x}"


def generate_golden_output():
    records = []

    assert os.path.isfile(CSV_PATH), f"Input file {CSV_PATH} does not exist or is not a regular file."
    with open(CSV_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            dt = datetime.strptime(row["timestamp"], "%Y-%m-%d %H:%M:%S").replace(tzinfo=timezone.utc)
            records.append({
                "timestamp": dt,
                "server": row["server_id"],
                "val": row["config_val"]
            })

    assert os.path.isfile(JSON_PATH), f"Input file {JSON_PATH} does not exist or is not a regular file."
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)
        assert isinstance(data, list), "JSON input must be an array."
        for item in data:
            dt = datetime.fromtimestamp(item["time"], tz=timezone.utc)
            records.append({
                "timestamp": dt,
                "server": item["server"],
                "val": item["val"]
            })

    records.sort(key=lambda x: x["timestamp"])

    buckets = {}
    for r in records:
        bucket_dt = r["timestamp"].replace(minute=0, second=0, microsecond=0)
        bucket_str = bucket_dt.strftime("%Y-%m-%dT%H:%M:%SZ")

        if bucket_str not in buckets:
            buckets[bucket_str] = {}

        dedup_key = (r["server"], r["val"])
        if dedup_key not in buckets[bucket_str]:
            buckets[bucket_str][dedup_key] = r["val"]

    aggregated = {}
    for bucket_str, items in buckets.items():
        hashes = [compute_hash(val) for val in items.values()]
        aggregated[bucket_str] = sorted(hashes)

    return aggregated


def load_output():
    assert os.path.isfile(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output file is not valid JSON.")


def run_pipeline():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist or is not a regular file."
    start_time = time.perf_counter()
    try:
        result = subprocess.run(
            ["python3", SCRIPT_PATH],
            capture_output=True,
            text=True,
            timeout=THRESHOLD + 1.0
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Performance check failed: execution exceeded {THRESHOLD:.1f} seconds.")
    execution_time = time.perf_counter() - start_time

    assert result.returncode == 0, f"Script failed to execute. Stderr: {result.stderr}"
    assert execution_time <= THRESHOLD, (
        f"Performance check failed: Execution took {execution_time:.2f} seconds, "
        f"which exceeds the maximum allowed time of {THRESHOLD} seconds. "
        "Make sure to reverse-engineer the hashing binary and implement it natively in Python."
    )


def test_output_correctness():
    student_output = load_output()
    golden_output = generate_golden_output()
    assert student_output == golden_output, "The aggregated JSON output does not match the expected golden output."


def test_performance():
    run_pipeline()


def test_pipeline_on_verifier_generated_inputs():
    # Exercise the submitted pipeline on a fresh, full-sized dataset so deleting,
    # replacing, or precomputing the original inputs cannot satisfy the verifier.
    original_csv = open(CSV_PATH, "rb").read()
    original_json = open(JSON_PATH, "rb").read()
    original_output = open(OUTPUT_PATH, "rb").read() if os.path.isfile(OUTPUT_PATH) else None

    rng = random.Random(secrets.randbits(128))
    nonce = secrets.token_hex(8)
    start = datetime(2024, 2, 1, tzinfo=timezone.utc)
    csv_rows = []
    json_rows = []

    # Unique values make per-record subprocess hashing too slow, while inserted
    # duplicates also verify bucket-local server/value deduplication.
    previous_csv = None
    previous_json = None
    for i in range(25000):
        offset = rng.randrange(5 * 86400)
        dt = start + timedelta(seconds=offset)
        server = f"server_{rng.randrange(1, 18)}"
        val = f"config_{nonce}_csv_{i}_{rng.randrange(1 << 30)}"
        if i % 19 == 18 and previous_csv is not None:
            prev_dt, server, val = previous_csv
            dt = prev_dt.replace(minute=min(prev_dt.minute + 1, 59), second=prev_dt.second)
        else:
            previous_csv = (dt, server, val)
        csv_rows.append([dt.strftime("%Y-%m-%d %H:%M:%S"), server, val])

        offset2 = rng.randrange(5 * 86400)
        dt2 = start + timedelta(seconds=offset2)
        server2 = f"server_{rng.randrange(1, 18)}"
        val2 = f"config_{nonce}_json_{i}_{rng.randrange(1 << 30)}"
        if i % 23 == 22 and previous_json is not None:
            prev_dt2, server2, val2 = previous_json
            dt2 = prev_dt2.replace(minute=min(prev_dt2.minute + 1, 59), second=prev_dt2.second)
        else:
            previous_json = (dt2, server2, val2)
        json_rows.append({"time": int(dt2.timestamp()), "server": server2, "val": val2})

    try:
        with open(CSV_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "server_id", "config_val"])
            writer.writerows(csv_rows)
        with open(JSON_PATH, "w", encoding="utf-8") as f:
            json.dump(json_rows, f)

        expected = generate_golden_output()
        run_pipeline()
        actual = load_output()
        assert actual == expected, "Pipeline output is incorrect for verifier-generated inputs."
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        with open(JSON_PATH, "wb") as f:
            f.write(original_json)
        if original_output is None:
            try:
                os.remove(OUTPUT_PATH)
            except FileNotFoundError:
                pass
        else:
            os.makedirs(os.path.dirname(OUTPUT_PATH), exist_ok=True)
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
