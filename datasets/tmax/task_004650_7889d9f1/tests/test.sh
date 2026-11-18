#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import subprocess

SANITIZER_BIN = "/home/user/sanitizer"
SANITIZER_SRC = "/home/user/sanitizer.c"
LIB_DIR = "/app/fastpbkdf2"
LIB_PATH = os.path.join(LIB_DIR, "libfastpbkdf2.a")
MAKEFILE = os.path.join(LIB_DIR, "Makefile")
EVIL_DIR = "/opt/corpora/evil"
CLEAN_DIR = "/opt/corpora/clean"
ITERATIONS = 100000


def run_sanitizer(input_data: bytes) -> bytes:
    result = subprocess.run(
        [SANITIZER_BIN],
        input=input_data,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5
    )
    assert result.returncode == 0, result.stderr.decode("utf-8", errors="replace")
    return result.stdout


def test_sanitizer_executable_exists():
    assert os.path.isfile(SANITIZER_BIN), f"Executable {SANITIZER_BIN} not found."
    assert os.access(SANITIZER_BIN, os.X_OK), f"{SANITIZER_BIN} is not executable."
    with open(SANITIZER_BIN, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sanitizer must be a compiled executable"
    assert os.path.isfile(SANITIZER_SRC), f"C source {SANITIZER_SRC} not found."


def test_fastpbkdf2_was_fixed_built_and_linked():
    with open(MAKEFILE, "r", encoding="utf-8", errors="replace") as f:
        makefile_text = f.read()
    assert "-Oinvalid" not in makefile_text, "The invalid compiler flag remains in the Makefile"

    build = subprocess.run(
        ["make", "-B"], cwd=LIB_DIR,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert build.returncode == 0, build.stderr.decode("utf-8", errors="replace")
    assert os.path.isfile(LIB_PATH), "libfastpbkdf2.a was not built"

    archive = subprocess.run(
        ["ar", "t", LIB_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert archive.returncode == 0, archive.stderr.decode("utf-8", errors="replace")
    assert b"fastpbkdf2.o" in archive.stdout, "Library archive lacks fastpbkdf2.o"

    library_symbols = subprocess.run(
        ["nm", "-g", LIB_PATH], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert library_symbols.returncode == 0
    assert b"fastpbkdf2_hmac_sha256" in library_symbols.stdout

    executable_symbols = subprocess.run(
        ["nm", "-a", SANITIZER_BIN], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=5
    )
    assert executable_symbols.returncode == 0, "sanitizer is stripped or cannot be inspected"
    assert re.search(rb"\bfastpbkdf2_hmac_sha256\b", executable_symbols.stdout), \
        "sanitizer is not linked against the required fastpbkdf2 SHA-256 implementation"


def test_clean_corpus_preserved():
    clean_files = [f for f in os.listdir(CLEAN_DIR) if os.path.isfile(os.path.join(CLEAN_DIR, f))]
    assert clean_files, "No clean corpus files found."

    modified_files = []
    for filename in clean_files:
        filepath = os.path.join(CLEAN_DIR, filename)
        with open(filepath, "rb") as f:
            input_data = f.read()

        output_data = run_sanitizer(input_data)

        if output_data != input_data:
            modified_files.append(filename)

    assert not modified_files, f"{len(modified_files)} of {len(clean_files)} clean files modified: {', '.join(modified_files)}"


def test_evil_corpus_redacted():
    evil_files = [f for f in os.listdir(EVIL_DIR) if os.path.isfile(os.path.join(EVIL_DIR, f))]
    assert evil_files, "No evil corpus files found."

    bypassed_files = []
    for filename in evil_files:
        filepath = os.path.join(EVIL_DIR, filename)
        with open(filepath, "rb") as f:
            input_data = f.read()

        output_data = run_sanitizer(input_data)
        output_text = output_data.decode("utf-8", errors="replace")

        has_private_key = (
            "BEGIN PRIVATE KEY" in output_text or
            "BEGIN RSA PRIVATE KEY" in output_text or
            "END PRIVATE KEY" in output_text or
            "END RSA PRIVATE KEY" in output_text
        )
        has_redacted = "REDACTED" in output_text

        if has_private_key or not has_redacted:
            bypassed_files.append(filename)

    assert not bypassed_files, f"{len(bypassed_files)} of {len(evil_files)} evil files bypassed: {', '.join(bypassed_files)}"


def pbkdf2_hex(password: str, salt: str) -> str:
    return hashlib.pbkdf2_hmac(
        "sha256", password.encode(), salt.encode(), ITERATIONS, dklen=32
    ).hex()


def test_derived_authentication_and_mixed_pem_behavior():
    cases = [
        ("alice_91", "password", "auditSaltA91"),
        ("svc-build7", "123456", "buildSaltB72"),
        ("ops.admin", "admin", "opsSaltC53"),
    ]

    input_lines = ["TRACE request accepted\n"]
    expected_lines = ["TRACE request accepted\n"]

    for username, password, salt in cases:
        digest = pbkdf2_hex(password, salt)
        input_lines.append(f"AUTH user:{username} hash:{digest} salt:{salt}\n")
        expected_lines.append(f"AUTH user:{username} REDACTED\n")
        normal = f"INFO authentication processing completed for {username}\n"
        input_lines.append(normal)
        expected_lines.append(normal)

    strong_salt = "strongSaltZ84"
    strong_hash = pbkdf2_hex("correct-horse-battery-staple", strong_salt)
    strong_line = f"AUTH user:secure-user hash:{strong_hash} salt:{strong_salt}\n"
    input_lines.append(strong_line)
    expected_lines.append(strong_line)

    certificate = [
        "-----BEGIN CERTIFICATE-----\n",
        "MIIC-public-certificate-data-12345\n",
        "-----END CERTIFICATE-----\n",
    ]
    input_lines.extend(certificate)
    expected_lines.extend(certificate)

    input_lines.extend([
        "prefix -----BEGIN PRIVATE KEY----- sensitive\n",
        "secret-private-material-one\n",
        "suffix -----END PRIVATE KEY-----\n",
    ])
    input_lines.append("NOTICE between private key blocks\n")
    expected_lines.append("NOTICE between private key blocks\n")
    input_lines.extend([
        "-----BEGIN RSA PRIVATE KEY-----\n",
        "secret-rsa-material-two\n",
        "-----END RSA PRIVATE KEY-----\n",
    ])
    input_lines.append("Final normal log line.\n")
    expected_lines.append("Final normal log line.\n")

    actual = run_sanitizer("".join(input_lines).encode())
    expected = "".join(expected_lines).encode()
    assert actual == expected, (
        "sanitizer did not exactly redact derived weak hashes/private-key blocks "
        "while preserving strong authentication, certificates, and normal logs"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
