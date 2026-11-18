#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import random
import re
import secrets
import subprocess
import tempfile
import pytest


def run_checked(cmd, timeout=5):
    try:
        return subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {cmd}")


def test_tls_certificate_and_key():
    """Verify the encrypted RSA-2048 key and its valid, matching self-signed certificate."""
    key_path = "/home/user/audit_key.pem"
    cert_path = "/home/user/audit_cert.pem"

    assert os.path.exists(key_path), f"Missing private key at {key_path}"
    assert os.path.exists(cert_path), f"Missing certificate at {cert_path}"
    assert os.path.isfile(key_path), f"Private key is not a regular file: {key_path}"
    assert os.path.isfile(cert_path), f"Certificate is not a regular file: {cert_path}"

    # Preserve the original passphrase and key-validity assertion.
    passphrase = "4829audit"
    cmd = ["openssl", "rsa", "-in", key_path, "-passin", f"pass:{passphrase}", "-check", "-noout"]
    result = run_checked(cmd)
    assert result.returncode == 0, (
        "Private key is not encrypted with the correct passphrase or is invalid. "
        f"OpenSSL stderr: {result.stderr.strip()}"
    )

    # An empty passphrase must not open the key, proving that it is actually encrypted.
    no_password = run_checked([
        "openssl", "pkey", "-in", key_path, "-passin", "pass:", "-noout"
    ])
    assert no_password.returncode != 0, "Private key is not encrypted"

    key_details = run_checked([
        "openssl", "rsa", "-in", key_path, "-passin", f"pass:{passphrase}",
        "-text", "-noout"
    ])
    assert key_details.returncode == 0, key_details.stderr.strip()
    assert re.search(r"Private-Key:\s*\(2048 bit", key_details.stdout), (
        "Private key is not RSA 2048-bit"
    )

    parsed_cert = run_checked(["openssl", "x509", "-in", cert_path, "-noout"])
    assert parsed_cert.returncode == 0, f"Invalid X.509 certificate: {parsed_cert.stderr.strip()}"

    # Verification checks the certificate signature and current validity period.
    verified = run_checked(["openssl", "verify", "-CAfile", cert_path, cert_path])
    assert verified.returncode == 0, (
        "Certificate is invalid, expired/not-yet-valid, or not self-signed: "
        f"{verified.stderr.strip()}"
    )

    names = run_checked([
        "openssl", "x509", "-in", cert_path, "-noout", "-subject", "-issuer",
        "-nameopt", "RFC2253"
    ])
    assert names.returncode == 0, names.stderr.strip()
    fields = {}
    for line in names.stdout.splitlines():
        if "=" in line:
            name, value = line.split("=", 1)
            fields[name.strip()] = value.strip()
    assert fields.get("subject"), "Certificate has no subject"
    assert fields.get("issuer") == fields.get("subject"), (
        "Certificate issuer and subject differ; certificate is not self-signed"
    )

    key_public = run_checked([
        "openssl", "rsa", "-in", key_path, "-passin", f"pass:{passphrase}",
        "-pubout"
    ])
    cert_public = run_checked([
        "openssl", "x509", "-in", cert_path, "-pubkey", "-noout"
    ])
    assert key_public.returncode == 0, key_public.stderr.strip()
    assert cert_public.returncode == 0, cert_public.stderr.strip()
    assert "".join(key_public.stdout.split()) == "".join(cert_public.stdout.split()), (
        "Certificate public key does not correspond to the private key"
    )


def test_classifier_corpus():
    """Preserve verification against the supplied clean and evil corpus."""
    classifier_path = "/home/user/arg_classifier.py"
    assert os.path.exists(classifier_path), f"Missing classifier script at {classifier_path}"
    assert os.path.isfile(classifier_path), f"Classifier is not a regular file: {classifier_path}"

    clean_dir = "/app/corpus/clean"
    evil_dir = "/app/corpus/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    assert len(clean_files) > 0, "No clean corpus files found to test."
    assert len(evil_files) > 0, "No evil corpus files found to test."

    clean_failures = []
    for f in clean_files:
        result = run_checked(["python3", classifier_path, f])
        output = result.stdout.strip()
        if result.returncode != 0 or output != "CLEAN":
            clean_failures.append(f"{os.path.basename(f)} (Output: {output})")

    evil_failures = []
    for f in evil_files:
        result = run_checked(["python3", classifier_path, f])
        output = result.stdout.strip()
        if result.returncode != 0 or output != "EVIL":
            evil_failures.append(f"{os.path.basename(f)} (Output: {output})")

    error_msg = ""
    if evil_failures:
        error_msg += f"{len(evil_failures)} of {len(evil_files)} evil bypassed: {', '.join(evil_failures)}. "
    if clean_failures:
        error_msg += f"{len(clean_failures)} of {len(clean_files)} clean modified/rejected: {', '.join(clean_failures)}."

    assert not evil_failures and not clean_failures, error_msg.strip()


def test_classifier_generated_content_not_pathnames():
    """Exercise freshly generated commands at neutral, unpredictable paths."""
    classifier_path = "/home/user/arg_classifier.py"
    assert os.path.isfile(classifier_path), f"Missing classifier script at {classifier_path}"

    token = lambda n=10: secrets.token_hex(n // 2)
    cases = []

    # Expected labels are derived from whether each generated command contains
    # a sensitive option with a value or one of the specified injection forms.
    for _ in range(8):
        line = f"python3 job_{token(8)}.py --input data_{token(8)}.csv --output report_{token(8)}.json"
        cases.append((line, False, False))

    for flag in ("--password", "--secret", "--token"):
        line = f"worker_{token(8)} --user user_{token(6)} {flag} value_{token(12)}"
        cases.append((line, True, False))

    injected_values = [
        lambda: f"tmp_{token(6)};id",
        lambda: f"tmp_{token(6)} && whoami",
        lambda: f"tmp_{token(6)} | sh",
        lambda: f"tmp_$(id)_{token(6)}",
        lambda: f"tmp_`whoami`_{token(6)}",
    ]
    for make_value in injected_values:
        line = f"runner_{token(8)} --file {make_value()} --mode normal"
        cases.append((line, False, True))

    random.SystemRandom().shuffle(cases)
    failures = []
    with tempfile.TemporaryDirectory(prefix=f"argcheck_{token(12)}_") as directory:
        for line, has_sensitive_flag, has_injection in cases:
            expected = "EVIL" if has_sensitive_flag or has_injection else "CLEAN"
            path = os.path.join(directory, token(20) + ".dat")
            with open(path, "w", encoding="utf-8") as handle:
                handle.write(line + "\n")

            result = run_checked(["python3", classifier_path, path])
            actual = result.stdout.strip()
            if result.returncode != 0 or actual != expected:
                failures.append(
                    f"command={line!r}, expected={expected}, output={actual!r}, rc={result.returncode}"
                )

    assert not failures, "Generated classifier failures: " + "; ".join(failures)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
