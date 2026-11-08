#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_cracked_pin_file_exists_and_correct():
    """Check if cracked_pin.txt exists and contains the correct PIN."""
    path = "/home/user/cracked_pin.txt"
    assert os.path.isfile(path), f"File {path} is missing. The PIN was not written."

    with open(path, "r") as f:
        content = f.read()

    assert content == "7392", f"Expected PIN '7392', but found {repr(content)} in {path}."

def test_evidence_extracted():
    """Check if the evidence.zip was extracted to /home/user/evidence/."""
    evidence_dir = "/home/user/evidence"
    assert os.path.isdir(evidence_dir), f"Directory {evidence_dir} is missing. Evidence was not extracted."

    pyc_path = os.path.join(evidence_dir, "login_validator.pyc")
    hash_path = os.path.join(evidence_dir, "target_hash.txt")

    assert os.path.isfile(pyc_path), f"File {pyc_path} is missing from the extracted directory."
    assert os.path.isfile(hash_path), f"File {hash_path} is missing from the extracted directory."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
