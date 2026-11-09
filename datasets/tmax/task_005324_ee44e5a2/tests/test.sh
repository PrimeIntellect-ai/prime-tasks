#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import os
import re
import secrets
import subprocess

LOG_FILE = "/home/user/api_requests.log"
C_SOURCE_FILE = "/home/user/revoke_keys.c"
EXECUTABLE_FILE = "/home/user/revoke_keys"
OUTPUT_FILE = "/home/user/revoked_hashes.txt"


def test_c_source_exists():
    assert os.path.exists(C_SOURCE_FILE), f"C source file {C_SOURCE_FILE} does not exist."
    assert os.path.isfile(C_SOURCE_FILE), f"Path {C_SOURCE_FILE} is not a file."


def test_executable_exists():
    assert os.path.exists(EXECUTABLE_FILE), f"Executable {EXECUTABLE_FILE} does not exist."
    assert os.path.isfile(EXECUTABLE_FILE), f"Path {EXECUTABLE_FILE} is not a file."
    assert os.access(EXECUTABLE_FILE, os.X_OK), f"File {EXECUTABLE_FILE} is not executable."
    with open(EXECUTABLE_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {EXECUTABLE_FILE} is not a compiled executable."


def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"Path {OUTPUT_FILE} is not a file."


def test_output_file_contents():
    # Derive expected hashes from the log file
    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} is missing."

    malicious_keys = set()
    with open(LOG_FILE, 'r') as f:
        for line in f:
            # Match IP and Auth Bearer
            # Format: [YYYY-MM-DD HH:MM:SS] IP: <ip_address> Method: <method> Path: <path> Auth: Bearer <api_key> Status: <status_code>
            ip_match = re.search(r"IP:\s*([0-9\.]+)", line)
            if ip_match:
                ip_addr = ip_match.group(1)
                if ip_addr.startswith("198.51.100."):
                    auth_match = re.search(r"Auth:\s*Bearer\s*(\S+)", line)
                    if auth_match:
                        malicious_keys.add(auth_match.group(1))

    expected_hashes = []
    for key in malicious_keys:
        sha256_hash = hashlib.sha256(key.encode('utf-8')).hexdigest()
        expected_hashes.append(sha256_hash)

    expected_hashes.sort()
    expected_content = "\n".join(expected_hashes) + "\n" if expected_hashes else ""

    with open(OUTPUT_FILE, 'r') as f:
        actual_content = f.read()

    # Standardize newlines for comparison
    actual_lines = [line.strip() for line in actual_content.strip().split('\n') if line.strip()]
    expected_lines = [line.strip() for line in expected_content.strip().split('\n') if line.strip()]

    assert actual_lines == expected_lines, f"Contents of {OUTPUT_FILE} do not match the expected sorted, unique SHA-256 hashes."


def test_program_and_source_process_fresh_log():
    rebuilt_executable = "/tmp/revoke_keys_from_source"
    compile_result = subprocess.run(
        ["gcc", "-o", rebuilt_executable, C_SOURCE_FILE, "-lssl", "-lcrypto"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, f"C source failed to compile: {compile_result.stderr}"

    keys = ["sk_dynamic_" + secrets.token_hex(16) for _ in range(3)]
    benign_key = "sk_benign_" + secrets.token_hex(16)
    dynamic_log = (
        f"[2026-01-01 00:00:00] IP: 198.51.100.7 Method: GET Path: /a Auth: Bearer {keys[1]} Status: 200\n"
        f"[2026-01-01 00:00:01] IP: 10.20.30.40 Method: POST Path: /b Auth: Bearer {benign_key} Status: 403\n"
        f"[2026-01-01 00:00:02] IP: 198.51.100.250 Method: DELETE Path: /c Auth: Bearer {keys[0]} Status: 200\n"
        f"[2026-01-01 00:00:03] IP: 198.51.100.7 Method: GET Path: /d Auth: Bearer {keys[1]} Status: 500\n"
        f"[2026-01-01 00:00:04] IP: 198.51.101.7 Method: GET Path: /e Auth: Bearer {benign_key} Status: 200\n"
        f"[2026-01-01 00:00:05] IP: 198.51.100.99 Method: PUT Path: /f Auth: Bearer {keys[2]} Status: 201\n"
    )
    expected = "\n".join(sorted(hashlib.sha256(k.encode("utf-8")).hexdigest() for k in set(keys))) + "\n"

    with open(LOG_FILE, "rb") as f:
        original_log = f.read()
    output_existed = os.path.exists(OUTPUT_FILE)
    original_output = None
    if output_existed:
        with open(OUTPUT_FILE, "rb") as f:
            original_output = f.read()

    try:
        with open(LOG_FILE, "w") as f:
            f.write(dynamic_log)

        for program in (EXECUTABLE_FILE, rebuilt_executable):
            if os.path.exists(OUTPUT_FILE):
                os.remove(OUTPUT_FILE)
            result = subprocess.run(
                [program],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, f"{program} failed when executed: {result.stderr}"
            assert os.path.isfile(OUTPUT_FILE), f"{program} did not create {OUTPUT_FILE}."
            with open(OUTPUT_FILE, "r") as f:
                actual = f.read()
            assert actual == expected, f"{program} did not produce exact sorted, unique hashes for a fresh log."
    finally:
        with open(LOG_FILE, "wb") as f:
            f.write(original_log)
        if output_existed:
            with open(OUTPUT_FILE, "wb") as f:
                f.write(original_output)
        elif os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        if os.path.exists(rebuilt_executable):
            os.remove(rebuilt_executable)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
