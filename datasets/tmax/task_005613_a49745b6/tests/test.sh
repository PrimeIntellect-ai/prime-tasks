#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def get_expected_ip():
    log_path = "/home/user/app_requests.log"
    assert os.path.exists(log_path), f"Missing {log_path} required to derive expected IP."

    with open(log_path, "r") as f:
        for line in f:
            if not line.strip():
                continue
            try:
                entry = json.loads(line)
                cookie = entry.get("headers", {}).get("Cookie", "")
                if "auth_bypass=" in cookie:
                    return entry.get("ip")
            except json.JSONDecodeError:
                continue
    pytest.fail("Could not derive expected attacker_ip from app_requests.log")

def get_expected_password():
    proc_dir = "/home/user/proc_dump"
    assert os.path.exists(proc_dir), f"Missing {proc_dir} required to derive expected password."

    for pid in os.listdir(proc_dir):
        cmdline_path = os.path.join(proc_dir, pid, "cmdline")
        if os.path.isfile(cmdline_path):
            with open(cmdline_path, "rb") as f:
                content = f.read()
                args = content.split(b'\x00')
                # Remove empty trailing elements if any
                args = [a.decode('utf-8') for a in args if a]
                if any("backend_worker.py" in a for a in args):
                    # Usually: python3, /home/user/backend_worker.py, admin_user, password
                    if len(args) >= 4:
                        return args[3]
    pytest.fail("Could not derive expected leaked_password from proc_dump")

def test_compliance_audit_json():
    audit_file = "/home/user/compliance_audit.json"
    assert os.path.isfile(audit_file), f"The file {audit_file} does not exist."

    with open(audit_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {audit_file} does not contain valid JSON.")

    assert isinstance(data, dict), f"The JSON in {audit_file} must be an object."

    expected_ip = get_expected_ip()
    expected_password = get_expected_password()
    expected_cwe = "CWE-214"

    assert "attacker_ip" in data, f"Missing 'attacker_ip' key in {audit_file}."
    assert data["attacker_ip"] == expected_ip, f"Incorrect attacker_ip. Expected {expected_ip}, got {data['attacker_ip']}."

    assert "cwe_id" in data, f"Missing 'cwe_id' key in {audit_file}."
    assert isinstance(data["cwe_id"], str), "cwe_id must be a string."
    assert data["cwe_id"].upper() == expected_cwe, f"Incorrect cwe_id. Expected {expected_cwe}, got {data['cwe_id']}."

    assert "leaked_password" in data, f"Missing 'leaked_password' key in {audit_file}."
    assert data["leaked_password"] == expected_password, f"Incorrect leaked_password. Expected {expected_password}, got {data['leaked_password']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
