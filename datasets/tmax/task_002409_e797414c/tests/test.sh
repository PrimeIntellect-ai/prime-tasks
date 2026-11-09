#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import json
import pytest


def test_audit_report_content():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"Audit report missing: {report_path}"

    with open(report_path, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    expected_ip = "172.16.8.99"
    expected_file = "/home/user/.ssh/authorized_keys"
    expected_comment = "pwned@hacker.net"

    assert report_data.get("attacker_ip") == expected_ip, f"Expected attacker_ip to be '{expected_ip}', got '{report_data.get('attacker_ip')}'"
    assert report_data.get("compromised_file") == expected_file, f"Expected compromised_file to be '{expected_file}', got '{report_data.get('compromised_file')}'"
    assert report_data.get("removed_ssh_key_comment") == expected_comment, f"Expected removed_ssh_key_comment to be '{expected_comment}', got '{report_data.get('removed_ssh_key_comment')}'"


def test_authorized_keys_remediated():
    keys_path = "/home/user/.ssh/authorized_keys"
    assert os.path.isfile(keys_path), f"File missing: {keys_path}"

    with open(keys_path, "r") as f:
        contents = f.read()

    lines = contents.splitlines()
    has_admin = any("admin@corp.local" in line for line in lines)
    has_attacker = any("pwned@hacker.net" in line for line in lines)

    assert has_admin, "Legitimate key (admin@corp.local) was incorrectly removed from authorized_keys."
    assert not has_attacker, "Attacker key (pwned@hacker.net) is still present in authorized_keys."

    legitimate_key = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQC3... admin@corp.local"
    attacker_key_material = "AAAAC3NzaC1lZDI1NTE5AAAAIAxx..."
    active_lines = [line.strip() for line in lines if line.strip() and not line.lstrip().startswith("#")]

    assert active_lines == [legitimate_key], (
        "authorized_keys must contain exactly the original legitimate admin key and no other active entries."
    )
    assert attacker_key_material not in contents, (
        "The attacker's SSH key material remains in authorized_keys, possibly with a changed comment."
    )


def test_upload_script_permissions():
    script_path = "/home/user/webapp/cgi-bin/upload.sh"
    assert os.path.isfile(script_path), f"File missing: {script_path}"

    st = os.stat(script_path)
    permissions = stat.S_IMODE(st.st_mode)
    assert permissions == 0o755, f"Permissions for {script_path} should be 755, but are {oct(permissions)}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
