#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import binascii
import hashlib
import os
import subprocess
import tempfile


def test_validator_compiled_from_verified_source():
    source_path = "/home/user/validator.c"
    checksum_path = "/home/user/checksum.sha256"
    binary_path = "/home/user/validator"

    assert os.path.isfile(source_path), f"The source file '{source_path}' is missing."
    assert os.path.isfile(checksum_path), f"The checksum file '{checksum_path}' is missing."

    checksum_result = subprocess.run(
        ["/usr/bin/sha256sum", "-c", checksum_path],
        cwd="/home/user",
        capture_output=True,
        text=True,
    )
    assert checksum_result.returncode == 0, (
        "validator.c does not match checksum.sha256.\n"
        f"stdout: {checksum_result.stdout.strip()}\n"
        f"stderr: {checksum_result.stderr.strip()}"
    )

    assert os.path.isfile(binary_path), f"The compiled binary '{binary_path}' is missing. Did you compile validator.c?"
    assert os.access(binary_path, os.X_OK), f"The file '{binary_path}' is not executable."

    with tempfile.TemporaryDirectory() as temp_dir:
        expected_binary = os.path.join(temp_dir, "validator")
        compile_result = subprocess.run(
            ["/usr/bin/gcc", source_path, "-o", expected_binary],
            capture_output=True,
            text=True,
        )
        assert compile_result.returncode == 0, (
            "The verified validator.c could not be compiled with the required gcc command.\n"
            f"stdout: {compile_result.stdout.strip()}\n"
            f"stderr: {compile_result.stderr.strip()}"
        )

        def file_hash(path):
            digest = hashlib.sha256()
            with open(path, "rb") as handle:
                for chunk in iter(lambda: handle.read(65536), b""):
                    digest.update(chunk)
            return digest.digest()

        assert file_hash(binary_path) == file_hash(expected_binary), (
            f"'{binary_path}' is not the binary produced by compiling the verified "
            "validator.c with 'gcc /home/user/validator.c -o /home/user/validator'."
        )


def test_cert_verify_log():
    log_path = "/home/user/cert_verify.log"
    assert os.path.isfile(log_path), f"The certificate verification log '{log_path}' is missing."

    with open(log_path, "rb") as handle:
        log_content = handle.read()

    assert b"OK" in log_content, (
        f"The log file '{log_path}' does not contain 'OK'. Ensure you verified the certificate correctly."
    )

    verify_result = subprocess.run(
        [
            "/usr/bin/openssl",
            "verify",
            "-CAfile",
            "/home/user/ca.crt",
            "/home/user/server.crt",
        ],
        capture_output=True,
    )
    assert verify_result.returncode == 0, (
        "openssl verify does not validate server.crt against ca.crt.\n"
        f"stdout: {verify_result.stdout.decode(errors='replace').strip()}\n"
        f"stderr: {verify_result.stderr.decode(errors='replace').strip()}"
    )
    assert log_content == verify_result.stdout, (
        "cert_verify.log is not the exact stdout produced by "
        "'openssl verify -CAfile /home/user/ca.crt /home/user/server.crt'."
    )


def test_forged_token_exists_and_valid():
    token_path = "/home/user/forged_token.txt"
    assert os.path.isfile(token_path), f"The forged token file '{token_path}' is missing."

    with open(token_path, "r") as handle:
        token = handle.read().strip()

    assert token, "The forged token file is empty."

    parts = token.split(".")
    assert len(parts) == 3, "The token does not have the correct format: <Header>.<Payload>.<Signature>"

    header_hex, payload_hex, sig_hex = parts

    try:
        header_bytes = binascii.unhexlify(header_hex)
        payload_bytes = binascii.unhexlify(payload_hex)
        signature_bytes = binascii.unhexlify(sig_hex)
    except (binascii.Error, ValueError):
        assert False, "The header, payload, and signature must be valid hex-encoded strings."

    assert signature_bytes, "The token must contain a dummy hex-encoded signature."

    header_str = header_bytes.decode("ascii", errors="ignore")
    assert '"alg":"none"' in header_str, "The token header does not contain the bypass string '\"alg\":\"none\"'."

    decrypted_payload = bytes(b ^ 0x5A for b in payload_bytes)
    assert decrypted_payload == b'{"role":"admin"}', (
        "The encrypted payload must decrypt to exactly '{\"role\":\"admin\"}'."
    )


def test_validator_execution_with_token():
    binary_path = "/home/user/validator"
    token_path = "/home/user/forged_token.txt"

    if not os.path.isfile(binary_path) or not os.path.isfile(token_path):
        return

    with open(token_path, "r") as handle:
        token = handle.read().strip()

    result = subprocess.run([binary_path, token], capture_output=True, text=True)

    assert result.returncode == 0, (
        f"The validator exited with status {result.returncode}.\n"
        f"Output was: {result.stdout.strip()}\n"
        f"Errors were: {result.stderr.strip()}"
    )
    assert "Access Granted: Admin" in result.stdout, (
        "Running the validator with the forged token did not grant admin access.\n"
        f"Output was: {result.stdout.strip()}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
