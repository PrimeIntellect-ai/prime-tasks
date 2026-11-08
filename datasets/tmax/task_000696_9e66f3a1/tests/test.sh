#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import subprocess

import pytest
import requests

DECODER_DIR = "/home/user/c2_decoder"
DECODER_SRC = os.path.join(DECODER_DIR, "decoder.c")
DECODER_BIN = os.path.join(DECODER_DIR, "decoder")


def expected_stddev(digits):
    values = [int(c) for c in digits]
    mean = sum(values) / len(values)
    variance = sum((x - mean) ** 2 for x in values) / len(values)
    return math.sqrt(variance)


def run_decoder(path, digits):
    result = subprocess.run(
        [path, digits], text=True, capture_output=True, timeout=10
    )
    assert result.returncode == 0, (
        f"decoder failed for {digits!r}: stdout={result.stdout!r}, "
        f"stderr={result.stderr!r}"
    )
    output = result.stdout.strip()
    match = re.fullmatch(r"TOKEN-(-?\d+)-(-?\d+\.\d{2})", output)
    assert match, f"Unexpected decoder output for {digits!r}: {output!r}"
    assert int(match.group(1)) == 120, "Recursive key derivation did not produce 120"
    actual = float(match.group(2))
    assert math.isfinite(actual), f"Decoder produced a non-finite value: {output!r}"
    expected = expected_stddev(digits)
    assert abs(actual - expected) <= 0.011, (
        f"Wrong standard deviation for {digits!r}: got {actual}, expected {expected}"
    )
    return output


@pytest.fixture(scope="session")
def activation_token():
    assert os.path.isfile(DECODER_SRC), "decoder.c is missing"

    if os.path.exists(DECODER_BIN):
        os.remove(DECODER_BIN)
    build = subprocess.run(
        ["make"], cwd=DECODER_DIR, text=True, capture_output=True, timeout=30
    assert build.returncode == 0, (
        f"make failed: stdout={build.stdout!r}, stderr={build.stderr!r}"
    )
    assert os.path.isfile(DECODER_BIN), "make did not create decoder"
    assert os.access(DECODER_BIN, os.X_OK), "decoder is not executable"
    with open(DECODER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "decoder is not a compiled ELF executable"

    asan_bin = "/tmp/decoder_asan"
    asan_build = subprocess.run(
        [
            "gcc", "-g", "-O0", "-fsanitize=address", "-fno-omit-frame-pointer",
            "-o", asan_bin, DECODER_SRC, "-lm"
        ], text=True, capture_output=True, timeout=30
    assert asan_build.returncode == 0, (
        f"decoder.c failed sanitizer compilation: {asan_build.stderr!r}"
    )
    asan_run = subprocess.run(
        [asan_bin, "0123456789"], text=True, capture_output=True, timeout=10,
        env={**os.environ, "ASAN_OPTIONS": "detect_leaks=0:halt_on_error=1"}
    assert asan_run.returncode == 0, (
        "decoder has a memory-safety or recursion failure on a ten-digit input: "
        f"stdout={asan_run.stdout!r}, stderr={asan_run.stderr!r}"
    )

    cases = ["7384", "7777", "0123456789"]
    for _ in range(5):
        length = 2 + secrets.randbelow(8)
        cases.append("".join(str(secrets.randbelow(10)) for _ in range(length)))
    outputs = {digits: run_decoder(DECODER_BIN, digits) for digits in cases}
    return outputs["7384"]


def test_ping_endpoint(activation_token):
    url = "http://127.0.0.1:8080/ping"
    try:
        response = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to C2 server at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200 for /ping, got {response.status_code}"
    assert "pong" in response.text.lower(), f"Expected 'pong' in response body, got {response.text}"
    assert response.text.strip() == "pong", f"Expected plaintext body 'pong', got {response.text!r}"


def is_successful_registration(response):
    if response.status_code != 200:
        return False
    try:
        return response.json().get("status") == "registered"
    except ValueError:
        return False


def test_register_rejects_invalid_authorization(activation_token):
    url = "http://127.0.0.1:8080/register"
    payload = {"agent": "test_bot"}

    no_auth = requests.post(url, json=payload, timeout=5)
    assert not is_successful_registration(no_auth), \
        "Registration succeeded without an Authorization header"

    wrong_token = "TOKEN-" + secrets.token_hex(16)
    bad_auth = requests.post(
        url, json=payload,
        headers={"Authorization": f"Bearer {wrong_token}"}, timeout=5)
    assert not is_successful_registration(bad_auth), \
        "Registration succeeded with an invalid bearer token"


def test_register_checks_agent_value(activation_token):
    url = "http://127.0.0.1:8080/register"
    response = requests.post(
        url,
        json={"agent": "not_test_bot_" + secrets.token_hex(8)},
        headers={"Authorization": f"Bearer {activation_token}"},
        timeout=5,
    )
    assert not is_successful_registration(response), \
        "Registration succeeded for an unexpected agent value"


def test_register_endpoint(activation_token):
    url = "http://127.0.0.1:8080/register"
    headers = {
        "Authorization": f"Bearer {activation_token}"
    }
    payload = {
        "agent": "test_bot"
    }
    try:
        response = requests.post(url, json=payload, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to C2 server at {url}: {e}")

    assert response.status_code == 200, f"Expected status code 200 for /register, got {response.status_code}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response from /register, got: {response.text}")

    assert data.get("status") == "registered", f"Expected status 'registered' in JSON, got {data.get('status')}"

    transcript = str(data.get("transcript", "")).lower()
    assert "seven three eight four" in transcript or "7384" in transcript, \
        f"Expected transcript to contain 'seven three eight four' or '7384', got: {transcript}"
    normalized = " ".join(re.findall(r"[a-z]+", transcript))
    assert "the launch sequence code is seven three eight four" in normalized, \
        f"Expected the full audio transcript, got: {transcript}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
