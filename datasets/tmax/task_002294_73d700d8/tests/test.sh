#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import base64
import json
import os
import secrets
import shutil
import subprocess
import tempfile
import pytest

TOKEN_PATH = "/home/user/evidence/token.jwt"
FINGERPRINT_PATH = "/home/user/fingerprint.txt"


def _b64url(data):
    return base64.urlsafe_b64encode(data).decode("ascii").rstrip("=")


def _make_segment_with_url_alphabet(document, field):
    # Exercise the URL-safe alphabet as well as omitted padding.
    for codepoint in range(0x80, 0x1000):
        document[field] = chr(codepoint)
        raw = json.dumps(document, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
        encoded = _b64url(raw)
        if "-" in encoded or "_" in encoded:
            return encoded
    pytest.fail("Could not construct a Base64Url test segment")


def _run_and_check_decoder(binary, token, expected_path, expected_fingerprint, original_fp):
    with open(TOKEN_PATH, "w", encoding="ascii") as f:
        f.write(token)

    if original_fp is None:
        try:
            os.remove(FINGERPRINT_PATH)
        except FileNotFoundError:
            pass
    else:
        with open(FINGERPRINT_PATH, "wb") as f:
            f.write(original_fp)

    try:
        result = subprocess.run(
            [binary], capture_output=True, text=True, timeout=15, check=False
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Decoder {binary} did not terminate")

    combined_output = result.stdout + "\n" + result.stderr
    reported_path = expected_path in combined_output

    wrote_expected_fingerprint = False
    if os.path.isfile(FINGERPRINT_PATH):
        with open(FINGERPRINT_PATH, "r", encoding="utf-8", errors="replace") as f:
            wrote_expected_fingerprint = f.read().strip() == expected_fingerprint

    assert result.returncode == 0, (
        f"Decoder {binary} failed on a valid JWT (exit {result.returncode}).\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert reported_path or wrote_expected_fingerprint, (
        f"Decoder {binary} did not use the exfil_path from the supplied JWT. "
        "It neither reported the decoded path nor produced the fingerprint of "
        "the certificate at that path."
    )


def test_decoder_cpp_exists():
    path = "/home/user/decoder.cpp"
    assert os.path.isfile(path), f"C++ source file {path} does not exist. Did you write the program?"


def test_decoder_executable_exists():
    path = "/home/user/decoder"
    assert os.path.isfile(path), f"Executable file {path} does not exist. Did you compile your program?"
    assert os.access(path, os.X_OK), f"File {path} is not executable."


def test_decoder_parses_runtime_jwt_and_exfil_path():
    with open(TOKEN_PATH, "rb") as f:
        original_token = f.read()
    original_fp = None
    if os.path.isfile(FINGERPRINT_PATH):
        with open(FINGERPRINT_PATH, "rb") as f:
            original_fp = f.read()

    workdir = tempfile.mkdtemp(prefix="jwt-decoder-check-")
    cert_path = os.path.join(workdir, secrets.token_hex(12) + ".crt")
    key_path = os.path.join(workdir, secrets.token_hex(12) + ".key")
    rebuilt_decoder = os.path.join(workdir, "decoder-from-source")

    try:
        subprocess.run(
            [
                "openssl", "req", "-x509", "-newkey", "rsa:2048",
                "-keyout", key_path, "-out", cert_path, "-days", "1", "-nodes",
                "-subj", "/CN=" + secrets.token_hex(10) + ".invalid"
            ],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=True,
            timeout=30,
        )
        expected_fingerprint = subprocess.run(
            ["openssl", "x509", "-in", cert_path, "-noout", "-fingerprint", "-sha256"],
            capture_output=True, text=True, check=True, timeout=10,
        ).stdout.strip()

        header = {"alg": "none", "typ": "JWT"}
        payload = {
            "role": "runtime-test-" + secrets.token_hex(8),
            "exfil_path": cert_path,
        }
        header_segment = _make_segment_with_url_alphabet(header, "kid")
        payload_segment = _make_segment_with_url_alphabet(payload, "note")
        token = header_segment + "." + payload_segment + "."

        subprocess.run(
            ["g++", "-std=c++17", "/home/user/decoder.cpp", "-o", rebuilt_decoder],
            capture_output=True, text=True, check=True, timeout=30,
        )

        # Check both the required executable and a fresh build of the submitted source.
        _run_and_check_decoder(
            "/home/user/decoder", token, cert_path, expected_fingerprint, original_fp
        )
        _run_and_check_decoder(
            rebuilt_decoder, token, cert_path, expected_fingerprint, original_fp
        )
    finally:
        with open(TOKEN_PATH, "wb") as f:
            f.write(original_token)
        if original_fp is None:
            try:
                os.remove(FINGERPRINT_PATH)
            except FileNotFoundError:
                pass
        else:
            with open(FINGERPRINT_PATH, "wb") as f:
                f.write(original_fp)
        shutil.rmtree(workdir, ignore_errors=True)


def test_fingerprint_file_correct():
    cert_path = "/home/user/isolated_env/tmp/rogue.crt"
    fingerprint_path = "/home/user/fingerprint.txt"

    assert os.path.isfile(cert_path), f"Rogue certificate {cert_path} is missing."
    assert os.path.isfile(fingerprint_path), f"Result file {fingerprint_path} does not exist. Did you save the fingerprint?"

    # Compute expected fingerprint
    try:
        result = subprocess.run(
            ["openssl", "x509", "-in", cert_path, "-noout", "-fingerprint", "-sha256"],
            capture_output=True,
            text=True,
            check=True
        )
        expected_fingerprint = result.stdout.strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compute expected fingerprint using openssl: {e}")

    # Read student's fingerprint
    with open(fingerprint_path, "r") as f:
        actual_fingerprint = f.read().strip()

    assert actual_fingerprint == expected_fingerprint, (
        f"The fingerprint in {fingerprint_path} is incorrect.\n"
        f"Expected: {expected_fingerprint}\n"
        f"Found: {actual_fingerprint}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
