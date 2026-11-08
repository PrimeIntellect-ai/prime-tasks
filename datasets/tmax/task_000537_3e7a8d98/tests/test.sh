#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import pytest

def test_incident_report():
    report_path = "/home/user/incident_report.json"
    assert os.path.isfile(report_path), f"File {report_path} is missing."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{report_path} is not valid JSON.")

    expected_ip = "192.168.45.99"
    expected_payload = "../../../../home/user/.ssh/authorized_keys"

    assert isinstance(data, dict), "incident_report.json must contain a JSON object."
    assert set(data.keys()) == {"attacker_ip", "traversal_payload"}, "incident_report.json must contain exactly the two requested keys."

    assert "attacker_ip" in data, "Key 'attacker_ip' missing in incident_report.json."
    assert data["attacker_ip"] == expected_ip, f"Expected attacker_ip {expected_ip}, got {data['attacker_ip']}."

    assert "traversal_payload" in data, "Key 'traversal_payload' missing in incident_report.json."
    assert data["traversal_payload"] == expected_payload, f"Expected traversal_payload {expected_payload}, got {data['traversal_payload']}."

def test_admin_token():
    token_path = "/home/user/admin_token.txt"
    assert os.path.isfile(token_path), f"File {token_path} is missing."

    # Compute the expected token dynamically based on the logic provided
    username = "system_admin"
    key = "S3cr3tK3y"
    encoded = base64.b64encode(username.encode()).decode()
    token_str = "".join(chr(ord(encoded[i]) ^ ord(key[i % len(key)])) for i in range(len(encoded)))
    expected_token = base64.b64encode(token_str.encode()).decode()

    with open(token_path, "r") as f:
        actual_token = f.read().strip()

    assert actual_token == expected_token, f"Expected token {expected_token}, got {actual_token}."

def test_rogue_cert():
    cert_path = "/home/user/rogue_cert.txt"
    assert os.path.isfile(cert_path), f"File {cert_path} is missing."

    with open(cert_path, "r") as f:
        actual_cert = f.read().strip()

    expected_cert = "service_beta.pem"
    assert actual_cert == expected_cert, f"Expected rogue cert filename {expected_cert}, got {actual_cert}."

def test_hardened_sshd_config():
    config_path = "/home/user/hardened_sshd_config"
    assert os.path.isfile(config_path), f"File {config_path} is missing."

    with open(config_path, "r") as f:
        lines = [line.strip() for line in f if line.strip() and not line.strip().startswith("#")]

    expected_directives = {
        "PasswordAuthentication": "no",
        "PermitRootLogin": "no",
        "AllowUsers": "user"
    }

    parsed_directives = {}
    for line in lines:
        parts = line.split()
        if len(parts) >= 2:
            parsed_directives[parts[0]] = parts[1]

    for key, expected_val in expected_directives.items():
        assert key in parsed_directives, f"Directive {key} is missing in hardened_sshd_config."
        assert parsed_directives[key] == expected_val, f"Expected {key} to be {expected_val}, got {parsed_directives[key]}."

    assert len(lines) == 3, "hardened_sshd_config must contain exactly three directives."
    parsed_lines = []
    for line in lines:
        parts = line.split()
        assert len(parts) == 2, f"Invalid or extra content in SSH directive: {line}"
        parsed_lines.append((parts[0], parts[1]))
    assert set(parsed_lines) == set(expected_directives.items()), "hardened_sshd_config contains extra, duplicate, or incorrect directives."

def test_authorized_keys_cleaned():
    keys_path = "/home/user/.ssh/authorized_keys"
    assert os.path.isfile(keys_path), f"File {keys_path} is missing."

    with open(keys_path, "r") as f:
        content = f.read()

    assert "legitimate_user_key" in content, "Legitimate SSH key was removed from authorized_keys."
    assert "attacker_key_from_192.168.45.99" not in content, "Attacker SSH key was not removed from authorized_keys."

    expected_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQ... legitimate_user_key"
    assert content in (expected_key, expected_key + "\n"), "authorized_keys must preserve the complete legitimate key and contain no fabricated or extra entries."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
