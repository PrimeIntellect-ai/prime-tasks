#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import hashlib

def test_artifact_hash_file_exists():
    output_path = "/home/user/artifact_hash.txt"
    assert os.path.exists(output_path), f"The output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"{output_path} is not a regular file."

def test_artifact_hash_is_correct():
    output_path = "/home/user/artifact_hash.txt"
    assert os.path.exists(output_path), f"The output file {output_path} does not exist."

    with open(output_path, "r") as f:
        actual_hash = f.read().strip()

    # Recompute the expected hash based on the setup specification
    artifact_data = b"MOCK_SECRET_DATA_FOR_LAYER_42_" * 1000
    expected_hash = hashlib.sha256(artifact_data).hexdigest()

    assert actual_hash == expected_hash, f"Expected hash {expected_hash}, but got {actual_hash}."

def test_no_files_extracted_to_disk():
    # Ensure the student did not extract the archives to disk in /home/user
    user_dir = "/home/user"
    extracted_files_found = []

    for filename in os.listdir(user_dir):
        if filename.startswith("layer_") and filename.endswith(".tar"):
            extracted_files_found.append(filename)
        if filename == "secret_artifact.bin":
            extracted_files_found.append(filename)

    assert not extracted_files_found, (
        f"Found extracted files on disk: {', '.join(extracted_files_found)}. "
        "The task requires streaming I/O without extracting archives to disk."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
