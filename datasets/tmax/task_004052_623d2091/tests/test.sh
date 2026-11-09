#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_secret_txt_exists_and_correct():
    """Verify that /home/user/secret.txt exists and contains the correct access token."""
    path = "/home/user/secret.txt"

    assert os.path.exists(path), f"The file {path} does not exist."
    assert os.path.isfile(path), f"{path} is not a regular file."

    with open(path, "r", encoding="utf-8") as f:
        content = f.read()

    expected_token = "AUTH_TOKEN_99_SYSADMIN_ACCESS_7721"

    assert content == expected_token, (
        f"The content of {path} is incorrect. "
        f"Expected '{expected_token}', but got '{content}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
