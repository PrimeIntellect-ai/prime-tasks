#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import socket
import ssl
import string
import subprocess
import tempfile
import urllib.error
import urllib.request

import pytest


def test_phase1_password_recovery():
    """Verify that the cracked password is saved correctly."""
    pass_file = "/app/config/admin_pass.txt"
    assert os.path.isfile(pass_file), f"Password file not found at {pass_file}"

    with open(pass_file, "r") as f:
        password = f.read().strip()

    assert password == "admin123", (
        f"Incorrect password in {pass_file}. Expected 'admin123', got '{password}'"
    )


def test_phase2_tls_certs_exist_and_identity():
    """Verify that valid TLS files exist and the certificate identifies rotation.local."""
    cert_file = "/app/certs/cert.pem"
    key_file = "/app/certs/key.pem"

    assert os.path.isfile(cert_file), f"Certificate file not found at {cert_file}"
    assert os.path.isfile(key_file), f"Private key file not found at {key_file}"

    cert_check = subprocess.run(
        ["openssl", "x509", "-in", cert_file, "-noout", "-checkhost", "rotation.local"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert cert_check.returncode == 0, (
        "Certificate is invalid or does not identify rotation.local: "
        + cert_check.stdout
        + cert_check.stderr
    )

    key_check = subprocess.run(
        ["openssl", "pkey", "-in", key_file, "-noout", "-check"],
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert key_check.returncode == 0, "Private key is not a valid key: " + key_check.stderr


def test_phase2_nginx_running_and_proxying():
    """Verify that Nginx is listening on 8443 with TLS and proxying to the backend."""
    url = "https://127.0.0.1:8443/ping"
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        req = urllib.request.Request(url)
        with urllib.request.urlopen(req, context=ctx, timeout=5) as response:
            status = response.getcode()
            assert status == 200, f"Expected HTTP 200 from {url}, got {status}"
    except urllib.error.URLError as e:
        pytest.fail(
            f"Failed to connect to Nginx on {url}. Is it running and configured for TLS? Error: {e}"
        )

    with open("/app/certs/cert.pem", "r", encoding="ascii") as f:
        configured_der = ssl.PEM_cert_to_DER_cert(f.read())

    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw_sock:
        with ctx.wrap_socket(raw_sock, server_hostname="rotation.local") as tls_sock:
            served_der = tls_sock.getpeercert(binary_form=True)

    assert served_der == configured_der, (
        "Nginx is not serving the certificate stored at /app/certs/cert.pem"
    )


def test_phase3_sanitizer_exists():
    """Verify that both the C source and compiled sanitizer exist."""
    source_path = "/home/user/sanitizer.c"
    binary_path = "/home/user/sanitizer"

    assert os.path.isfile(source_path), f"Sanitizer source not found at {source_path}"
    assert os.path.isfile(binary_path), f"Sanitizer binary not found at {binary_path}"
    assert os.access(binary_path, os.X_OK), f"Sanitizer binary at {binary_path} is not executable"

    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Sanitizer is not a compiled ELF binary"


def run_sanitizer(binary_path, value):
    try:
        return subprocess.run(
            [binary_path, value], capture_output=True, timeout=3
        ).returncode
    except subprocess.TimeoutExpired:
        pytest.fail(f"Sanitizer timed out for input {value!r}")


def assert_sanitizer_behavior(binary_path):
    # Preserve the original corpus checks.
    evil_dir = "/app/corpus/evil"
    clean_dir = "/app/corpus/clean"
    assert os.path.isdir(evil_dir), f"Evil corpus directory missing: {evil_dir}"
    assert os.path.isdir(clean_dir), f"Clean corpus directory missing: {clean_dir}"

    evil_payloads = os.listdir(evil_dir)
    clean_payloads = os.listdir(clean_dir)

    evil_bypassed = [p for p in evil_payloads if run_sanitizer(binary_path, p) != 1]
    clean_rejected = [p for p in clean_payloads if run_sanitizer(binary_path, p) != 0]

    error_msgs = []
    if evil_bypassed:
        error_msgs.append(
            f"{len(evil_bypassed)} of {len(evil_payloads)} evil bypassed: {evil_bypassed}"
        )
    if clean_rejected:
        error_msgs.append(
            f"{len(clean_rejected)} of {len(clean_payloads)} clean rejected: {clean_rejected}"
        )
    assert not error_msgs, " | ".join(error_msgs)

    alphabet = string.ascii_letters + string.digits + "_-"

    def token(min_len=1, max_len=24):
        length = min_len + secrets.randbelow(max_len - min_len + 1)
        return "".join(secrets.choice(alphabet) for _ in range(length))

    # Fresh unpredictable valid filenames prevent a filename lookup table from passing.
    valid = [f"{token()}.{token(1, 10)}" for _ in range(80)]

    # Fresh traversal and encoding variants exercise the required rejection behavior.
    invalid = []
    enc_dot = ["%2e", "%2E"]
    enc_sep = ["%2f", "%2F", "%5c", "%5C"]
    for _ in range(30):
        name = f"{token()}.{token(1, 8)}"
        invalid.extend([
            "../" + name,
            "..\\" + name,
            "/" + name,
            token() + "/../" + name,
            token() + "\\..\\" + name,
            secrets.choice(enc_dot) + secrets.choice(enc_dot) + secrets.choice(enc_sep) + name,
            "%252e%252e%252f" + name,
            token() + "%00." + token(1, 5),
            token() + "." + token(1, 5) + "." + token(1, 5),
            token() + " " + token() + ".pem",
        ])

    invalid.extend([
        ".hidden",
        "no_extension",
        "trailing.",
        "two..dots",
        "../",
        "..\\",
        "%2e%2e%2fetc%2fpasswd",
        "%2E%2E%5Cwindows%5Csystem.ini",
        "valid.txt%00.jpg",
        "//etc/passwd",
        "C:\\Windows\\win.ini",
        "name/withslash.pem",
        "name\\withbackslash.pem",
        "name\nnewline.pem",
    ])

    grammar = re.compile(r"^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$")
    assert all(grammar.fullmatch(v) for v in valid)
    assert all(not grammar.fullmatch(v) for v in invalid)

    rejected_valid = [v for v in valid if run_sanitizer(binary_path, v) != 0]
    accepted_invalid = [v for v in invalid if run_sanitizer(binary_path, v) != 1]

    assert not rejected_valid, f"Safe generated filenames rejected: {rejected_valid[:10]}"
    assert not accepted_invalid, f"Suspicious generated filenames accepted: {accepted_invalid[:10]}"

    # The program must accept exactly one filename argument.
    assert subprocess.run([binary_path], capture_output=True, timeout=3).returncode != 0
    assert subprocess.run(
        [binary_path, valid[0], valid[1]], capture_output=True, timeout=3
    ).returncode != 0


def test_phase3_adversarial_corpus_and_generated_cases():
    """Exercise both the submitted binary and a fresh build of the submitted C source."""
    binary_path = "/home/user/sanitizer"
    source_path = "/home/user/sanitizer.c"

    assert_sanitizer_behavior(binary_path)

    with tempfile.TemporaryDirectory(prefix="sanitizer-build-") as build_dir:
        rebuilt = os.path.join(build_dir, "sanitizer")
        compile_result = subprocess.run(
            ["gcc", source_path, "-o", rebuilt],
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert compile_result.returncode == 0, (
            "The submitted sanitizer.c does not compile:\n"
            + compile_result.stdout
            + compile_result.stderr
        )
        assert_sanitizer_behavior(rebuilt)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
