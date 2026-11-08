#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import base64
import hashlib
import pytest

def test_recovered_paths_correctness():
    base_dir = "/home/user/ci_artifacts"
    log_file = os.path.join(base_dir, "link_error.log")
    registry_file = os.path.join(base_dir, "registry.dat")
    output_file = os.path.join(base_dir, "recovered_paths.txt")

    assert os.path.isfile(log_file), f"Expected log file {log_file} is missing."
    assert os.path.isfile(registry_file), f"Expected registry file {registry_file} is missing."
    assert os.path.isfile(output_file), f"Output file {output_file} was not created."

    # 1. Parse missing libraries from log
    missing_libs = set()
    with open(log_file, "r") as f:
        for line in f:
            match = re.search(r"cannot find -l(\S+)", line)
            if match:
                missing_libs.add(match.group(1))

    # 2. Parse registry and find valid paths
    expected_paths = []
    with open(registry_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(":")
            if len(parts) != 3:
                continue

            hex_name, b64_path, expected_md5 = parts

            try:
                lib_name = bytes.fromhex(hex_name).decode('utf-8')
            except ValueError:
                continue

            if lib_name in missing_libs:
                try:
                    decoded_path = base64.b64decode(b64_path).decode('utf-8')
                except Exception:
                    continue

                computed_md5 = hashlib.md5(decoded_path.encode('utf-8')).hexdigest()
                if computed_md5 == expected_md5:
                    expected_paths.append(decoded_path)

    expected_paths.sort()

    # Ensure writable source artifacts were not emptied or altered to change the answer.
    canonical_expected_paths = [
        "/opt/ci_cache/libmathutils.so",
        "/opt/network/libnetstack.so",
        "/usr/local/lib/libcoreengine.so",
    ]
    assert expected_paths == canonical_expected_paths, (
        "The source artifacts were modified and no longer produce the expected "
        f"recovery result. Got: {expected_paths}"
    )

    # 3. Read student's output
    with open(output_file, "r") as f:
        student_lines = [line.strip() for line in f if line.strip()]

    # 4. Compare
    assert student_lines == expected_paths, (
        f"Contents of {output_file} do not match the expected recovered paths. "
        f"Expected: {expected_paths}, Got: {student_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
