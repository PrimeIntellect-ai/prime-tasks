#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import stat
import subprocess


def test_cwe_finding():
    path = "/home/user/cwe_finding.txt"
    assert os.path.isfile(path), f"File not found: {path}"

    with open(path, "r") as f:
        content = f.read().strip().upper()

    valid_cwes = {"CWE-120", "CWE-119", "CWE-242"}
    assert content in valid_cwes, f"Expected one of {valid_cwes} in {path}, but found '{content}'"


def test_ddt_max():
    path = "/home/user/ddt_max.txt"
    assert os.path.isfile(path), f"File not found: {path}"

    with open(path, "r") as f:
        content = f.read().strip()

    with open("/home/user/sbox.txt", "r") as f:
        sbox = [int(value) for value in f.read().split()]

    assert len(sbox) == 16, "S-box must contain exactly 16 entries"
    assert all(0 <= value <= 15 for value in sbox), "S-box entries must be 4-bit values"

    candidates = []
    for delta_in in range(16):
        counts = [0] * 16
        for x in range(16):
            delta_out = sbox[x] ^ sbox[x ^ delta_in]
            counts[delta_out] += 1
        for delta_out, count in enumerate(counts):
            if not (delta_in == 0 and delta_out == 0):
                candidates.append((delta_in, delta_out, count))

    max_count = max(item[2] for item in candidates)
    smallest_delta_in = min(item[0] for item in candidates if item[2] == max_count)
    tied = [item for item in candidates if item[2] == max_count and item[0] == smallest_delta_in]
    assert len(tied) == 1, "Supplied S-box has an unresolved DeltaOut tie"
    expected = ",".join(str(value) for value in tied[0])

    assert content == expected, f"Expected '{expected}' in {path}, but found '{content}'"


def test_sensitive_data_redaction():
    clean_log_path = "/home/user/clean_requests.log"
    assert os.path.isfile(clean_log_path), f"File not found: {clean_log_path}"

    with open(clean_log_path, "r") as f:
        content = f.read()

    # Check that the specific credit card numbers are gone
    assert "4111222233334444" not in content, "Original 16-digit credit card number was not redacted"
    assert "5555666677778888" not in content, "Original 16-digit credit card number was not redacted"

    # Check that [REDACTED] is present in the expected locations
    assert "CreditCard: [REDACTED]" in content, "Expected 'CreditCard: [REDACTED]' in the cleaned log"
    assert "CC: [REDACTED], Expiry: 12/25" in content, "Expected 'CC: [REDACTED], Expiry: 12/25' in the cleaned log"

    # Verify no other 16-digit sequences exist just to be sure
    sixteen_digits = re.findall(r'\b\d{16}\b', content)
    assert len(sixteen_digits) == 0, f"Found unredacted 16-digit numbers in the cleaned log: {sixteen_digits}"


def test_redaction_program_implementation():
    source_path = "/home/user/redact.cpp"
    source_stat = os.lstat(source_path)
    assert stat.S_ISREG(source_stat.st_mode), f"Expected a regular C++ source file at {source_path}"

    executable = "/tmp/redact_submission"
    compile_result = subprocess.run(
        ["g++", "-std=c++17", source_path, "-o", executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"redact.cpp did not compile:\n{compile_result.stderr}"

    request_path = "/home/user/requests.log"
    clean_path = "/home/user/clean_requests.log"
    original_requests = open(request_path, "rb").read()
    original_clean = open(clean_path, "rb").read() if os.path.exists(clean_path) else None

    test_input = (
        "Card: 1234567890123456\n"
        "Two: 0000111122223333 and 9999888877776666.\n"
        "Short: 123456789012345\n"
        "Long: 12345678901234567\n"
        "Wrapped: (4242424242424242)\n"
    )
    expected = re.sub(r"(?<![0-9])[0-9]{16}(?![0-9])", "[REDACTED]", test_input)

    try:
        with open(request_path, "w") as f:
            f.write(test_input)
        if os.path.exists(clean_path):
            os.remove(clean_path)

        run_result = subprocess.run(
            [executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )
        assert run_result.returncode == 0, f"Redaction program failed:\n{run_result.stderr}"
        assert os.path.isfile(clean_path), "Redaction program did not create /home/user/clean_requests.log"

        with open(clean_path, "r") as f:
            actual = f.read()
        assert actual == expected, "Redaction program did not correctly redact arbitrary input"
    finally:
        with open(request_path, "wb") as f:
            f.write(original_requests)
        if original_clean is None:
            if os.path.exists(clean_path):
                os.remove(clean_path)
        else:
            with open(clean_path, "wb") as f:
                f.write(original_clean)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
