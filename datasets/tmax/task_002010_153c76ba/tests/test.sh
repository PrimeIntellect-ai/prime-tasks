#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
from collections import defaultdict

REDACTED_LOG_PATH = '/home/user/audit_trail_redacted.log'
BLOCK_IPS_PATH = '/home/user/block_ips.sh'

EXPECTED_RAW_CONTENT = """[2023-10-01T10:00:01] | IP: 192.168.1.50 | Port: 22 | User: admin@corp.com | Pass: P@ssw0rd123 | Status: Failed
[2023-10-01T10:00:05] | IP: 10.0.0.5 | Port: 8080 | User: test@demo.org | Pass: 123456 | Status: Failed
[2023-10-01T10:00:10] | IP: 10.0.0.5 | Port: 8080 | User: test@demo.org | Pass: password | Status: Failed
[2023-10-01T10:00:15] | IP: 10.0.0.5 | Port: 8080 | User: test@demo.org | Pass: admin | Status: Failed
[2023-10-01T10:00:20] | IP: 192.168.1.100 | Port: 22 | User: root@system.net | Pass: toor | Status: Success
[2023-10-01T10:01:00] | IP: 172.16.0.4 | Port: 443 | User: alice@wonderland.com | Pass: qweqwe | Status: Failed
[2023-10-01T10:01:05] | IP: 172.16.0.4 | Port: 443 | User: bob@wonderland.com | Pass: asdasd | Status: Failed
[2023-10-01T10:01:10] | IP: 172.16.0.4 | Port: 443 | User: charlie@wonderland.com | Pass: zxczxc | Status: Failed
[2023-10-01T10:01:15] | IP: 172.16.0.4 | Port: 443 | User: dave@wonderland.com | Pass: 111111 | Status: Failed"""

def get_expected_redacted():
    expected_lines = []
    for line in EXPECTED_RAW_CONTENT.strip().split('\n'):
        # Redact email domain (replace everything after @ up to the next space/boundary with ***)
        line = re.sub(r'(User: [^@]+)@[^ ]+', r'\1@***', line)
        # Redact password (replace everything between 'Pass: ' and ' | ' with ***)
        line = re.sub(r'(Pass: ).+?( \|)', r'\g<1>***\2', line)
        expected_lines.append(line)
    return "\n".join(expected_lines)

def get_expected_block_ips():
    failures = defaultdict(int)
    for line in EXPECTED_RAW_CONTENT.strip().split('\n'):
        if 'Status: Failed' in line:
            match = re.search(r'IP: ([0-9\.]+)', line)
            if match:
                failures[match.group(1)] += 1

    blocked_ips = [ip for ip, count in failures.items() if count >= 3]
    blocked_ips.sort()

    return "\n".join(f"iptables -A INPUT -s {ip} -j DROP" for ip in blocked_ips)

def test_redacted_log_exists_and_correct():
    assert os.path.exists(REDACTED_LOG_PATH), f"The redacted log file {REDACTED_LOG_PATH} was not created."

    with open(REDACTED_LOG_PATH, 'r') as f:
        content = f.read().strip()

    expected_content = get_expected_redacted()

    assert content == expected_content, (
        f"The content of {REDACTED_LOG_PATH} does not match the expected redacted output.\n"
        f"Expected:\n{expected_content}\n\nGot:\n{content}"
    )

def test_block_ips_script_exists_and_correct():
    assert os.path.exists(BLOCK_IPS_PATH), f"The block IPs script {BLOCK_IPS_PATH} was not created."

    with open(BLOCK_IPS_PATH, 'r') as f:
        content = f.read().strip()

    expected_content = get_expected_block_ips()

    assert content == expected_content, (
        f"The content of {BLOCK_IPS_PATH} does not match the expected bash script output.\n"
        f"Expected:\n{expected_content}\n\nGot:\n{content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
