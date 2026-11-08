#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import re
import stat
import subprocess
import tempfile

import pytest


def compute_expected_pin() -> str:
    target_hash = 0x1337CFEB
    for i in range(10000):
        pin = f"{i:04d}"
        h = 0x1337BEEF
        for char in pin:
            h = ((h << 4) ^ (h >> 28) ^ ord(char)) & 0xFFFFFFFF
        if h == target_hash:
            return pin
    pytest.fail("Test setup error: Could not compute expected PIN.")


@pytest.fixture(scope="session")
def expected_data():
    pin = compute_expected_pin()
    payload = f"{pin}:DUMP_AUDIT"
    payload_base64 = base64.b64encode(payload.encode("utf-8")).decode("utf-8")
    return {
        "pin": pin,
        "payload_base64": payload_base64,
        "valid_cwes": {"CWE-798", "CWE-259"},
    }


def test_bruteforce_source_compiles_and_finds_pin(expected_data):
    source = "/home/user/bruteforce.c"
    assert os.path.lexists(source), f"The required C source file {source} is missing."
    assert not os.path.islink(source), f"{source} must be an actual C source file, not a symbolic link."
    source_stat = os.stat(source)
    assert stat.S_ISREG(source_stat.st_mode), f"{source} is not a regular file."
    assert source_stat.st_size > 0, f"{source} is empty."

    with tempfile.TemporaryDirectory(prefix="verify_bruteforce_") as tmpdir:
        executable = os.path.join(tmpdir, "bruteforce")
        build = subprocess.run(
            ["gcc", "-std=c11", "-O2", source, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert build.returncode == 0, (
            f"{source} did not compile successfully with gcc.\n"
            f"Compiler output:\n{build.stdout}{build.stderr}"
        )

        run = subprocess.run(
            [executable],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert run.returncode == 0, (
            "The compiled brute-force program did not execute successfully.\n"
            f"Program output:\n{run.stdout}{run.stderr}"
        )
        output = run.stdout + "\n" + run.stderr
        assert re.search(rf"(?<!\d){re.escape(expected_data['pin'])}(?!\d)", output), (
            "The compiled brute-force program did not report the PIN obtained by "
            "brute-forcing the discovered custom hash."
        )


def test_audit_trail_log_created_by_legacy_processor(expected_data):
    processor = "/home/user/legacy_processor"
    log_path = "/home/user/audit_trail.log"
    assert os.path.isfile(processor), f"The legacy processor {processor} is missing."

    if os.path.lexists(log_path):
        if os.path.isdir(log_path) and not os.path.islink(log_path):
            pytest.fail(f"The expected log path {log_path} is a directory.")
        os.unlink(log_path)

    result = subprocess.run(
        [processor, expected_data["payload_base64"]],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        "legacy_processor did not accept the correct base64 payload.\n"
        f"Program output:\n{result.stdout}{result.stderr}"
    )
    assert os.path.exists(log_path), (
        f"The audit log {log_path} was not created. "
        "Ensure you successfully executed the legacy_processor binary with the correct base64 payload."
    )

    with open(log_path, "r") as f:
        content = f.read()

    expected_msg = "AUDIT_SUCCESS: COMPLIANCE_DATA_EXTRACTED"
    assert expected_msg in content, (
        f"The audit log {log_path} exists but does not contain the expected success message. "
        f"Expected to find '{expected_msg}'."
    )


def test_compliance_audit_json(expected_data):
    json_path = "/home/user/compliance_audit.json"
    assert os.path.exists(json_path), f"The final report file {json_path} is missing."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"The file {json_path} does not contain valid JSON. Error: {e}")

    assert "pin" in data, f"The JSON file {json_path} is missing the 'pin' key."
    assert data["pin"] == expected_data["pin"], (
        "The submitted PIN is incorrect. "
        "Expected the 4-digit string that hashes to 0x1337cfeb."
    )

    assert "payload_base64" in data, f"The JSON file {json_path} is missing the 'payload_base64' key."
    assert data["payload_base64"] == expected_data["payload_base64"], (
        "The submitted base64 payload is incorrect. "
        "Ensure it is exactly the base64 encoding of '[PIN]:DUMP_AUDIT'."
    )

    assert "cwe_id" in data, f"The JSON file {json_path} is missing the 'cwe_id' key."
    assert data["cwe_id"] in expected_data["valid_cwes"], (
        f"The submitted CWE ID '{data['cwe_id']}' is incorrect. "
        "Expected the standard CWE identifier for 'Use of Hard-coded Credentials' (e.g., CWE-798)."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
