#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import subprocess

EXPECTED_SOURCE = (
    '192.168.1.10 - - [10/Oct/2023:13:55:36 -0700] "GET /login?redirect_to=/home HTTP/1.1" 200 2326 session_id=abc123xyz\n'
    '10.0.0.5 - - [10/Oct/2023:13:56:10 -0700] "GET /login?redirect_to=https://evil.phish.com/login HTTP/1.1" 302 - session_id=def456uvw\n'
    '172.16.0.2 - - [10/Oct/2023:13:58:22 -0700] "GET /login?redirect_to=http://malware.site/download HTTP/1.1" 302 - session_id=ghi789rst\n'
    '192.168.1.11 - - [10/Oct/2023:14:01:05 -0700] "GET /login?redirect_to=/settings HTTP/1.1" 200 1542 session_id=jkl012mno\n'
)

AUTH_FILE = '/home/user/auth_logs.txt'
OUTPUT_FILES = [
    '/home/user/redacted_logs.txt',
    '/home/user/redirect_targets.txt',
    '/home/user/log_checksum.txt',
    '/home/user/poc.txt',
]


def redact(content):
    return re.sub(r'session_id=[A-Za-z0-9]+(?=\r?$)',
                  'session_id=[REDACTED]', content, flags=re.MULTILINE)


def read_text(path):
    with open(path, 'r', newline='') as f:
        return f.read()


def test_python_script_exists_and_performs_redaction():
    """Execute the submitted Python script on fresh input and verify its output."""
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        for name in files:
            path = os.path.join(root, name)
            if path in [AUTH_FILE] + OUTPUT_FILES or not os.path.isfile(path):
                continue
            is_python = name.endswith('.py')
            if not is_python:
                try:
                    with open(path, 'rb') as f:
                        is_python = b'python' in f.readline().lower()
                except OSError:
                    pass
            if is_python:
                candidates.append(path)

    assert candidates, 'No Python script was written under /home/user.'

    tracked = [AUTH_FILE] + OUTPUT_FILES
    snapshots = {}
    for path in tracked:
        if os.path.exists(path):
            with open(path, 'rb') as f:
                snapshots[path] = f.read()
        else:
            snapshots[path] = None

    token1 = secrets.token_hex(9)
    token2 = secrets.token_hex(11)
    synthetic = (
        '203.0.113.4 - - [11/Oct/2023:01:02:03 +0000] "GET /login?redirect_to=/home HTTP/1.1" 200 1 session_id=' + token1 + '\n'
        '198.51.100.9 - - [11/Oct/2023:01:03:04 +0000] "GET /login?redirect_to=https://example.net/a HTTP/1.1" 302 - session_id=' + token2 + '\n'
        '192.0.2.8 - - [11/Oct/2023:01:04:05 +0000] "POST /other HTTP/1.1" 200 2 session_id=A1B2C3D4\n'
        '192.0.2.10 - - [11/Oct/2023:01:05:06 +0000] "GET /login?redirect_to=http://example.org/b HTTP/1.1" 302 - session_id=Z9Y8X7\n'
    )
    expected = redact(synthetic)
    working_script = None

    try:
        for candidate in candidates:
            for path, data in snapshots.items():
                if data is None:
                    try:
                        os.remove(path)
                    except FileNotFoundError:
                        pass
                else:
                    with open(path, 'wb') as f:
                        f.write(data)

            with open(AUTH_FILE, 'w', newline='') as f:
                f.write(synthetic)
            try:
                os.remove('/home/user/redacted_logs.txt')
            except FileNotFoundError:
                pass

            try:
                result = subprocess.run(
                    ['python3', candidate],
                    cwd=os.path.dirname(candidate) or '/home/user',
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                    timeout=15,
                    check=False,
                )
            except (OSError, subprocess.TimeoutExpired):
                continue

            if result.returncode == 0 and os.path.isfile('/home/user/redacted_logs.txt'):
                try:
                    if read_text('/home/user/redacted_logs.txt') == expected:
                        working_script = candidate
                        break
                except (OSError, UnicodeError):
                    pass
    finally:
        for path, data in snapshots.items():
            if data is None:
                try:
                    os.remove(path)
                except FileNotFoundError:
                    pass
            else:
                with open(path, 'wb') as f:
                    f.write(data)

    assert working_script is not None, (
        'No submitted Python script correctly redacted fresh auth log input.'
    )


def test_redacted_logs_exists_and_content():
    """Test that redacted_logs.txt exactly preserves the source with tokens redacted."""
    redacted_file = '/home/user/redacted_logs.txt'
    assert os.path.isfile(redacted_file), f"File missing: {redacted_file}"
    assert os.path.isfile(AUTH_FILE), f"File missing: {AUTH_FILE}"

    source = read_text(AUTH_FILE)
    content = read_text(redacted_file)
    assert source == EXPECTED_SOURCE, 'auth_logs.txt was modified.'
    assert content == redact(source), (
        'redacted_logs.txt must preserve all source log content and replace only session token values.'
    )

    lines = [line for line in content.splitlines() if line.strip()]
    assert len(lines) == 4, "redacted_logs.txt should contain exactly 4 lines."

    for line in lines:
        assert "session_id=[REDACTED]" in line, f"Session ID not redacted correctly in line: {line}"
        assert not re.search(r"session_id=(?!\[REDACTED\])[a-zA-Z0-9]+", line), f"Unredacted session ID found in line: {line}"


def test_redirect_targets_exists_and_content():
    """Test that redirect_targets.txt contains the correct sorted external URLs."""
    targets_file = '/home/user/redirect_targets.txt'
    assert os.path.isfile(targets_file), f"File missing: {targets_file}"

    with open(targets_file, 'r') as f:
        content = f.read().strip()

    expected_targets = [
        "http://malware.site/download",
        "https://evil.phish.com/login"
    ]

    actual_targets = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual_targets == expected_targets, f"redirect_targets.txt content is incorrect. Expected {expected_targets}, got {actual_targets}"


def test_log_checksum_exists_and_matches():
    """Test that log_checksum.txt contains the correct SHA256 hash of redacted_logs.txt."""
    checksum_file = '/home/user/log_checksum.txt'
    redacted_file = '/home/user/redacted_logs.txt'

    assert os.path.isfile(checksum_file), f"File missing: {checksum_file}"
    assert os.path.isfile(redacted_file), f"File missing: {redacted_file}"

    sha256_hash = hashlib.sha256()
    with open(redacted_file, "rb") as f:
        for byte_block in iter(lambda: f.read(4096), b""):
            sha256_hash.update(byte_block)
    actual_hash = sha256_hash.hexdigest()

    with open(checksum_file, 'r') as f:
        checksum_content = f.read().strip()

    assert actual_hash in checksum_content, f"Checksum file does not contain the correct hash. Expected hash: {actual_hash}"


def test_poc_exists_and_content():
    """Test that poc.txt contains the correct PoC URL."""
    poc_file = '/home/user/poc.txt'
    assert os.path.isfile(poc_file), f"File missing: {poc_file}"

    with open(poc_file, 'r') as f:
        content = f.read().strip()

    expected_poc = "http://127.0.0.1:5000/login?redirect_to=http://attacker.com/steal"
    assert content == expected_poc, f"poc.txt content is incorrect. Expected '{expected_poc}', got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
