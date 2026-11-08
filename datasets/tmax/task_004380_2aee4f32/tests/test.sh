#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import json
import csv
import subprocess
import pytest

def get_expected_data():
    csv_path = "/home/user/logs/login_attempts.csv"
    if not os.path.exists(csv_path):
        return [], []

    failed_counts = {}
    with open(csv_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    for row in rows:
        if row["status"] == "FAILED":
            ip = row["ip_address"]
            failed_counts[ip] = failed_counts.get(ip, 0) + 1

    flagged_ips = [ip for ip, count in failed_counts.items() if count >= 4]

    flagged_rows = [row for row in rows if row["status"] == "FAILED" and row["ip_address"] in flagged_ips]

    return sorted(flagged_ips), flagged_rows

def test_block_rules_script():
    script_path = "/home/user/network_policy/block_rules.sh"
    assert os.path.isfile(script_path), f"File {script_path} does not exist."

    flagged_ips, _ = get_expected_data()

    expected_lines = [f"iptables -A INPUT -s {ip} -j DROP" for ip in flagged_ips]

    with open(script_path, "r") as f:
        content = f.read()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    actual_rule_lines = [
        line for line in actual_lines
        if line == "iptables" or line.startswith("iptables ")
    ]

    assert actual_rule_lines == expected_lines, f"Contents of {script_path} do not contain the expected iptables rules in the correct order."

def test_permissions():
    files_to_check = [
        ("/home/user/secure_archive", 0o700),
        ("/home/user/secure_archive/audit_report.enc", 0o400),
        ("/home/user/keys/audit.key", 0o400),
        ("/home/user/network_policy/block_rules.sh", 0o744)
    ]

    for path, expected_mode in files_to_check:
        assert os.path.exists(path), f"Path {path} does not exist."
        st = os.stat(path)
        actual_mode = stat.S_IMODE(st.st_mode)
        assert actual_mode == expected_mode, f"Permissions for {path} are {oct(actual_mode)}, expected {oct(expected_mode)}."

def test_encrypted_audit_report():
    enc_path = "/home/user/secure_archive/audit_report.enc"
    key_path = "/home/user/keys/audit.key"

    assert os.path.isfile(enc_path), f"Encrypted report {enc_path} does not exist."
    assert os.path.isfile(key_path), f"Key file {key_path} does not exist."

    # We use subprocess to decrypt to avoid importing third-party libraries directly in the test file
    decrypt_script = f"""
import sys
try:
    from cryptography.fernet import Fernet
except ImportError:
    print("cryptography library not installed", file=sys.stderr)
    sys.exit(1)

with open('{key_path}', 'rb') as f:
    key = f.read().strip()

with open('{enc_path}', 'rb') as f:
    enc_data = f.read().strip()

try:
    fernet = Fernet(key)
    dec_data = fernet.decrypt(enc_data)
    print(dec_data.decode('utf-8'))
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(2)
"""

    result = subprocess.run(["python3", "-c", decrypt_script], capture_output=True, text=True)

    assert result.returncode == 0, f"Failed to decrypt {enc_path}. Error: {result.stderr.strip()}"

    try:
        decrypted_json = json.loads(result.stdout.strip())
    except json.JSONDecodeError:
        pytest.fail("Decrypted data is not valid JSON.")

    _, expected_rows = get_expected_data()

    assert isinstance(decrypted_json, list), "Decrypted JSON must be a list of objects."
    assert len(decrypted_json) == len(expected_rows), "Number of records in encrypted JSON does not match expected."

    # Sort both lists of dicts to compare safely
    def sort_key(d):
        return (d.get("timestamp", ""), d.get("ip_address", ""), d.get("username", ""))

    assert sorted(decrypted_json, key=sort_key) == sorted(expected_rows, key=sort_key), "Decrypted records do not match the expected flagged FAILED attempts."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
