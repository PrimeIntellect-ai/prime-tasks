#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import stat
import subprocess
from pathlib import Path

import pytest


def read_nonempty_lines(path):
    with open(path, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def expected_ssh_findings(config_path):
    settings = {}
    with open(config_path, "r") as f:
        for raw_line in f:
            line = raw_line.split("#", 1)[0].strip()
            if not line:
                continue
            parts = line.split()
            if len(parts) < 2:
                continue
            directive = parts[0].lower()
            # OpenSSH uses the first obtained value for a keyword.
            if directive in ("permitrootlogin", "passwordauthentication"):
                settings.setdefault(directive, parts[1].lower())

    findings = []
    if settings.get("permitrootlogin") == "yes":
        findings.append("FAILED: PermitRootLogin")
    if settings.get("passwordauthentication") == "yes":
        findings.append("FAILED: PasswordAuthentication")
    return findings


def expected_vulnerable_keys(keys_dir):
    vulnerable = []
    for entry in Path(keys_dir).iterdir():
        if not entry.name.startswith("id_rsa") or not entry.is_file():
            continue
        if entry.stat().st_mode & stat.S_IROTH:
            vulnerable.append(str(entry.resolve()))
    return sorted(vulnerable)


def test_ssh_audit_log():
    config_path = "/home/user/audit/sshd_config"
    log_path = "/home/user/ssh_audit.log"
    assert os.path.isfile(config_path), f"The file {config_path} does not exist."
    assert os.path.isfile(log_path), f"The file {log_path} does not exist."

    lines = read_nonempty_lines(log_path)

    # Preserve the original fixture assertions.
    assert "FAILED: PermitRootLogin" in lines, "Missing 'FAILED: PermitRootLogin' in ssh_audit.log"
    assert "FAILED: PasswordAuthentication" in lines, "Missing 'FAILED: PasswordAuthentication' in ssh_audit.log"

    expected = expected_ssh_findings(config_path)
    assert sorted(lines) == sorted(expected), (
        f"ssh_audit.log must contain exactly the findings derived from {config_path}; "
        f"expected {expected}, got {lines}"
    )


def test_vuln_keys_log():
    keys_dir = "/home/user/audit/keys"
    log_path = "/home/user/vuln_keys.log"
    assert os.path.isdir(keys_dir), f"The directory {keys_dir} does not exist."
    assert os.path.isfile(log_path), f"The file {log_path} does not exist."

    lines = read_nonempty_lines(log_path)

    # Preserve the original fixture assertions.
    expected_vuln_key = "/home/user/audit/keys/id_rsa_weak"
    assert expected_vuln_key in lines, f"Missing '{expected_vuln_key}' in vuln_keys.log"
    for not_vuln in ["/home/user/audit/keys/id_rsa_prod", "/home/user/audit/keys/id_rsa_dev"]:
        assert not_vuln not in lines, f"Non-vulnerable key '{not_vuln}' should not be in vuln_keys.log"

    expected = expected_vulnerable_keys(keys_dir)
    assert sorted(lines) == expected, (
        f"vuln_keys.log must contain exactly the world-readable id_rsa* files; "
        f"expected {expected}, got {lines}"
    )


def test_payload_txt():
    service_path = "/home/user/audit/auth_service.py"
    payload_path = "/home/user/payload.txt"
    assert os.path.isfile(service_path), f"The file {service_path} does not exist."
    assert os.path.isfile(payload_path), f"The file {payload_path} does not exist."

    with open(payload_path, "r") as f:
        encoded = f.read().strip()

    try:
        decoded = base64.b64decode(encoded).decode("utf-8")
    except Exception as e:
        pytest.fail(f"Failed to base64 decode the payload: {e}")

    try:
        data = json.loads(decoded)
    except Exception as e:
        pytest.fail(f"Failed to JSON parse the decoded payload: {e}")

    # Preserve the original payload assertions.
    assert data.get("username") == "auditor", "Payload JSON does not have 'username' set to 'auditor'"
    assert data.get("role") == "admin", "Payload JSON does not have 'role' set to 'admin'"

    result = subprocess.run(
        ["python3", service_path, payload_path],
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"auth_service.py exited with status {result.returncode}: {result.stderr}"
    )
    assert result.stdout.strip() == "AUTH_SUCCESS", (
        f"The submitted payload did not authenticate through auth_service.py; "
        f"stdout was {result.stdout!r}, stderr was {result.stderr!r}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
