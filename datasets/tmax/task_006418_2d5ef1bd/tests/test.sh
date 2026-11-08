#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

OUTPUT_PATH = '/home/user/clean_logs.jsonl'

@pytest.fixture
def clean_logs():
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    assert os.path.isfile(OUTPUT_PATH), f"Path {OUTPUT_PATH} is not a file."

    data = []
    with open(OUTPUT_PATH, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                data.append(json.loads(line))
            except json.JSONDecodeError as e:
                pytest.fail(f"Could not parse line {line_num} as JSON: {e}")
    return data

def test_record_count(clean_logs):
    assert len(clean_logs) == 7, f"Expected exactly 7 records, got {len(clean_logs)}"

def test_chronological_sorting(clean_logs):
    timestamps = [record.get("ts") for record in clean_logs]
    assert all(timestamps[i] <= timestamps[i+1] for i in range(len(timestamps)-1)), "Records are not sorted chronologically by 'ts'."

def test_expected_data_content(clean_logs):
    expected_data = [
        {"ts": "2023-05-12T14:00:00Z", "user_id": "u1", "message": "hello from ***@***.***"},
        {"ts": "2023-05-12T14:01:00Z", "user_id": "u2", "message": "testing \ud83d\ude00"},
        {"ts": "2023-05-12T14:02:00Z", "user_id": "unknown", "message": "imputed"},
        {"ts": "2023-05-12T14:03:00Z", "user_id": "u3", "message": "reach out to ***@***.***."},
        {"ts": "2023-05-12T14:04:00Z", "user_id": "unknown", "message": "imputed"},
        {"ts": "2023-05-12T14:05:00Z", "user_id": "u1", "message": "skip ahead"},
        {"ts": "2023-05-12T14:06:00Z", "user_id": "u4", "message": "bad escape  here"}
    ]

    assert len(clean_logs) == len(expected_data), f"Expected {len(expected_data)} records, got {len(clean_logs)}"

    for i, (actual, expected) in enumerate(zip(clean_logs, expected_data)):
        assert actual.get("ts") == expected["ts"], f"Record {i} timestamp mismatch. Expected {expected['ts']}, got {actual.get('ts')}"
        assert actual.get("user_id") == expected["user_id"], f"Record {i} user_id mismatch. Expected {expected['user_id']}, got {actual.get('user_id')}"
        assert actual.get("message") == expected["message"], f"Record {i} message mismatch. Expected {expected['message']}, got {actual.get('message')}"
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_etl.py
import json
import os
import random
import re
import string
import subprocess
from datetime import datetime, timedelta, timezone

SCRIPT = '/home/user/process_etl.py'
RAW = '/home/user/raw_chat_logs.jsonl'
OUTPUT = '/home/user/clean_logs.jsonl'

assert os.path.isfile(SCRIPT), f"Required ETL script {SCRIPT} does not exist or is not a file"

rng = random.SystemRandom()
token = ''.join(rng.choice(string.ascii_lowercase) for _ in range(12))
base = datetime(2024, rng.randint(1, 11), rng.randint(1, 25), rng.randint(1, 20), rng.randint(0, 50), tzinfo=timezone.utc)
email1 = f"Person.{token}+tag@Sub-{token}.example"
email2 = f"HELP-{token}@service.test"

records = {
    0: {
        "ts": base.strftime('%Y-%m-%dT%H:%M:%SZ'),
        "user_id": f"start-{token}",
        "message": f"  MIXED INVALIDMARK Contact {email1}  ",
    },
    2: {
        "ts": int((base + timedelta(minutes=2)).timestamp()),
        "user_id": f"epoch-{token}",
        "message": f"  SECOND {email2}! ",
    },
    5: {
        "ts": (base + timedelta(minutes=5)).strftime('%m/%d/%Y %H:%M:%S'),
        "user_id": f"us-{token}",
        "message": "  Final Plain MESSAGE  ",
    },
}

# Emit the records out of order. The first line contains a literal malformed
# JSON unicode escape, not an already-decoded Python string.
line0 = json.dumps(records[0], ensure_ascii=False).replace('INVALIDMARK', r'\u12GZ')
input_lines = [json.dumps(records[5]), line0, json.dumps(records[2])]

email_re = re.compile(r'[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}')
def normalize(message):
    return email_re.sub('***@***.***', message).lower().strip()

expected = []
for offset in range(6):
    instant = base + timedelta(minutes=offset)
    ts = instant.strftime('%Y-%m-%dT%H:%M:%SZ')
    if offset not in records:
        expected.append({"ts": ts, "user_id": "unknown", "message": "imputed"})
        continue
    message = records[offset]["message"]
    if offset == 0:
        message = message.replace('INVALIDMARK', '')
    expected.append({
        "ts": ts,
        "user_id": records[offset]["user_id"],
        "message": normalize(message),
    })

raw_backup = open(RAW, 'rb').read()
output_existed = os.path.exists(OUTPUT)
output_backup = open(OUTPUT, 'rb').read() if output_existed else None
try:
    with open(RAW, 'w', encoding='utf-8', newline='\n') as f:
        f.write('\n'.join(input_lines) + '\n')

    result = subprocess.run(
        ['python3', SCRIPT],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"ETL script failed on varied input with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(OUTPUT), f"ETL script did not create {OUTPUT}"

    actual = []
    with open(OUTPUT, 'r', encoding='utf-8') as f:
        for line_num, line in enumerate(f, 1):
            if not line.strip():
                continue
            try:
                actual.append(json.loads(line))
            except json.JSONDecodeError as exc:
                raise AssertionError(f"Dynamic output line {line_num} is invalid JSON: {exc}")

    assert actual == expected, f"ETL output for varied input was incorrect.\nExpected: {expected!r}\nActual: {actual!r}"
finally:
    with open(RAW, 'wb') as f:
        f.write(raw_backup)
    if output_existed:
        with open(OUTPUT, 'wb') as f:
            f.write(output_backup)
    elif os.path.exists(OUTPUT):
        os.remove(OUTPUT)
DYNAMIC_EOF

if [ -f /home/user/process_etl.py ] \
   && python3 /home/user/process_etl.py \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 \
   && python3 /tmp/test_dynamic_etl.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
