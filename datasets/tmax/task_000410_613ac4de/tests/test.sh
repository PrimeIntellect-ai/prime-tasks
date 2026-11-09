#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import json
import os
import posixpath
import secrets
import subprocess

import pytest

SOURCE = "/home/user/audit.cpp"
EXECUTABLE = "/tmp/audit_submission"
MANIFEST = "/home/user/threat_manifest.csv"


def write_original_fixture():
    os.makedirs("/home/user/quarantine", exist_ok=True)
    os.makedirs("/home/user/app_data", exist_ok=True)

    with open("/home/user/config.json", "w") as f:
        f.write('{"base_dir": "/home/user/app_data"}\n')

    with open("/home/user/extraction.log", "w") as f:
        f.write("""Record ID: 101
Path: /home/user/app_data/docs/readme.txt
Size: 15

Record ID: 102
Path: /home/user/app_data/docs/../../.ssh/id_rsa
Size: 17

Record ID: 103
Path: /home/user/app_data/images/logo.png
Size: 13

Record ID: 104
Path: /home/user/app_data/../app_data_backup/secret.key
Size: 17

Record ID: 105
Path: /home/user/app_data/./config/settings.ini
Size: 20
""")

    contents = {
        101: b"readme content\n",
        102: b"fake private key\n",
        103: b"logo content\n",
        104: b"secret key value\n",
        105: b"settings config\n",
    }
    for rec_id, content in contents.items():
        with open(f"/home/user/quarantine/{rec_id}.dat", "wb") as f:
            f.write(content)


def run_submission():
    if os.path.exists(MANIFEST):
        os.remove(MANIFEST)
    result = subprocess.run(
        [EXECUTABLE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Compiled audit program exited with status {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


@pytest.fixture(scope="session", autouse=True)
def prepare_submission():
    assert os.path.isfile(SOURCE), f"The required C++ source file was not found at {SOURCE}"

    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"audit.cpp did not compile as C++17. stdout={compile_result.stdout!r}, "
        f"stderr={compile_result.stderr!r}"
    )
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK), (
        "Compilation did not produce an executable program"
    )

    write_original_fixture()
    run_submission()
    yield


def test_threat_manifest_exists():
    manifest_path = "/home/user/threat_manifest.csv"
    assert os.path.isfile(manifest_path), f"The threat manifest file was not found at {manifest_path}"


def test_threat_manifest_content():
    manifest_path = "/home/user/threat_manifest.csv"
    assert os.path.isfile(manifest_path), f"The threat manifest file was not found at {manifest_path}"

    # Recompute expected hashes
    def get_hash(content):
        return hashlib.sha256(content.encode('utf-8')).hexdigest()

    expected_rows = {
        "102": {
            "path": "/home/user/.ssh/id_rsa",
            "hash": get_hash("fake private key\n")
        },
        "104": {
            "path": "/home/user/app_data_backup/secret.key",
            "hash": get_hash("secret key value\n")
        }
    }

    actual_rows = {}
    with open(manifest_path, "r", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            assert len(row) == 3, f"Invalid CSV format in row: {row}. Expected 3 columns."
            rec_id, path, sha256 = [col.strip() for col in row]
            actual_rows[rec_id] = {"path": path, "hash": sha256}

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} records in manifest, found {len(actual_rows)}."

    for rec_id, expected_data in expected_rows.items():
        assert rec_id in actual_rows, f"Record ID {rec_id} is missing from the manifest."
        assert actual_rows[rec_id]["path"] == expected_data["path"], f"Incorrect normalized path for Record ID {rec_id}. Expected {expected_data['path']}, got {actual_rows[rec_id]['path']}."
        assert actual_rows[rec_id]["hash"] == expected_data["hash"], f"Incorrect SHA256 hash for Record ID {rec_id}. Expected {expected_data['hash']}, got {actual_rows[rec_id]['hash']}."


def test_program_handles_runtime_generated_fixture():
    token = secrets.token_hex(8)
    base_dir = f"/home/user/vault_{token}"
    os.makedirs(base_dir, exist_ok=True)
    os.makedirs("/home/user/quarantine", exist_ok=True)

    first_id = 200000 + secrets.randbelow(500000)
    records = [
        (first_id, f"{base_dir}/docs/../safe.txt", b"safe data " + token.encode()),
        (first_id + 1, f"{base_dir}/docs/../../../escape_{token}/payload.bin", b"\x00malicious\xff" + secrets.token_bytes(19)),
        (first_id + 2, f"{base_dir}_backup/secret.key", secrets.token_bytes(37)),
        (first_id + 3, f"{base_dir}/nested/./still-safe.dat", b"another safe file"),
        (first_id + 4, f"{base_dir}/a/../../other/../outside.bin", secrets.token_bytes(53)),
    ]

    with open("/home/user/config.json", "w") as f:
        json.dump({"base_dir": base_dir}, f, indent=2)
        f.write("\n")

    with open("/home/user/extraction.log", "w") as f:
        for index, (rec_id, raw_path, content) in enumerate(records):
            if index:
                f.write("\n")
            f.write(f"Record ID: {rec_id}\n")
            f.write(f"Path: {raw_path}\n")
            f.write(f"Size: {len(content)}\n")

    for rec_id, _, content in records:
        with open(f"/home/user/quarantine/{rec_id}.dat", "wb") as f:
            f.write(content)

    expected_rows = {}
    for rec_id, raw_path, content in records:
        normalized = posixpath.normpath(raw_path)
        inside = normalized.startswith(base_dir + "/")
        if not inside:
            expected_rows[str(rec_id)] = {
                "path": normalized,
                "hash": hashlib.sha256(content).hexdigest(),
            }

    run_submission()
    assert os.path.isfile(MANIFEST), "The executed audit program did not create the manifest"

    actual_rows = {}
    row_count = 0
    with open(MANIFEST, "r", newline="") as f:
        for row in csv.reader(f):
            if not row:
                continue
            row_count += 1
            assert len(row) == 3, f"Invalid CSV format in generated row: {row}"
            rec_id, path, checksum = [column.strip() for column in row]
            assert rec_id not in actual_rows, f"Duplicate manifest record ID: {rec_id}"
            actual_rows[rec_id] = {"path": path, "hash": checksum}

    assert row_count == len(expected_rows), (
        f"Expected {len(expected_rows)} escaping records, found {row_count}"
    )
    assert actual_rows == expected_rows, (
        f"Manifest for runtime-generated inputs was incorrect. "
        f"Expected {expected_rows}, got {actual_rows}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
