#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import hashlib
import re

def test_flagged_payloads_log():
    log_path = "/home/user/flagged_payloads.log"
    assert os.path.isfile(log_path), f"Log file {log_path} is missing. Did the script run and create it?"

    payloads_dir = "/home/user/payloads"
    expected_lines = []

    # Patterns as described in the task
    patterns = [
        re.compile(r"nc -e"),
        re.compile(r"curl .* \| bash"),
        re.compile(r"wget .* -O- \| sh")
    ]

    # Recompute the expected output dynamically based on the files present
    for filename in sorted(os.listdir(payloads_dir)):
        if not filename.endswith(".json"):
            continue

        filepath = os.path.join(payloads_dir, filename)
        with open(filepath, "rb") as f:
            raw_bytes = f.read()

        try:
            data = json.loads(raw_bytes.decode('utf-8'))
            build_script_b64 = data.get("build_script", "")
            build_script = base64.b64decode(build_script_b64).decode('utf-8')

            is_malicious = False
            for p in patterns:
                if p.search(build_script):
                    is_malicious = True
                    break

            if is_malicious:
                file_hash = hashlib.sha256(raw_bytes).hexdigest()
                expected_lines.append(f"{filename}:{file_hash}")
        except Exception as e:
            # Skip files that aren't valid JSON or don't have valid base64, 
            # though the task assumes well-formed inputs.
            pass

    # Read the actual log file
    with open(log_path, "r") as f:
        content = f.read().strip()
        if content:
            actual_lines = [line.strip() for line in content.split('\n') if line.strip()]
        else:
            actual_lines = []

    assert actual_lines == expected_lines, (
        f"Log file contents do not match the expected results.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
