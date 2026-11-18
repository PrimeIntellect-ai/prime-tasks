#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import re
import secrets
import shutil
import subprocess
import tempfile

import pytest

INSPECTOR_DIR = "/home/user/inspector"
SOURCE = os.path.join(INSPECTOR_DIR, "traffic_inspector.c")
BINARY = os.path.join(INSPECTOR_DIR, "traffic_inspector")
LOG = os.path.join(INSPECTOR_DIR, "decrypted_log.txt")
CSP = "Content-Security-Policy: default-src 'self';"


def run_checked(args, **kwargs):
    result = subprocess.run(args, capture_output=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed: {args}\nstdout: {result.stdout!r}\nstderr: {result.stderr!r}"
    )
    return result


@pytest.fixture(scope="session")
def compiled_binaries():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} does not exist."

    if os.path.lexists(BINARY):
        os.remove(BINARY)
    run_checked(["gcc", SOURCE, "-o", BINARY, "-lcrypto"], text=True)
    assert os.path.isfile(BINARY), "Compilation did not create the required executable."
    assert os.access(BINARY, os.X_OK), "The compiled utility is not executable."

    asan_binary = "/tmp/traffic_inspector_asan"
    if os.path.lexists(asan_binary):
        os.remove(asan_binary)
    run_checked([
        "gcc", "-fsanitize=address", "-fno-omit-frame-pointer",
        SOURCE, "-o", asan_binary, "-lcrypto"
    ], text=True)
    return BINARY, asan_binary


def public_key_from_private(key_path):
    return run_checked(
        ["openssl", "pkey", "-in", key_path, "-pubout", "-outform", "DER"]
    ).stdout


def public_key_from_certificate(cert_path):
    pem = run_checked(
        ["openssl", "x509", "-in", cert_path, "-pubkey", "-noout"]
    ).stdout
    return run_checked(
        ["openssl", "pkey", "-pubin", "-outform", "DER"], input=pem
    ).stdout


def test_certificate_exists_and_valid():
    cert_path = "/home/user/certs/server.crt"
    key_path = "/home/user/certs/server.key"

    assert os.path.exists(cert_path), f"Certificate file {cert_path} does not exist."
    assert os.path.exists(key_path), f"Private key file {key_path} does not exist."

    key_check = subprocess.run(
        ["openssl", "rsa", "-in", key_path, "-check", "-noout"],
        capture_output=True, text=True
    )
    assert key_check.returncode == 0, f"Private key is invalid or cannot be read: {key_check.stderr}"

    key_text = run_checked(
        ["openssl", "pkey", "-in", key_path, "-text", "-noout"], text=True
    ).stdout
    assert re.search(r"Private-Key:\s*\(2048 bit", key_text), "The private key is not RSA 2048-bit."

    cert_check = subprocess.run(
        ["openssl", "x509", "-in", cert_path, "-noout", "-subject"],
        capture_output=True, text=True
    )
    assert cert_check.returncode == 0, f"Certificate is invalid or cannot be read: {cert_check.stderr}"

    subject = cert_check.stdout.strip()
    assert re.search(r'CN\s*=\s*inspector\.local', subject), f"Certificate subject does not contain CN=inspector.local. Subject found: {subject}"

    rfc_subject = run_checked([
        "openssl", "x509", "-in", cert_path, "-noout", "-subject", "-nameopt", "RFC2253"
    ], text=True).stdout.strip()
    normalized_subject = re.sub(r"^subject=\s*", "", rfc_subject)
    assert re.search(r"(?:^|,)CN=inspector\.local(?:,|$)", normalized_subject), (
        f"Certificate CN is not exactly inspector.local: {rfc_subject}"
    )

    issuer_subject = run_checked([
        "openssl", "x509", "-in", cert_path, "-noout", "-subject", "-issuer", "-nameopt", "RFC2253"
    ], text=True).stdout.splitlines()
    values = {}
    for line in issuer_subject:
        if "=" in line:
            name, value = line.split("=", 1)
            values[name.strip()] = value.strip()
    assert values.get("subject") == values.get("issuer"), "The certificate is not self-issued."

    verify = subprocess.run(
        ["openssl", "verify", "-CAfile", cert_path, cert_path],
        capture_output=True, text=True
    )
    assert verify.returncode == 0, f"The certificate's self-signature is invalid: {verify.stderr}"

    assert public_key_from_private(key_path) == public_key_from_certificate(cert_path), (
        "The certificate does not match server.key."
    )

    dates = run_checked(
        ["openssl", "x509", "-in", cert_path, "-noout", "-dates"], text=True
    ).stdout.splitlines()
    date_values = dict(line.split("=", 1) for line in dates)
    fmt = "%b %d %H:%M:%S %Y %Z"
    not_before = datetime.datetime.strptime(date_values["notBefore"], fmt).replace(tzinfo=datetime.timezone.utc)
    not_after = datetime.datetime.strptime(date_values["notAfter"], fmt).replace(tzinfo=datetime.timezone.utc)
    assert not_after - not_before == datetime.timedelta(days=365), (
        "The certificate validity period is not exactly 365 days."
    )
    now = datetime.datetime.now(datetime.timezone.utc)
    assert not_before <= now <= not_after, "The certificate is not currently valid."


