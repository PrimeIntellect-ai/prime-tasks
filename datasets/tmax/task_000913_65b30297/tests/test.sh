#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import datetime
import hashlib
import json
import os
import secrets
import time
import urllib.parse
import uuid

import pytest
import requests

URL = "http://127.0.0.1:8443/upload"
SAFE_UPLOADS_DIR = "/home/user/safe_uploads"
LOG_FILE = "/home/user/firewall_access.log"
XOR_KEY = b"NETSEC2024"
SALT = "S@lt123"


def auth_token_for(date):
    return hashlib.md5((date.strftime("%Y-%m-%d") + SALT).encode()).hexdigest()


def get_valid_auth_token():
    return auth_token_for(datetime.datetime.utcnow())


def xor_crypt(data):
    return bytes(b ^ XOR_KEY[i % len(XOR_KEY)] for i, b in enumerate(data))


def read_logs():
    if not os.path.exists(LOG_FILE):
        return []
    records = []
    with open(LOG_FILE, "r", encoding="utf-8", errors="replace") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
            except json.JSONDecodeError:
                continue
            if isinstance(record, dict):
                records.append(record)
    return records


def post_and_check_log(filename, data, expected_status, auth=None):
    before = len(read_logs())
    headers = {"X-File-Name": filename}
    if auth is not None:
        headers["X-Custom-Auth"] = auth
    try:
        response = requests.post(URL, headers=headers, data=data, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the service: {exc}")

    deadline = time.time() + 2
    new_records = []
    while time.time() < deadline:
        records = read_logs()
        new_records = records[before:]
        if any(r.get("filename") == filename and r.get("status") == expected_status for r in new_records):
            break
        time.sleep(0.05)

    matches = [r for r in new_records if r.get("filename") == filename and r.get("status") == expected_status]
    assert matches, f"No new {expected_status} log entry for {filename!r}"
    entry = matches[-1]
    assert {"status", "filename", "reason"}.issubset(entry), "Log entry is missing required keys"
    assert isinstance(entry["reason"], str) and entry["reason"].strip(), "Log reason must be non-empty"
    return response


def remove_file(path):
    try:
        if os.path.isfile(path) or os.path.islink(path):
            os.unlink(path)
    except FileNotFoundError:
        pass


def test_original_fixed_cases():
    filename = "test_valid_report.txt"
    plaintext = b"This is a secret report."
    destination = os.path.join(SAFE_UPLOADS_DIR, filename)
    remove_file(destination)

    response = post_and_check_log(filename, xor_crypt(plaintext), "ACCEPTED", get_valid_auth_token())
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    assert os.path.exists(destination), f"File was not saved to {destination}"
    with open(destination, "rb") as f:
        assert f.read() == plaintext, "Saved file content does not match decrypted payload"

    filename = "test_invalid_auth.txt"
    destination = os.path.join(SAFE_UPLOADS_DIR, filename)
    remove_file(destination)
    response = post_and_check_log(filename, xor_crypt(b"Data"), "REJECTED", "invalid_token123")
    assert response.status_code in (401, 403), f"Expected HTTP 401 or 403, got {response.status_code}"
    assert not os.path.exists(destination), "Invalid-auth request created a file"

    filename = "../test_traversal.txt"
    outside = os.path.abspath(os.path.join(SAFE_UPLOADS_DIR, filename))
    remove_file(outside)
    response = post_and_check_log(filename, xor_crypt(b"Data"), "REJECTED", get_valid_auth_token())
    assert response.status_code in (400, 403), f"Expected HTTP 400 or 403, got {response.status_code}"
    assert not os.path.exists(outside), "Traversal request wrote outside the upload directory"


def test_randomized_valid_uploads_are_decrypted():
    for _ in range(4):
        filename = f"upload_{uuid.uuid4().hex}.bin"
        plaintext = secrets.token_bytes(37 + secrets.randbelow(400))
        destination = os.path.join(SAFE_UPLOADS_DIR, filename)
        remove_file(destination)

        response = post_and_check_log(filename, xor_crypt(plaintext), "ACCEPTED", get_valid_auth_token())
        assert response.status_code == 200
        assert os.path.isfile(destination), f"Missing uploaded file {destination}"
        with open(destination, "rb") as f:
            assert f.read() == plaintext, "Random payload was not correctly decrypted"


def test_randomized_invalid_and_missing_auth_are_rejected():
    now = datetime.datetime.utcnow()
    invalid_tokens = [
        secrets.token_hex(16),
        auth_token_for(now - datetime.timedelta(days=1)),
        auth_token_for(now + datetime.timedelta(days=1)),
        None,
    ]
    valid = get_valid_auth_token()
    if invalid_tokens[0] == valid:
        invalid_tokens[0] = "0" * 32 if valid != "0" * 32 else "f" * 32

    for token in invalid_tokens:
        filename = f"unauthorized_{uuid.uuid4().hex}.dat"
        destination = os.path.join(SAFE_UPLOADS_DIR, filename)
        remove_file(destination)
        response = post_and_check_log(filename, xor_crypt(secrets.token_bytes(61)), "REJECTED", token)
        assert response.status_code in (401, 403), f"Invalid token was accepted with HTTP {response.status_code}"
        assert not os.path.exists(destination), "Unauthorized request created a file"


def test_randomized_traversal_and_absolute_paths_are_blocked():
    marker = uuid.uuid4().hex
    cases = [
        f"../outside_{marker}.txt",
        f"nested/../../outside_{marker}.txt",
        f"..%2Foutside_{marker}.txt",
        f"..%2foutside_{marker}.txt",
        f"%2e%2e%2Foutside_{marker}.txt",
        f"/tmp/absolute_{marker}.txt",
        f"%2Ftmp%2Fencoded_absolute_{marker}.txt",
    ]

    for filename in cases:
        decoded = urllib.parse.unquote(filename)
        if os.path.isabs(decoded):
            escaped_target = os.path.abspath(decoded)
        else:
            escaped_target = os.path.abspath(os.path.join(SAFE_UPLOADS_DIR, decoded))
        literal_target = os.path.abspath(os.path.join(SAFE_UPLOADS_DIR, filename))

        for candidate in {escaped_target, literal_target}:
            remove_file(candidate)

        response = post_and_check_log(filename, xor_crypt(secrets.token_bytes(73)), "REJECTED", get_valid_auth_token())
        assert response.status_code in (400, 403), f"Traversal {filename!r} returned HTTP {response.status_code}"
        for candidate in {escaped_target, literal_target}:
            assert not os.path.exists(candidate), f"Blocked filename wrote to {candidate}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
