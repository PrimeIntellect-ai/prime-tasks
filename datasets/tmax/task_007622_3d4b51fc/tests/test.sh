#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import base64
import re
import subprocess
import pytest

@pytest.fixture(scope="session", autouse=True)
def compile_and_run_decryptor():
    source_path = "/home/user/decryptor.rs"
    executable_path = "/tmp/decryptor_verifier_bin"

    assert os.path.exists(source_path), f"The required Rust source file {source_path} is missing."
    assert os.path.isfile(source_path), f"{source_path} must be a file."

    compile_result = subprocess.run(
        ["rustc", source_path, "-o", executable_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {source_path} with rustc.\n"
        f"stdout:\n{compile_result.stdout}\n"
        f"stderr:\n{compile_result.stderr}"
    )
    assert os.path.isfile(executable_path), "rustc did not produce the decryptor executable."

    # Require the freshly compiled Rust program itself to recreate the requested outputs.
    for output_path in (
        "/home/user/decrypted_payload.txt",
        "/home/user/privesc_binary.txt",
    ):
        if os.path.lexists(output_path):
            if os.path.isdir(output_path) and not os.path.islink(output_path):
                pytest.fail(f"{output_path} must be a file, not a directory.")
            os.unlink(output_path)

    run_result = subprocess.run(
        [executable_path],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert run_result.returncode == 0, (
        "The compiled Rust decryptor did not run successfully.\n"
        f"stdout:\n{run_result.stdout.decode(errors='replace')}\n"
        f"stderr:\n{run_result.stderr.decode(errors='replace')}"
    )


def derive_expected_payload():
    traffic_path = "/home/user/traffic.txt"
    if not os.path.exists(traffic_path):
        pytest.fail(f"Required file {traffic_path} is missing.")

    with open(traffic_path, "r") as f:
        content = f.read()

    # Extract base64 payload
    b64_match = re.search(r'\[Suspicious Payload\]\n([A-Za-z0-9+/=]+)', content)
    if not b64_match:
        pytest.fail("Could not find base64 payload in traffic.txt")

    encrypted_bytes = base64.b64decode(b64_match.group(1))

    # Brute force the key (0-255)
    # C = (P * 5 + 17) ^ KEY mod 256
    # P = ((C ^ KEY) - 17) * inv_5 mod 256
    # Multiplicative inverse of 5 modulo 256 is 205, since (5 * 205) % 256 = 1025 % 256 = 1

    inv_5 = 205
    expected_plaintext = None

    for key in range(256):
        decrypted = bytearray()
        for c in encrypted_bytes:
            p = (((c ^ key) - 17) * inv_5) % 256
            decrypted.append(p)

        if decrypted.startswith(b"ELEVATE: "):
            expected_plaintext = decrypted.decode('utf-8', errors='ignore')
            break

    if not expected_plaintext:
        pytest.fail("Could not derive the expected plaintext from the payload.")

    return expected_plaintext


def test_decrypted_payload_file():
    expected_payload = derive_expected_payload()
    payload_path = "/home/user/decrypted_payload.txt"

    assert os.path.exists(payload_path), f"The file {payload_path} was not created."
    assert os.path.isfile(payload_path), f"{payload_path} must be a file."

    with open(payload_path, "r") as f:
        actual_payload = f.read().strip()

    assert actual_payload == expected_payload.strip(), (
        f"Contents of {payload_path} do not match the expected decrypted payload.\n"
        f"Expected: {expected_payload.strip()}\n"
        f"Found: {actual_payload}"
    )


def test_privesc_binary_file():
    expected_payload = derive_expected_payload()

    # Extract the binary path from the payload
    # Payload format: ELEVATE: sudo /path/to/binary ...
    match = re.search(r'ELEVATE:\s+sudo\s+(/[^\s]+)', expected_payload)
    if not match:
        pytest.fail("Could not parse the binary path from the derived payload.")

    expected_binary = match.group(1)
    binary_path = "/home/user/privesc_binary.txt"

    assert os.path.exists(binary_path), f"The file {binary_path} was not created."
    assert os.path.isfile(binary_path), f"{binary_path} must be a file."

    with open(binary_path, "r") as f:
        actual_binary = f.read().strip()

    assert actual_binary == expected_binary, (
        f"Contents of {binary_path} do not match the expected binary path.\n"
        f"Expected: {expected_binary}\n"
        f"Found: {actual_binary}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
