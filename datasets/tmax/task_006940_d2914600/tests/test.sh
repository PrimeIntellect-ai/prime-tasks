#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import hashlib
import base64
import re
import pytest

EVIDENCE_FILE = "/home/user/forensics/evidence.txt"
LOG_FILE = "/home/user/forensics/logs/http_req.log"
SYSTEM_ROOT = "/home/user/forensics/system_root"

ORIGINAL_SUID_PATH = "/home/user/forensics/system_root/var/log/.hidden_shell"
ORIGINAL_SUID_BYTES = b'int main(){ setuid(0); system("/bin/bash"); return 0; }\n'
ORIGINAL_LOG_BYTES = b'''GET /index.html HTTP/1.1
Host: www.example.com
User-Agent: Mozilla/5.0
Cookie: session_id=8472948293

POST /login HTTP/1.1
Host: www.example.com
User-Agent: Mozilla/5.0
Cookie: session_id=8472948293

GET /images/logo.png HTTP/1.1
Host: www.example.com
User-Agent: curl/7.68.0
Cookie: MalCookie=YWRtaW5fcGFzc3dvcmQ9SDBudDNyU2VjcmV0IQ==

GET /about.html HTTP/1.1
Host: www.example.com
User-Agent: Mozilla/5.0
Cookie: session_id=9938472911
'''


def find_suid_binary(root_dir):
    for dirpath, _, filenames in os.walk(root_dir):
        for filename in filenames:
            filepath = os.path.join(dirpath, filename)
            if os.path.isfile(filepath):
                st = os.stat(filepath)
                if st.st_mode & 0o4000:
                    return filepath
    return None


def get_file_sha256(filepath):
    sha256 = hashlib.sha256()
    with open(filepath, "rb") as f:
        sha256.update(f.read())
    return sha256.hexdigest()


def extract_and_decode_malcookie(log_path):
    with open(log_path, "r") as f:
        content = f.read()

    match = re.search(r"Cookie:\s*MalCookie=([A-Za-z0-9+/=]+)", content)
    if match:
        encoded_val = match.group(1)
        return base64.b64decode(encoded_val).decode('utf-8')
    return None


def trusted_exfil_data():
    match = re.search(rb"Cookie:\s*MalCookie=([A-Za-z0-9+/=]+)", ORIGINAL_LOG_BYTES)
    assert match is not None
    return base64.b64decode(match.group(1)).decode("utf-8")


def test_original_evidence_is_intact():
    suid_stat = os.lstat(ORIGINAL_SUID_PATH)
    assert stat.S_ISREG(suid_stat.st_mode), "Original SUID fixture is not a regular file."
    assert suid_stat.st_uid == 0, "Original SUID fixture is no longer root-owned."
    assert stat.S_IMODE(suid_stat.st_mode) == 0o4755, "Original SUID fixture permissions were changed."
    with open(ORIGINAL_SUID_PATH, "rb") as f:
        assert f.read() == ORIGINAL_SUID_BYTES, "Original SUID fixture contents were changed."

    log_stat = os.lstat(LOG_FILE)
    assert stat.S_ISREG(log_stat.st_mode), "HTTP evidence log is not a regular file."
    assert log_stat.st_uid == 0, "HTTP evidence log is no longer root-owned."
    with open(LOG_FILE, "rb") as f:
        assert f.read() == ORIGINAL_LOG_BYTES, "HTTP evidence log contents were changed."


def test_evidence_file_exists():
    assert os.path.isfile(EVIDENCE_FILE), f"The evidence file {EVIDENCE_FILE} does not exist."


def test_evidence_file_contents():
    assert os.path.isfile(EVIDENCE_FILE), f"The evidence file {EVIDENCE_FILE} does not exist."

    # Preserve the original checks derived from the currently mounted artifacts.
    suid_binary_path = find_suid_binary(SYSTEM_ROOT)
    assert suid_binary_path is not None, "Could not find SUID binary in system_root to compute expected truth."

    expected_hash = get_file_sha256(suid_binary_path)
    expected_exfil = extract_and_decode_malcookie(LOG_FILE)
    assert expected_exfil is not None, "Could not extract MalCookie from logs to compute expected truth."

    expected_lines = [
        f"SUID_BINARY: {suid_binary_path}",
        f"SUID_HASH: {expected_hash}",
        f"EXFIL_DATA: {expected_exfil}"
    ]

    with open(EVIDENCE_FILE, "r") as f:
        actual_content = f.read()

    actual_lines = [line.strip() for line in actual_content.strip().split("\n") if line.strip()]

    assert len(actual_lines) == 3, f"Evidence file should have exactly 3 lines, found {len(actual_lines)}."
    assert actual_lines[0] == expected_lines[0], f"First line mismatch. Expected: '{expected_lines[0]}', Got: '{actual_lines[0]}'"
    assert actual_lines[1] == expected_lines[1], f"Second line mismatch. Expected: '{expected_lines[1]}', Got: '{actual_lines[1]}'"
    assert actual_lines[2] == expected_lines[2], f"Third line mismatch. Expected: '{expected_lines[2]}', Got: '{actual_lines[2]}'"

    # Also compare against immutable oracle data so mutable evidence cannot redefine truth.
    trusted_lines = [
        f"SUID_BINARY: {ORIGINAL_SUID_PATH}",
        f"SUID_HASH: {hashlib.sha256(ORIGINAL_SUID_BYTES).hexdigest()}",
        f"EXFIL_DATA: {trusted_exfil_data()}"
    ]
    assert actual_lines == trusted_lines, "Report does not match the originally supplied forensic evidence."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
