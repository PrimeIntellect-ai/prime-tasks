#!/bin/bash
set +e
mkdir -p /logs/verifier

/start_services.sh >/dev/null 2>&1 || true

if pgrep -f '/home/user/worker.py' >/dev/null 2>&1; then
    export WORKER_WAS_RUNNING=1
else
    export WORKER_WAS_RUNNING=0
fi

pkill -f '/home/user/worker.py' >/dev/null 2>&1 || true
sleep 1
redis-cli DEL data_queue >/dev/null 2>&1 || true
rm -f /home/user/processed_logs.csv

nohup python3 /home/user/worker.py >/tmp/verifier_worker.log 2>&1 &
export WORKER_PID=$!
sleep 2

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sys
import json
import csv
import time
import random
import urllib.request
import pytest
import importlib.util

CSV_FILE = "/home/user/processed_logs.csv"
SANITIZER_PATH = "/home/user/sanitizer.py"
WORKER_PATH = "/home/user/worker.py"

seed = random.SystemRandom().randint(1000000, 9000000)
CLEAN_RECORDS = [
    {"user_id": seed, "email": "alice.smith@company.com", "ssn": "123-45-6789", "age": 31, "event_type": "login_success"},
    {"user_id": seed + 1, "email": "bob@example.org", "ssn": "987-65-4321", "age": 0, "event_type": "EVENT_2"},
    {"user_id": seed + 2, "email": "carol@sub.example.net", "ssn": "111-22-3333", "age": 120, "event_type": "purchase"},
]
CLEAN_LINES = [json.dumps(record, separators=(",", ":")).encode("utf-8") for record in CLEAN_RECORDS]

EVIL_LINES = [
    b'{not valid json',
    b'{"user_id":1,"email":"x@example.com","ssn":"1","age":20,"event_type":"bad\\u12G4"}',
    b'\xff\xfe\xfd',
    json.dumps({"user_id": seed + 10, "email": "x@example.com", "ssn": "1", "age": -1, "event_type": "login"}).encode(),
    json.dumps({"user_id": seed + 11, "email": "x@example.com", "ssn": "1", "age": 121, "event_type": "login"}).encode(),
    json.dumps({"user_id": seed + 12, "email": "x@example.com", "ssn": "1", "age": 20, "event_type": "drop-table"}).encode(),
    json.dumps({"user_id": seed + 13, "email": "x@example.com", "ssn": "1", "age": 20, "event_type": ""}).encode(),
]

for missing_key in ["user_id", "email", "ssn", "age", "event_type"]:
    record = {"user_id": seed + 20, "email": "x@example.com", "ssn": "1", "age": 20, "event_type": "login"}
    del record[missing_key]
    EVIL_LINES.append(json.dumps(record).encode())

for key, bad_value in [
    ("user_id", "7"),
    ("user_id", True),
    ("email", 42),
    ("ssn", 123456789),
    ("age", "20"),
    ("age", True),
    ("event_type", 42),
]:
    record = {"user_id": seed + 30, "email": "x@example.com", "ssn": "1", "age": 20, "event_type": "login"}
    record[key] = bad_value
    EVIL_LINES.append(json.dumps(record).encode())


def load_sanitizer():
    assert os.path.isfile(SANITIZER_PATH), f"{SANITIZER_PATH} does not exist or is not a regular file."
    spec = importlib.util.spec_from_file_location("sanitizer", SANITIZER_PATH)
    sanitizer = importlib.util.module_from_spec(spec)
    sys.modules["sanitizer"] = sanitizer
    spec.loader.exec_module(sanitizer)
    assert hasattr(sanitizer, "process_and_sanitize"), "process_and_sanitize function missing."
    assert callable(sanitizer.process_and_sanitize), "process_and_sanitize is not callable."
    return sanitizer.process_and_sanitize


def test_required_artifacts_and_running_worker():
    assert os.path.isfile(WORKER_PATH), f"{WORKER_PATH} does not exist or is not a regular file."
    assert os.environ.get("WORKER_WAS_RUNNING") == "1", "The worker was not left running by the agent."
    pid = int(os.environ["WORKER_PID"])
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail("worker.py exited when executed by the verifier. Output:\n" + _worker_output())


