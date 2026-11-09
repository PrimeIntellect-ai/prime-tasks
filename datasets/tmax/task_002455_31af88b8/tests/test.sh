#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
from collections import defaultdict

def test_anomalies_file():
    input_file = "/home/user/backup_data.jsonl"
    output_file = "/home/user/anomalies.txt"

    assert os.path.exists(output_file), f"Output file {output_file} does not exist. The task requires writing the results to this file."
    assert os.path.isfile(output_file), f"{output_file} is not a file."

    # Recompute the expected truth from the input data
    collections = defaultdict(list)
    with open(input_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            doc = json.loads(line)
            if doc.get("metrics", {}).get("status") == "success":
                collections[doc["collection"]].append(doc)

    expected_anomalies = []
    for coll, docs in collections.items():
        # Sort by timestamp ascending
        docs.sort(key=lambda x: x["timestamp"])

        # Take the last 3 successful backups
        last_3 = docs[-3:]
        if not last_3:
            continue

        # Calculate moving average
        avg = sum(d["metrics"]["size_bytes"] for d in last_3) / len(last_3)
        latest_size = last_3[-1]["metrics"]["size_bytes"]

        # Check if strictly greater than 1.5 * average
        if latest_size > 1.5 * avg:
            expected_anomalies.append(coll)

    expected_anomalies.sort()

    # Read the actual output
    with open(output_file, 'r') as f:
        actual_anomalies = [line.strip() for line in f if line.strip()]

    assert actual_anomalies == expected_anomalies, (
        f"The anomalies in {output_file} do not match the expected results.\n"
        f"Expected: {expected_anomalies}\n"
        f"Actual: {actual_anomalies}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
