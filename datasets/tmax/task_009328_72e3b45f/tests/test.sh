#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import stat
import subprocess
import sys
import pytest

UPLOAD_DIR = '/home/user/uploads'
REPORT_PATH = '/home/user/report.json'
SCRIPT_PATH = '/home/user/scan_uploads.py'

ORIGINAL_EXPECTED = {
    'clean.txt': 'safe',
    'traversal.txt': 'malicious',
    'xss.txt': 'malicious',
    'hidden.enc': 'malicious',
}

ORIGINAL_MODES = {
    'clean.txt': 0o644,
    'traversal.txt': 0o000,
    'xss.txt': 0o000,
    'hidden.enc': 0o000,
}


def load_report():
    assert os.path.isfile(REPORT_PATH), f'The report file {REPORT_PATH} does not exist.'
    with open(REPORT_PATH, 'r') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'The file {REPORT_PATH} does not contain valid JSON.')


def assert_modes(expected_permissions):
    for filename, expected_mode in expected_permissions.items():
        filepath = os.path.join(UPLOAD_DIR, filename)
        assert os.path.isfile(filepath), f'The file {filepath} is missing.'
        actual_mode = stat.S_IMODE(os.stat(filepath).st_mode)
        assert actual_mode == expected_mode, (
            f'The permissions for {filename} are incorrect. '
            f'Expected {oct(expected_mode)}, got {oct(actual_mode)}.'
        )


def test_initial_report_json_exists_and_correct():
    report_data = load_report()
    assert report_data == ORIGINAL_EXPECTED, (
        f'The content of {REPORT_PATH} does not match the expected report mapping.'
    )


def test_initial_file_permissions():
    assert_modes(ORIGINAL_MODES)


def test_script_scans_new_files_and_bruteforces_xor():
    script_stat = os.lstat(SCRIPT_PATH)
    assert stat.S_ISREG(script_stat.st_mode), f'{SCRIPT_PATH} must be a regular file.'
    assert not os.path.islink(SCRIPT_PATH), f'{SCRIPT_PATH} must not be a symbolic link.'

    token = secrets.token_hex(10)
    cases = {
        f'{token}_safe.txt': (b'Routine upload with harmless text.', 'safe'),
        f'{token}_traversal.log': (b'asset=../../private/config', 'malicious'),
        f'{token}_script.data': (b'prefix <script src=/payload.js> suffix', 'malicious'),
        f'{token}_onerror.txt': (b'image=x onerror=run_payload()', 'malicious'),
        f'{token}_near_miss.txt': (b'Harmless: .. / <Script and onerror = are not exact signatures.', 'safe'),
    }

    expected = dict(ORIGINAL_EXPECTED)
    expected_modes = dict(ORIGINAL_MODES)
    for filename, (content, status) in cases.items():
        with open(os.path.join(UPLOAD_DIR, filename), 'wb') as f:
            f.write(content)
        expected[filename] = status
        expected_modes[filename] = 0o000 if status == 'malicious' else 0o644

    enc_name = f'{token}_encrypted.enc'
    plaintext = b'audit record: destination=../../../root/secret'
    key = secrets.randbelow(255) + 1
    ciphertext = bytes(byte ^ key for byte in plaintext)
    with open(os.path.join(UPLOAD_DIR, enc_name), 'wb') as f:
        f.write(ciphertext)
    expected[enc_name] = 'malicious'
    expected_modes[enc_name] = 0o000

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'{SCRIPT_PATH} failed with exit code {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )

    report_data = load_report()
    assert report_data == expected, (
        'The report does not reflect all files and their dynamically derived statuses. '
        f'Expected {expected!r}, got {report_data!r}.'
    )
    assert_modes(expected_modes)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
