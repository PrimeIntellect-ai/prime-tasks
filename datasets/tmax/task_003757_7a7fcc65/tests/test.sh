#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import py_compile

import pytest
import requests
import urllib3

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

URL = "https://127.0.0.1:8443/exfil"
AUTH_TOKEN = "OpDagger_2024"
RC4_KEY = b"deadbeefcafebabe"
LOG_PATH = "/home/user/exfil_log.txt"


def rc4_encrypt(key: bytes, data: bytes) -> bytes:
    S = list(range(256))
    j = 0
    for i in range(256):
        j = (j + S[i] + key[i % len(key)]) % 256
        S[i], S[j] = S[j], S[i]

    out = bytearray()
    i = j = 0
    for byte in data:
        i = (i + 1) % 256
        j = (j + S[i]) % 256
        S[i], S[j] = S[j], S[i]
        out.append(byte ^ S[(S[i] + S[j]) % 256])
    return bytes(out)


def post(payload: bytes, token=None):
    headers = {} if token is None else {"X-Auth-Token": token}
    try:
        return requests.post(URL, headers=headers, data=payload, verify=False, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to honeypot: {exc}")


def test_honeypot_script_exists_and_is_python():
    path = "/home/user/c2_honeypot.py"
    assert os.path.isfile(path), f"Honeypot script missing at {path}"
    py_compile.compile(path, doraise=True)


def test_tls_certificates_exist():
    crt_path = "/home/user/certs/server.crt"
    key_path = "/home/user/certs/server.key"
    assert os.path.exists(crt_path), f"Certificate file missing at {crt_path}"
    assert os.path.exists(key_path), f"Private key file missing at {key_path}"


def test_missing_auth_returns_401():
    response = post(b"dummy")
    assert response.status_code == 401, f"Expected HTTP 401 for missing auth, got {response.status_code}"
    assert response.content == b"", "Missing-auth response body must be empty"


def test_invalid_auth_returns_401():
    response = post(b"dummy", "BadToken123")
    assert response.status_code == 401, f"Expected HTTP 401 for invalid auth, got {response.status_code}"
    assert response.content == b"", "Invalid-auth response body must be empty"


def test_authentication_requires_exact_token():
    for bad_token in (AUTH_TOKEN + "x", " " + AUTH_TOKEN, AUTH_TOKEN.lower()):
        response = post(secrets.token_bytes(23), bad_token)
        assert response.status_code == 401
        assert response.content == b""


def test_valid_auth_decryption_and_redaction():
    plaintext = b"User: admin, CC: 1111222233334444, Role: root"
    encrypted_payload = rc4_encrypt(RC4_KEY, plaintext)
    response = post(encrypted_payload, AUTH_TOKEN)

    assert response.status_code == 200, f"Expected HTTP 200 for valid auth, got {response.status_code}"
    expected_redacted_string = "User: admin, CC: [REDACTED_CC], Role: root"
    expected_length = len(expected_redacted_string.encode("utf-8"))
    expected_body = f"ACK: {expected_length}"
    assert response.text == expected_body, f"Expected response body '{expected_body}', got '{response.text}'"


def test_randomized_rc4_redaction_ack_and_exact_logging():
    alphabet = string.ascii_letters + string.digits
    marker = "".join(secrets.choice(alphabet) for _ in range(29))
    card1 = "".join(secrets.choice(string.digits) for _ in range(16))
    card2 = "".join(secrets.choice(string.digits) for _ in range(16))

    plaintexts = [
        f"node={marker}; payload has no card; café=東京",
        f"{marker}: first={card1}; second={card2}; end",
        f"prefix-{card1}-middle-{marker}-suffix",
    ]
    expected = [re.sub(r"[0-9]{16}", "[REDACTED_CC]", text) for text in plaintexts]

    before = b""
    if os.path.exists(LOG_PATH):
        with open(LOG_PATH, "rb") as handle:
            before = handle.read()

    for plain, redacted in zip(plaintexts, expected):
        ciphertext = rc4_encrypt(RC4_KEY, plain.encode("utf-8"))
        response = post(ciphertext, AUTH_TOKEN)
        assert response.status_code == 200
        assert response.content == f"ACK: {len(redacted.encode('utf-8'))}".encode("ascii")

    assert os.path.isfile(LOG_PATH), f"Log file missing at {LOG_PATH}"
    with open(LOG_PATH, "rb") as handle:
        after = handle.read()
    appended = after[len(before):]
    expected_append = b"".join(text.encode("utf-8") + b"\n" for text in expected)
    assert appended == expected_append, "Log did not append exactly the randomized decrypted/redacted records"


def test_exfil_log_contents():
    assert os.path.exists(LOG_PATH), f"Log file missing at {LOG_PATH}"
    with open(LOG_PATH, "r", encoding="utf-8") as f:
        log_contents = f.read()
    expected_log_entry = "User: admin, CC: [REDACTED_CC], Role: root\n"
    assert expected_log_entry in log_contents, "The expected redacted log entry was not found in the log file."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
