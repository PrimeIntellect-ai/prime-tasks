#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import hashlib

OUTPUT_DIR = "/home/user/output"
VALIDATION_TXT = os.path.join(OUTPUT_DIR, "validation.txt")
DAILY_CONFIGS_CSV = os.path.join(OUTPUT_DIR, "daily_configs.csv")

def test_validation_txt_exists_and_content():
    assert os.path.exists(VALIDATION_TXT), f"File {VALIDATION_TXT} is missing."
    with open(VALIDATION_TXT, 'r') as f:
        content = f.read().strip()
    expected_content = "Dropped count: 2"
    assert content == expected_content, f"Expected validation content '{expected_content}', but got '{content}'."

def test_daily_configs_csv_exists_and_content():
    assert os.path.exists(DAILY_CONFIGS_CSV), f"File {DAILY_CONFIGS_CSV} is missing."

    def compute_hash(configs):
        filtered = {k: v for k, v in configs.items() if v}
        sorted_keys = sorted(filtered.keys())
        formatted = "|".join(f"{k}:{filtered[k]}" for k in sorted_keys)
        return hashlib.sha256(formatted.encode('utf-8')).hexdigest()

    expected_rows = [
        {"date": "2023-10-01", "server_id": "srv1", "state_hash": compute_hash({"config_a": "v1", "config_b": "v2"})},
        {"date": "2023-10-01", "server_id": "srv2", "state_hash": compute_hash({"config_a": "on", "config_c": "yes"})},
        {"date": "2023-10-02", "server_id": "srv1", "state_hash": compute_hash({"config_b": "v2"})},
        {"date": "2023-10-02", "server_id": "srv1", "state_hash": compute_hash({"config_a": "v1", "config_c": "v3"})},
        {"date": "2023-10-02", "server_id": "srv2", "state_hash": compute_hash({"config_a": "on", "config_c": "yes"})},
        {"date": "2023-10-02", "server_id": "srv2", "state_hash": compute_hash({})},
    ]
    expected_rows.sort(key=lambda x: (x["date"], x["server_id"], x["state_hash"]))

    with open(DAILY_CONFIGS_CSV, 'r', newline='') as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)

    assert reader.fieldnames == ["date", "server_id", "state_hash"], \
        f"Expected CSV headers ['date', 'server_id', 'state_hash'], got {reader.fieldnames}"
    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows in {DAILY_CONFIGS_CSV}, but got {len(actual_rows)}."

    for i, (expected, actual) in enumerate(zip(expected_rows, actual_rows)):
        assert actual["date"] == expected["date"], f"Row {i+1}: Expected date {expected['date']}, got {actual['date']}."
        assert actual["server_id"] == expected["server_id"], f"Row {i+1}: Expected server_id {expected['server_id']}, got {actual['server_id']}."
        assert actual["state_hash"] == expected["state_hash"], f"Row {i+1}: Expected state_hash {expected['state_hash']}, got {actual['state_hash']}."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_configs.py
import csv
import hashlib
import json
import os
import subprocess
import uuid

INPUT_DIR = "/home/user/config_exports"
OUTPUT_DIR = "/home/user/output"
SCRIPT = "/home/user/process_configs.py"
token = uuid.uuid4().hex
csv_path = os.path.join(INPUT_DIR, f"challenge_{token}.csv")
json_path = os.path.join(INPUT_DIR, f"challenge_{token}.json")