def _worker_output():
    try:
        with open("/tmp/verifier_worker.log", "r", errors="replace") as f:
            return f.read()
    except OSError:
        return "(worker output unavailable)"


def test_sanitizer_logic():
    process_and_sanitize = load_sanitizer()

    clean_failed = []
    for i, line in enumerate(CLEAN_LINES):
        result = process_and_sanitize(line)
        if result is None:
            clean_failed.append(f"Line {i+1}")
        else:
            assert isinstance(result, dict), f"Clean line {i+1} did not return a dictionary"
            assert result.get("ssn") == "XXX-XX-XXXX", f"SSN not masked properly in clean line {i+1}"
            email = result.get("email", "")
            assert email.startswith("hidden@"), f"Email not masked properly in clean line {i+1}"
            expected = dict(CLEAN_RECORDS[i])
            expected["ssn"] = "XXX-XX-XXXX"
            expected["email"] = "hidden@" + CLEAN_RECORDS[i]["email"].split("@", 1)[1]
            assert result == expected, f"Clean line {i+1} was not normalized correctly: {result}"

    evil_failed = []
    for i, line in enumerate(EVIL_LINES):
        try:
            result = process_and_sanitize(line)
        except Exception as exc:
            pytest.fail(f"Sanitizer raised {type(exc).__name__} for invalid line {i+1}; it must return None")
        if result is not None:
            evil_failed.append(f"Line {i+1}")

    errors = []
    if clean_failed:
        errors.append(f"{len(clean_failed)} clean records rejected: {', '.join(clean_failed[:5])}")
    if evil_failed:
        errors.append(f"{len(evil_failed)} evil records bypassed: {', '.join(evil_failed[:5])}")
    assert not errors, "Sanitizer logic failed:\n" + "\n".join(errors)


def post_payload(payload):
    req = urllib.request.Request("http://127.0.0.1:8080/ingest", data=payload, method="POST")
    try:
        with urllib.request.urlopen(req, timeout=2) as response:
            assert response.status == 200
    except Exception as exc:
        pytest.fail(f"Failed to POST to ingestion API: {exc}")


def test_end_to_end_worker():
    for line in CLEAN_LINES + EVIL_LINES:
        post_payload(line)

    expected_by_id = {str(record["user_id"]): record for record in CLEAN_RECORDS}
    deadline = time.time() + 10
    rows = []
    fieldnames = None
    while time.time() < deadline:
        if os.path.exists(CSV_FILE):
            try:
                with open(CSV_FILE, "r", newline="") as f:
                    reader = csv.DictReader(f)
                    fieldnames = reader.fieldnames
                    rows = list(reader)
                if len(rows) >= len(CLEAN_LINES):
                    break
            except OSError:
                pass
        time.sleep(0.2)

    assert os.path.exists(CSV_FILE), f"CSV file {CSV_FILE} was not created by the worker."
    assert fieldnames == ["user_id", "email", "ssn", "age", "event_type"], "CSV headers are incorrect."
    assert len(rows) >= len(CLEAN_LINES), f"Expected at least {len(CLEAN_LINES)} rows in CSV, found {len(rows)}."

    for row in rows:
        assert row["ssn"] == "XXX-XX-XXXX", f"Row found with unmasked SSN: {row}"
        assert row["email"].startswith("hidden@"), f"Row found with unmasked email: {row}"

    assert len(rows) == len(CLEAN_LINES), f"Expected exactly {len(CLEAN_LINES)} accepted rows, found {len(rows)}; invalid payloads may have been written."
    assert set(row["user_id"] for row in rows) == set(expected_by_id), f"CSV contains missing or unexpected records: {rows}"
    for row in rows:
        source = expected_by_id[row["user_id"]]
        assert row == {
            "user_id": str(source["user_id"]),
            "email": "hidden@" + source["email"].split("@", 1)[1],
            "ssn": "XXX-XX-XXXX",
            "age": str(source["age"]),
            "event_type": source["event_type"],
        }, f"CSV row was not normalized correctly: {row}"

    pid = int(os.environ["WORKER_PID"])
    try:
        os.kill(pid, 0)
    except OSError:
        pytest.fail("Worker exited during end-to-end processing. Output:\n" + _worker_output())
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
