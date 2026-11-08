#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import random
import secrets
import socket
import string
import pytest

HOST = '127.0.0.1'
PORT = 8080
TIMEOUT = 2.0
SALT = 'N3tw0rk_S3cr3t_99!'


def send_request(request_str: str) -> str:
    """Helper to send a request to the auth service and read the response."""
    try:
        with socket.create_connection((HOST, PORT), timeout=TIMEOUT) as s:
            s.sendall(request_str.encode('utf-8'))
            response = s.recv(1024).decode('utf-8')
            return response
    except ConnectionRefusedError:
        pytest.fail(f"Connection refused to {HOST}:{PORT}. Is the service running?")
    except socket.timeout:
        pytest.fail(f"Connection to {HOST}:{PORT} timed out waiting for response.")
    except Exception as e:
        pytest.fail(f"Unexpected error communicating with service: {e}")


def checksum(payload_hex: str) -> str:
    return hashlib.md5((payload_hex + SALT).encode('utf-8')).hexdigest()


def alter_checksum(value: str) -> str:
    replacement = '0' if value[0] != '0' else '1'
    return replacement + value[1:]


def random_token(length: int = 14) -> str:
    alphabet = string.ascii_letters + string.digits
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def mixed_case_hex(data: bytes) -> str:
    value = data.hex()
    return ''.join(c.upper() if c in 'abcdef' and secrets.randbits(1) else c for c in value)


def test_valid_user_request():
    """Test a valid user request."""
    request = "AUTH v1 alice cd1af472d5045479ec364377bb411bc7 68656c6c6f\n"
    expected = "ACCEPT: USER\n"
    response = send_request(request)
    assert response == expected, f"Expected {expected!r}, got {response!r}"


def test_valid_admin_request():
    """Test a valid admin request."""
    request = "AUTH v1 bob ea7223b24660eb0e94bb510bbf819340 737570657261646d696e313233\n"
    expected = "ACCEPT: ADMIN\n"
    response = send_request(request)
    assert response == expected, f"Expected {expected!r}, got {response!r}"


def test_intrusion_attempt_valid_hash():
    """Test an intrusion attempt with a valid hash (should be rejected as intrusion)."""
    request = "AUTH v1 al'ice cd1af472d5045479ec364377bb411bc7 68656c6c6f\n"
    expected = "REJECT: INTRUSION\n"
    response = send_request(request)
    assert response == expected, f"Expected {expected!r}, got {response!r}"


def test_intrusion_attempt_invalid_hash():
    """Test an intrusion attempt with an invalid hash (intrusion check must happen first)."""
    request = "AUTH v1 admin; 00000000000000000000000000000000 68656c6c6f\n"
    expected = "REJECT: INTRUSION\n"
    response = send_request(request)
    assert response == expected, f"Expected {expected!r}, got {response!r}"


def test_integrity_failure():
    """Test an integrity failure (bad hash, clean username)."""
    request = "AUTH v1 charlie 11111111111111111111111111111111 68656c6c6f\n"
    expected = "REJECT: INTEGRITY\n"
    response = send_request(request)
    assert response == expected, f"Expected {expected!r}, got {response!r}"


def test_randomized_protocol_behavior():
    cases = []

    for i in range(12):
        raw = ('user-data-' + random_token(20)).encode('ascii')
        assert b'admin' not in raw
        payload = mixed_case_hex(raw) if i % 2 else raw.hex()
        user = 'u' + random_token()
        cases.append((f"AUTH v1 {user} {checksum(payload)} {payload}\n", "ACCEPT: USER\n"))

    for i in range(12):
        raw = ('prefix-' + random_token(8) + '-admin-' + random_token(8)).encode('ascii')
        payload = mixed_case_hex(raw) if i % 2 else raw.hex()
        user = 'a' + random_token()
        cases.append((f"AUTH v1 {user} {checksum(payload)} {payload}\n", "ACCEPT: ADMIN\n"))

    for i in range(12):
        raw = ('integrity-' + random_token(22)).encode('ascii')
        payload = mixed_case_hex(raw) if i % 2 else raw.hex()
        bad = alter_checksum(checksum(payload))
        user = 'i' + random_token()
        cases.append((f"AUTH v1 {user} {bad} {payload}\n", "REJECT: INTEGRITY\n"))

    for restricted in ["'", '"', ';', '<', '>']:
        raw = ('intrusion-' + random_token(16)).encode('ascii')
        payload = mixed_case_hex(raw)
        user = 'left' + restricted + 'right' + random_token(5)
        valid = checksum(payload)
        cases.append((f"AUTH v1 {user} {valid} {payload}\n", "REJECT: INTRUSION\n"))
        cases.append((f"AUTH v1 {user} {alter_checksum(valid)} {payload}\n", "REJECT: INTRUSION\n"))

    random.SystemRandom().shuffle(cases)
    for request, expected in cases:
        response = send_request(request)
        assert response == expected, f"For request {request!r}, expected {expected!r}, got {response!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
