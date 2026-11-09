#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import hashlib
import json
import os
import pwd
import secrets
import shutil
import stat
import subprocess
import sys
import tempfile
import urllib.parse

import pytest
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes

HOME = '/home/user'
REPORT = os.path.join(HOME, 'incident_report.json')
TRAFFIC = os.path.join(HOME, 'traffic_logs.json')
KEY = os.path.join(HOME, 'secret.key')
SYSTEM = os.path.join(HOME, 'system')
HASHES = os.path.join(HOME, 'system_hashes.txt')
REQUIRED_KEYS = {"malicious_requests", "decrypted_payloads", "tampered_files", "suid_files"}


def encrypt_payload(key, text):
    iv = os.urandom(16)
    padder = padding.PKCS7(128).padder()
    padded = padder.update(text.encode('utf-8')) + padder.finalize()
    encryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor()
    ciphertext = encryptor.update(padded) + encryptor.finalize()
    return base64.b64encode(iv + ciphertext).decode('ascii')


def expected_from_inputs():
    with open(TRAFFIC, 'r') as f:
        logs = json.load(f)
    with open(KEY, 'rb') as f:
        key = f.read()

    malicious = []
    decrypted = []
    for log in logs:
        decoded_url = urllib.parse.unquote(log.get('url', '')).lower()
        if '../' in decoded_url and log.get('status') == 201:
            malicious.append(log.get('request_id'))
            raw = base64.b64decode(log.get('payload', ''), validate=True)
            assert len(raw) >= 32 and len(raw[16:]) % 16 == 0
            decryptor = Cipher(algorithms.AES(key), modes.CBC(raw[:16])).decryptor()
            padded = decryptor.update(raw[16:]) + decryptor.finalize()
            unpadder = padding.PKCS7(128).unpadder()
            plaintext = unpadder.update(padded) + unpadder.finalize()
            decrypted.append(plaintext.decode('utf-8'))

    tampered = []
    with open(HASHES, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                expected_hash, filename = parts
                path = os.path.join(SYSTEM, filename)
                if os.path.exists(path):
                    with open(path, 'rb') as pf:
                        actual_hash = hashlib.sha256(pf.read()).hexdigest()
                    if actual_hash != expected_hash:
                        tampered.append(path)

    suid = []
    for filename in os.listdir(SYSTEM):
        path = os.path.join(SYSTEM, filename)
        if os.path.isfile(path) and os.stat(path).st_mode & stat.S_ISUID:
            suid.append(path)

    return {
        'malicious_requests': sorted(malicious),
        'decrypted_payloads': sorted(decrypted),
        'tampered_files': sorted(tampered),
        'suid_files': sorted(suid),
    }


def load_and_validate_report(expected):
    assert os.path.exists(REPORT), f"Expected report file not found at {REPORT}"
    assert os.path.isfile(REPORT), f"Expected {REPORT} to be a file"
    with open(REPORT, 'r') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT} is not valid JSON.")

    assert isinstance(report, dict), 'Incident report must be a JSON object'
    actual_keys = set(report.keys())
    assert REQUIRED_KEYS.issubset(actual_keys), f"Report is missing keys: {REQUIRED_KEYS - actual_keys}"
    for key in REQUIRED_KEYS:
        assert isinstance(report[key], list), f"{key} must be an array"
        assert report[key] == sorted(report[key]), f"{key} must be sorted in ascending alphabetical order"
        assert report[key] == expected[key], f"Expected {key} {expected[key]}, got {report[key]}"
    return report


def find_scripts():
    scripts = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if os.path.join(root, d) != SYSTEM and d not in {'.cache', '__pycache__'}]
        for filename in files:
            path = os.path.join(root, filename)
            if filename.endswith('.py') and os.path.isfile(path) and not os.path.islink(path):
                scripts.append(path)
    return sorted(scripts)


def run_script(path):
    user = pwd.getpwnam('user')

    def demote():
        os.setgroups([])
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    return subprocess.run(
        [sys.executable, path],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        preexec_fn=demote,
    )


