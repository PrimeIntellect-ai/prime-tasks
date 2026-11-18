#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import json
import hashlib
import subprocess
import pytest

RAW_LOGS_PATH = '/home/user/raw_logs.txt'
WORDLIST_PATH = '/home/user/wordlist.txt'
SCRIPT_PATH = '/home/user/policy_enforcer.py'
REDACTED_LOGS_PATH = '/home/user/redacted_logs.txt'
SECURITY_REPORT_PATH = '/home/user/security_report.json'

def get_expected_redacted_logs():
    with open(RAW_LOGS_PATH, 'r') as f:
        raw_logs = f.read()

    # Replace any 4 groups of 4 digits separated by hyphens with [REDACTED]
    redacted_logs = re.sub(r'\b\d{4}-\d{4}-\d{4}-\d{4}\b', '[REDACTED]', raw_logs)
    return redacted_logs

def get_expected_security_report():
    with open(RAW_LOGS_PATH, 'r') as f:
        lines = f.readlines()

    with open(WORDLIST_PATH, 'r') as f:
        words = [line.strip() for line in f if line.strip()]

    ip_malicious_counts = {}
    hashes_found = set()

    malicious_patterns = [
        re.compile(r'<script>', re.IGNORECASE),
        re.compile(r"' or '1'='1", re.IGNORECASE)
    ]

    for line in lines:
        # Parse log line: [TIMESTAMP] [IP] [LEVEL] MESSAGE
        match = re.match(r'^\[.*?\]\s+\[(.*?)\]\s+\[.*?\]\s+(.*)$', line)
        if match:
            ip = match.group(1)
            message = match.group(2)

            # Check for malicious requests
            is_malicious = any(p.search(message) for p in malicious_patterns)
            if is_malicious:
                ip_malicious_counts[ip] = ip_malicious_counts.get(ip, 0) + 1

            # Check for leaked hashes
            hash_match = re.search(r'Auth failed: hash=([a-fA-F0-9]{32})', message)
            if hash_match:
                hashes_found.add(hash_match.group(1))

    blocked_ips = sorted([ip for ip, count in ip_malicious_counts.items() if count >= 3])

    weak_passwords = {}
    for word in words:
        word_hash = hashlib.md5(word.encode('utf-8')).hexdigest()
        if word_hash in hashes_found:
            weak_passwords[word_hash] = word

    return {
        "blocked_ips": blocked_ips,
        "weak_passwords": weak_passwords
    }

def test_policy_enforcer_exists_and_processes_inputs():
    assert os.path.isfile(SCRIPT_PATH), f"The required Python script {SCRIPT_PATH} was not created."

    paths = [RAW_LOGS_PATH, WORDLIST_PATH, REDACTED_LOGS_PATH, SECURITY_REPORT_PATH]
    backups = {}
    for path in paths:
        if os.path.exists(path):
            with open(path, 'rb') as f:
                backups[path] = f.read()
        else:
            backups[path] = None

    swordfish_hash = hashlib.md5(b'swordfish').hexdigest()
    alpha_hash = hashlib.md5(b'alpha').hexdigest()
    unknown_hash = hashlib.md5(b'not-in-wordlist').hexdigest()
    challenge_logs = (
        '[2026-01-01T00:00:00] [203.0.113.9] [INFO] Card 1111-2222-3333-4444 accepted\n'
        '[2026-01-01T00:00:01] [203.0.113.9] [WARN] Input: <ScRiPt>alert(1)</script>\n'
        "[2026-01-01T00:00:02] [203.0.113.9] [WARN] Query: ' OR '1'='1\n"
        '[2026-01-01T00:00:03] [203.0.113.9] [WARN] Again: <script>x</script>\n'
        '[2026-01-01T00:00:04] [198.51.100.2] [WARN] Input: <script>x</script>\n'
        "[2026-01-01T00:00:05] [198.51.100.2] [WARN] Query: ' or '1'='1\n"
        f'[2026-01-01T00:00:06] [192.0.2.1] [DEBUG] Auth failed: hash={swordfish_hash}\n'
        f'[2026-01-01T00:00:07] [192.0.2.2] [DEBUG] Auth failed: hash={alpha_hash}\n'
        f'[2026-01-01T00:00:08] [192.0.2.3] [DEBUG] Auth failed: hash={unknown_hash}\n'
        '[2026-01-01T00:00:09] [192.0.2.4] [INFO] Cards 5555-6666-7777-8888 and 9999-0000-1111-2222\n'
    )

    try:
        with open(RAW_LOGS_PATH, 'w') as f:
            f.write(challenge_logs)
        with open(WORDLIST_PATH, 'w') as f:
            f.write('alpha\nswordfish\nother\n')

        expected_redacted = get_expected_redacted_logs()
        expected_report = get_expected_security_report()

        for path in (REDACTED_LOGS_PATH, SECURITY_REPORT_PATH):
            if os.path.exists(path):
                os.remove(path)

        result = subprocess.run(
            ['python3', SCRIPT_PATH],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Running {SCRIPT_PATH} failed with exit code {result.returncode}. "
            f"stderr: {result.stderr}"
        )
        assert os.path.exists(REDACTED_LOGS_PATH), f"Running {SCRIPT_PATH} did not create {REDACTED_LOGS_PATH}."
        assert os.path.exists(SECURITY_REPORT_PATH), f"Running {SCRIPT_PATH} did not create {SECURITY_REPORT_PATH}."

        with open(REDACTED_LOGS_PATH, 'r') as f:
            actual_redacted = f.read()
        assert actual_redacted == expected_redacted, "The policy enforcer did not correctly redact the supplied logs."

        with open(SECURITY_REPORT_PATH, 'r') as f:
            try:
                actual_report = json.load(f)
            except json.JSONDecodeError:
                pytest.fail(f"Running {SCRIPT_PATH} produced an invalid JSON security report.")
        assert actual_report == expected_report, "The policy enforcer did not correctly analyze the supplied logs."
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, 'wb') as f:
                    f.write(content)

def test_redacted_logs():
    assert os.path.exists(REDACTED_LOGS_PATH), f"The file {REDACTED_LOGS_PATH} was not created."

    expected_content = get_expected_redacted_logs()

    with open(REDACTED_LOGS_PATH, 'r') as f:
        actual_content = f.read()

    assert actual_content == expected_content, "The redacted logs do not match the expected output. Ensure exact formatting and line order are maintained, and all CC numbers are replaced with '[REDACTED]'."

def test_security_report():
    assert os.path.exists(SECURITY_REPORT_PATH), f"The file {SECURITY_REPORT_PATH} was not created."

    with open(SECURITY_REPORT_PATH, 'r') as f:
        try:
            actual_report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {SECURITY_REPORT_PATH} does not contain valid JSON.")

    expected_report = get_expected_security_report()

    assert "blocked_ips" in actual_report, "The security report is missing the 'blocked_ips' key."
    assert "weak_passwords" in actual_report, "The security report is missing the 'weak_passwords' key."

    assert isinstance(actual_report["blocked_ips"], list), "'blocked_ips' should be a list."
    assert isinstance(actual_report["weak_passwords"], dict), "'weak_passwords' should be a dictionary."

    assert sorted(actual_report["blocked_ips"]) == expected_report["blocked_ips"], "The 'blocked_ips' list does not match the expected IPs with 3 or more malicious requests."
    assert actual_report["weak_passwords"] == expected_report["weak_passwords"], "The 'weak_passwords' dictionary does not match the expected cracked hashes."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
