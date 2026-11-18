#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import hashlib
import subprocess
import pytest
import re
import secrets
import string
import random


def get_expected_attacker_ip():
    access_log_path = "/home/user/incident/logs/access.log"
    if not os.path.exists(access_log_path):
        return None
    with open(access_log_path, "r") as f:
        for line in f:
            if ".." in line and " 200 " in line:
                return line.split()[0]
    return None


def get_expected_compromised_user(attacker_ip):
    auth_log_path = "/home/user/incident/logs/auth.log"
    if not os.path.exists(auth_log_path) or not attacker_ip:
        return None
    with open(auth_log_path, "r") as f:
        for line in f:
            if "Accepted " in line and attacker_ip in line:
                parts = line.split()
                try:
                    user_index = parts.index("for") + 1
                    return parts[user_index]
                except ValueError:
                    continue
    return None


def get_expected_corrupted_files():
    backups_dir = "/home/user/incident/backups"
    current_dir = "/home/user/incident/current"
    corrupted = []
    if not os.path.exists(backups_dir) or not os.path.exists(current_dir):
        return corrupted

    for filename in os.listdir(backups_dir):
        backup_path = os.path.join(backups_dir, filename)
        current_path = os.path.join(current_dir, filename)
        if os.path.isfile(backup_path) and os.path.isfile(current_path):
            with open(backup_path, "rb") as b, open(current_path, "rb") as c:
                if hashlib.sha256(b.read()).hexdigest() != hashlib.sha256(c.read()).hexdigest():
                    corrupted.append(filename)
    return sorted(corrupted)


def test_audit_report_exists_and_valid():
    report_path = "/home/user/incident/audit_report.json"
    assert os.path.isfile(report_path), f"Audit report not found at {report_path}"

    with open(report_path, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Audit report is not valid JSON")

    attacker_ip = get_expected_attacker_ip()
    assert report_data.get("attacker_ip") == attacker_ip, f"Expected attacker_ip {attacker_ip}, got {report_data.get('attacker_ip')}"

    compromised_user = get_expected_compromised_user(attacker_ip)
    assert report_data.get("compromised_user") == compromised_user, f"Expected compromised_user {compromised_user}, got {report_data.get('compromised_user')}"

    assert report_data.get("cwe_id") == "CWE-22", f"Expected cwe_id CWE-22, got {report_data.get('cwe_id')}"

    corrupted_files = get_expected_corrupted_files()
    assert report_data.get("corrupted_files") == corrupted_files, f"Expected corrupted_files {corrupted_files}, got {report_data.get('corrupted_files')}"


def test_script_patched_invalid_input():
    script_path = "/home/user/incident/cgi-bin/download.sh"
    assert os.path.isfile(script_path), f"Script not found at {script_path}"
    assert os.access(script_path, os.X_OK), "Script is not executable"

    invalid_inputs = [
        "../etc/passwd",
        "/etc/shadow",
        "file;id",
        "test|ls",
        "invalid!name"
    ]

    for invalid in invalid_inputs:
        result = subprocess.run([script_path, invalid], capture_output=True, text=True)
        assert result.returncode == 1, f"Script did not exit with code 1 for invalid input: {invalid}"
        assert "Invalid filename" in result.stdout or "Invalid filename" in result.stderr, f"Script did not output 'Invalid filename' for input: {invalid}"


def test_script_patched_valid_input():
    script_path = "/home/user/incident/cgi-bin/download.sh"

    valid_inputs = [
        "report.pdf",
        "valid_file_name.123"
    ]

    os.makedirs("/var/www/uploads", exist_ok=True)
    for valid in valid_inputs:
        dummy_path = f"/var/www/uploads/{valid}"
        with open(dummy_path, "w") as f:
            f.write("test")

        result = subprocess.run([script_path, valid], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed (exit code {result.returncode}) for valid input: {valid}"
        assert "Invalid filename" not in result.stdout and "Invalid filename" not in result.stderr, f"Script rejected valid input: {valid}"

        if os.path.exists(dummy_path):
            os.remove(dummy_path)


def expected_valid_filename(name):
    return re.fullmatch(r"[A-Za-z0-9_.]+", name) is not None and ".." not in name


def test_script_enforces_complete_allowlist_on_generated_inputs():
    script_path = "/home/user/incident/cgi-bin/download.sh"
    upload_dir = "/var/www/uploads"
    os.makedirs(upload_dir, exist_ok=True)

    token = "verify_" + secrets.token_hex(10)
    allowed_chars = string.ascii_letters + string.digits + "_."
    allowed_set = set(allowed_chars)

    cases = []

    # Exercise every disallowed non-NUL ASCII character in an otherwise
    # unpredictable filename. This includes spaces, hyphens, @, shell
    # metacharacters, controls, and slash.
    for codepoint in range(1, 128):
        char = chr(codepoint)
        if char not in allowed_set:
            cases.append(token + "x" + char + "y")

    # Non-ASCII characters are outside the explicit ASCII allowlist.
    for _ in range(16):
        cases.append(token + "u" + chr(0x100 + secrets.randbelow(0x700)) + "z")

    # Period is allowed individually, but every occurrence of '..' is not.
    cases.extend([
        token + "..tail",
        token + "a..b",
        token + "...tail",
        token + "dir/../" + token + "target",
    ])

    # Generate unpredictable allowed names using the same predicate used to
    # derive the expected result, avoiding accidental '..' sequences.
    for _ in range(40):
        while True:
            name = token + "_" + "".join(secrets.choice(allowed_chars) for _ in range(24))
            if expected_valid_filename(name):
                cases.append(name)
                break

    # Make each target exist where possible so invalid cases cannot pass merely
    # because cat failed on a missing path.
    for name in cases:
        target = os.path.join(upload_dir, name)
        try:
            os.makedirs(os.path.dirname(target), exist_ok=True)
            with open(target, "w") as f:
                f.write("generated test payload")
        except (IsADirectoryError, NotADirectoryError):
            pass

    random.SystemRandom().shuffle(cases)
    for name in cases:
        result = subprocess.run(
            [script_path, name], capture_output=True, text=True, timeout=5
        )
        combined_output = result.stdout + result.stderr
        if expected_valid_filename(name):
            assert result.returncode == 0, f"Script rejected allowed generated filename {name!r} with code {result.returncode}"
            assert "Invalid filename" not in combined_output, f"Script marked allowed generated filename invalid: {name!r}"
        else:
            assert result.returncode == 1, f"Script accepted disallowed generated filename {name!r} with code {result.returncode}"
            assert "Invalid filename" in combined_output, f"Script did not report Invalid filename for {name!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
