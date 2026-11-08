#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
import uuid

import pytest


def test_etl_script_exists():
    """Verify that the ETL script was created."""
    assert os.path.isfile("/home/user/etl.py"), "The ETL script /home/user/etl.py does not exist."


def test_json_output_exists_and_valid():
    """Verify that the initially generated output contains the correct masked data."""
    json_path = "/home/user/clean_data/employees_masked.json"
    assert os.path.isfile(json_path), f"The output file {json_path} does not exist. Did you run your ETL script?"

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {json_path} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON output should be an array (list) of objects."
    assert len(data) == 3, f"Expected 3 records in the JSON output, but found {len(data)}."

    expected_records = [
        {"id": "1", "name": "Alice Smith", "email": "***@company.com", "ssn": "XXX-XX-XXXX"},
        {"id": "2", "name": "Bob Jones", "email": "***@test.org", "ssn": "XXX-XX-XXXX"},
        {"id": "3", "name": "Charlie Brown", "email": "***@domain.net", "ssn": "XXX-XX-XXXX"}
    ]

    data_sorted = sorted(data, key=lambda x: str(x.get("id", "")))
    expected_sorted = sorted(expected_records, key=lambda x: x["id"])

    for i, (actual, expected) in enumerate(zip(data_sorted, expected_sorted)):
        assert actual.get("id") == expected["id"], f"Record {i} ID mismatch: expected {expected['id']}, got {actual.get('id')}"
        assert actual.get("name") == expected["name"], f"Record {i} Name mismatch: expected {expected['name']}, got {actual.get('name')}"
        assert actual.get("email") == expected["email"], f"Record {i} Email mismatch: expected {expected['email']}, got {actual.get('email')}"
        assert actual.get("ssn") == expected["ssn"], f"Record {i} SSN mismatch: expected {expected['ssn']}, got {actual.get('ssn')}"


def test_etl_executes_and_derives_output_from_csv():
    """Replace the CSV with unpredictable data, execute the script, and verify its output."""
    csv_path = "/home/user/raw_data/employees.csv"
    json_path = "/home/user/clean_data/employees_masked.json"

    with open(csv_path, "rb") as f:
        original_csv = f.read()
    original_json = None
    if os.path.exists(json_path):
        with open(json_path, "rb") as f:
            original_json = f.read()

    token = uuid.uuid4().hex
    records = [
        {"id": token[:8], "name": "Dynamic Alpha", "email": f"alpha.{token[:6]}@{token[6:12]}.example", "ssn": "111-22-3333"},
        {"id": token[8:16], "name": "Dynamic Beta", "email": f"beta_{token[12:18]}@{token[18:24]}.test", "ssn": "444-55-6666"},
        {"id": token[16:24], "name": "Dynamic Gamma", "email": f"gamma-{token[20:26]}@{token[26:32]}.invalid", "ssn": "777-88-9999"},
        {"id": token[24:32], "name": "Dynamic Delta", "email": f"delta{token[:5]}@dynamic.local", "ssn": "000-12-3456"},
    ]

    try:
        with open(csv_path, "w", newline="") as f:
            writer = csv.DictWriter(f, fieldnames=["id", "name", "email", "ssn"])
            writer.writeheader()
            writer.writerows(records)

        if os.path.exists(json_path):
            os.remove(json_path)

        result = subprocess.run(
            ["/usr/bin/python3", "/home/user/etl.py"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, f"ETL script failed when executed: {result.stderr}"
        assert os.path.isfile(json_path), "Executing the ETL script did not generate the output JSON file."

        try:
            with open(json_path, "r") as f:
                actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The ETL script generated invalid JSON.")

        expected = [
            {
                "id": row["id"],
                "name": row["name"],
                "email": "***@" + row["email"].split("@", 1)[1],
                "ssn": "XXX-XX-XXXX",
            }
            for row in records
        ]

        assert isinstance(actual, list), "The generated JSON output should be an array."
        assert len(actual) == len(expected), "The generated JSON must contain one record per CSV row."
        assert sorted(actual, key=lambda x: str(x.get("id", ""))) == sorted(expected, key=lambda x: x["id"]), (
            "The ETL script did not derive the correctly masked records from the current CSV input."
        )
    finally:
        with open(csv_path, "wb") as f:
            f.write(original_csv)
        if original_json is None:
            if os.path.exists(json_path):
                os.remove(json_path)
        else:
            with open(json_path, "wb") as f:
                f.write(original_json)


def test_cron_configuration():
    """Verify the cron job file is created with exactly one correct line."""
    cron_path = "/home/user/pipeline.cron"
    assert os.path.isfile(cron_path), f"The cron file {cron_path} does not exist."

    with open(cron_path, "r") as f:
        raw_content = f.read()

    lines = [line.strip() for line in raw_content.splitlines() if line.strip()]
    assert len(lines) >= 1, f"The cron file {cron_path} is empty."

    actual_tokens = lines[0].split()
    expected_tokens = "0 0 * * 0 /usr/bin/python3 /home/user/etl.py".split()

    assert actual_tokens == expected_tokens, (
        f"The cron expression in {cron_path} is incorrect. "
        f"Expected: '0 0 * * 0 /usr/bin/python3 /home/user/etl.py', but got: '{lines[0]}'"
    )

    assert len(raw_content.splitlines()) == 1, f"The cron file {cron_path} must contain exactly one line."

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
