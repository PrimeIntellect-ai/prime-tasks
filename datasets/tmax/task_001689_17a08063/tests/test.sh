#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os

EXPECTED_ORIGINAL = '''May 10 10:00:01 kernel: [    0.000000] Linux version 5.15.0
May 10 10:05:22 sshd[102]: Failed password for root from 192.168.1.15 port 22
May 10 10:05:25 sshd[102]: Failed password for invalid user admin from 10.0.5.99 port 22 ssh2
May 10 10:06:00 bash[200]: command logged: echo "-----BEGIN OPENSSH PRIVATE KEY-----
b3BlbnNzaC1rZXktdjEAAAAABG5vbmUAAAAEbm9uZQAAAAAAAAABAAAAMwAAAAtzc2gtZW
QyNTUxOQAAACD+L8M5X/w1...
-----END OPENSSH PRIVATE KEY-----" > /tmp/key
May 10 10:07:00 sshd[105]: Failed password for bob from 192.168.1.15 port 22
May 10 10:08:15 sshd[108]: Accepted publickey for dev from 10.0.5.100 port 22
May 10 10:10:00 bash[205]: command logged: cat /root/.ssh/id_ed25519
-----BEGIN OPENSSH PRIVATE KEY-----
xyz123abc...
-----END OPENSSH PRIVATE KEY-----
May 10 10:12:00 systemd[1]: Started cron utility.
'''


def redact_private_key_blocks(content):
    output = []
    in_key = False

    for line in content.splitlines(keepends=True):
        if not in_key and "-----BEGIN OPENSSH PRIVATE KEY-----" in line:
            output.append("[REDACTED]\n")
            if "-----END OPENSSH PRIVATE KEY-----" not in line:
                in_key = True
            continue

        if in_key:
            if "-----END OPENSSH PRIVATE KEY-----" in line:
                in_key = False
            continue

        output.append(line)

    assert not in_key, "Test fixture contains an unterminated private-key block."
    return "".join(output)


def test_blocked_ips_created_and_correct():
    """Test that blocked_ips.txt contains the correct unique IPs."""
    blocked_ips_path = '/home/user/blocked_ips.txt'
    assert os.path.isfile(blocked_ips_path), f"File {blocked_ips_path} is missing."

    with open(blocked_ips_path, 'r') as f:
        content = f.read().strip()

    ips = [line.strip() for line in content.splitlines() if line.strip()]
    expected_ips = ["10.0.5.99", "192.168.1.15"]

    assert sorted(ips) == expected_ips, f"Expected IPs {expected_ips}, but got {sorted(ips)}"
    assert len(ips) == len(set(ips)), "Duplicate IPs found in blocked_ips.txt"


def test_syslog_redacted_created_and_correct():
    """Test that syslog_redacted.txt is created and correctly redacts private keys."""
    redacted_syslog_path = '/home/user/syslog_redacted.txt'
    original_syslog_path = '/home/user/syslog.txt'

    assert os.path.isfile(redacted_syslog_path), f"File {redacted_syslog_path} is missing."

    with open(redacted_syslog_path, 'r') as f:
        redacted_content = f.read()

    # Keep the original sensitive-data assertions.
    assert "BEGIN OPENSSH PRIVATE KEY" not in redacted_content, "Found 'BEGIN OPENSSH PRIVATE KEY' in redacted syslog."
    assert "END OPENSSH PRIVATE KEY" not in redacted_content, "Found 'END OPENSSH PRIVATE KEY' in redacted syslog."
    assert "b3BlbnNzaC1rZXktdjE" not in redacted_content, "Found key body data in redacted syslog."

    assert "[REDACTED]" in redacted_content, "The string '[REDACTED]' was not found in the redacted syslog."

    assert "Linux version 5.15.0" in redacted_content, "Original non-sensitive lines were altered or removed."
    assert "Failed password for root from 192.168.1.15" in redacted_content, "Original non-sensitive lines were altered or removed."
    assert "Started cron utility." in redacted_content, "Original non-sensitive lines were altered or removed."

    assert os.path.isfile(original_syslog_path), f"File {original_syslog_path} is missing."
    with open(original_syslog_path, 'r') as f:
        original_content = f.read()

    assert "BEGIN OPENSSH PRIVATE KEY" in original_content, "The original syslog.txt file was modified."
    assert original_content == EXPECTED_ORIGINAL, "The original syslog.txt file was modified."

    expected_redacted = redact_private_key_blocks(EXPECTED_ORIGINAL)
    assert redacted_content == expected_redacted, (
        "syslog_redacted.txt must preserve every non-sensitive line exactly and "
        "replace each complete private-key block with exactly one [REDACTED] line."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
