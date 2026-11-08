#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import subprocess
import pytest

REPORT_PATH = "/home/user/vuln_report.json"
GENERATOR_PATH = "/home/user/generate_report.rs"
MAIN_RS_PATH = "/home/user/target_system/src/main.rs"
RELEASES_PATH = "/home/user/target_system/releases.txt"
SUDOERS_PATH = "/home/user/target_system/config/sudoers_rules"

@pytest.fixture(scope="session", autouse=True)
def compile_and_run_report_generator():
    """Compile and execute the submitted Rust generator from a clean report state."""
    assert os.path.exists(GENERATOR_PATH), f"Report generator source not found at {GENERATOR_PATH}"
    assert os.path.isfile(GENERATOR_PATH), f"Report generator is not a file: {GENERATOR_PATH}"

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    generator_bin = "/tmp/generate_report_test"
    if os.path.exists(generator_bin):
        os.remove(generator_bin)

    compile_proc = subprocess.run(
        ["rustc", GENERATOR_PATH, "-o", generator_bin],
        capture_output=True,
        text=True
    )
    assert compile_proc.returncode == 0, \
        f"Failed to compile {GENERATOR_PATH}:\n{compile_proc.stderr}"

    try:
        run_proc = subprocess.run(
            [generator_bin],
            cwd="/home/user",
            capture_output=True,
            text=True
        )
        assert run_proc.returncode == 0, \
            f"Report generator failed:\nstdout:\n{run_proc.stdout}\nstderr:\n{run_proc.stderr}"
        assert os.path.isfile(REPORT_PATH), \
            f"Executing the Rust generator did not create {REPORT_PATH}"
    finally:
        if os.path.exists(generator_bin):
            os.remove(generator_bin)

def get_report_data():
    assert os.path.exists(REPORT_PATH), f"Report file not found at {REPORT_PATH}"
    with open(REPORT_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

def test_generate_report_script_exists():
    """Verify the student created the Rust report generator."""
    assert os.path.exists(GENERATOR_PATH), f"Report generator source not found at {GENERATOR_PATH}"

def test_report_version_is_correct():
    """Dynamically verify the version matches the hash of main.rs."""
    report = get_report_data()
    assert "version" in report, "Report missing 'version' key."

    assert os.path.exists(MAIN_RS_PATH), f"Missing {MAIN_RS_PATH}"
    with open(MAIN_RS_PATH, "rb") as f:
        actual_hash = hashlib.sha256(f.read()).hexdigest()

    assert os.path.exists(RELEASES_PATH), f"Missing {RELEASES_PATH}"
    expected_version = None
    with open(RELEASES_PATH, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 2 and parts[0] == actual_hash:
                expected_version = parts[1]
                break

    assert expected_version is not None, "Could not find matching hash in releases.txt (setup issue)."
    assert report["version"] == expected_version, f"Expected version '{expected_version}', but got '{report['version']}'."

def test_report_vulnerability_type():
    """Verify the vulnerability type is identified as command injection."""
    report = get_report_data()
    assert "vulnerability" in report, "Report missing 'vulnerability' key."

    vuln = report["vulnerability"].lower().replace("_", " ")
    assert "command" in vuln and "injection" in vuln, \
        f"Expected vulnerability to be 'command injection', got '{report['vulnerability']}'."

def test_report_escalation_user():
    """Verify the target escalation user is correctly identified from sudoers."""
    report = get_report_data()
    assert "escalation_user" in report, "Report missing 'escalation_user' key."

    assert os.path.exists(SUDOERS_PATH), f"Missing {SUDOERS_PATH}"
    expected_user = None
    with open(SUDOERS_PATH, "r") as f:
        for line in f:
            if line.strip() and not line.startswith("#"):
                if "(" in line and ")" in line:
                    expected_user = line.split("(")[1].split(")")[0]
                    break

    assert expected_user is not None, "Could not find target user in sudoers_rules (setup issue)."
    assert report["escalation_user"] == expected_user, \
        f"Expected escalation user '{expected_user}', but got '{report['escalation_user']}'."

def test_report_poc_payload_structure():
    """Verify the PoC payload contains the required command and comment character."""
    report = get_report_data()
    assert "poc_payload" in report, "Report missing 'poc_payload' key."

    payload = report["poc_payload"]
    assert "whoami > /tmp/pwned" in payload, "Payload does not contain 'whoami > /tmp/pwned'."
    assert "#" in payload, "Payload does not contain '#' to comment out trailing bash syntax."

def test_report_poc_payload_execution():
    """Verify the payload successfully exploits the vulnerable binary."""
    report = get_report_data()
    payload = report.get("poc_payload", "")

    pwned_file = "/tmp/pwned"
    if os.path.exists(pwned_file):
        os.remove(pwned_file)

    vuln_bin = "/tmp/vuln_bin_test"

    compile_proc = subprocess.run(
        ["rustc", MAIN_RS_PATH, "-o", vuln_bin],
        capture_output=True,
        text=True
    )
    assert compile_proc.returncode == 0, f"Failed to compile {MAIN_RS_PATH}:\n{compile_proc.stderr}"

    subprocess.run([vuln_bin, payload], capture_output=True)

    assert os.path.exists(pwned_file), \
        "The payload was executed, but /tmp/pwned was not created. The injection failed."

    if os.path.exists(pwned_file):
        os.remove(pwned_file)
    if os.path.exists(vuln_bin):
        os.remove(vuln_bin)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
