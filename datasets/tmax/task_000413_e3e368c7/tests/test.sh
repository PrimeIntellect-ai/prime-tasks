#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import struct
import secrets
import shutil
import subprocess
import pytest

BASE_DIR = "/home/user/backups"
CSV_PATH = os.path.join(BASE_DIR, "index.csv")
JSON_PATH = "/home/user/archive_summary.json"
C_FILE_PATH = "/home/user/archive_tool.c"
EXECUTABLE_PATH = "/tmp/archive_tool_verified"


def get_expected_data():
    expected = []
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            backup_id = row["BackupID"]
            rel_path = row["RelativePath"]
            offset = int(row["HeaderOffset"])

            bin_path = os.path.join(BASE_DIR, rel_path)
            with open(bin_path, "rb") as bin_f:
                bin_f.seek(offset)
                header = bin_f.read(8)

            magic_bytes = header[0:4]
            magic_str = "".join(f"{b:02X}" for b in magic_bytes)
            timestamp = struct.unpack("<I", header[4:8])[0]

            expected.append({
                "BackupID": backup_id,
                "Magic": magic_str,
                "Timestamp": timestamp
            })
    return expected


def assert_json_matches(expected_data):
    with open(JSON_PATH, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON output: {e}")

    assert isinstance(actual_data, list), "JSON output must be an array of objects."

    actual_sorted = sorted(actual_data, key=lambda x: x.get("BackupID", ""))
    expected_sorted = sorted(expected_data, key=lambda x: x["BackupID"])

    assert len(actual_sorted) == len(expected_sorted), f"Expected {len(expected_sorted)} entries, found {len(actual_sorted)}"

    for actual, expected in zip(actual_sorted, expected_sorted):
        assert actual.get("BackupID") == expected["BackupID"], f"BackupID mismatch: expected {expected['BackupID']}, got {actual.get('BackupID')}"
        assert actual.get("Magic") == expected["Magic"], f"Magic mismatch for {expected['BackupID']}: expected {expected['Magic']}, got {actual.get('Magic')}"
        assert actual.get("Timestamp") == expected["Timestamp"], f"Timestamp mismatch for {expected['BackupID']}: expected {expected['Timestamp']}, got {actual.get('Timestamp')}"


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_submission():
    assert os.path.isfile(C_FILE_PATH), f"C source file not found at {C_FILE_PATH}"
    subprocess.run(
        ["gcc", "-std=c11", "-O2", C_FILE_PATH, "-o", EXECUTABLE_PATH],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    subprocess.run(
        [EXECUTABLE_PATH],
        check=True,
        timeout=15,
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_c_source_exists():
    assert os.path.isfile(C_FILE_PATH), f"C source file not found at {C_FILE_PATH}"


def test_json_output_exists():
    assert os.path.isfile(JSON_PATH), f"JSON output file not found at {JSON_PATH}"


def test_json_output_content():
    expected_data = get_expected_data()
    assert_json_matches(expected_data)


def test_compiled_program_extracts_fresh_headers():
    with open(CSV_PATH, "rb") as f:
        original_index = f.read()

    nonce = secrets.token_hex(8)
    generated_root = os.path.join(BASE_DIR, f"verifier_{nonce}")
    os.makedirs(generated_root)

    rows = []
    try:
        for i in range(4):
            backup_id = f"VERIFY-{nonce}-{i}"
            rel_path = f"verifier_{nonce}/node_{i}/data_{secrets.token_hex(4)}.bin"
            offset = 37 + secrets.randbelow(3000)
            magic = secrets.token_bytes(4)
            timestamp = secrets.randbelow(2 ** 32)

            full_path = os.path.join(BASE_DIR, rel_path)
            os.makedirs(os.path.dirname(full_path), exist_ok=True)
            data = bytearray(secrets.token_bytes(offset + 48))
            data[offset:offset + 4] = magic
            data[offset + 4:offset + 8] = struct.pack("<I", timestamp)
            with open(full_path, "wb") as f:
                f.write(data)

            rows.append([backup_id, rel_path, str(offset)])

        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["BackupID", "RelativePath", "HeaderOffset"])
            writer.writerows(rows)

        expected_data = get_expected_data()
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        subprocess.run(
            [EXECUTABLE_PATH],
            check=True,
            timeout=15,
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
        assert os.path.isfile(JSON_PATH), f"JSON output file not found at {JSON_PATH}"
        assert_json_matches(expected_data)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_index)
        shutil.rmtree(generated_root, ignore_errors=True)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        subprocess.run(
            [EXECUTABLE_PATH],
            check=True,
            timeout=15,
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
