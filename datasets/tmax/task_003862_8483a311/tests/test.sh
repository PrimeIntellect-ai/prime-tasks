#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import os
import secrets
import socket
import ssl
import string
import subprocess
import urllib.request

import pytest

SANITIZER = "/home/user/sanitizer"
SOURCE = "/home/user/sanitizer.c"
CERT = "/home/user/certs/server.crt"
KEY = "/home/user/certs/server.key"
ALLOWED = set(b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_")


def run_sanitizer(path, content):
    try:
        return subprocess.run(
            [path], input=content, capture_output=True, timeout=2
        ).returncode
    except Exception as exc:
        pytest.fail(f"Execution of {path} failed: {exc}")


def expected_status(content):
    line = content.split(b"\n", 1)[0]
    safe = all(byte in ALLOWED for byte in line) and b".." not in line
    return 0 if safe else 1


def test_tls_server_running_and_serving():
    url = "https://127.0.0.1:8443/index.html"
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE

    try:
        with urllib.request.urlopen(url, context=ctx, timeout=5) as response:
            content = response.read().decode("utf-8").strip()
            assert content == "Deployment Node Active", \
                f"Expected index.html to contain 'Deployment Node Active', but got: '{content}'"
    except urllib.error.URLError as exc:
        pytest.fail(f"Failed to connect to the TLS server at {url}. Is it running? Error: {exc}")
    except Exception as exc:
        pytest.fail(f"Unexpected error while verifying TLS server: {exc}")


def test_required_certificate_and_key():
    assert os.path.isfile(CERT), f"TLS certificate is missing at {CERT}"
    assert os.path.isfile(KEY), f"TLS private key is missing at {KEY}"

    cert_check = subprocess.run(
        ["openssl", "x509", "-in", CERT, "-noout"], capture_output=True, text=True
    )
    assert cert_check.returncode == 0, f"Invalid certificate at {CERT}: {cert_check.stderr}"

    key_check = subprocess.run(
        ["openssl", "pkey", "-in", KEY, "-noout", "-check"], capture_output=True, text=True
    )
    assert key_check.returncode == 0, f"Invalid private key at {KEY}: {key_check.stderr}"

    cert_pub = subprocess.run(
        ["openssl", "x509", "-in", CERT, "-pubkey", "-noout"],
        capture_output=True,
        check=True,
    ).stdout
    key_pub = subprocess.run(
        ["openssl", "pkey", "-in", KEY, "-pubout"],
        capture_output=True,
        check=True,
    ).stdout
    assert cert_pub == key_pub, "The certificate and private key do not match"

    self_signed = subprocess.run(
        ["openssl", "verify", "-CAfile", CERT, CERT], capture_output=True, text=True
    )
    assert self_signed.returncode == 0, "The supplied certificate is not self-signed"

    pem = open(CERT, "r", encoding="ascii").read()
    expected_der = ssl.PEM_cert_to_DER_cert(pem)
    ctx = ssl.create_default_context()
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    with socket.create_connection(("127.0.0.1", 8443), timeout=5) as raw:
        with ctx.wrap_socket(raw, server_hostname="127.0.0.1") as tls_socket:
            served_der = tls_socket.getpeercert(binary_form=True)
    assert served_der == expected_der, "The HTTPS server is not using /home/user/certs/server.crt"


def test_sanitizer_binary_exists():
    assert os.path.isfile(SANITIZER), f"The sanitizer binary is missing at {SANITIZER}"
    assert os.access(SANITIZER, os.X_OK), f"The sanitizer binary at {SANITIZER} is not executable"
    with open(SANITIZER, "rb") as binary:
        assert binary.read(4) == b"\x7fELF", "The sanitizer must be a compiled executable"


def test_sanitizer_source_exists_and_compiles(tmp_path):
    assert os.path.isfile(SOURCE), f"The required C source is missing at {SOURCE}"
    output = tmp_path / "sanitizer_from_source"
    result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", SOURCE, "-o", str(output)],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Failed to compile {SOURCE}: {result.stderr}"
    assert output.is_file() and os.access(output, os.X_OK)


def test_sanitizer_adversarial_corpus():
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"
    clean_files = glob.glob(os.path.join(clean_dir, "*"))
    evil_files = glob.glob(os.path.join(evil_dir, "*"))

    assert len(clean_files) > 0, f"No clean corpus files found in {clean_dir}"
    assert len(evil_files) > 0, f"No evil corpus files found in {evil_dir}"

    clean_failures = []
    evil_failures = []
    for path in clean_files:
        with open(path, "rb") as corpus_file:
            content = corpus_file.read()
        if run_sanitizer(SANITIZER, content) != 0:
            clean_failures.append(os.path.basename(path))

    for path in evil_files:
        with open(path, "rb") as corpus_file:
            content = corpus_file.read()
        if run_sanitizer(SANITIZER, content) != 1:
            evil_failures.append(os.path.basename(path))

    errors = []
    if clean_failures:
        errors.append(
            f"{len(clean_failures)} of {len(clean_files)} clean modified (rejected): "
            + ", ".join(clean_failures)
        )
    if evil_failures:
        errors.append(
            f"{len(evil_failures)} of {len(evil_files)} evil inputs did not return exactly 1: "
            + ", ".join(evil_failures)
        )
    if errors:
        pytest.fail(" | ".join(errors))


def test_sanitizer_generated_policy_cases(tmp_path):
    rebuilt = tmp_path / "rebuilt_sanitizer"
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", SOURCE, "-o", str(rebuilt)],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, f"Failed to compile {SOURCE}: {compile_result.stderr}"

    alphabet = string.ascii_letters + string.digits + "-_"

    def token(minimum=4, maximum=20):
        return "".join(secrets.choice(alphabet) for _ in range(secrets.randbelow(maximum - minimum + 1) + minimum))

    cases = [
        b".", b"-", b"_", b"A" * 256, b"safe_name\n/ignored/after/newline",
        b"a..b", b"..hidden", b"trailing..", b"a...b", b"name\x00suffix",
    ]

    for _ in range(60):
        pieces = [token() for _ in range(secrets.randbelow(5) + 1)]
        cases.append(".".join(pieces).encode("ascii"))

    prefix = token().encode("ascii")
    suffix = token().encode("ascii")
    for byte in range(256):
        if byte not in ALLOWED and byte != 10:
            cases.append(prefix + bytes([byte]) + suffix)

    for _ in range(50):
        left = token().encode("ascii")
        right = token().encode("ascii")
        cases.append(left + b".." + right)

    for _ in range(100):
        length = secrets.randbelow(255) + 1
        cases.append(b"A" + secrets.token_bytes(length))

    for executable in (SANITIZER, str(rebuilt)):
        for index, content in enumerate(cases):
            expected = expected_status(content)
            actual = run_sanitizer(executable, content)
            assert actual == expected, (
                f"{executable} returned {actual}, expected {expected}, "
                f"for generated case {index}: {content!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
