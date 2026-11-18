#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

ARCHIVE_DIR = "/home/user/config_archives"
EXTRACTED_DIR = "/home/user/extracted_logs"
PARSER_PATH = "/home/user/parser.py"
MANIFEST_PATH = "/home/user/deploy_manifest.json"
CHECKSUM_PATH = "/home/user/manifest_checksum.txt"

EXPECTED_RAW_LOGS = {
    "batch_01": """[TRANSACTION]
User: svc_deploy_ops
Timestamp: 1690000000
Modified_Files:
 - /etc/nginx/nginx.conf|a1b2c3d4e5f6
 - /etc/systemd/system/myapp.service|999988887777
!! DEBUG: Flushed routing table cache
[END]
[TRANSACTION]
User: manual_admin
Timestamp: 1690000050
Modified_Files:
 - /etc/sudoers|deadbeef1234
[END]
!! DEBUG: Checking sync status...
""",
    "batch_02": """!! DEBUG: Initialization started
[TRANSACTION]
User: svc_deploy_ops
Timestamp: 1690000100
Modified_Files:
 - /etc/nginx/nginx.conf|f1e2d3c4b5a6
 - /etc/redis/redis.conf|111122223333
[END]
[TRANSACTION]
User: svc_deploy_ops
Timestamp: 1690000200
Modified_Files:
 - /etc/redis/redis.conf|abcdefabcdef
[END]
""",
}


def cleaned(text):
    return "".join(line for line in text.splitlines(keepends=True)
                   if not line.startswith("!! DEBUG"))


