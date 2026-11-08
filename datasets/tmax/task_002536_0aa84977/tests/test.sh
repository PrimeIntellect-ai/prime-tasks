#!/bin/bash
set +e
mkdir -p /logs/verifier

workdir=$(mktemp -d)
cp -p /home/user/backups_metadata.jsonl "$workdir/backups_metadata.jsonl"
metadata_backup_status=$?
report_existed=0
if [ -e /home/user/backup_report.json ]; then
    report_existed=1
    cp -p /home/user/backup_report.json "$workdir/backup_report.json"
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess

SCRIPT_PATH = "/home/user/analyze_backups.py"
INPUT_PATH = "/home/user/backups_metadata.jsonl"
REPORT_PATH = "/home/user/backup_report.json"


def run_script():
    result = subprocess.run(
        ["runuser", "-u", "user", "--", "python3", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}. "
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )


def load_report():
    assert os.path.isfile(REPORT_PATH), f"The output file {REPORT_PATH} was not created."
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {REPORT_PATH} does not contain valid JSON."


def test_script_exists_and_generates_report():
    assert os.path.isfile(SCRIPT_PATH), f"The required script {SCRIPT_PATH} was not created."
    os.remove(REPORT_PATH) if os.path.exists(REPORT_PATH) else None
    run_script()
    assert os.path.isfile(REPORT_PATH), f"Executing {SCRIPT_PATH} did not create {REPORT_PATH}."


def test_backup_report_exists_and_valid():
    report_path = "/home/user/backup_report.json"
    assert os.path.isfile(report_path), f"The output file {report_path} was not created."

    with open(report_path, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"The file {report_path} does not contain valid JSON."

    assert isinstance(report_data, list), f"The JSON in {report_path} must be a list (JSON array)."

    expected_data = [
        {
            "region": "eu-west-1",
            "database_name": "auth_db",
            "latest_backup": "2023-10-01T02:00:00Z",
            "total_size_bytes": 10485760
        },
        {
            "region": "eu-west-1",
            "database_name": "inventory_db",
            "latest_backup": "2023-10-01T04:00:00Z",
            "total_size_bytes": 8388608
        },
        {
            "region": "us-east-1",
            "database_name": "payment_db",
            "latest_backup": "2023-10-02T03:00:00Z",
            "total_size_bytes": 105428800
        },
        {
            "region": "us-east-1",
            "database_name": "auth_db",
            "latest_backup": "2023-10-03T02:00:00Z",
            "total_size_bytes": 21485760
        }
    ]

    assert len(report_data) == len(expected_data), f"Expected {len(expected_data)} records, found {len(report_data)}."

    for i, (actual, expected) in enumerate(zip(report_data, expected_data)):
        assert isinstance(actual, dict), f"Record at index {i} is not a JSON object."
        assert actual.get("region") == expected["region"], f"Record {i}: Expected region {expected['region']}, got {actual.get('region')}."
        assert actual.get("database_name") == expected["database_name"], f"Record {i}: Expected database_name {expected['database_name']}, got {actual.get('database_name')}."
        assert actual.get("latest_backup") == expected["latest_backup"], f"Record {i}: Expected latest_backup {expected['latest_backup']}, got {actual.get('latest_backup')}."
        assert actual.get("total_size_bytes") == expected["total_size_bytes"], f"Record {i}: Expected total_size_bytes {expected['total_size_bytes']}, got {actual.get('total_size_bytes')}."

        # Check that there are no extra keys
        assert set(actual.keys()) == set(expected.keys()), f"Record {i} has unexpected keys: {set(actual.keys()) - set(expected.keys())}"


def test_script_aggregates_unseen_input():
    token = secrets.token_hex(6)
    amount_a = secrets.randbelow(900000) + 100000
    amount_b = secrets.randbelow(900000) + 1100000
    amount_c = secrets.randbelow(900000) + 3100000
    amount_d = secrets.randbelow(900000) + 5100000

    records = [
        {"backup_id": f"{token}-1", "database_name": f"alpha_{token}", "region": f"region-b-{token}", "status": "SUCCESS", "timestamp": "2025-01-01T01:00:00Z", "size_bytes": amount_a},
        {"backup_id": f"{token}-2", "database_name": f"alpha_{token}", "region": f"region-b-{token}", "status": "SUCCESS", "timestamp": "2025-04-03T01:00:00Z", "size_bytes": amount_b},
        {"backup_id": f"{token}-3", "database_name": f"alpha_{token}", "region": f"region-b-{token}", "status": "FAILED", "timestamp": "2026-12-31T23:59:59Z", "size_bytes": amount_d},
        {"backup_id": f"{token}-4", "database_name": f"beta_{token}", "region": f"region-a-{token}", "status": "SUCCESS", "timestamp": "2024-06-07T03:00:00Z", "size_bytes": amount_c},
        {"backup_id": f"{token}-5", "database_name": f"gamma_{token}", "region": f"region-a-{token}", "status": "SUCCESS", "timestamp": "2025-02-02T04:00:00Z", "size_bytes": amount_d},
        {"backup_id": f"{token}-6", "database_name": f"gamma_{token}", "region": f"region-a-{token}", "status": "IN_PROGRESS", "timestamp": "2027-02-02T04:00:00Z", "size_bytes": amount_b},
    ]

    grouped = {}
    for record in records:
        if record["status"] != "SUCCESS":
            continue
        key = (record["region"], record["database_name"])
        if key not in grouped:
            grouped[key] = {"latest_backup": record["timestamp"], "total_size_bytes": 0}
        grouped[key]["latest_backup"] = max(grouped[key]["latest_backup"], record["timestamp"])
        grouped[key]["total_size_bytes"] += record["size_bytes"]

    expected = [
        {
            "region": region,
            "database_name": database,
            "latest_backup": values["latest_backup"],
            "total_size_bytes": values["total_size_bytes"],
        }
        for (region, database), values in grouped.items()
    ]
    expected.sort(key=lambda item: (item["region"], -item["total_size_bytes"]))

    with open(INPUT_PATH, "w") as f:
        for record in records:
            f.write(json.dumps(record) + "\n")
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    run_script()
    actual = load_report()
    assert isinstance(actual, list), f"The JSON in {REPORT_PATH} must be a list (JSON array)."
    assert actual == expected, f"Report for unseen input was incorrect. Expected {expected}, got {actual}."
    for i, item in enumerate(actual):
        assert isinstance(item, dict), f"Record at index {i} is not a JSON object."
        assert set(item.keys()) == {"region", "database_name", "latest_backup", "total_size_bytes"}, f"Record {i} has incorrect keys."
TEST_EOF

status=1
if [ "$metadata_backup_status" -eq 0 ]; then
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
    status=$?
fi

cp -p "$workdir/backups_metadata.jsonl" /home/user/backups_metadata.jsonl 2>/dev/null
if [ "$report_existed" -eq 1 ]; then
    cp -p "$workdir/backup_report.json" /home/user/backup_report.json 2>/dev/null
else
    rm -f /home/user/backup_report.json
fi
rm -rf "$workdir"

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