csv_rows = [
    {"timestamp": "2041-07-08T01:02:03Z", "server_id": f"csv-{token}", "config_a": f"a-{token}", "config_b": f"b-{token}", "config_c": "", "description": "first line\nsecond line\nthird line"},
    {"timestamp": "2041-07-08T02:03:04Z", "server_id": f"csv-{token}", "config_a": f"a-{token}", "config_b": f"b-{token}", "config_c": "", "description": "duplicate state"},
    {"timestamp": "2041-07-08T03:04:05Z", "server_id": f"csv-{token}", "config_a": "", "config_b": "", "config_c": f"c-{token}", "description": "second state"},
    {"timestamp": "", "server_id": f"bad-{token}", "config_a": "x", "config_b": "y", "config_c": "z", "description": "must be dropped"},
]
json_rows = [
    {"timestamp": "2041-07-09T04:05:06Z", "server_id": f"json-{token}", "configs": {"config_a": f"ja-{token}", "config_b": "", "config_c": None}, "description": "json state"},
    {"timestamp": "2041-07-09T05:06:07Z", "server_id": f"empty-{token}", "configs": {}, "description": "empty state"},
    {"timestamp": "2041-07-09T06:07:08Z", "server_id": "", "configs": {"config_a": "invalid"}, "description": "must be dropped"},
]

def read_inputs():
    records = []
    for name in sorted(os.listdir(INPUT_DIR)):
        path = os.path.join(INPUT_DIR, name)
        if name.endswith(".csv"):
            with open(path, newline="", encoding="utf-8") as f:
                for row in csv.DictReader(f):
                    records.append({
                        "timestamp": row.get("timestamp"),
                        "server_id": row.get("server_id"),
                        "configs": {k: row.get(k) for k in ("config_a", "config_b", "config_c")},
                    })
        elif name.endswith(".json"):
            with open(path, encoding="utf-8") as f:
                data = json.load(f)
            for row in data:
                records.append({
                    "timestamp": row.get("timestamp"),
                    "server_id": row.get("server_id"),
                    "configs": row.get("configs") or {},
                })
    return records

def expected_result(records):
    dropped = 0
    unique = set()
    for record in records:
        timestamp = record.get("timestamp")
        server_id = record.get("server_id")
        if timestamp is None or timestamp == "" or server_id is None or server_id == "":
            dropped += 1
            continue
        configs = record.get("configs") or {}
        parts = []
        for key in sorted(("config_a", "config_b", "config_c")):
            value = configs.get(key)
            if value is not None and value != "":
                parts.append(f"{key}:{value}")
        state_hash = hashlib.sha256("|".join(parts).encode("utf-8")).hexdigest()
        unique.add((timestamp[:10], server_id, state_hash))
    return dropped, sorted(unique)

try:
    with open(csv_path, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["timestamp", "server_id", "config_a", "config_b", "config_c", "description"])
        writer.writeheader()
        writer.writerows(csv_rows)
    with open(json_path, "w", encoding="utf-8") as f:
        json.dump(json_rows, f)

    expected_dropped, expected_rows = expected_result(read_inputs())
    for output_name in ("validation.txt", "daily_configs.csv"):
        try:
            os.remove(os.path.join(OUTPUT_DIR, output_name))
        except FileNotFoundError:
            pass

    subprocess.run(["python3", SCRIPT], check=True, timeout=30)

    validation_path = os.path.join(OUTPUT_DIR, "validation.txt")
    assert os.path.isfile(validation_path), "validation.txt was not regenerated"
    with open(validation_path, encoding="utf-8") as f:
        assert f.read().strip() == f"Dropped count: {expected_dropped}"

    daily_path = os.path.join(OUTPUT_DIR, "daily_configs.csv")
    assert os.path.isfile(daily_path), "daily_configs.csv was not regenerated"
    with open(daily_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        actual = list(reader)
        assert reader.fieldnames == ["date", "server_id", "state_hash"]
    actual_rows = [(r["date"], r["server_id"], r["state_hash"]) for r in actual]
    assert actual_rows == expected_rows, f"Dynamic ingestion result mismatch: expected {expected_rows}, got {actual_rows}"
finally:
    for path in (csv_path, json_path):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
DYNAMIC_EOF

if test -f /home/user/process_configs.py \
   && python3 -m py_compile /home/user/process_configs.py \
   && rm -f /home/user/output/validation.txt /home/user/output/daily_configs.csv \
   && python3 /home/user/process_configs.py \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short \
   && python3 /tmp/test_dynamic_configs.py; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
