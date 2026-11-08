#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import gzip
import base64

def test_output_file_exists():
    output_path = "/home/user/organized_logs/critical_errors.csv.gz"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"Output path {output_path} is not a file."

def test_output_content_matches_extracted_logs():
    logs_dir = "/home/user/logs_raw/"
    expected_lines = []

    # Dynamically recompute the expected state from the source files
    for fname in os.listdir(logs_dir):
        path = os.path.join(logs_dir, fname)
        if fname.endswith(".log"):
            with open(path, "rt", encoding="utf-8") as f:
                lines = f.readlines()
        elif fname.endswith(".log.gz"):
            with gzip.open(path, "rt", encoding="utf-8") as f:
                lines = f.readlines()
        else:
            continue

        for line in lines:
            line = line.strip()
            if not line:
                continue

            # Format: YYYY-MM-DDTHH:MM:SSZ [LEVEL] The rest of the message goes here
            parts = line.split(" ", 2)
            if len(parts) < 3:
                continue

            ts, lvl, msg = parts
            if lvl in ("[ERROR]", "[CRITICAL]"):
                lvl_clean = lvl.strip("[]")
                msg_b64 = base64.b64encode(msg.encode("utf-8")).decode("utf-8")
                expected_lines.append(f"{ts},{lvl_clean},{msg_b64}")

    # Sort chronologically by timestamp
    expected_lines.sort()
    expected_content = "\n".join(expected_lines).strip()

    output_path = "/home/user/organized_logs/critical_errors.csv.gz"

    try:
        with gzip.open(output_path, "rt", encoding="utf-8") as f:
            actual_content = f.read().strip()
    except gzip.BadGzipFile:
        assert False, f"Output file {output_path} is not a valid gzip-compressed file."

    assert actual_content == expected_content, (
        "The decompressed output CSV content does not match the expected extracted, "
        "base64-encoded, and sorted logs."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
