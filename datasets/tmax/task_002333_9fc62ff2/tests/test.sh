#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess
import tempfile

import pandas as pd
import pytest

SCRIPT_PATH = "/home/user/etl_pipeline.py"
OUTPUT_PARQUET = "/home/user/output.parquet"
DATA_DIR = "/home/user/data"
EXPECTED_COLUMNS = ["user_id", "name", "email", "phone", "timestamp"]


def run_pipeline(input_file, output_file):
    """Run the submitted ETL pipeline."""
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    result = subprocess.run(
        ["python3", SCRIPT_PATH, input_file, output_file],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Pipeline execution failed for {input_file}.\n"
        f"STDERR: {result.stderr}\nSTDOUT: {result.stdout}"
    )


def get_parquet_data(file_path):
    """Read Parquet data through a subprocess."""
    assert os.path.isfile(file_path), f"Output file {file_path} was not created."
    code = f'''
import pandas as pd
import json
import sys
try:
    df = pd.read_parquet({file_path!r})
    for col in df.columns:
        if pd.api.types.is_datetime64_any_dtype(df[col]):
            df[col] = df[col].dt.strftime("%Y-%m-%dT%H:%M:%SZ")
    print(df.to_json(orient="records"))
except Exception as e:
    print(json.dumps({{"error": str(e)}}))
    sys.exit(1)
'''
    result = subprocess.run(["python3", "-c", code], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"Failed to read parquet file {file_path}.\nSTDERR: {result.stderr}"
    )
    data = json.loads(result.stdout)
    if isinstance(data, dict) and "error" in data:
        pytest.fail(f"Error reading parquet file: {data['error']}")
    return data


@pytest.fixture(scope="module")
def processed_data():
    """Run the pipeline on all provided batches and return consolidated data."""
    if os.path.exists(OUTPUT_PARQUET):
        os.remove(OUTPUT_PARQUET)

    run_pipeline(os.path.join(DATA_DIR, "batch1.jsonl"), OUTPUT_PARQUET)
    run_pipeline(os.path.join(DATA_DIR, "batch2.csv"), OUTPUT_PARQUET)
    run_pipeline(os.path.join(DATA_DIR, "batch3_retry.jsonl"), OUTPUT_PARQUET)

    records = get_parquet_data(OUTPUT_PARQUET)
    return {str(r.get("user_id")): r for r in records}


def test_pipeline_creates_output_file(processed_data):
    assert os.path.isfile(OUTPUT_PARQUET), f"Output file {OUTPUT_PARQUET} is missing."


def test_deduplication_and_row_count(processed_data):
    assert len(processed_data) == 4, (
        f"Expected exactly 4 unique users after deduplication, got {len(processed_data)}."
    )
    expected_user_ids = {"1", "2", "3", "4"}
    assert set(processed_data.keys()) == expected_user_ids, (
        f"Expected user IDs {expected_user_ids}, got {set(processed_data.keys())}."
    )


def test_user1_masking(processed_data):
    user = processed_data.get("1")
    assert user is not None, "User 1 is missing from the output."
    assert user.get("email") == "***@example.com", f"User 1 email not masked correctly. Got: {user.get('email')}"
    assert user.get("phone") == "123-456-XXXX", f"User 1 phone not masked correctly. Got: {user.get('phone')}"


def test_user2_update_and_masking(processed_data):
    user = processed_data.get("2")
    assert user is not None, "User 2 is missing from the output."
    assert user.get("name") == "Bob Updated", f"User 2 name not updated. Got: {user.get('name')}"
    assert user.get("email") == "***@test.com", f"User 2 email not masked correctly. Got: {user.get('email')}"
    assert user.get("phone") == "555-000-XXXX", f"User 2 phone not masked correctly. Got: {user.get('phone')}"
    assert user.get("timestamp") == "2023-10-01T10:15:00Z", f"User 2 timestamp not updated. Got: {user.get('timestamp')}"


def test_user3_csv_ingestion(processed_data):
    user = processed_data.get("3")
    assert user is not None, "User 3 is missing from the output."
    assert user.get("email") == "***@domain.org", f"User 3 email not masked correctly. Got: {user.get('email')}"
    assert user.get("phone") == "999-888-XXXX", f"User 3 phone not masked correctly. Got: {user.get('phone')}"


