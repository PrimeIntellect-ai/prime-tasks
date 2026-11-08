#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import glob
import hashlib
import pytest

def get_vulnerable_module():
    """Dynamically identify the vulnerable module based on the presence of an f-string SQL query."""
    handlers_dir = "/home/user/app/handlers/"
    if not os.path.exists(handlers_dir):
        return "report_generator"  # Fallback if directory is missing for some reason

    for filepath in glob.glob(os.path.join(handlers_dir, "*.py")):
        with open(filepath, "r") as f:
            content = f.read()
            # Look for direct f-string formatting in SQL execution
            if "cursor.execute(f\"SELECT" in content or "cursor.execute(f'SELECT" in content:
                return os.path.splitext(os.path.basename(filepath))[0]

    return "report_generator"

def test_final_payload():
    payload_file = "/home/user/final_payload.txt"
    assert os.path.exists(payload_file), f"File {payload_file} does not exist. You must save your payload here."

    module_name = get_vulnerable_module()
    base_payload = f"{module_name}:<svg onload=alert(1)>:"

    # Compute the expected nonce to verify the student's work
    expected_nonce = 1
    while True:
        test_payload = f"{base_payload}{expected_nonce}"
        if hashlib.md5(test_payload.encode()).hexdigest().startswith("00000"):
            break
        expected_nonce += 1

    expected_payload = f"{base_payload}{expected_nonce}"

    with open(payload_file, "r") as f:
        actual_payload = f.read()

    assert actual_payload == expected_payload, (
        f"The payload in {payload_file} is incorrect. "
        f"Ensure you identified the correct module, formatted the payload properly, "
        f"found the lowest positive nonce for the MD5 collision, and did not include a trailing newline."
    )

def test_traversal_path():
    traversal_file = "/home/user/traversal_path.txt"
    assert os.path.exists(traversal_file), f"File {traversal_file} does not exist. You must save your traversal path here."

    upload_dir = "/home/user/app/public/uploads/"
    target_file = "/home/user/secret_config.json"

    # Compute the expected relative path dynamically
    expected_path = os.path.relpath(target_file, upload_dir)

    with open(traversal_file, "r") as f:
        actual_path = f.read()

    assert actual_path == expected_path, (
        f"The traversal path in {traversal_file} is incorrect. "
        f"Expected the minimal relative path from {upload_dir} to {target_file} without a trailing newline."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
