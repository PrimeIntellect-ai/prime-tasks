#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import zipfile
import urllib.request
import urllib.error


def test_hr_data_jsonl():
    path = "/home/user/normalized/hr_data.jsonl"
    assert os.path.isfile(path), f"File missing: {path}"

    with open(path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 3, f"Expected 3 lines in {path}, got {len(lines)}"

    parsed = [json.loads(line) for line in lines]
    assert parsed[0]["id"] == "1"
    assert parsed[0]["name"] == "José Guitiérrez"
    assert parsed[0]["role"] == "Manager"

    expected = [
        {"id": "1", "name": "José Guitiérrez", "role": "Manager"},
        {"id": "2", "name": "Müller Schmidt", "role": "Analyst"},
        {"id": "3", "name": "Renée Dubois", "role": "Developer"},
    ]
    assert parsed == expected, f"Unexpected HR records: {parsed!r}"


def test_finance_data_jsonl():
    path = "/home/user/normalized/finance_data.jsonl"
    assert os.path.isfile(path), f"File missing: {path}"

    with open(path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected 2 lines in {path}, got {len(lines)}"

    parsed = [json.loads(line) for line in lines]
    assert parsed[0]["tx_id"] == "A100"
    assert parsed[0]["amount"] == 1500.5
    assert parsed[0]["currency"] == "€"

    expected = [
        {"tx_id": "A100", "amount": 1500.5, "currency": "€"},
        {"tx_id": "A101", "amount": 300.0, "currency": "£"},
    ]
    assert parsed == expected, f"Unexpected finance records: {parsed!r}"


def test_manifest_json():
    path = "/home/user/normalized/manifest.json"
    assert os.path.isfile(path), f"File missing: {path}"

    with open(path, "r", encoding="utf-8") as f:
        manifest = json.load(f)

    assert manifest.get("hr_data.csv") == 3, "Manifest hr_data.csv count incorrect"
    assert manifest.get("finance_data.json") == 2, "Manifest finance_data.json count incorrect"


def test_backup_zip():
    path = "/home/user/final/backup_v2.zip"
    assert os.path.isfile(path), f"File missing: {path}"

    assert zipfile.is_zipfile(path), f"{path} is not a valid zip file"
    with zipfile.ZipFile(path, "r") as z:
        names = z.namelist()
        # Ensure the files are present in the zip, regardless of whether they are in a folder
        basenames = [os.path.basename(n) for n in names]
        assert "hr_data.jsonl" in basenames, "hr_data.jsonl missing in zip"
        assert "finance_data.jsonl" in basenames, "finance_data.jsonl missing in zip"
        assert "manifest.json" in basenames, "manifest.json missing in zip"

        # Each archived output must be the actual corresponding normalized file.
        for basename in ("hr_data.jsonl", "finance_data.jsonl", "manifest.json"):
            members = [n for n in names if os.path.basename(n) == basename]
            assert len(members) == 1, f"Expected exactly one archived {basename}, got {members!r}"
            normalized_path = os.path.join("/home/user/normalized", basename)
            with open(normalized_path, "rb") as f:
                expected_bytes = f.read()
            assert z.read(members[0]) == expected_bytes, \
                f"Archived {basename} does not match {normalized_path}"


def test_http_server():
    url = "http://localhost:8123/backup_v2.zip"
    try:
        req = urllib.request.urlopen(url, timeout=2)
        assert req.getcode() == 200, f"Expected HTTP 200, got {req.getcode()}"
    except Exception as e:
        assert False, f"Failed to fetch {url}: {e}"


def test_server_pid():
    path = "/home/user/server.pid"
    assert os.path.isfile(path), f"File missing: {path}"

    with open(path, "r") as f:
        pid_str = f.read().strip()

    assert pid_str.isdigit(), f"PID file does not contain a valid integer: {pid_str}"

    # Check if process exists
    pid = int(pid_str)
    try:
        os.kill(pid, 0)
    except OSError:
        assert False, f"Process with PID {pid} is not running"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
