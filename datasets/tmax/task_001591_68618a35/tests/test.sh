#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import json
import os
import re
import secrets
import subprocess

import pytest

HOME = "/home/user"
REPORT = os.path.join(HOME, "audit_report.json")
INPUTS = [
    os.path.join(HOME, "access.log"),
    os.path.join(HOME, "shadow_leak.txt"),
    os.path.join(HOME, "wordlist.txt"),
    os.path.join(HOME, "sudoers_audit.txt"),
]


def test_01_audit_report_exists_and_valid():
    assert os.path.isfile(REPORT), f"The file {REPORT} does not exist. Ensure your script generated it."

    with open(REPORT, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {REPORT} does not contain valid JSON.")

    expected_keys = {"attacker_ip", "cracked_password", "privesc_command"}
    missing_keys = expected_keys - set(report_data.keys())
    assert not missing_keys, f"The JSON report is missing the following required keys: {missing_keys}"

    assert report_data["attacker_ip"] == "10.0.0.55", \
        f"Expected attacker_ip to be '10.0.0.55', but got '{report_data['attacker_ip']}'."

    assert report_data["cracked_password"] == "compliance2023", \
        f"Expected cracked_password to be 'compliance2023', but got '{report_data['cracked_password']}'."

    assert report_data["privesc_command"] == "/usr/bin/tar", \
        f"Expected privesc_command to be '/usr/bin/tar', but got '{report_data['privesc_command']}'."


def find_python_scripts():
    candidates = []
    ignored_dirs = {".cache", ".local", ".git", "__pycache__", "venv", ".venv"}
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if d not in ignored_dirs]
        for name in files:
            path = os.path.join(root, name)
            if path == REPORT or path in INPUTS or not os.path.isfile(path):
                continue
            try:
                with open(path, "rb") as f:
                    raw = f.read(1024 * 1024 + 1)
                if len(raw) > 1024 * 1024:
                    continue
                text = raw.decode("utf-8")
                has_python_name = name.endswith(".py")
                has_python_shebang = text.startswith("#!") and "python" in text.splitlines()[0].lower()
                if not (has_python_name or has_python_shebang):
                    continue
                ast.parse(text, filename=path)
                candidates.append(path)
            except (OSError, UnicodeDecodeError, SyntaxError):
                continue
    return sorted(candidates)


def derive_expected():
    attacker_ip = None
    with open(INPUTS[0], "r") as f:
        for line in f:
            match = re.match(r'^(\S+).*"GET /admin/keys\.zip HTTP/[^" ]+"\s+200(?:\s|$)', line)
            if match:
                attacker_ip = match.group(1)
                break

    target_hash = None
    with open(INPUTS[1], "r") as f:
        for line in f:
            username, digest = line.strip().split(":", 1)
            if username == "audit_usr":
                target_hash = digest
                break

    cracked_password = None
    with open(INPUTS[2], "r") as f:
        for line in f:
            candidate = line.rstrip("\r\n")
            if hashlib.sha256(candidate.encode()).hexdigest() == target_hash:
                cracked_password = candidate
                break

    privesc_command = None
    with open(INPUTS[3], "r") as f:
        for line in f:
            match = re.match(r'^\s*audit_usr\s+ALL=\(root\)\s+NOPASSWD:\s*(/\S+)\s*$', line)
            if match:
                privesc_command = match.group(1)
                break

    assert attacker_ip and cracked_password and privesc_command
    return {
        "attacker_ip": attacker_ip,
        "cracked_password": cracked_password,
        "privesc_command": privesc_command,
    }


def test_02_python_script_recomputes_report_from_inputs():
    scripts = find_python_scripts()
    assert scripts, "No Python script was found under /home/user."

    originals = {path: open(path, "rb").read() for path in INPUTS}
    original_report = open(REPORT, "rb").read() if os.path.isfile(REPORT) else None

    token = secrets.token_hex(6)
    dynamic_password = "Audit" + secrets.token_hex(8)
    fixtures = {
        INPUTS[0]: (
            '192.0.2.10 - - [11/Sep/2026:10:00:00 +0000] "GET /index.html HTTP/1.1" 200 100\n'
            '198.51.100.23 - - [11/Sep/2026:10:01:00 +0000] "GET /admin/keys.zip HTTP/1.1" 403 20\n'
            f'10.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1}.{secrets.randbelow(200) + 1} - - [11/Sep/2026:10:02:00 +0000] "GET /admin/keys.zip HTTP/1.1" 200 9000\n'
        ).encode(),
        INPUTS[1]: (
            'root:e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855\n'
            f'audit_usr:{hashlib.sha256(dynamic_password.encode()).hexdigest()}\n'
        ).encode(),
        INPUTS[2]: (
            'password123\nincorrect-value\n' + dynamic_password + '\nchangeme\n'
        ).encode(),
        INPUTS[3]: (
            'root ALL=(ALL:ALL) ALL\n'
            '%sudo ALL=(ALL:ALL) ALL\n'
            f'audit_usr ALL=(root) NOPASSWD: /usr/bin/audit_tool_{token}\n'
        ).encode(),
    }

    errors = []
    matched_script = None
    try:
        for script in scripts:
            for path, content in fixtures.items():
                with open(path, "wb") as f:
                    f.write(content)
            if os.path.exists(REPORT):
                os.remove(REPORT)

            expected = derive_expected()
            try:
                result = subprocess.run(
                    ["python3", script],
                    cwd=HOME,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    text=True,
                    timeout=10,
                )
            except subprocess.TimeoutExpired:
                errors.append(f"{script}: timed out")
                continue

            if result.returncode != 0:
                errors.append(f"{script}: exited with status {result.returncode}")
                continue
            if not os.path.isfile(REPORT):
                errors.append(f"{script}: did not create {REPORT}")
                continue
            try:
                with open(REPORT, "r") as f:
                    data = json.load(f)
            except (OSError, json.JSONDecodeError) as exc:
                errors.append(f"{script}: created an invalid report ({exc})")
                continue

            required = {"attacker_ip", "cracked_password", "privesc_command"}
            if required - set(data.keys()):
                errors.append(f"{script}: report is missing required keys")
                continue
            if all(data[key] == value for key, value in expected.items()):
                matched_script = script
                break
            errors.append(f"{script}: report values were not derived from the modified inputs")
    finally:
        for path, content in originals.items():
            with open(path, "wb") as f:
                f.write(content)
        if original_report is None:
            if os.path.exists(REPORT):
                os.remove(REPORT)
        else:
            with open(REPORT, "wb") as f:
                f.write(original_report)

    assert matched_script is not None, "No submitted Python script generated the correct report from changed inputs. " + "; ".join(errors)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
