#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re

def test_decrypted_flag_exists_and_correct():
    flag_path = "/home/user/investigation/decrypted_flag.txt"
    assert os.path.exists(flag_path), f"Expected output file {flag_path} does not exist."
    assert os.path.isfile(flag_path), f"{flag_path} is not a file."

    # Derive the key from the artifacts to ensure we validate against the logical truth
    crash_report_path = "/home/user/investigation/crash_report.txt"
    memory_dump_path = "/home/user/investigation/memory.dump"

    assert os.path.exists(crash_report_path), "crash_report.txt is missing."
    with open(crash_report_path, "r") as f:
        crash_content = f.read()

    partial_key_match = re.search(r"partial_key\s*=\s*'([^']+)'", crash_content)
    assert partial_key_match is not None, "Could not find partial_key in crash_report.txt"
    partial_key = partial_key_match.group(1)

    assert os.path.exists(memory_dump_path), "memory.dump is missing."
    with open(memory_dump_path, "rb") as f:
        memory_content = f.read()

    key_fragment_match = re.search(b"KEY_START_(.*?)_KEY_END", memory_content)
    assert key_fragment_match is not None, "Could not find key fragment in memory.dump"
    key_fragment = key_fragment_match.group(1).decode('utf-8', errors='ignore')

    full_key = partial_key + key_fragment
    assert full_key == "X7ab9Xz", f"Derived key '{full_key}' does not match expected."

    # Read the decrypted flag
    with open(flag_path, "r") as f:
        decrypted_flag = f.read().strip()

    # We expect the flag to be properly decrypted and match the known format/value
    expected_flag = "FLAG{c0r3_dump_pc4p_n1nj4_m4st3r}"
    assert decrypted_flag == expected_flag, f"Decrypted flag is incorrect. Expected '{expected_flag}', got '{decrypted_flag}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
