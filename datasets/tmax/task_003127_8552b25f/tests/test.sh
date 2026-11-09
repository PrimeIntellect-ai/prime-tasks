#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import re
import secrets
import subprocess
from pathlib import Path
import pytest
from datetime import datetime

def decode_base64url(data):
    """Decode base64url encoded string."""
    data = data.replace('-', '+').replace('_', '/')
    padding = len(data) % 4
    if padding:
        data += '=' * (4 - padding)
    try:
        return base64.b64decode(data).decode('utf-8')
    except Exception:
        return ""

def get_expected_expired_cn():
    """Find the expired certificate in /home/user/certs/ and return its CN."""
    certs_dir = "/home/user/certs"
    expired_cns = []

    if not os.path.exists(certs_dir):
        return None

    for filename in os.listdir(certs_dir):
        if filename.endswith(".pem"):
            filepath = os.path.join(certs_dir, filename)
            try:
                end_date_str = subprocess.check_output(
                    ["openssl", "x509", "-enddate", "-noout", "-in", filepath],
                    stderr=subprocess.DEVNULL
                ).decode('utf-8').strip().split('=')[1]

                end_date = datetime.strptime(end_date_str, "%b %d %H:%M:%S %Y %Z")

                if end_date < datetime.utcnow():
                    subject_str = subprocess.check_output(
                        ["openssl", "x509", "-subject", "-noout", "-in", filepath],
                        stderr=subprocess.DEVNULL
                    ).decode('utf-8').strip()

                    match = re.search(r'CN\s*=\s*([^,\n]+)', subject_str)
                    if match:
                        expired_cns.append(match.group(1).strip())
            except Exception:
                continue

    return expired_cns[0] if expired_cns else None

def get_expected_vulnerable_subjects():
    """Parse access.log to find vulnerable JWT subjects."""
    log_path = "/home/user/access.log"
    if not os.path.exists(log_path):
        return []

    vulnerable_subjects = []

    with open(log_path, 'r') as f:
        for line in f:
            match = re.search(r'Bearer\s+([a-zA-Z0-9_-]+\.[a-zA-Z0-9_-]+\.?[a-zA-Z0-9_-]*)', line)
            if match:
                token = match.group(1)
                parts = token.split('.')
                if len(parts) >= 2:
                    header_str = decode_base64url(parts[0])
                    payload_str = decode_base64url(parts[1])

                    try:
                        header = json.loads(header_str)
                        if header.get('alg', '').lower() == 'none':
                            payload = json.loads(payload_str)
                            if 'sub' in payload:
                                vulnerable_subjects.append(payload['sub'])
                    except json.JSONDecodeError:
                        continue

    return sorted(vulnerable_subjects)

def test_expired_cert_file_exists():
    assert os.path.isfile("/home/user/expired_cert.txt"), "The file /home/user/expired_cert.txt was not created."

def test_expired_cert_content():
    expected_cn = get_expected_expired_cn()
    assert expected_cn is not None, "Could not determine the expected expired certificate CN from /home/user/certs/."

    with open("/home/user/expired_cert.txt", "r") as f:
        content = f.read().strip()

    assert content == expected_cn, f"Expected /home/user/expired_cert.txt to contain '{expected_cn}', but got '{content}'."

def test_scan_jwts_script_exists_and_executable():
    script_path = "/home/user/scan_jwts.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."
    syntax = subprocess.run(
        ["bash", "-n", script_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )
    assert syntax.returncode == 0, f"The script is not valid Bash: {syntax.stderr}"

def test_vulnerable_subjects_file_exists():
    assert os.path.isfile("/home/user/vulnerable_subjects.txt"), "The file /home/user/vulnerable_subjects.txt was not created."

def test_vulnerable_subjects_content():
    expected_subjects = get_expected_vulnerable_subjects()

    with open("/home/user/vulnerable_subjects.txt", "r") as f:
        actual_subjects = [line.strip() for line in f if line.strip()]

    assert actual_subjects == expected_subjects, (
        f"Expected vulnerable subjects to be {expected_subjects}, "
        f"but got {actual_subjects}. Ensure the output is sorted alphabetically and contains only the subjects."
    )

def encode_segment(raw):
    if isinstance(raw, str):
        raw = raw.encode('utf-8')
    return base64.urlsafe_b64encode(raw).decode('ascii').rstrip('=')

def make_token(header_json, payload, signature=""):
    header = encode_segment(header_json)
    body = encode_segment(json.dumps(payload, separators=(',', ':')).encode('utf-8'))
    return f"{header}.{body}.{signature}"

def test_scan_jwts_script_processes_runtime_log():
    log_path = Path("/home/user/access.log")
    output_path = Path("/home/user/vulnerable_subjects.txt")
    script_path = "/home/user/scan_jwts.sh"

    original_log = log_path.read_bytes()
    original_output = output_path.read_bytes() if output_path.exists() else None

    suffix = secrets.token_hex(8)
    vulnerable_subjects = [f"zulu_{suffix}", f"alpha_{suffix}"]
    safe_subject = f"safe_{suffix}"

    vulnerable_one = make_token(
        '{"alg":"none","typ":"JWT"}',
        {"sub": vulnerable_subjects[0], "role": "admin"}
    )
    vulnerable_two = make_token(
        '{"typ":"JWT", "alg": "none"}',
        {"role": "user", "sub": vulnerable_subjects[1]}
    )
    signed_token = make_token(
        '{"alg":"HS256","typ":"JWT"}',
        {"sub": safe_subject},
        "signature"
    )

    runtime_log = (
        f'127.0.0.1 - - [11/Sep/2026:01:00:00 +0000] "GET /one HTTP/1.1" 200 1 "-" "Agent Bearer {vulnerable_one}"\n'
        f'127.0.0.1 - - [11/Sep/2026:01:00:01 +0000] "GET /safe HTTP/1.1" 200 1 "-" "Agent Bearer {signed_token}"\n'
        f'127.0.0.1 - - [11/Sep/2026:01:00:02 +0000] "GET /two HTTP/1.1" 200 1 "-" "Agent Bearer {vulnerable_two}"\n'
    )

    try:
        log_path.write_text(runtime_log, encoding='utf-8')
        if output_path.exists():
            output_path.unlink()

        completed = subprocess.run(
            ["bash", script_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10
        )
        assert completed.returncode == 0, (
            f"scan_jwts.sh failed when executed: {completed.stderr}"
        )
        assert output_path.is_file(), (
            "scan_jwts.sh did not create /home/user/vulnerable_subjects.txt when executed."
        )

        expected_subjects = get_expected_vulnerable_subjects()
        assert expected_subjects == sorted(vulnerable_subjects)
        with output_path.open('r', encoding='utf-8') as f:
            actual_subjects = [line.strip() for line in f if line.strip()]

        assert actual_subjects == expected_subjects, (
            "Executing scan_jwts.sh against a runtime-generated access log did not "
            f"produce the expected subjects {expected_subjects}; got {actual_subjects}."
        )
    finally:
        log_path.write_bytes(original_log)
        if original_output is None:
            if output_path.exists():
                output_path.unlink()
        else:
            output_path.write_bytes(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
