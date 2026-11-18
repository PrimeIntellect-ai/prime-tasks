#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import json
import os
import subprocess
import tempfile
from cryptography.hazmat.primitives import padding
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from crypt_auth_lib import decrypt_session

DETECTOR = "/home/user/detector.py"
SOURCE = "/app/crypt_auth_lib-2.1/crypt_auth_lib/decryptor.py"
KEY_TEXT = "SuperSecretKey123!"
KEY = b"SuperSecretKey12"
PATTERNS = ["<script>", "javascript:", "onload=", "' or 1=1", "union select", "../"]


def encrypt_json(value):
    iv = os.urandom(16)
    raw = json.dumps(value).encode("utf-8")
    padder = padding.PKCS7(128).padder()
    padded = padder.update(raw) + padder.finalize()
    encryptor = Cipher(algorithms.AES(KEY), modes.CBC(iv)).encryptor()
    ciphertext = encryptor.update(padded) + encryptor.finalize()
    return base64.b64encode(iv + ciphertext).decode("ascii"), raw


def run_detector(headers):
    fd, path = tempfile.mkstemp(prefix="request_", suffix=".req", dir="/tmp", text=True)
    try:
        with os.fdopen(fd, "w") as f:
            for key, value in headers:
                f.write(f"{key}: {value}\n")
        result = subprocess.run(
            ["python3", DETECTOR, path], capture_output=True, text=True, timeout=10
        )
        return result.returncode, result.stdout
    finally:
        os.unlink(path)


def make_headers(token, extra=None):
    headers = [
        ("Host", "random.example"),
        ("User-Agent", "VerifierBrowser/1.0"),
        ("Cookie", f"theme=blue; Session-Token={token}; preference=compact"),
        ("Accept", "*/*"),
    ]
    if extra is not None:
        headers.append(("X-Random-Metadata", extra))
    return headers


def assert_result(headers, expected):
    code, stdout = run_detector(headers)
    assert code == 0, f"detector exited with {code}"
    assert stdout == expected + "\n", f"expected exactly {expected!r}, got {stdout!r}"


def test_detector_exists():
    assert os.path.isfile(DETECTOR), f"{DETECTOR} does not exist."


def test_crypt_auth_lib_fixed_and_installed():
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing."
    token, raw = encrypt_json({"user": "runtime-check", "role": "user"})
    assert decrypt_session(token, KEY_TEXT) == raw

    installed = subprocess.run(
        ["python3", "-c", "from crypt_auth_lib import decrypt_session; import sys; sys.stdout.write(decrypt_session(sys.argv[1], sys.argv[2]).decode())", token, KEY_TEXT],
        cwd="/tmp", capture_output=True, text=True, timeout=10
    )
    assert installed.returncode == 0, installed.stderr
    assert installed.stdout == raw.decode("utf-8")


def test_generated_clean_requests():
    clean_values = [
        {"user": "alice", "role": "auditor", "note": "ordinary value"},
        {"user": "bob", "role": "user", "nested": {"items": ["alpha", "beta"]}},
    ]
    for value in clean_values:
        token, _ = encrypt_json(value)
        assert_result(make_headers(token, "normal header value"), "CLEAN")


def test_each_signature_in_decrypted_json_case_insensitive():
    for i, pattern in enumerate(PATTERNS):
        mixed = pattern.upper() if i % 2 == 0 else pattern.swapcase()
        token, _ = encrypt_json({"user": "generated", "details": {"value": f"prefix {mixed} suffix"}})
        assert_result(make_headers(token), "EVIL")


def test_each_signature_in_header_values_case_insensitive():
    for i, pattern in enumerate(PATTERNS):
        mixed = pattern.swapcase() if i % 2 == 0 else pattern.upper()
        token, _ = encrypt_json({"user": "generated", "role": "user"})
        assert_result(make_headers(token, f"prefix {mixed} suffix"), "EVIL")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
