#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_repo_mounted():
    mount_dir = "/home/user/repo_mount"
    assert os.path.isdir(mount_dir), f"The directory {mount_dir} does not exist. Did you extract the tarball?"

def test_corrupted_artifacts_file():
    output_file = "/home/user/corrupted_artifacts.txt"
    assert os.path.exists(output_file), f"The file {output_file} does not exist."
    assert os.path.isfile(output_file), f"{output_file} is not a file."

    with open(output_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_artifacts = ["libB", "libD"]

    assert lines == expected_artifacts, (
        f"Contents of {output_file} are incorrect. "
        f"Expected {expected_artifacts}, but got {lines}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
