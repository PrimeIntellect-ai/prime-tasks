#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import crypt
import json
import os
import secrets
import shutil
import stat
import subprocess
from pathlib import Path

import pytest

SCRIPT = Path("/home/user/policy_tester.py")
REPORT = Path("/home/user/audit_report.json")
INPUTS = [
    Path("/home/user/sshd_config_test"),
    Path("/home/user/iptables_export.txt"),
    Path("/home/user/shadow_test"),
    Path("/home/user/wordlist.txt"),
]


def remove_path(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def write_case(case):
    for path, content in case["files"].items():
        remove_path(path)
        path.write_text(content, encoding="utf-8")
        path.chmod(0o644)


def run_and_check_case(case):
    remove_path(REPORT)
    result = subprocess.run(
        ["python3", str(SCRIPT)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"policy_tester.py exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert REPORT.is_file(), "Executing policy_tester.py did not create audit_report.json"
    try:
        data = json.loads(REPORT.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        pytest.fail(f"Executing policy_tester.py produced invalid JSON: {exc}")

    expected = case["expected"]
    assert set(data.keys()) == set(expected.keys())
    for key, value in expected.items():
        assert isinstance(data[key], list), f"{key} must be an array"
        assert data[key] == sorted(data[key]), f"{key} must be sorted alphabetically"
        assert data[key] == value, f"{key} mismatch. Expected: {value}, Found: {data[key]}"


def test_policy_script_exists_and_executes_real_analysis():
    assert SCRIPT.exists(), f"Missing required script: {SCRIPT}"
    assert stat.S_ISREG(SCRIPT.lstat().st_mode), f"{SCRIPT} must be a regular file"
    assert SCRIPT.stat().st_size > 0, f"{SCRIPT} is empty"

    compiled = subprocess.run(
        ["python3", "-m", "py_compile", str(SCRIPT)],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    assert compiled.returncode == 0, f"policy_tester.py is not valid Python: {compiled.stderr}"

    for path in INPUTS:
        assert path.is_file(), f"Missing required input file: {path}"

    backups = {
        path: (path.read_bytes(), stat.S_IMODE(path.stat().st_mode))
        for path in INPUTS
    }

    token = secrets.token_hex(8)
    cracked_user = f"audit_{token}"
    cracked_password = f"CrackMe_{token}"
    cracked_hash = crypt.crypt(cracked_password, crypt.mksalt(crypt.METHOD_SHA512))
    unlisted_password = f"NotListed_{secrets.token_hex(8)}"
    unlisted_hash = crypt.crypt(unlisted_password, crypt.mksalt(crypt.METHOD_SHA512))
    unauthorized_port = str(secrets.randbelow(30000) + 20000)

    cases = [
        {
            "files": {
                Path("/home/user/sshd_config_test"): (
                    "Port 22\nPermitRootLogin no\nPasswordAuthentication no\n"
                ),
                Path("/home/user/iptables_export.txt"): (
                    "-P INPUT DROP\n-P FORWARD DROP\n-P OUTPUT ACCEPT\n"
                    "-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT\n"
                ),
                Path("/home/user/wordlist.txt"): (
                    f"irrelevant_{token}\n{cracked_password}\nanother_{token}\n"
                ),
                Path("/home/user/shadow_test"): (
                    f"root:*::::::\n{cracked_user}:{cracked_hash}:18000:0:99999:7:::\n"
                ),
            },
            "expected": {
                "ssh_violations": [],
                "firewall_violations": [],
                "compromised_users": [cracked_user],
            },
        },
        {
            "files": {
                Path("/home/user/sshd_config_test"): (
                    "Port 22\nPermitRootLogin prohibit-password\n"
                    "# PasswordAuthentication no\n"
                ),
                Path("/home/user/iptables_export.txt"): (
                    "-P INPUT ACCEPT\n-P FORWARD DROP\n-P OUTPUT ACCEPT\n"
                    "-A INPUT -p tcp -m tcp --dport 22 -j ACCEPT\n"
                    f"-A INPUT -p tcp -m tcp --dport {unauthorized_port} -j ACCEPT\n"
                ),
                Path("/home/user/wordlist.txt"): (
                    f"wrong_{token}\nstill_wrong_{token}\n"
                ),
                Path("/home/user/shadow_test"): (
                    f"root:*::::::\nuncaught_{token}:{unlisted_hash}:18000:0:99999:7:::\n"
                ),
            },
            "expected": {
                "ssh_violations": ["PasswordAuthentication", "PermitRootLogin"],
                "firewall_violations": [
                    "INPUT policy is not DROP",
                    f"Unauthorized port {unauthorized_port} ACCEPT",
                ],
                "compromised_users": [],
            },
        },
    ]

    final_result = None
    try:
        for case in cases:
            write_case(case)
            run_and_check_case(case)
    finally:
        for path, (content, mode) in backups.items():
            remove_path(path)
            path.write_bytes(content)
            path.chmod(mode)
        remove_path(REPORT)
        final_result = subprocess.run(
            ["python3", str(SCRIPT)],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=60,
        )

    assert final_result.returncode == 0, (
        "policy_tester.py failed on the shipped inputs after behavioral testing.\n"
        f"stdout:\n{final_result.stdout}\nstderr:\n{final_result.stderr}"
    )
    assert REPORT.is_file(), "policy_tester.py did not generate the final audit_report.json"


def get_expected_ssh_violations():
    violations = []
    settings = {}

    if os.path.exists("/home/user/sshd_config_test"):
        with open("/home/user/sshd_config_test", "r") as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith("#"):
                    parts = line.split()
                    if len(parts) >= 2:
                        settings[parts[0]] = parts[1]

    if settings.get("PermitRootLogin") != "no":
        violations.append("PermitRootLogin")
    if settings.get("PasswordAuthentication") != "no":
        violations.append("PasswordAuthentication")

    return sorted(violations)


def get_expected_firewall_violations():
    violations = []

    if os.path.exists("/home/user/iptables_export.txt"):
        with open("/home/user/iptables_export.txt", "r") as f:
            for line in f:
                line = line.strip()
                if line.startswith("-P INPUT"):
                    if not line.endswith("DROP"):
                        violations.append("INPUT policy is not DROP")
                elif line.startswith("-A INPUT"):
                    if "-p tcp" in line and "--dport" in line and "-j ACCEPT" in line:
                        parts = line.split()
                        try:
                            dport_idx = parts.index("--dport")
                            port = parts[dport_idx + 1]
                            if port != "22":
                                violations.append(f"Unauthorized port {port} ACCEPT")
                        except (ValueError, IndexError):
                            pass
    return sorted(violations)


def get_expected_compromised_users():
    words = []
    if os.path.exists("/home/user/wordlist.txt"):
        with open("/home/user/wordlist.txt", "r") as f:
            words = [w.strip() for w in f.readlines() if w.strip()]

    compromised = []
    if os.path.exists("/home/user/shadow_test"):
        with open("/home/user/shadow_test", "r") as f:
            for line in f:
                parts = line.strip().split(":")
                if len(parts) >= 2:
                    user = parts[0]
                    hash_val = parts[1]
                    if hash_val not in ("*", "!") and len(hash_val) > 10:
                        for word in words:
                            if crypt.crypt(word, hash_val) == hash_val:
                                compromised.append(user)
                                break
    return sorted(compromised)


def test_audit_report_exists():
    path = "/home/user/audit_report.json"
    assert os.path.isfile(path), f"Missing file: {path}. The script must generate the JSON report."


def test_audit_report_structure_and_content():
    path = "/home/user/audit_report.json"
    assert os.path.isfile(path), "Cannot test content because audit_report.json is missing."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {path} does not contain valid JSON.")

    expected_keys = {"ssh_violations", "firewall_violations", "compromised_users"}
    assert set(data.keys()) == expected_keys, f"JSON keys do not match the required structure. Expected: {expected_keys}, Found: {set(data.keys())}"

    expected_ssh = get_expected_ssh_violations()
    expected_firewall = get_expected_firewall_violations()
    expected_users = get_expected_compromised_users()

    actual_ssh = sorted(data["ssh_violations"])
    actual_firewall = sorted(data["firewall_violations"])
    actual_users = sorted(data["compromised_users"])

    assert actual_ssh == expected_ssh, f"ssh_violations mismatch. Expected: {expected_ssh}, Found: {actual_ssh}"
    assert actual_firewall == expected_firewall, f"firewall_violations mismatch. Expected: {expected_firewall}, Found: {actual_firewall}"
    assert actual_users == expected_users, f"compromised_users mismatch. Expected: {expected_users}, Found: {actual_users}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
