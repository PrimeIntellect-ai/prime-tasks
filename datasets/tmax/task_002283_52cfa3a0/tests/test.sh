#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import copy
import secrets
import subprocess
from collections import defaultdict

SCRIPT_PATH = "/home/user/process_feedback.py"
INPUT_PATH = "/home/user/raw_feedback.jsonl"
ANON_PATH = "/home/user/processed/anonymized_feedback.jsonl"
SUMMARY_PATH = "/home/user/processed/hourly_lang_summary.csv"
LOG_PATH = "/home/user/logs/pipeline.log"


def get_expected_data():
    assert os.path.exists(INPUT_PATH), f"Input file {INPUT_PATH} is missing."

    valid_records = []
    dropped_count = 0

    with open(INPUT_PATH, "r") as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)

            # Validation Checkpoint
            if not record.get("timestamp") or not record.get("text") or not record.get("lang"):
                dropped_count += 1
                continue

            # Masking
            if "user_email" in record and record["user_email"]:
                email = record["user_email"]
                if "@" in email:
                    local, domain = email.split("@", 1)
                    if local:
                        record["user_email"] = f"{local[0]}***@{domain}"

            if "ip_address" in record and record["ip_address"]:
                record["ip_address"] = "[IP_REDACTED]"

            valid_records.append(record)

    # Bucketing
    buckets = defaultdict(int)
    for r in valid_records:
        ts = r["timestamp"]
        hour_bucket = ts[:14] + "00:00Z"
        lang = r["lang"]
        buckets[(hour_bucket, lang)] += 1

    return valid_records, dropped_count, buckets


def read_anonymized():
    actual_records = []
    with open(ANON_PATH, "r") as f:
        for line in f:
            if line.strip():
                actual_records.append(json.loads(line))
    return actual_records