def install_dynamic_fixture(token):
    key = secrets.token_bytes(16)
    text_a = 'alpha-' + token
    text_z = 'zulu-' + token
    logs = [
        {'request_id': 'ordinary-' + token, 'method': 'GET', 'url': '/index', 'status': 200, 'payload': ''},
        {'request_id': 'z-' + token, 'method': 'POST', 'url': '/upload?to=..%2Fprivate', 'status': 201, 'payload': encrypt_payload(key, text_z)},
        {'request_id': 'a-' + token, 'method': 'POST', 'url': '/upload?to=../private', 'status': 201, 'payload': encrypt_payload(key, text_a)},
        {'request_id': 'denied-' + token, 'method': 'POST', 'url': '/upload?to=../../private', 'status': 403, 'payload': ''},
    ]

    with open(KEY, 'wb') as f:
        f.write(key)
    with open(TRAFFIC, 'w') as f:
        json.dump(logs, f)

    shutil.rmtree(SYSTEM, ignore_errors=True)
    os.makedirs(SYSTEM, mode=0o755)
    good_name = 'good_' + token
    bad_name = 'changed_' + token
    suid_name = 'privileged_' + token
    contents = {
        good_name: secrets.token_bytes(31),
        bad_name: secrets.token_bytes(37),
        suid_name: secrets.token_bytes(43),
    }
    for name, data in contents.items():
        with open(os.path.join(SYSTEM, name), 'wb') as f:
            f.write(data)
        os.chmod(os.path.join(SYSTEM, name), 0o755)
    os.chmod(os.path.join(SYSTEM, suid_name), 0o4755)

    with open(HASHES, 'w') as f:
        f.write(f"{hashlib.sha256(contents[good_name]).hexdigest()}  {good_name}\n")
        f.write(f"{hashlib.sha256(b'known-good-but-different').hexdigest()}  {bad_name}\n")
        f.write(f"{hashlib.sha256(contents[suid_name]).hexdigest()}  {suid_name}\n")

    os.chmod(KEY, 0o644)
    os.chmod(TRAFFIC, 0o644)
    os.chmod(HASHES, 0o644)


def test_python_analysis_tool_executes_and_report_is_correct():
    scripts = find_scripts()
    assert scripts, 'No Python analysis script was created under /home/user'

    backup = tempfile.mkdtemp(prefix='incident-verifier-')
    shutil.copy2(TRAFFIC, os.path.join(backup, 'traffic_logs.json'))
    shutil.copy2(KEY, os.path.join(backup, 'secret.key'))
    shutil.copy2(HASHES, os.path.join(backup, 'system_hashes.txt'))
    shutil.copytree(SYSTEM, os.path.join(backup, 'system'), copy_function=shutil.copy2)

    selected = None
    failures = []
    try:
        token = secrets.token_hex(8)
        for script in scripts:
            install_dynamic_fixture(token)
            if os.path.lexists(REPORT):
                if os.path.isdir(REPORT) and not os.path.islink(REPORT):
                    shutil.rmtree(REPORT)
                else:
                    os.unlink(REPORT)
            expected = expected_from_inputs()
            try:
                result = run_script(script)
                assert result.returncode == 0, f"exit {result.returncode}: {result.stderr[-500:]}"
                load_and_validate_report(expected)
                selected = script
                break
            except Exception as exc:
                failures.append(f"{script}: {exc}")
    finally:
        shutil.copy2(os.path.join(backup, 'traffic_logs.json'), TRAFFIC)
        shutil.copy2(os.path.join(backup, 'secret.key'), KEY)
        shutil.copy2(os.path.join(backup, 'system_hashes.txt'), HASHES)
        shutil.rmtree(SYSTEM, ignore_errors=True)
        shutil.copytree(os.path.join(backup, 'system'), SYSTEM, copy_function=shutil.copy2)
        shutil.rmtree(backup)
        if os.path.lexists(REPORT):
            if os.path.isdir(REPORT) and not os.path.islink(REPORT):
                shutil.rmtree(REPORT)
            else:
                os.unlink(REPORT)

    assert selected is not None, 'No submitted Python script produced a correct report when executed on derived test inputs. ' + ' | '.join(failures)

    expected_before_run = expected_from_inputs()
    result = run_script(selected)
    assert result.returncode == 0, f"Analysis script failed on the provided inputs: {result.stderr}"
    report = load_and_validate_report(expected_before_run)

    # Preserve the original verifier's independent checks on the provided data.
    with open(TRAFFIC, 'r') as f:
        logs = json.load(f)
    expected_malicious_requests = []
    for log in logs:
        decoded_url = urllib.parse.unquote(log.get('url', '')).lower()
        if '../' in decoded_url and log.get('status') == 201:
            expected_malicious_requests.append(log.get('request_id'))
    expected_malicious_requests.sort()
    assert report.get('malicious_requests') == expected_malicious_requests

    expected_payloads = sorted(['Overwrite logger', 'Set SUID on backup'])
    assert report.get('decrypted_payloads') == expected_payloads

    expected_tampered = []
    with open(HASHES, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                expected_hash, filename = parts
                file_path = os.path.join(SYSTEM, filename)
                if os.path.exists(file_path):
                    with open(file_path, 'rb') as pf:
                        actual_hash = hashlib.sha256(pf.read()).hexdigest()
                    if actual_hash != expected_hash:
                        expected_tampered.append(file_path)
    expected_tampered.sort()
    assert report.get('tampered_files') == expected_tampered

    expected_suid = []
    for filename in os.listdir(SYSTEM):
        file_path = os.path.join(SYSTEM, filename)
        if os.path.isfile(file_path) and os.stat(file_path).st_mode & stat.S_ISUID:
            expected_suid.append(file_path)
    expected_suid.sort()
    assert report.get('suid_files') == expected_suid
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
