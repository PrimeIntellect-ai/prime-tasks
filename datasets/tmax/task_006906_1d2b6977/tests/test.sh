#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat
import json
import pytest

def test_ssh_key_permissions():
    key_path = "/home/user/.ssh/id_rsa"
    assert os.path.isfile(key_path), f"{key_path} does not exist."

    st = os.stat(key_path)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions in (0o600, 0o400), f"Permissions for {key_path} are {oct(permissions)}, expected 0o600 or 0o400."

def test_audit_json_exists():
    audit_path = "/home/user/audit.json"
    assert os.path.isfile(audit_path), f"{audit_path} does not exist."

def test_audit_json_content():
    audit_path = "/home/user/audit.json"
    assert os.path.isfile(audit_path), f"{audit_path} does not exist."

    try:
        with open(audit_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"{audit_path} is not a valid JSON file.")

    assert "modified_file" in data, "Missing 'modified_file' in audit.json"
    assert data["modified_file"] == "server.py", f"Expected 'server.py' for modified_file, got {data['modified_file']}"

    assert "injection_line_number" in data, "Missing 'injection_line_number' in audit.json"
    assert data["injection_line_number"] == 4, f"Expected injection_line_number to be 4, got {data['injection_line_number']}"

    assert "xss_line_number" in data, "Missing 'xss_line_number' in audit.json"
    assert data["xss_line_number"] == 4, f"Expected xss_line_number to be 4, got {data['xss_line_number']}"

    assert "ssh_permissions_fixed" in data, "Missing 'ssh_permissions_fixed' in audit.json"
    assert data["ssh_permissions_fixed"] is True, f"Expected ssh_permissions_fixed to be true, got {data['ssh_permissions_fixed']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
