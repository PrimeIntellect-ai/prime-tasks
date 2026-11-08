#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import re
import socket
import subprocess
import pytest

HOST = "127.0.0.1"
PORT = 9090
B64_ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"


def send_and_receive(host, port, payload):
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as s:
        s.settimeout(5.0)
        try:
            s.connect((host, port))
        except ConnectionRefusedError:
            pytest.fail(f"Connection refused to {host}:{port}. Ensure the service is running.")
        except Exception as e:
            pytest.fail(f"Failed to connect to {host}:{port}: {e}")

        s.sendall(payload.encode("ascii"))

        data = b""
        while True:
            try:
                chunk = s.recv(1024)
                if not chunk:
                    break
                data += chunk
            except socket.timeout:
                break

        return data.decode("utf-8")


def read_badge_secret():
    output = subprocess.check_output(
        ["tesseract", "/app/admin_badge.png", "stdout", "--psm", "6"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    candidates = re.findall(r"[A-Za-z0-9+/]{8,}={0,2}", output)
    assert candidates, f"OCR did not find a base64 token in the badge: {output!r}"

    for token in sorted(candidates, key=len, reverse=True):
        try:
            return base64.b64decode(token, validate=True)
        except Exception:
            pass
    pytest.fail(f"OCR found no decodable base64 token in the badge: {output!r}")


def equivalent_base64_encodings(raw):
    canonical = base64.b64encode(raw).decode("ascii")
    padding = len(canonical) - len(canonical.rstrip("="))
    variants = {canonical}

    # Base64 decoders recover the same bytes for all choices of unused pad bits.
    # Exercising these encodings prevents raw-string token comparisons.
    if padding:
        index = len(canonical.rstrip("=")) - 1
        value = B64_ALPHABET.index(canonical[index])
        variable_bits = 4 if padding == 2 else 2
        fixed = value & ~((1 << variable_bits) - 1)
        for low_bits in range(1 << variable_bits):
            replacement = B64_ALPHABET[fixed | low_bits]
            variant = canonical[:index] + replacement + canonical[index + 1:]
            assert base64.b64decode(variant) == raw
            variants.add(variant)

    return list(variants)


def test_service_access_granted():
    """Retain the original correct-token assertion."""
    payload = "c2VjcmV0X2FkbWluX3Rva2VuXzEyMw==\n"
    response = send_and_receive(HOST, PORT, payload)
    assert response == "ACCESS_GRANTED\n", (
        f"Expected 'ACCESS_GRANTED\\n' for correct token, but got: {response!r}"
    )


def test_service_access_denied():
    """Retain the original incorrect-token assertion."""
    payload = "aW52YWxpZF90b2tlbg==\n"
    response = send_and_receive(HOST, PORT, payload)
    assert response == "ACCESS_DENIED\n", (
        f"Expected 'ACCESS_DENIED\\n' for incorrect token, but got: {response!r}"
    )


def test_decoding_and_repeated_general_validation():
    secret = read_badge_secret()
    cases = []

    for encoded in equivalent_base64_encodings(secret):
        cases.append((encoded + "\n", "ACCESS_GRANTED\n"))

    # Generate fresh incorrect plaintexts, including same-length mutations of the
    # real key, and derive their base64 payloads rather than trusting fixed values.
    for _ in range(20):
        mutated = bytearray(secret)
        position = random.randrange(len(mutated))
        mutated[position] ^= random.randrange(1, 256)
        wrong = bytes(mutated)
        assert wrong != secret
        cases.append((base64.b64encode(wrong).decode("ascii") + "\n", "ACCESS_DENIED\n"))

    for _ in range(20):
        while True:
            wrong = os.urandom(random.randint(1, max(2, len(secret) + 12)))
            if wrong != secret:
                break
        cases.append((base64.b64encode(wrong).decode("ascii") + "\n", "ACCESS_DENIED\n"))

    random.SystemRandom().shuffle(cases)
    for payload, expected in cases:
        response = send_and_receive(HOST, PORT, payload)
        assert response == expected, (
            f"For payload {payload!r}, expected {expected!r}, got {response!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
