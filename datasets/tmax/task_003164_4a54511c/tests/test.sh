#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import hashlib
import pytest
from collections import defaultdict

REPORT_FILE = "/home/user/compliance_report.csv"
AUDIT_DIR = "/home/user/audit_data"

def derive_expected_data():
    # 1. Parse syslog.log to find compromised accounts
    syslog_path = os.path.join(AUDIT_DIR, "syslog.log")
    failed_attempts = defaultdict(lambda: defaultdict(int))
    accepted_attempts = defaultdict(set)

    with open(syslog_path, 'r') as f:
        for line in f:
            parts = line.split()
            if "Failed password for" in line:
                user_idx = parts.index("for") + 1
                user = parts[user_idx]
                ip_idx = parts.index("from") + 1
                ip = parts[ip_idx]
                failed_attempts[user][ip] += 1
            elif "Accepted password for" in line:
                user_idx = parts.index("for") + 1
                user = parts[user_idx]
                ip_idx = parts.index("from") + 1
                ip = parts[ip_idx]
                accepted_attempts[user].add(ip)

    compromised = {}
    for user, ips in failed_attempts.items():
        for ip, count in ips.items():
            if count >= 3 and ip in accepted_attempts[user]:
                compromised[user] = ip

    # 2. Extract hashes and crack passwords
    shadow_path = os.path.join(AUDIT_DIR, "shadow.bak")
    hashes = {}
    with open(shadow_path, 'r') as f:
        for line in f:
            if ':' in line:
                user, h = line.strip().split(':', 1)
                hashes[user] = h

    wordlist_path = os.path.join(AUDIT_DIR, "wordlist.txt")
    words = []
    with open(wordlist_path, 'r') as f:
        words = [line.strip() for line in f if line.strip()]

    cracked = {}
    for user in compromised:
        user_hash = hashes.get(user)
        for word in words:
            if hashlib.md5(word.encode()).hexdigest() == user_hash:
                cracked[user] = word
                break

    # 3. Map UIDs and find listening ports
    passwd_path = os.path.join(AUDIT_DIR, "passwd.bak")
    uids = {}
    with open(passwd_path, 'r') as f:
        for line in f:
            parts = line.strip().split(':')
            if len(parts) >= 3:
                uids[parts[0]] = parts[2]

    netstat_path = os.path.join(AUDIT_DIR, "netstat.txt")
    ports = {}
    with open(netstat_path, 'r') as f:
        for line in f:
            if "LISTEN" in line:
                parts = line.split()
                # tcp 0 0 0.0.0.0:4444 0.0.0.0:* LISTEN 1002 12346 -
                local_addr = parts[3]
                port = local_addr.split(':')[-1]
                uid = parts[6]
                ports[uid] = port

    # 4. Correlate
    results = []
    for user in sorted(compromised.keys()):
        ip = compromised[user]
        password = cracked.get(user, "")
        uid = uids.get(user, "")
        port = ports.get(uid, "")
        results.append({
            "Username": user,
            "Attacker_IP": ip,
            "Cracked_Password": password,
            "Listening_Port": port
        })

    return results

def test_report_exists():
    assert os.path.isfile(REPORT_FILE), f"The report file {REPORT_FILE} was not found."

def test_report_content():
    expected_data = derive_expected_data()

    with open(REPORT_FILE, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"The report file {REPORT_FILE} is empty."

    header = rows[0]
    expected_header = ["Username", "Attacker_IP", "Cracked_Password", "Listening_Port"]
    assert header == expected_header, f"Header is incorrect. Expected {expected_header}, got {header}."

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, but found {len(data_rows)}."

    for i, expected_row in enumerate(expected_data):
        actual_row = data_rows[i]
        assert actual_row[0] == expected_row["Username"], f"Row {i+1}: Expected Username '{expected_row['Username']}', got '{actual_row[0]}'."
        assert actual_row[1] == expected_row["Attacker_IP"], f"Row {i+1}: Expected Attacker_IP '{expected_row['Attacker_IP']}', got '{actual_row[1]}'."
        assert actual_row[2] == expected_row["Cracked_Password"], f"Row {i+1}: Expected Cracked_Password '{expected_row['Cracked_Password']}', got '{actual_row[2]}'."
        assert actual_row[3] == expected_row["Listening_Port"], f"Row {i+1}: Expected Listening_Port '{expected_row['Listening_Port']}', got '{actual_row[3]}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
