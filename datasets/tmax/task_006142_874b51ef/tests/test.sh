#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import gzip

def test_db_timeout_updates_directory():
    output_dir = "/home/user/db_timeout_updates"
    assert os.path.isdir(output_dir), f"Directory {output_dir} does not exist."

def test_chunk_files_exist_and_counts():
    output_dir = "/home/user/db_timeout_updates"
    expected_files = ["update_chunk_0.log.gz", "update_chunk_1.log.gz", "update_chunk_2.log.gz"]

    # Check that only the expected files are in the directory
    actual_files = set(os.listdir(output_dir))
    assert actual_files == set(expected_files), f"Expected exactly {expected_files} in {output_dir}, found {actual_files}."

    expected_counts = {
        "update_chunk_0.log.gz": 500,
        "update_chunk_1.log.gz": 500,
        "update_chunk_2.log.gz": 234
    }

    for filename, expected_count in expected_counts.items():
        filepath = os.path.join(output_dir, filename)
        assert os.path.isfile(filepath), f"File {filepath} is missing."

        with gzip.open(filepath, "rt") as f:
            lines = f.readlines()
            assert len(lines) == expected_count, f"File {filepath} should have {expected_count} lines, but has {len(lines)}."

def test_content_matches():
    input_file = "/home/user/server_configs.log.gz"
    output_dir = "/home/user/db_timeout_updates"
    expected_files = ["update_chunk_0.log.gz", "update_chunk_1.log.gz", "update_chunk_2.log.gz"]

    # Read original matching lines
    original_matching_lines = []
    with gzip.open(input_file, "rt") as f:
        for line in f:
            parts = [p.strip() for p in line.split("|")]
            if len(parts) >= 4 and parts[2] == "UPDATE" and parts[3] == "db_timeout":
                original_matching_lines.append(line)

    # Read output matching lines
    output_matching_lines = []
    for filename in expected_files:
        filepath = os.path.join(output_dir, filename)
        if os.path.isfile(filepath):
            with gzip.open(filepath, "rt") as f:
                output_matching_lines.extend(f.readlines())

    assert len(output_matching_lines) == len(original_matching_lines), \
        f"Total output lines ({len(output_matching_lines)}) does not match expected total ({len(original_matching_lines)})."

    for i, (out_line, orig_line) in enumerate(zip(output_matching_lines, original_matching_lines)):
        assert out_line == orig_line, f"Line {i} mismatch. Expected: {orig_line!r}, Got: {out_line!r}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
