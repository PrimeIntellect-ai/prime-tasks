#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import string
import subprocess
import tempfile
import pytest

KEY_PATH = "/home/user/certs/server.key"
CRT_PATH = "/home/user/certs/server.crt"
VALIDATOR_PATH = "/home/user/auth_validator"
SOURCE_PATH = "/home/user/auth_validator.c"
PASSPHRASE = "AUTH_MASTER_8472"


def run(command, **kwargs):
    return subprocess.run(command, capture_output=True, **kwargs)


def test_server_key_encrypted_with_correct_passphrase():
    assert os.path.isfile(KEY_PATH), f"Private key not found at {KEY_PATH}"

    result = run(
        ["openssl", "rsa", "-in", KEY_PATH, "-passin", f"pass:{PASSPHRASE}", "-check", "-noout"],
        text=True,
    )
    assert result.returncode == 0, (
        "Failed to verify private key with the expected passphrase. "
        f"OpenSSL output: {result.stderr}"
    )

    # Supplying -passin also succeeds for an unencrypted key, so confirm that an
    # incorrect passphrase cannot decrypt it.
    wrong_passphrase = "wrong-" + secrets.token_hex(16)
    wrong = run(
        ["openssl", "rsa", "-in", KEY_PATH, "-passin", f"pass:{wrong_passphrase}", "-check", "-noout"],
        text=True,
    )
    assert wrong.returncode != 0, "The private key is not protected by the recovered passphrase"

    details = run(
        ["openssl", "rsa", "-in", KEY_PATH, "-passin", f"pass:{PASSPHRASE}", "-text", "-noout"],
        text=True,
    )
    assert details.returncode == 0, details.stderr
    assert re.search(r"Private-Key:\s*\(2048 bit", details.stdout), (
        "The private key must be an RSA 2048-bit key"
    )


def test_server_crt_common_name():
    assert os.path.isfile(CRT_PATH), f"Certificate not found at {CRT_PATH}"

    result = run(
        ["openssl", "x509", "-in", CRT_PATH, "-noout", "-subject"],
        text=True,
    )
    assert result.returncode == 0, f"Failed to read certificate. OpenSSL output: {result.stderr}"
    assert "secure-api.internal" in result.stdout, (
        "Expected Common Name 'secure-api.internal' not found in certificate subject: "
        f"{result.stdout}"
    )

    exact_subject = run(
        ["openssl", "x509", "-in", CRT_PATH, "-noout", "-subject", "-nameopt", "RFC2253"],
        text=True,
    )
    assert exact_subject.returncode == 0, exact_subject.stderr
    subject_value = exact_subject.stdout.strip().removeprefix("subject=")
    assert re.search(r"(?:^|,)CN=secure-api\.internal(?:,|$)", subject_value), (
        f"Certificate CN is not exactly secure-api.internal: {subject_value}"
    )


def test_certificate_is_2048_bit_self_signed_and_matches_key():
    cert_details = run(
        ["openssl", "x509", "-in", CRT_PATH, "-noout", "-text"],
        text=True,
    )
    assert cert_details.returncode == 0, cert_details.stderr
    assert "Public Key Algorithm: rsaEncryption" in cert_details.stdout
    assert re.search(r"Public-Key:\s*\(2048 bit\)", cert_details.stdout), (
        "Certificate must contain a 2048-bit RSA public key"
    )

    key_public = run(
        ["openssl", "pkey", "-in", KEY_PATH, "-passin", f"pass:{PASSPHRASE}", "-pubout", "-outform", "DER"]
    )
    assert key_public.returncode == 0, key_public.stderr.decode(errors="replace")

    cert_public_pem = run(["openssl", "x509", "-in", CRT_PATH, "-pubkey", "-noout"])
    assert cert_public_pem.returncode == 0, cert_public_pem.stderr.decode(errors="replace")
    cert_public = run(
        ["openssl", "pkey", "-pubin", "-outform", "DER"],
        input=cert_public_pem.stdout,
    )
    assert cert_public.returncode == 0, cert_public.stderr.decode(errors="replace")
    assert key_public.stdout == cert_public.stdout, "Certificate does not match the submitted private key"

    subject = run(
        ["openssl", "x509", "-in", CRT_PATH, "-noout", "-subject", "-nameopt", "RFC2253"],
        text=True,
    )
    issuer = run(
        ["openssl", "x509", "-in", CRT_PATH, "-noout", "-issuer", "-nameopt", "RFC2253"],
        text=True,
    )
    assert subject.returncode == 0 and issuer.returncode == 0
    assert subject.stdout.strip().removeprefix("subject=") == issuer.stdout.strip().removeprefix("issuer="), (
        "Certificate issuer and subject differ; it is not self-signed"
    )

    verified = run(
        ["openssl", "verify", "-CAfile", CRT_PATH, "-check_ss_sig", CRT_PATH],
        text=True,
    )
    assert verified.returncode == 0, f"Certificate self-signature verification failed: {verified.stderr}"