def make_and_run(binary, status_line, extra_text, asan=False):
    token = secrets.token_hex(24)
    plaintext = (
        status_line + "\n"
        + f"Server: Dynamic-{token}\n"
        + f"X-Random-Verification: {extra_text}-{token}\n"
        + "Content-Type: text/html\n\n"
        + f"<html><body>{token}</body></html>\n"
    )
    expected = status_line + "\n" + CSP + "\n" + plaintext.split("\n", 1)[1]

    with tempfile.TemporaryDirectory() as workdir:
        local_binary = os.path.join(workdir, "traffic_inspector")
        shutil.copy2(binary, local_binary)
        key = secrets.token_bytes(32)
        with open(os.path.join(workdir, "key.bin"), "wb") as f:
            f.write(key)
        plain_path = os.path.join(workdir, "plain.txt")
        with open(plain_path, "wb") as f:
            f.write(plaintext.encode("utf-8"))
        run_checked([
            "openssl", "enc", "-aes-256-cbc", "-in", plain_path,
            "-out", os.path.join(workdir, "traffic.enc"),
            "-K", key.hex(), "-iv", "0" * 32
        ])

        env = os.environ.copy()
        if asan:
            env["ASAN_OPTIONS"] = "detect_leaks=0:halt_on_error=1"
        result = subprocess.run(
            [local_binary], cwd=workdir, capture_output=True, text=True,
            timeout=15, env=env
        )
        assert result.returncode == 0, (
            f"Utility crashed or failed on generated input.\nstdout: {result.stdout}\nstderr: {result.stderr}"
        )
        output_path = os.path.join(workdir, "decrypted_log.txt")
        assert os.path.isfile(output_path), "Utility did not create decrypted_log.txt."
        with open(output_path, "r", encoding="utf-8") as f:
            output = f.read()
        assert output == expected, (
            "Generated traffic was not decrypted intact or the CSP header was not placed immediately after the status line."
        )


def test_cwe_remediation(compiled_binaries):
    with open(SOURCE, "r", encoding="utf-8") as f:
        content = f.read()

    compact = re.sub(r"\s+", "", content)
    assert "strcpy(buffer,req)" not in compact, "The vulnerable strcpy call is still present in the C code."

    _, asan_binary = compiled_binaries
    long_reason = "HTTP/1.1 200 OK " + secrets.token_hex(100)
    make_and_run(asan_binary, long_reason, "overflow-check", asan=True)


def test_decrypted_log_contents(compiled_binaries):
    binary, _ = compiled_binaries

    if os.path.lexists(LOG):
        os.remove(LOG)
    result = subprocess.run(
        [binary], cwd=INSPECTOR_DIR, capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"The required utility failed when executed.\nstdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.exists(LOG), f"Decrypted log file {LOG} does not exist. Did the utility compile and run successfully?"

    with open(LOG, "r", encoding="utf-8") as f:
        content = f.read()

    expected_csp = "Content-Security-Policy: default-src 'self';"
    assert expected_csp in content, "The required Content-Security-Policy header was not found in the decrypted log."

    lines = content.splitlines()
    assert len(lines) >= 2 and lines[0] == "HTTP/1.1 200 OK" and lines[1] == expected_csp, (
        "The CSP header is not immediately after the decrypted HTTP status line."
    )

    expected_payload = "<html><body>Secret payload!</body></html>"
    assert expected_payload in content, "The decrypted payload is missing or corrupted in the output log."

    make_and_run(binary, "HTTP/1.1 200 OK", "runtime-decryption-check")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
