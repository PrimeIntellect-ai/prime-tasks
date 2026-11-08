#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import subprocess
import tempfile

import pytest
from cryptography.fernet import Fernet

REPORT_PATH = "/home/user/policy_report.json"
SCRIPT_PATH = "/home/user/policy_check.py"
METADATA_PATH = "/home/user/metadata.enc"
KEY_PATH = "/home/user/key.txt"
ARTIFACT_PATH = "/home/user/artifact.bin"
EXPECTED_KEYS = [
    "metadata_decrypted",
    "xss_found",
    "banned_function_system_found",
    "policy_passed",
]


def run_submission():
    if os.path.lexists(REPORT_PATH):
        os.remove(REPORT_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"policy_check.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(REPORT_PATH), "Running policy_check.py did not create policy_report.json."


def load_and_validate_report():
    try:
        with open(REPORT_PATH, "r") as f:
            report = json.load(f)
    except (OSError, json.JSONDecodeError) as exc:
        pytest.fail(f"Could not read a valid JSON report: {exc}")

    for key in EXPECTED_KEYS:
        assert key in report, f"Key '{key}' is missing from the JSON report."
        assert isinstance(report[key], bool), f"Value for '{key}' must be a boolean."
    return report


@pytest.fixture(scope="session", autouse=True)
def execute_script_before_checks():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."
    run_submission()


def test_policy_report_exists():
    """Verify that the policy report JSON file was created."""
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} does not exist. Did you run your script?"


def test_policy_report_content():
    """Verify that the policy report contains the correct boolean values."""
    assert os.path.isfile(REPORT_PATH), f"Cannot check content, {REPORT_PATH} is missing."

    try:
        with open(REPORT_PATH, 'r') as f:
            report = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT_PATH} does not contain valid JSON.")

    expected_keys = ["metadata_decrypted", "xss_found", "banned_function_system_found", "policy_passed"]
    for key in expected_keys:
        assert key in report, f"Key '{key}' is missing from the JSON report."
        assert isinstance(report[key], bool), f"Value for '{key}' must be a boolean."

    assert report["metadata_decrypted"] is True, "Expected 'metadata_decrypted' to be true."
    assert report["xss_found"] is True, "Expected 'xss_found' to be true, since <script> is in the metadata."
    assert report["banned_function_system_found"] is True, "Expected 'banned_function_system_found' to be true, since 'system' is used in the ELF binary."
    assert report["policy_passed"] is False, "Expected 'policy_passed' to be false, since violations were found."


def test_script_exists():
    """Verify that the student wrote the script at the requested location."""
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} is missing."


def test_script_analyzes_controlled_inputs():
    """Exercise the submitted script on independently generated metadata and ELF files."""
    with tempfile.TemporaryDirectory() as td:
        backups = {}
        for path in (METADATA_PATH, KEY_PATH, ARTIFACT_PATH):
            backup = os.path.join(td, os.path.basename(path) + ".original")
            shutil.copy2(path, backup)
            backups[path] = backup

        benign_source = os.path.join(td, "benign.c")
        banned_source = os.path.join(td, "banned.c")
        benign_binary = os.path.join(td, "benign.bin")
        banned_binary = os.path.join(td, "banned.bin")

        with open(benign_source, "w") as f:
            f.write('#include <stdio.h>\nint main(void) { puts("safe"); return 0; }\n')
        with open(banned_source, "w") as f:
            f.write('#include <stdlib.h>\nint main(void) { return system("true"); }\n')

        subprocess.run(["gcc", benign_source, "-o", benign_binary], check=True, timeout=20)
        subprocess.run(["gcc", banned_source, "-o", banned_binary], check=True, timeout=20)

        cases = [
            ({"description": "A harmless value containing <scripture> only"}, benign_binary,
             {"metadata_decrypted": True, "xss_found": False,
              "banned_function_system_found": False, "policy_passed": True}),
            ({"description": "prefix <ScRiPt>alert(1)</script> suffix"}, benign_binary,
             {"metadata_decrypted": True, "xss_found": True,
              "banned_function_system_found": False, "policy_passed": False}),
            ({"description": "clean metadata"}, banned_binary,
             {"metadata_decrypted": True, "xss_found": False,
              "banned_function_system_found": True, "policy_passed": False}),
        ]

        try:
            for metadata, binary, expected in cases:
                key = Fernet.generate_key()
                encrypted = Fernet(key).encrypt(json.dumps(metadata).encode("utf-8"))
                with open(KEY_PATH, "wb") as f:
                    f.write(key + b"\n")
                with open(METADATA_PATH, "wb") as f:
                    f.write(encrypted)
                shutil.copy2(binary, ARTIFACT_PATH)

                run_submission()
                report = load_and_validate_report()
                for field, expected_value in expected.items():
                    assert report[field] is expected_value, (
                        f"For controlled input, expected {field}={expected_value}, "
                        f"but got {report[field]}."
                    )
        finally:
            for path, backup in backups.items():
                shutil.copy2(backup, path)
            run_submission()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