def test_auth_validator_artifacts():
    assert os.path.isfile(SOURCE_PATH), f"C source not found at {SOURCE_PATH}"
    assert os.path.getsize(SOURCE_PATH) > 0, "C source is empty"
    assert os.path.isfile(VALIDATOR_PATH), f"auth_validator executable not found at {VALIDATOR_PATH}"
    assert os.access(VALIDATOR_PATH, os.X_OK), f"auth_validator at {VALIDATOR_PATH} is not executable"
    with open(VALIDATOR_PATH, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "auth_validator must be a compiled native executable"


def execute_validator(log_path):
    try:
        result = run(
            [VALIDATOR_PATH, CRT_PATH, log_path],
            text=True,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("auth_validator execution timed out.")
    assert result.returncode == 0, (
        f"auth_validator exited with non-zero code {result.returncode}. Stderr: {result.stderr}"
    )
    return [line.strip() for line in result.stdout.splitlines() if line.strip()]


def test_auth_validator_accuracy_on_original_fixture():
    logs_path = "/app/hidden_test_logs.csv"
    output_lines = execute_validator(logs_path)
    expected = [
        "Req1: PASS",
        "Req2: FAIL",
        "Req3: FAIL",
        "Req4: PASS",
    ]

    correct = sum(1 for output, wanted in zip(output_lines, expected) if output == wanted)
    accuracy = correct / len(expected) if expected else 0.0
    assert accuracy >= 1.0, (
        f"auth_validator accuracy is {accuracy}, expected >= 1.0. Output was: {output_lines}"
    )


def random_hex(length):
    alphabet = "0123456789abcdefABCDEF"
    return "".join(secrets.choice(alphabet) for _ in range(length))


def make_token(valid):
    if valid:
        return random_hex(32)
    choice = secrets.randbelow(4)
    if choice == 0:
        return random_hex(31)
    if choice == 1:
        return random_hex(33)
    if choice == 2:
        position = secrets.randbelow(32)
        token = list(random_hex(32))
        token[position] = secrets.choice("ghijklmnopqrstuvwxyz-_!")
        return "".join(token)
    return ""


def make_csp(valid):
    default = "default-src 'self'"
    trusted = "require-trusted-types-for 'script'"
    if valid:
        fragments = [default, trusted]
        if secrets.randbelow(2):
            fragments.reverse()
        if secrets.randbelow(2):
            fragments.append("img-src https:")
        return "; ".join(fragments)

    choice = secrets.randbelow(4)
    if choice == 0:
        return default + "; img-src https:"
    if choice == 1:
        return trusted + "; object-src 'none'"
    if choice == 2:
        return "default-src 'none'; require-trusted-types-for 'script'"
    return "default-src 'self'; require-trusted-types-for script"


def test_auth_validator_on_fresh_derived_inputs():
    records = []
    expected = []

    # Ensure all four truth-table combinations occur, then add randomized cases.
    validity_pairs = [(True, True), (True, False), (False, True), (False, False)] * 10
    validity_pairs += [
        (bool(secrets.randbelow(2)), bool(secrets.randbelow(2)))
        for _ in range(80)
    ]

    for index, (token_valid, csp_valid) in enumerate(validity_pairs):
        request_id = f"R{secrets.token_hex(8)}_{index}"
        token = make_token(token_valid)
        csp = make_csp(csp_valid)
        records.append(f"{request_id},{token},{csp}")
        status = "PASS" if token_valid and csp_valid else "FAIL"
        expected.append(f"{request_id}: {status}")

    with tempfile.TemporaryDirectory() as directory:
        log_path = os.path.join(directory, secrets.token_hex(12) + ".csv")
        with open(log_path, "w", encoding="utf-8", newline="\n") as log_file:
            log_file.write("\n".join(records) + "\n")
        actual = execute_validator(log_path)

    assert actual == expected, (
        "auth_validator did not correctly parse and validate freshly generated CSV records. "
        f"Expected {expected!r}, got {actual!r}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