def test_archive_integrity_and_extraction():
    assert os.path.isdir(ARCHIVE_DIR), f"Directory {ARCHIVE_DIR} does not exist."

    expected_archives = {
        "batch_01.tar.gz", "batch_02.tar.gz", "batch_err_corrupt.tar.gz"
    }
    actual_archives = {
        name for name in os.listdir(ARCHIVE_DIR) if name.endswith(".tar.gz")
    }
    assert actual_archives == expected_archives, (
        f"Archive set was changed. Expected {expected_archives}, found {actual_archives}"
    )

    for base, expected_text in EXPECTED_RAW_LOGS.items():
        archive = os.path.join(ARCHIVE_DIR, base + ".tar.gz")
        integrity = subprocess.run(
            ["tar", "-tzf", archive], stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, text=True
        )
        assert integrity.returncode == 0, f"Valid archive failed integrity check: {archive}"

        extracted = subprocess.run(
            ["tar", "-xOzf", archive, "changelog.txt"],
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
        )
        assert extracted.returncode == 0, f"Could not read changelog.txt from {archive}"
        assert extracted.stdout == expected_text, f"Source archive content was changed: {archive}"

    corrupt = os.path.join(ARCHIVE_DIR, "batch_err_corrupt.tar.gz")
    corrupt_check = subprocess.run(
        ["tar", "-tzf", corrupt], stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert corrupt_check.returncode != 0, "The designated corrupt archive is unexpectedly valid."

    assert os.path.isdir(EXTRACTED_DIR), f"Directory {EXTRACTED_DIR} does not exist."
    expected_files = {"batch_01.txt", "batch_02.txt"}
    actual_files = set(os.listdir(EXTRACTED_DIR))
    assert expected_files.issubset(actual_files), (
        f"Expected files {expected_files} not found in {EXTRACTED_DIR}. Found: {actual_files}"
    )
    assert actual_files == expected_files, (
        f"Only logs from valid archives should be present. Found: {actual_files}"
    )

    for base, raw_text in EXPECTED_RAW_LOGS.items():
        filepath = os.path.join(EXTRACTED_DIR, base + ".txt")
        with open(filepath, "r", encoding="utf-8") as f:
            contents = f.read()
        for line in contents.splitlines(keepends=True):
            assert not line.startswith("!! DEBUG"), (
                f"File {filepath} still contains '!! DEBUG' lines."
            )
        assert contents == cleaned(raw_text), (
            f"Extracted and cleaned content in {filepath} does not match its archive."
        )


def test_parser_script_exists():
    assert os.path.isfile(PARSER_PATH), f"Python script {PARSER_PATH} does not exist."


def test_deploy_manifest():
    assert os.path.isfile(MANIFEST_PATH), f"JSON manifest {MANIFEST_PATH} does not exist."

    with open(MANIFEST_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {MANIFEST_PATH} is not valid JSON.")

    expected_data = {
        "/etc/nginx/nginx.conf": "f1e2d3c4b5a6",
        "/etc/systemd/system/myapp.service": "999988887777",
        "/etc/redis/redis.conf": "abcdefabcdef"
    }

    assert data == expected_data, (
        f"JSON content in {MANIFEST_PATH} does not match expected output.\n"
        f"Expected: {expected_data}\nActual: {data}"
    )


def test_manifest_checksum():
    assert os.path.isfile(CHECKSUM_PATH), f"Checksum file {CHECKSUM_PATH} does not exist."
    assert os.path.isfile(MANIFEST_PATH), (
        f"Manifest file {MANIFEST_PATH} does not exist to verify checksum."
    )

    with open(MANIFEST_PATH, "rb") as f:
        actual_sha256 = hashlib.sha256(f.read()).hexdigest()

    with open(CHECKSUM_PATH, "r") as f:
        checksum_content = f.read().strip()

    assert checksum_content.startswith(actual_sha256), (
        f"Checksum in {CHECKSUM_PATH} does not match the actual SHA256 of {MANIFEST_PATH}.\n"
        f"Expected hash starting with: {actual_sha256}\nActual content: {checksum_content}"
    )


def test_parser_executes_and_parses_dynamic_logs():
    token = secrets.token_hex(8)
    hash_old = secrets.token_hex(20)
    hash_middle = secrets.token_hex(20)
    hash_latest = secrets.token_hex(20)
    hash_unique = secrets.token_hex(20)
    hash_ignored = secrets.token_hex(20)

    shared_path = f"/dynamic/{token}/shared.conf"
    unique_path = f"/dynamic/{token}/unique.conf"
    ignored_path = f"/dynamic/{token}/ignored.conf"

    log_01 = f"""[TRANSACTION]
User: svc_deploy_ops
Timestamp: 9999999999
Modified_Files:
 - {shared_path}|{hash_old}
[END]
[TRANSACTION]
User: svc_deploy_ops_extra
Timestamp: 1
Modified_Files:
 - {ignored_path}|{hash_ignored}
[END]
"""
    log_02 = f"""[TRANSACTION]
User: svc_deploy_ops
Timestamp: 1
Modified_Files:
 - {shared_path}|{hash_middle}
 - {unique_path}|{hash_unique}
[END]
[TRANSACTION]
User: svc_deploy_ops
Timestamp: 2
Modified_Files:
 - {shared_path}|{hash_latest}
[END]
"""
    expected = {
        shared_path: hash_latest,
        unique_path: hash_unique,
    }

    backup_root = tempfile.mkdtemp(prefix="parser-verifier-")
    backup_logs = os.path.join(backup_root, "extracted_logs")
    shutil.copytree(EXTRACTED_DIR, backup_logs)
    manifest_backup = os.path.join(backup_root, "deploy_manifest.json")
    checksum_backup = os.path.join(backup_root, "manifest_checksum.txt")
    manifest_existed = os.path.exists(MANIFEST_PATH)
    checksum_existed = os.path.exists(CHECKSUM_PATH)
    if manifest_existed:
        shutil.copy2(MANIFEST_PATH, manifest_backup)
    if checksum_existed:
        shutil.copy2(CHECKSUM_PATH, checksum_backup)

    try:
        shutil.rmtree(EXTRACTED_DIR)
        os.mkdir(EXTRACTED_DIR)
        with open(os.path.join(EXTRACTED_DIR, "batch_01.txt"), "w", encoding="utf-8") as f:
            f.write(log_01)
        with open(os.path.join(EXTRACTED_DIR, "batch_02.txt"), "w", encoding="utf-8") as f:
            f.write(log_02)
        if os.path.exists(MANIFEST_PATH):
            os.remove(MANIFEST_PATH)

        result = subprocess.run(
            ["python3", PARSER_PATH], cwd="/home/user",
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
        )
        assert result.returncode == 0, (
            f"parser.py failed when executed. stdout={result.stdout!r} "
            f"stderr={result.stderr!r}"
        )
        assert os.path.isfile(MANIFEST_PATH), "parser.py did not create deploy_manifest.json."
        with open(MANIFEST_PATH, "r", encoding="utf-8") as f:
            try:
                actual = json.load(f)
            except json.JSONDecodeError as exc:
                pytest.fail(f"parser.py produced invalid JSON: {exc}")
        assert isinstance(actual, dict), "parser.py output is not a flat JSON object."
        assert actual == expected, (
            f"parser.py did not parse, filter, order, and deduplicate dynamic logs. "
            f"Expected {expected}, got {actual}"
        )
    finally:
        shutil.rmtree(EXTRACTED_DIR, ignore_errors=True)
        shutil.copytree(backup_logs, EXTRACTED_DIR)
        if manifest_existed:
            shutil.copy2(manifest_backup, MANIFEST_PATH)
        elif os.path.exists(MANIFEST_PATH):
            os.remove(MANIFEST_PATH)
        if checksum_existed:
            shutil.copy2(checksum_backup, CHECKSUM_PATH)
        elif os.path.exists(CHECKSUM_PATH):
            os.remove(CHECKSUM_PATH)
        shutil.rmtree(backup_root, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
