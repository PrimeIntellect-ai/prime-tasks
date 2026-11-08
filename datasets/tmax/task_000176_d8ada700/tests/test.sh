#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import pytest


def test_forge_token_accuracy():
    script_path = '/home/user/forge_token.py'
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"{script_path} is not a file."

    success = 0
    total = 100
    for _ in range(total):
        username = ''.join(random.choices(string.ascii_letters, k=8))
        try:
            result = subprocess.run(
                ['python3', script_path, username],
                capture_output=True,
                text=True,
                timeout=2,
            )
            token = result.stdout.strip()
            expected_sig = sum(ord(char) for char in username) ^ 0x5A
            expected_token = f'{username}.0.{expected_sig}'

            # Retain validation against the supplied stripped binary while also
            # requiring the token to be forged for this specific username.
            oracle = subprocess.run(
                ['/app/auth_validator', token],
                capture_output=True,
            )
            if token == expected_token and oracle.returncode == 0:
                success += 1
        except Exception:
            pass

    accuracy = success / total
    assert accuracy >= 0.95, f"Accuracy too low: {accuracy} (expected >= 0.95). The script did not forge tokens reliably."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
