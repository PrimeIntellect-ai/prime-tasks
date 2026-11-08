#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import subprocess
import tempfile

import pytest

SCRIPT = "/home/user/analyze.py"
PAYLOAD = "/home/user/payload.bin"
CA = "/home/user/ca.crt"
REPORT = "/home/user/report.json"


def run_submission():
    if os.path.exists(REPORT):
        os.remove(REPORT)

    try:
        result = subprocess.run(
            ["python3", SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("analyze.py did not finish within 30 seconds")

    assert result.returncode == 0, (
        f"analyze.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_original_analysis():
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist."
    run_submission()


def load_report():
    assert os.path.isfile(REPORT), f"The report file {REPORT} does not exist."
    try:
        with open(REPORT, "r") as f:
            return json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT} does not contain valid JSON.")


def test_analyze_script_exists():
    """Verify that the analyze.py script was created."""
    assert os.path.isfile(SCRIPT), f"The script {SCRIPT} does not exist."


def test_report_json_exists():
    """Verify that the report.json file was generated."""
    assert os.path.isfile(REPORT), f"The report file {REPORT} does not exist."


def test_report_json_content():
    """Verify the contents of the report.json file match the expected schema and values."""
    data = load_report()

    expected_keys = {"subject_cn", "is_valid_ca", "privesc_command"}
    assert set(data.keys()) == expected_keys, f"The JSON schema is incorrect. Expected keys: {expected_keys}, found: {set(data.keys())}"

    assert data["subject_cn"] == "EvilCorp", f"Incorrect subject_cn. Expected 'EvilCorp', got '{data['subject_cn']}'"
    assert data["is_valid_ca"] is False, f"Incorrect is_valid_ca. Expected False, got {data['is_valid_ca']}"
    assert data["privesc_command"] == "sudo chmod u+s /bin/bash", f"Incorrect privesc_command. Expected 'sudo chmod u+s /bin/bash', got '{data['privesc_command']}'"


def test_analyzes_changed_payload_and_ca():
    token = secrets.token_hex(8)
    expected_cn = f"AuditLeaf-{token}"
    root_cn = f"AuditRoot-{token}"
    expected_command = f"sudo chmod 4755 /tmp/audit-{token}"

    with open(PAYLOAD, "rb") as f:
        original_payload = f.read()
    with open(CA, "rb") as f:
        original_ca = f.read()
    with open(REPORT, "rb") as f:
        original_report = f.read()

    try:
        with tempfile.TemporaryDirectory() as td:
            root_key = os.path.join(td, "root.key")
            root_cert = os.path.join(td, "root.crt")
            leaf_key = os.path.join(td, "leaf.key")
            leaf_csr = os.path.join(td, "leaf.csr")
            leaf_cert = os.path.join(td, "leaf.crt")
            source = os.path.join(td, "payload.c")
            binary = os.path.join(td, "payload.bin")

            subprocess.run([
                "openssl", "req", "-x509", "-newkey", "rsa:2048",
                "-keyout", root_key, "-out", root_cert, "-days", "2",
                "-nodes", "-subj", f"/CN={root_cn}",
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([
                "openssl", "req", "-newkey", "rsa:2048",
                "-keyout", leaf_key, "-out", leaf_csr, "-nodes",
                "-subj", f"/CN={expected_cn}",
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
            subprocess.run([
                "openssl", "x509", "-req", "-in", leaf_csr,
                "-CA", root_cert, "-CAkey", root_key, "-CAcreateserial",
                "-out", leaf_cert, "-days", "2",
            ], check=True, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

            with open(source, "w") as f:
                f.write(
                    '#include <stdio.h>\n'
                    f'const char privesc[] = "{expected_command}";\n'
                    'int main(void) { puts("Executing payload..."); return 0; }\n'
                )

            subprocess.run(["gcc", "-o", binary, source], check=True)
            subprocess.run([
                "objcopy", "--add-section", f".malcert={leaf_cert}",
                "--set-section-flags", ".malcert=noload,readonly", binary,
            ], check=True)

            shutil.copyfile(binary, PAYLOAD)
            shutil.copyfile(root_cert, CA)
            os.chmod(PAYLOAD, 0o644)
            os.chmod(CA, 0o644)

            run_submission()
            data = load_report()
            expected_keys = {"subject_cn", "is_valid_ca", "privesc_command"}
            assert set(data.keys()) == expected_keys
            assert data["subject_cn"] == expected_cn
            assert data["is_valid_ca"] is True
            assert data["privesc_command"] == expected_command
    finally:
        with open(PAYLOAD, "wb") as f:
            f.write(original_payload)
        with open(CA, "wb") as f:
            f.write(original_ca)
        with open(REPORT, "wb") as f:
            f.write(original_report)
        os.chmod(PAYLOAD, 0o777)
        os.chmod(CA, 0o777)
        os.chmod(REPORT, 0o777)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
