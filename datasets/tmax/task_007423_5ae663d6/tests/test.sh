#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import pytest

REPORT_PATH = "/home/user/audit_report.json"
WEBAPP_DIR = "/home/user/webapp"
EXPECTED_WORLD_WRITABLE_FILE = "/home/user/webapp/cleanup.sh"


def get_world_writable_executables():
    """Return all regular files that are world-writable and world-executable."""
    matches = []
    if not os.path.isdir(WEBAPP_DIR):
        return matches

    for root, dirs, files in os.walk(WEBAPP_DIR):
        for name in files:
            path = os.path.join(root, name)
            st = os.stat(path)
            if stat.S_ISREG(st.st_mode) and (st.st_mode & stat.S_IWOTH) and (st.st_mode & stat.S_IXOTH):
                matches.append(path)
    return sorted(matches)


def test_audit_report_exists():
    assert os.path.exists(REPORT_PATH), f"The audit report was not found at {REPORT_PATH}."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a valid file."


def test_audit_report_content():
    assert os.path.exists(REPORT_PATH), f"The audit report was not found at {REPORT_PATH}."

    with open(REPORT_PATH, "r") as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    expected_keys = {"world_writable_file", "cwe_id", "db_pass"}
    assert set(report.keys()) == expected_keys, \
        f"Expected exactly the keys {expected_keys}, but got {set(report.keys())}."

    dangerous_files = get_world_writable_executables()
    assert dangerous_files == [EXPECTED_WORLD_WRITABLE_FILE], \
        f"Expected exactly one world-writable executable file, {EXPECTED_WORLD_WRITABLE_FILE}, but found {dangerous_files}."
    assert report["world_writable_file"] == EXPECTED_WORLD_WRITABLE_FILE, \
        f"Expected 'world_writable_file' to be '{EXPECTED_WORLD_WRITABLE_FILE}', but got '{report.get('world_writable_file')}'."

    actual_cwe = str(report.get("cwe_id", "")).strip().upper()
    assert actual_cwe == "CWE-321", \
        f"Expected 'cwe_id' to be 'CWE-321', but got '{report.get('cwe_id')}'."

    expected_db_pass = "P0w3rful_@ud1t_P@ss"
    assert report["db_pass"] == expected_db_pass, \
        "Expected 'db_pass' to be correct, but the decrypted value does not match the expected password."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