def test_user4_short_phone_masking(processed_data):
    user = processed_data.get("4")
    assert user is not None, "User 4 is missing from the output."
    assert user.get("email") == "***@company.net", f"User 4 email not masked correctly. Got: {user.get('email')}"
    assert user.get("phone") == "XXXX", f"User 4 short phone not masked correctly. Got: {user.get('phone')}"


def write_jsonl(path, rows):
    with open(path, "w", encoding="utf-8") as handle:
        for row in rows:
            handle.write(json.dumps(row) + "\n")


def write_csv(path, rows):
    with open(path, "w", encoding="utf-8", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=EXPECTED_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)


def assert_timestamp_equal(actual, expected):
    assert pd.to_datetime(actual, utc=True) == pd.to_datetime(expected, utc=True), (
        f"Expected timestamp {expected!r}, got {actual!r}"
    )


def test_random_inputs_alternate_output_timestamp_order_and_retries():
    """Exercise the interface with unpredictable data rather than known fixtures."""
    token = secrets.token_hex(8)
    base_id = 100000 + secrets.randbelow(800000)
    uid1, uid2, uid3 = base_id, base_id + 1, base_id + 2
    temp_dir = tempfile.mkdtemp(prefix=f"etl-verify-{token}-")
    first_path = os.path.join(temp_dir, f"initial-{token}.jsonl")
    second_path = os.path.join(temp_dir, f"updates-{token}.csv")
    stale_path = os.path.join(temp_dir, f"stale-{token}.jsonl")
    output_path = os.path.join(temp_dir, f"consolidated-{token}.parquet")

    initial = [
        {
            "user_id": uid1,
            "name": f"Old-{token}",
            "email": f"old.{token}@first.example",
            "phone": "ABCD",
            "timestamp": "2025-06-01T12:00:00+02:00",
        },
        {
            "user_id": uid2,
            "name": f"Keeper-{token}",
            "email": f"keeper.{token}@second.example",
            "phone": "12345",
            "timestamp": "2025-06-01T09:00:00-03:00",
        },
    ]
    updates = [
        {
            "user_id": uid1,
            "name": f"New-{token}",
            "email": f"new.{token}@updated.example",
            "phone": "xy",
            "timestamp": "2025-06-01T10:30:00Z",
        },
        {
            "user_id": uid2,
            "name": f"Stale-{token}",
            "email": f"stale.{token}@wrong.example",
            "phone": "99999999",
            "timestamp": "2025-06-01T11:30:00Z",
        },
        {
            "user_id": uid3,
            "name": f"Csv-{token}",
            "email": f"csv.{token}@third.example",
            "phone": "+1 222 333 4444",
            "timestamp": "2025-06-02T00:00:00Z",
        },
    ]
    stale = [
        {
            "user_id": uid3,
            "name": f"TooOld-{token}",
            "email": f"too.old.{token}@wrong.example",
            "phone": "0000",
            "timestamp": "2025-05-01T00:00:00Z",
        }
    ]

    write_jsonl(first_path, initial)
    write_csv(second_path, updates)
    write_jsonl(stale_path, stale)

    run_pipeline(first_path, output_path)
    run_pipeline(second_path, output_path)
    run_pipeline(second_path, output_path)  # exact retry must not append duplicates
    run_pipeline(stale_path, output_path)   # an older update must not replace state

    assert os.path.isfile(output_path)
    frame = pd.read_parquet(output_path)
    assert list(frame.columns) == EXPECTED_COLUMNS
    assert len(frame) == 3
    assert frame["user_id"].nunique() == 3
    assert {int(value) for value in frame["user_id"].tolist()} == {uid1, uid2, uid3}

    rows = {int(row["user_id"]): row for row in frame.to_dict(orient="records")}
    expected = {
        uid1: {
            "name": f"New-{token}",
            "email": "***@updated.example",
            "phone": "XXXX",
            "timestamp": "2025-06-01T10:30:00Z",
        },
        uid2: {
            "name": f"Keeper-{token}",
            "email": "***@second.example",
            "phone": "1XXXX",
            "timestamp": "2025-06-01T09:00:00-03:00",
        },
        uid3: {
            "name": f"Csv-{token}",
            "email": "***@third.example",
            "phone": "+1 222 333 XXXX",
            "timestamp": "2025-06-02T00:00:00Z",
        },
    }

    for user_id, wanted in expected.items():
        actual = rows[user_id]
        assert actual["name"] == wanted["name"]
        assert actual["email"] == wanted["email"]
        assert actual["phone"] == wanted["phone"]
        assert_timestamp_equal(actual["timestamp"], wanted["timestamp"])
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
