#!/bin/bash
set -e
mkdir -p /logs/verifier

SCRIPT=/home/user/process_data.sh
OUTPUT=/home/user/output.json

# Require the requested artifact to be a real executable file.
if [ ! -f "$SCRIPT" ] || [ -L "$SCRIPT" ] || [ ! -x "$SCRIPT" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

# Add an unpredictable ordinary input so a fixed fabricated output cannot pass.
probe_name="verifier_probe_$(python3 -c 'import secrets; print(secrets.token_hex(8))').bin"
probe_size=$((131072 + RANDOM % 32768))
head -c "$probe_size" /dev/zero > "/home/user/data/$probe_name"
chmod 644 "/home/user/data/$probe_name"

# Prove that the submitted script itself creates the result.
rm -f "$OUTPUT" /home/user/summary.json
if ! runuser -u user -- /bin/bash -c 'cd /home/user && ./process_data.sh'; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

OUTPUT_JSON_PATH = "/home/user/output.json"
DATA_DIR = b"/home/user/data"

def test_output_json_exists():
    assert os.path.isfile(OUTPUT_JSON_PATH), f"{OUTPUT_JSON_PATH} does not exist."

def test_output_json_valid_and_contains_keys():
    with open(OUTPUT_JSON_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {OUTPUT_JSON_PATH} as valid JSON: {e}")

    assert "average_size_mb" in data, "Key 'average_size_mb' is missing from JSON."
    assert "processed_files" in data, "Key 'processed_files' is missing from JSON."

def test_average_size_mb_format():
    with open(OUTPUT_JSON_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    avg_mb = data["average_size_mb"]
    assert isinstance(avg_mb, (int, float)), "average_size_mb must be a number."

    # The value should be around 0.11 or 0.12 based on the setup
    assert 0.0 < avg_mb < 1.0, f"average_size_mb should be > 0 and < 1, but got {avg_mb}"

    # Python's json.load strictly enforces leading zeros for floats < 1,
    # so successfully parsing it confirms the leading zero requirement.
    # We can also double check the raw string just in case:
    with open(OUTPUT_JSON_PATH, "r", encoding="utf-8") as f:
        raw_content = f.read()
        # It shouldn't contain ": ."
        assert ": ." not in raw_content.replace(" ", ""), "average_size_mb must have a leading zero (e.g., 0.11 instead of .11)"

def test_average_size_mb_matches_actual_files():
    with open(OUTPUT_JSON_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    avg_mb = data["average_size_mb"]
    assert isinstance(avg_mb, (int, float)) and not isinstance(avg_mb, bool), \
        "average_size_mb must be a JSON number."
    assert math.isfinite(avg_mb), "average_size_mb must be finite."

    file_paths = []
    for name in os.listdir(DATA_DIR):
        path = os.path.join(DATA_DIR, name)
        if os.path.isfile(path):
            file_paths.append(path)

    assert file_paths, "The data directory unexpectedly contains no files."
    expected = sum(os.stat(path).st_size for path in file_paths) / len(file_paths) / 1048576
    # The original script is intended to report two decimal places, so permit
    # either truncation or rounding at that precision.
    assert abs(avg_mb - expected) <= 0.011, \
        f"average_size_mb is incorrect: expected about {expected}, got {avg_mb}"

def test_processed_files_contains_utf8_resume():
    with open(OUTPUT_JSON_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    processed_files = data["processed_files"]
    assert isinstance(processed_files, list), "processed_files must be an array."

    expected_filename = "résumé.txt"
    assert expected_filename in processed_files, f"'{expected_filename}' (UTF-8) not found in processed_files array."

def test_all_files_processed():
    with open(OUTPUT_JSON_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    processed_files = data["processed_files"]

    # Read actual files in the directory
    actual_files_bytes = os.listdir(DATA_DIR)

    # Convert actual files to UTF-8 using latin-1 fallback
    expected_files = []
    for f_bytes in actual_files_bytes:
        try:
            expected_files.append(f_bytes.decode('utf-8'))
        except UnicodeDecodeError:
            expected_files.append(f_bytes.decode('latin-1'))

    assert len(processed_files) == len(expected_files), f"Expected {len(expected_files)} files, but got {len(processed_files)}."

    for f in expected_files:
        assert f in processed_files, f"File '{f}' is missing from the processed_files array."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
