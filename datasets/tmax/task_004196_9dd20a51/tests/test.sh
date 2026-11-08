#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import importlib.metadata
import secrets
import subprocess
import random
import re

import pytest
import requests

BASE_URL = "http://127.0.0.1:9090"
ENDPOINT = f"{BASE_URL}/etl/process"
API_KEY = "etl-secret-key-998"

ORIGINAL_ROWS = [
    ["101", "2023-11-20T08:15:00Z", "   Hello   World  "],
    ["102", "2023-11-20T08:45:00Z", " FIRST   TRY"],
    ["101", "2023-11-20T09:05:00Z", " Hello World Updated"],
    ["103", "2023-11-20T09:10:00Z", "   New   Line \n \t Test  "],
    ["102", "2023-11-20T08:45:00Z", " FIRST   TRY"],
]

EXPECTED_RESPONSE = {
    "2023-11-20T08": [
        {
            "record_id": "102",
            "event_time": "2023-11-20T08:45:00Z",
            "message": "first try",
        }
    ],
    "2023-11-20T09": [
        {
            "record_id": "101",
            "event_time": "2023-11-20T09:05:00Z",
            "message": "hello world updated",
        },
        {
            "record_id": "103",
            "event_time": "2023-11-20T09:10:00Z",
            "message": "new line test",
        },
    ],
}


def make_csv(rows):
    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(["record_id", "event_time", "message"])
    writer.writerows(rows)
    return output.getvalue()


CSV_PAYLOAD = make_csv(ORIGINAL_ROWS)


def sort_bucket(bucket):
    return sorted(bucket, key=lambda x: x["record_id"])


def normalize_result(data):
    assert isinstance(data, dict)
    return {key: sort_bucket(value) for key, value in data.items()}


def expected_for(rows):
    deduplicated = {}
    for record_id, event_time, message in rows:
        previous = deduplicated.get(record_id)
        if previous is None or event_time > previous["event_time"]:
            deduplicated[record_id] = {
                "record_id": record_id,
                "event_time": event_time,
                "message": re.sub(r"\s+", " ", message.lower()).strip(),
            }

    buckets = {}
    for record in deduplicated.values():
        buckets.setdefault(record["event_time"][:13], []).append(record)
    return buckets


def post_csv(payload, charset, key=API_KEY):
    headers = {
        "X-API-Key": key,
        "Content-Type": f"text/csv; charset={charset}",
    }
    return requests.post(ENDPOINT, data=payload.encode(charset), headers=headers, timeout=5)


def assert_success(response, expected):
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    assert response.headers.get("Content-Type", "").split(";", 1)[0].lower() == "application/json"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")
    assert normalize_result(data) == normalize_result(expected), (
        f"Response JSON does not match expected output.\n"
        f"Expected: {normalize_result(expected)}\nActual: {normalize_result(data)}"
    )


def test_vendored_package_is_fixed_installed_and_functional():
    result = subprocess.run(
        ["python3", "setup.py", "--name"],
        cwd="/app/vendor/csv-time-bucketer-1.2.0",
        text=True,
        capture_output=True,
        timeout=20,
    )
    assert result.returncode == 0, f"Vendored setup.py remains broken: {result.stderr}"
    assert result.stdout.strip().splitlines()[-1] == "csv-time-bucketer"
    assert importlib.metadata.version("csv-time-bucketer") == "1.2.0"

    from csv_time_bucketer import bucket_by_hour

    records = [
        {"record_id": "a", "event_time": "2041-02-03T04:05:06Z", "message": "x"},
        {"record_id": "b", "event_time": "2041-02-03T05:06:07Z", "message": "y"},
        {"record_id": "c", "event_time": "2041-02-03T04:59:59Z", "message": "z"},
    ]
    assert bucket_by_hour(records, "event_time") == {
        "2041-02-03T04": [records[0], records[2]],
        "2041-02-03T05": [records[1]],
    }


def test_missing_auth():
    try:
        response = requests.post(
            ENDPOINT,
            data=CSV_PAYLOAD.encode("utf-16le"),
            headers={"Content-Type": "text/csv; charset=utf-16le"},
            timeout=5,
        )
    except requests.exceptions.ConnectionError:
        pytest.fail("Server is not running or not listening on 127.0.0.1:9090")
    assert response.status_code == 401, (
        f"Expected 401 Unauthorized for missing API key, got {response.status_code}"
    )


def test_incorrect_auth():
    response = post_csv(CSV_PAYLOAD, "utf-16le", key="wrong-key")
    assert response.status_code == 401, (
        f"Expected 401 Unauthorized for incorrect API key, got {response.status_code}"
    )


def test_original_successful_processing_with_valid_multiline_csv():
    assert_success(post_csv(CSV_PAYLOAD, "utf-16le"), EXPECTED_RESPONSE)


def test_runtime_generated_payload_in_multiple_encodings():
    rng = random.SystemRandom()
    token = secrets.token_hex(8)
    month = rng.randint(1, 11)
    day = rng.randint(1, 20)
    ids = [f"{token}-{suffix}" for suffix in ("a", "b", "c", "d", "e")]

    rows = [
        [ids[0], f"2025-{month:02d}-{day:02d}T03:11:12Z", " OLD VALUE"],
        [ids[0], f"2025-{month:02d}-{day + 1:02d}T17:21:22Z", f"  Latest\t{token.upper()}  Value "],
        [ids[1], f"2025-{month:02d}-{day:02d}T08:01:02Z", " RETRIED OLD"],
        [ids[1], f"2025-{month:02d}-{day:02d}T19:01:03Z", "  CAFÉ   DéJÀ, Vu  "],
        [ids[2], f"2025-{month:02d}-{day:02d}T08:44:55Z", " one\n\t two   three "],
        [ids[3], f"2025-{month:02d}-{day + 1:02d}T00:00:01Z", "  Quoted, Message  "],
        [ids[4], f"2025-{month:02d}-{day:02d}T23:59:59Z", f" Unique {token} "],
        [ids[2], f"2025-{month:02d}-{day:02d}T08:44:55Z", " one\n\t two   three "],
    ]
    rng.shuffle(rows)
    payload = make_csv(rows)
    expected = expected_for(rows)

    assert_success(post_csv(payload, "iso-8859-1"), expected)
    assert_success(post_csv(payload, "utf-16le"), expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
