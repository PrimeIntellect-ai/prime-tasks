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

DECRYPT_RS = "/home/user/decrypt.rs"
REPORT = "/home/user/report.txt"
EVIDENCE = "/home/user/evidence.enc"
CERTIFICATE = "/home/user/attacker.pem"

KNOWN_PLAINTEXT = b"CRITICAL_EXFIL:root_password_hash_dumped"
KNOWN_EVIDENCE_LINE = "Decrypted Evidence: CRITICAL_EXFIL:root_password_hash_dumped"
KNOWN_CN_LINE = "Attacker CN: malicious-c2.local"


def recover_key(ciphertext, plaintext):
    assert len(ciphertext) == len(plaintext), "evidence.enc has an unexpected length"
    keystream = bytes(c ^ p for c, p in zip(ciphertext, plaintext))
    for period in range(1, len(keystream) + 1):
        if all(keystream[i] == keystream[i % period] for i in range(len(keystream))):
            key = keystream[:period]
            assert key.startswith(b"KEY_"), "Recovered XOR key does not have the required prefix"
            return key
    raise AssertionError("Could not recover a repeating XOR key")


def certificate_cn():
    result = subprocess.run(
        ["openssl", "x509", "-in", CERTIFICATE, "-noout", "-subject", "-nameopt", "RFC2253"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Unable to inspect attacker.pem: {result.stderr}"
    match = re.search(r"(?:^|,)CN=([^,]+)", result.stdout.strip().removeprefix("subject="))
    assert match, "No Common Name found in attacker.pem"
    return match.group(1)


def test_decrypt_rs_exists():
    path = DECRYPT_RS
    assert os.path.isfile(path), f"Rust decryption script missing at {path}"
    assert os.path.getsize(path) > 0, f"Rust decryption script at {path} is empty"


def test_report_txt_exists():
    assert os.path.isfile(REPORT), f"Final report missing at {REPORT}"


def test_report_txt_contents():
    assert os.path.isfile(REPORT), f"Final report missing at {REPORT}"
    with open(REPORT, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original expected-value assertions.
    assert KNOWN_EVIDENCE_LINE in content, "The decrypted evidence in the report is incorrect or missing."
    assert KNOWN_CN_LINE in content, "The attacker CN in the report is incorrect or missing."

    ciphertext = open(EVIDENCE, "rb").read()
    key = recover_key(ciphertext, KNOWN_PLAINTEXT)
    derived_plaintext = bytes(b ^ key[i % len(key)] for i, b in enumerate(ciphertext)).decode("utf-8")
    expected_lines = [
        f"Decrypted Evidence: {derived_plaintext}",
        f"Attacker CN: {certificate_cn()}",
    ]

    assert content.splitlines() == expected_lines, "report.txt must contain exactly the two requested lines"


def test_decrypt_rs_compiles_and_decrypts():
    original_ciphertext = open(EVIDENCE, "rb").read()
    key = recover_key(original_ciphertext, KNOWN_PLAINTEXT)

    fd, executable = tempfile.mkstemp(prefix="decrypt-verifier-")
    os.close(fd)
    os.unlink(executable)

    try:
        compiled = subprocess.run(
            ["rustc", DECRYPT_RS, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compiled.returncode == 0, f"decrypt.rs does not compile with rustc:\n{compiled.stderr}"
        assert os.path.isfile(executable) and os.access(executable, os.X_OK), "rustc did not produce an executable"

        cases = [KNOWN_PLAINTEXT]
        alphabet = (string.ascii_letters + string.digits + " _:-.!/").encode("ascii")
        for length in (7, 73):
            cases.append(bytes(secrets.choice(alphabet) for _ in range(length)))

        for plaintext in cases:
            ciphertext = bytes(b ^ key[i % len(key)] for i, b in enumerate(plaintext))
            with open(EVIDENCE, "wb") as f:
                f.write(ciphertext)

            result = subprocess.run(
                [executable],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=10,
            )
            assert result.returncode == 0, f"Compiled decryptor failed: {result.stderr.decode(errors='replace')}"
            assert result.stdout.rstrip(b"\r\n") == plaintext, "Compiled decryptor produced incorrect plaintext"
    finally:
        with open(EVIDENCE, "wb") as f:
            f.write(original_ciphertext)
        if os.path.exists(executable):
            os.unlink(executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
