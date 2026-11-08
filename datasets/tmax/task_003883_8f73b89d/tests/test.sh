#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import itertools
import os
import re
import shutil
import stat
import subprocess
import tempfile
from functools import lru_cache

HASH_PATH = "/home/user/pass_hash.txt"
CRACKER_PATH = "/home/user/cracker.c"

@lru_cache(maxsize=1)
def recovered_passphrase():
    with open(HASH_PATH, "r", encoding="ascii") as f:
        target = f.read().strip().lower()
    assert re.fullmatch(r"[0-9a-f]{64}", target), "pass_hash.txt is not a SHA256 hex digest"
    for chars in itertools.product("abcdefghijklmnopqrstuvwxyz", repeat=4):
        candidate = "".join(chars)
        if hashlib.sha256(candidate.encode()).hexdigest() == target:
            return candidate
    raise AssertionError("The supplied hash has no four-letter lowercase preimage")

def run_cracker(binary, expected):
    result = subprocess.run(
        [binary], cwd="/home/user", text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, (
        f"cracker exited with {result.returncode}: {result.stdout}{result.stderr}"
    )
    output = result.stdout + "\n" + result.stderr
    assert re.search(rf"(?<![a-z]){re.escape(expected)}(?![a-z])", output), (
        f"cracker output did not report the recovered passphrase {expected!r}"
    )

def test_cracker_c_exists_compiles_and_bruteforces():
    assert os.path.isfile(CRACKER_PATH), f"Missing C program: {CRACKER_PATH}"
    binary = "/tmp/submitted_cracker"
    built = subprocess.run(
        ["gcc", CRACKER_PATH, "-o", binary, "-lcrypto"],
        text=True, capture_output=True, timeout=30
    )
    assert built.returncode == 0, f"cracker.c does not compile:\n{built.stdout}{built.stderr}"

    original_hash = open(HASH_PATH, "rb").read()
    expected = recovered_passphrase()
    try:
        run_cracker(binary, expected)

        # Exercise the submitted program on another verifier-derived hash so a
        # program which merely prints the known image passphrase is rejected.
        digest = hashlib.sha256(original_hash.strip()).digest()
        alternate = "aa" + chr(ord("a") + digest[0] % 26) + chr(ord("a") + digest[1] % 26)
        alternate_hash = hashlib.sha256(alternate.encode()).hexdigest().encode("ascii")
        with open(HASH_PATH, "wb") as f:
            f.write(alternate_hash)
        run_cracker(binary, alternate)
    finally:
        with open(HASH_PATH, "wb") as f:
            f.write(original_hash)

def test_old_key_decrypts_with_recovered_passphrase():
    passphrase = recovered_passphrase()
    result = subprocess.run(
        ["openssl", "pkey", "-in", "/home/user/old_key.pem", "-passin", f"pass:{passphrase}", "-check", "-noout"],
        text=True, capture_output=True, timeout=15
    )
    assert result.returncode == 0, f"Old key could not be decrypted with the recovered passphrase: {result.stderr}"

def test_new_key_exists_and_valid():
    priv_path = "/home/user/new_key"
    pub_path = "/home/user/new_key.pub"

    assert os.path.isfile(priv_path), f"Missing new private key: {priv_path}"
    assert os.path.isfile(pub_path), f"Missing new public key: {pub_path}"

    with open(priv_path, "r") as f:
        priv_content = f.read()
    assert "OPENSSH PRIVATE KEY" in priv_content, f"The file {priv_path} does not appear to be a valid unencrypted OpenSSH private key."

    with tempfile.TemporaryDirectory() as td:
        private_copy = os.path.join(td, "new_key")
        shutil.copyfile(priv_path, private_copy)
        os.chmod(private_copy, stat.S_IRUSR | stat.S_IWUSR)
        derived = subprocess.run(
            ["ssh-keygen", "-y", "-P", "", "-f", private_copy],
            text=True, capture_output=True, timeout=15
        )
    assert derived.returncode == 0, f"new_key is not a valid unencrypted SSH private key: {derived.stderr}"

    pub_text = open(pub_path, "r", encoding="utf-8").read().strip()
    assert "\n" not in pub_text and "\r" not in pub_text, "new_key.pub must contain one public-key line"
    pub_fields = pub_text.split()
    derived_fields = derived.stdout.strip().split()
    assert len(pub_fields) >= 2, "new_key.pub is not a valid SSH public key"
    assert pub_fields[0] == "ssh-ed25519", "The new public key is not ED25519"
    assert len(derived_fields) >= 2 and derived_fields[:2] == pub_fields[:2], "new_key.pub does not correspond to new_key"

    checked = subprocess.run(
        ["ssh-keygen", "-lf", pub_path], text=True, capture_output=True, timeout=15
    )
    assert checked.returncode == 0 and "ED25519" in checked.stdout, f"Invalid ED25519 public key: {checked.stderr}"

def test_rotation_summary():
    summary_path = "/home/user/rotation_summary.txt"
    pub_path = "/home/user/new_key.pub"

    assert os.path.isfile(summary_path), f"Missing summary file: {summary_path}"
    assert os.path.isfile(pub_path), f"Missing public key file: {pub_path}"

    with open(pub_path, "r") as f:
        pub_key_content = f.read().strip()
    with open(summary_path, "r") as f:
        summary_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(summary_lines) >= 2, f"Summary file {summary_path} does not have enough lines."
    expected_passphrase = recovered_passphrase()
    assert summary_lines[0] == f"Old Passphrase: {expected_passphrase}", f"Line 1 of summary file is incorrect: {summary_lines[0]!r}"
    expected_line_2 = f"New Public Key: {pub_key_content}"
    assert summary_lines[1] == expected_line_2, f"Line 2 of summary file is incorrect. Expected {expected_line_2!r}, got {summary_lines[1]!r}"
    assert summary_lines == [f"Old Passphrase: {expected_passphrase}", expected_line_2], "Summary must contain exactly the required two non-empty lines"

def test_audit_log_redacted():
    log_path = "/home/user/audit.log"
    assert os.path.isfile(log_path), f"Missing audit log file: {log_path}"

    with open(log_path, "r") as f:
        log_content = f.read()

    passphrase = recovered_passphrase()
    assert passphrase not in log_content, "The audit log still contains the plaintext passphrase."
    assert "wolf" not in log_content, "The audit log still contains the plaintext passphrase 'wolf'."
    assert "-----BEGIN ENCRYPTED PRIVATE KEY-----" not in log_content, "The audit log still contains the old encrypted private key header."
    assert "-----END ENCRYPTED PRIVATE KEY-----" not in log_content, "The audit log still contains the old encrypted private key footer."
    assert "[REDACTED_PASS]" in log_content, "The audit log does not contain the required '[REDACTED_PASS]' string."
    assert "[REDACTED_KEY]" in log_content, "The audit log does not contain the required '[REDACTED_KEY]' string."

    expected = (
        "Audit started at 10:00 AM.\n"
        "User attempted to login with password: [REDACTED_PASS]\n"
        "SSH key generation output:\n"
        "[REDACTED_KEY]\n"
        "Audit finished at 10:05 AM. Next steps: ensure [REDACTED_PASS] is rotated.\n"
    )
    assert log_content == expected, "audit.log was not redacted in-place while preserving the non-sensitive log content"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
