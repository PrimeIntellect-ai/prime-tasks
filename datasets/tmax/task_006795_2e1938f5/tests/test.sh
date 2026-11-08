#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess

DECRYPTOR = "/home/user/decryptor.rs"
ENCRYPTED = "/home/user/logs/encrypted_log.bin"
DECRYPTED = "/home/user/logs/decrypted_log.txt"
FLAG = "/home/user/flag.txt"
BINARY = "/tmp/submission_decryptor"
HEADER = b"[SECURE_LOG_V1]"

ORIGINAL_PLAINTEXT = (
    b"[SECURE_LOG_V1]\n"
    b"2023-10-10 10:00:01 [INFO] System started\n"
    b"2023-10-10 10:05:23 [ALERT] MALWARE_SIGNATURE_MATCH detected from IP: 10.0.0.42 port: 4444\n"
    b"2023-10-10 10:06:00 [WARN] High CPU usage\n"
    b"2023-10-10 10:15:11 [ALERT] MALWARE_SIGNATURE_MATCH detected from IP: 192.168.1.100 port: 8080\n"
    b"2023-10-10 10:15:15 [INFO] User admin logged in\n"
    b"2023-10-10 10:20:05 [ALERT] MALWARE_SIGNATURE_MATCH detected from IP: 10.0.0.42 port: 4445\n"
    b"2023-10-10 10:25:00 [ALERT] BRUTE_FORCE_ATTACK detected from IP: 172.16.0.5 port: 22\n"
)


def crypt(data, seed):
    state = seed
    output = bytearray()
    for byte in data:
        state = (1103515245 * state + 12345) % 2147483648
        output.append(byte ^ (state & 0xFF))
    return bytes(output)


def independently_decrypt(ciphertext):
    # Only the low state byte is emitted, so all seeds in the same residue
    # class modulo 256 are equivalent. Recover that class from the known header.
    matching = []
    for seed_low_byte in range(256):
        if crypt(ciphertext[:len(HEADER)], seed_low_byte) == HEADER:
            matching.append(seed_low_byte)
    assert len(matching) == 1, f"Expected one seed residue class, found {matching}"
    return crypt(ciphertext, matching[0])


def expected_ips(plaintext):
    text = plaintext.decode("utf-8")
    found = set()
    for line in text.splitlines():
        if "[ALERT] MALWARE_SIGNATURE_MATCH" not in line:
            continue
        match = re.search(r"detected from IP:\s*([0-9]+(?:\.[0-9]+){3})", line)
        assert match, f"Malformed malware alert in verifier input: {line!r}"
        found.add(match.group(1))
    return sorted(found)


def run_submission(ciphertext, expected_plaintext):
    with open(ENCRYPTED, "wb") as f:
        f.write(ciphertext)

    for path in (DECRYPTED, FLAG):
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass

    subprocess.run(
        [BINARY],
        cwd="/home/user",
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    assert os.path.isfile(DECRYPTED), f"Expected decrypted log at {DECRYPTED} is missing."
    with open(DECRYPTED, "rb") as f:
        actual_plaintext = f.read()
    assert actual_plaintext == expected_plaintext, "The generated decrypted log does not match the encrypted input."

    text = actual_plaintext.decode("utf-8")
    assert "[SECURE_LOG_V1]" in text, "The decrypted log does not contain the expected known plaintext header."
    assert "MALWARE_SIGNATURE_MATCH" in text, "The decrypted log does not contain the expected alert lines."

    assert os.path.isfile(FLAG), f"Expected output file at {FLAG} is missing."
    with open(FLAG, "r", encoding="utf-8") as f:
        actual_ips = [line.strip() for line in f if line.strip()]
    assert actual_ips == expected_ips(expected_plaintext), \
        f"The contents of {FLAG} are not the sorted unique malware-alert IPs. Got: {actual_ips}"


def test_decryptor_rs_exists():
    assert os.path.isfile(DECRYPTOR), f"Expected decryptor source code at {DECRYPTOR} is missing."


def test_decryptor_compiles_runs_and_processes_ciphertext():
    with open(ENCRYPTED, "rb") as f:
        original_ciphertext = f.read()

    expected_original_ciphertext = crypt(ORIGINAL_PLAINTEXT, 42133)
    assert original_ciphertext == expected_original_ciphertext, "The provided encrypted log was modified."

    subprocess.run(
        ["rustc", DECRYPTOR, "-O", "-o", BINARY],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    # First exercise the submitted program on an unseen valid encrypted log so
    # pre-created or hardcoded output files cannot pass.
    a = secrets.randbelow(200) + 1
    b = secrets.randbelow(200) + 1
    synthetic_plaintext = (
        "[SECURE_LOG_V1]\n"
        "2026-01-01 00:00:00 [INFO] verifier generated event\n"
        f"2026-01-01 00:00:01 [ALERT] MALWARE_SIGNATURE_MATCH detected from IP: 198.51.100.{a} port: 9001\n"
        "2026-01-01 00:00:02 [ALERT] BRUTE_FORCE_ATTACK detected from IP: 203.0.113.9 port: 22\n"
        f"2026-01-01 00:00:03 [ALERT] MALWARE_SIGNATURE_MATCH detected from IP: 192.0.2.{b} port: 9002\n"
        f"2026-01-01 00:00:04 [ALERT] MALWARE_SIGNATURE_MATCH detected from IP: 198.51.100.{a} port: 9003\n"
    ).encode("utf-8")
    synthetic_ciphertext = crypt(synthetic_plaintext, secrets.randbelow(65536))
    derived_synthetic = independently_decrypt(synthetic_ciphertext)
    assert derived_synthetic == synthetic_plaintext
    run_submission(synthetic_ciphertext, derived_synthetic)

    # Run again on the actual task input and retain the required final files.
    derived_original = independently_decrypt(original_ciphertext)
    assert derived_original == ORIGINAL_PLAINTEXT
    run_submission(original_ciphertext, derived_original)

    with open(FLAG, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    expected_original_ips = ["10.0.0.42", "192.168.1.100"]
    assert lines == expected_original_ips, \
        f"The contents of {FLAG} do not match the expected unique, sorted IP addresses. Got: {lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
