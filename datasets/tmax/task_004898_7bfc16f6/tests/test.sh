#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess

from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.padding import PKCS7


def test_sanitized_payload_metric():
    script_file = "/home/user/analyze.py"
    target_file = "/home/user/sanitized_payload.elf"
    encrypted_file = "/app/payload.enc"

    assert os.path.exists(script_file), f"Expected analysis script {script_file} does not exist."
    assert stat.S_ISREG(os.stat(script_file).st_mode), f"{script_file} is not a regular file."

    # Independently decrypt the supplied payload and derive the exact required output.
    with open(encrypted_file, "rb") as f:
        encrypted = f.read()
    assert len(encrypted) >= 32 and (len(encrypted) - 16) % 16 == 0

    key_string = "N3tw0rkS3cur1ty2023!@#$"
    key = key_string.ljust(32, "X").encode("utf-8")
    iv, ciphertext = encrypted[:16], encrypted[16:]
    decryptor = Cipher(algorithms.AES(key), modes.CBC(iv)).decryptor()
    padded = decryptor.update(ciphertext) + decryptor.finalize()
    unpadder = PKCS7(128).unpadder()
    original = unpadder.update(padded) + unpadder.finalize()
    assert original.startswith(b"\x7fELF"), "The decrypted source payload is not an ELF file."

    octet = rb"(?:25[0-5]|2[0-4][0-9]|1[0-9]{2}|[1-9]?[0-9])"
    target_pattern = re.compile(rb"(?<![0-9])10\.42\." + octet + rb"\." + octet + rb"(?![0-9])")
    matches = list(target_pattern.finditer(original))
    assert matches, "The decrypted payload contains no 10.42.0.0/16 addresses."
    expected = target_pattern.sub(lambda m: b"*" * len(m.group(0)), original)

    # Force the submitted script itself to recreate the artifact.
    if os.path.lexists(target_file):
        os.remove(target_file)
    result = subprocess.run(
        ["python3", script_file],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
        check=False,
    )
    assert result.returncode == 0, (
        f"analyze.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout.decode(errors='replace')}\n"
        f"stderr:\n{result.stderr.decode(errors='replace')}"
    )

    assert os.path.exists(target_file), f"Expected output file {target_file} does not exist."
    assert stat.S_ISREG(os.stat(target_file).st_mode), f"{target_file} is not a regular file."

    with open(target_file, "rb") as f:
        data = f.read()

    # Check if it's still a valid ELF
    assert data.startswith(b"\x7fELF"), "The file is no longer a valid ELF binary. The ELF header is missing or corrupted."

    # Check if non-target IPs are intact
    assert b"192.168.1.100" in data, "Non-target IP '192.168.1.100' was modified or removed. It should remain intact."
    assert b"8.8.8.8" in data, "Non-target IP '8.8.8.8' was modified or removed. It should remain intact."

    # Check redaction of target IPs
    redacted_count = data.count(b"***********")
    target_ips_absent = (b"10.42.15.99" not in data) and (b"10.42.200.1" not in data)
    asterisks_present = redacted_count >= 2
    score = 1.0 if (target_ips_absent and asterisks_present) else 0.0
    assert score >= 1.0, f"Redaction Accuracy Score is {score}, expected >= 1.0. Target IPs were either not fully redacted or not replaced with the correct number of asterisks."

    # Require a byte-for-byte copy of the decrypted ELF with only every target
    # subnet IP replaced, preserving all other bytes and the exact file length.
    assert len(data) == len(original), "Sanitization changed the payload length."
    assert data == expected, "The output differs from the decrypted payload beyond the required 10.42.0.0/16 redactions."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
