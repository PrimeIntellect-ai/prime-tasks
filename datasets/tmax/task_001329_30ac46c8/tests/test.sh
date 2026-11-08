#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import hashlib
import pytest

APP_CONFIGS_DIR = "/home/user/app_configs"
CHECKSUM_FILE = "/home/user/configs_checksum.txt"

DB_CONF_PATH = os.path.join(APP_CONFIGS_DIR, "db.conf")
AWS_CONF_PATH = os.path.join(APP_CONFIGS_DIR, "aws.conf")
APP_CONF_PATH = os.path.join(APP_CONFIGS_DIR, "app.conf")

EXPECTED_DB_CONF = """DB_USER=admin
DB_PASSWORD=NewSecureDBPass2024!
DB_HOST=localhost
"""

EXPECTED_AWS_CONF = """AWS_ACCESS_KEY_ID=REDACTED
AWS_SECRET_ACCESS_KEY=REDACTED
AWS_REGION=us-east-1
"""

EXPECTED_APP_CONF = """APP_ENV=production
DB_PASSWORD=NewSecureDBPass2024!
AWS_ACCESS_KEY_ID=REDACTED
"""

def test_db_conf_content():
    assert os.path.isfile(DB_CONF_PATH), f"File {DB_CONF_PATH} is missing."
    with open(DB_CONF_PATH, 'r') as f:
        content = f.read()
    assert content == EXPECTED_DB_CONF, f"Content of {DB_CONF_PATH} does not match the expected redacted state."

def test_aws_conf_content():
    assert os.path.isfile(AWS_CONF_PATH), f"File {AWS_CONF_PATH} is missing."
    with open(AWS_CONF_PATH, 'r') as f:
        content = f.read()
    assert content == EXPECTED_AWS_CONF, f"Content of {AWS_CONF_PATH} does not match the expected redacted state."

def test_app_conf_content():
    assert os.path.isfile(APP_CONF_PATH), f"File {APP_CONF_PATH} is missing."
    with open(APP_CONF_PATH, 'r') as f:
        content = f.read()
    assert content == EXPECTED_APP_CONF, f"Content of {APP_CONF_PATH} does not match the expected redacted state."

def test_file_permissions():
    for file_path in [APP_CONF_PATH, AWS_CONF_PATH, DB_CONF_PATH]:
        assert os.path.isfile(file_path), f"File {file_path} is missing."
        st = os.stat(file_path)
        perms = stat.S_IMODE(st.st_mode)
        assert perms == 0o600, f"Permissions of {file_path} are {oct(perms)}, expected 0o600."

def test_checksum_file():
    assert os.path.isfile(CHECKSUM_FILE), f"Checksum file {CHECKSUM_FILE} is missing."

    # Compute expected checksums based on expected contents
    expected_checksums = []
    files_to_hash = [
        (APP_CONF_PATH, EXPECTED_APP_CONF),
        (AWS_CONF_PATH, EXPECTED_AWS_CONF),
        (DB_CONF_PATH, EXPECTED_DB_CONF)
    ]

    for path, expected_content in files_to_hash:
        file_hash = hashlib.sha256(expected_content.encode('utf-8')).hexdigest()
        expected_checksums.append(f"{file_hash}  {path}")

    expected_checksum_content = "\n".join(expected_checksums) + "\n"

    with open(CHECKSUM_FILE, 'r') as f:
        actual_content = f.read()

    assert actual_content == expected_checksum_content, f"Content of {CHECKSUM_FILE} does not match the expected sha256sum output."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