def read_summary():
    with open(SUMMARY_PATH, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, "CSV file is empty (missing header)."
        assert set(header) == {"hour_bucket", "lang", "feedback_count"}, \
            f"CSV header incorrect. Expected {{'hour_bucket', 'lang', 'feedback_count'}}, got {set(header)}"
        assert len(header) == 3, f"CSV must have exactly three columns, got {header}"

        hb_idx = header.index("hour_bucket")
        lang_idx = header.index("lang")
        count_idx = header.index("feedback_count")
        actual_buckets = {}
        for row in reader:
            if not row:
                continue
            assert len(row) == 3, f"CSV row must have exactly three columns: {row}"
            actual_buckets[(row[hb_idx], row[lang_idx])] = int(row[count_idx])
    return actual_buckets


def test_process_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing or is not a regular file."
    assert os.path.getsize(SCRIPT_PATH) > 0, f"Required script {SCRIPT_PATH} is empty."


def test_anonymized_feedback():
    expected_records, _, _ = get_expected_data()

    assert os.path.exists(ANON_PATH), f"Output file {ANON_PATH} is missing."
    actual_records = read_anonymized()

    assert len(actual_records) == len(expected_records), \
        f"Expected {len(expected_records)} anonymized records, but found {len(actual_records)}."

    expected_dict = {r["id"]: r for r in expected_records}
    actual_dict = {r["id"]: r for r in actual_records}

    for rid, expected_r in expected_dict.items():
        assert rid in actual_dict, f"Record with id {rid} is missing from output."
        actual_r = actual_dict[rid]

        assert actual_r.get("user_email") == expected_r.get("user_email"), \
            f"Email masking failed for id {rid}. Expected {expected_r.get('user_email')}, got {actual_r.get('user_email')}"

        assert actual_r.get("ip_address") == expected_r.get("ip_address"), \
            f"IP masking failed for id {rid}. Expected {expected_r.get('ip_address')}, got {actual_r.get('ip_address')}"

        assert actual_r == expected_r, \
            f"Record {rid} was not otherwise preserved. Expected {expected_r}, got {actual_r}"

    assert actual_dict == expected_dict, \
        f"Anonymized output records do not exactly match expected records."


def test_hourly_lang_summary():
    _, _, expected_buckets = get_expected_data()

    assert os.path.exists(SUMMARY_PATH), f"Output file {SUMMARY_PATH} is missing."
    actual_buckets = read_summary()

    assert actual_buckets == expected_buckets, \
        f"Aggregated buckets do not match expected. Expected {expected_buckets}, got {actual_buckets}"


def test_pipeline_logs():
    expected_records, dropped_count, _ = get_expected_data()

    assert os.path.exists(LOG_PATH), f"Log file {LOG_PATH} is missing."

    with open(LOG_PATH, "r") as f:
        log_content = f.read()

    expected_phrases = [
        "INFO: Pipeline started",
        f"WARNING: Dropped {dropped_count} records due to validation failures",
        f"INFO: Anonymized {len(expected_records)} valid records",
        "INFO: Pipeline complete"
    ]

    for phrase in expected_phrases:
        assert phrase in log_content, f"Expected log phrase '{phrase}' not found in pipeline.log"


def test_script_processes_fresh_unpredictable_input():
    token = secrets.token_hex(8)
    records = [
        {
            "id": f"{token}-a",
            "timestamp": "2024-07-08T03:17:41Z",
            "user_email": f"alpha.{token}@example.test",
            "ip_address": "203.0.113.10",
            "text": f"Preserve this text {token}",
            "lang": "de",
            "source": {"batch": token, "rank": 1}
        },
        {
            "id": f"{token}-b",
            "timestamp": "2024-07-08T03:59:59Z",
            "user_email": f"b{token}@domain.test",
            "text": f"Second feedback {token}",
            "lang": "de",
            "priority": 7
        },
        {
            "id": f"{token}-c",
            "timestamp": "2024-07-08T04:00:01Z",
            "ip_address": "198.51.100.23",
            "text": f"Troisième {token}",
            "lang": "fr",
            "tags": ["fresh", token]
        },
        {
            "id": f"{token}-d",
            "timestamp": "2024-07-09T18:45:00Z",
            "user_email": f"z{token}@mail.test",
            "ip_address": "192.0.2.44",
            "text": f"Another entry {token}",
            "lang": "en"
        },
        {
            "id": f"{token}-bad-lang",
            "timestamp": "2024-07-09T18:50:00Z",
            "text": "drop me",
            "lang": ""
        },
        {
            "id": f"{token}-bad-time",
            "timestamp": None,
            "text": "drop me too",
            "lang": "es"
        },
        {
            "id": f"{token}-bad-text",
            "timestamp": "2024-07-09T19:00:00Z",
            "text": "",
            "lang": "it"
        }
    ]

    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()

    try:
        with open(INPUT_PATH, "w") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")

        for path in (ANON_PATH, SUMMARY_PATH, LOG_PATH):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass

        result = subprocess.run(["python3", SCRIPT_PATH], capture_output=True, text=True)
        assert result.returncode == 0, \
            f"Script failed on fresh input. stdout={result.stdout!r}, stderr={result.stderr!r}"

        expected_records, dropped_count, expected_buckets = get_expected_data()
        assert os.path.exists(ANON_PATH), "Script did not create anonymized output on fresh input."
        assert os.path.exists(SUMMARY_PATH), "Script did not create summary output on fresh input."
        assert os.path.exists(LOG_PATH), "Script did not create its log on fresh input."

        actual_records = read_anonymized()
        expected_dict = {r["id"]: r for r in expected_records}
        actual_dict = {r["id"]: r for r in actual_records}
        assert actual_dict == expected_dict, \
            f"Fresh anonymized records differ. Expected {expected_dict}, got {actual_dict}"
        assert read_summary() == expected_buckets

        with open(LOG_PATH, "r") as f:
            log_content = f.read()
        for phrase in (
            "INFO: Pipeline started",
            f"WARNING: Dropped {dropped_count} records due to validation failures",
            f"INFO: Anonymized {len(expected_records)} valid records",
            "INFO: Pipeline complete"
        ):
            assert phrase in log_content, f"Fresh run is missing log phrase {phrase!r}"
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        for path in (ANON_PATH, SUMMARY_PATH, LOG_PATH):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        subprocess.run(["python3", SCRIPT_PATH], capture_output=True, text=True)
TEST_EOF

passed=0
if [ -f /home/user/process_feedback.py ]; then
    rm -f /home/user/processed/anonymized_feedback.jsonl \
          /home/user/processed/hourly_lang_summary.csv \
          /home/user/logs/pipeline.log
    if python3 /home/user/process_feedback.py; then
        if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
            passed=1
        fi
    fi
fi

echo "$passed" > /logs/verifier/reward.txt
