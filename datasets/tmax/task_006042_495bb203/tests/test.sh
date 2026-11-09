#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import shutil
import subprocess
import sys
import uuid
import secrets
import pytest

@pytest.fixture(scope="session", autouse=True)
def execute_script_with_dynamic_inputs():
    base_dir = "/home/user/storage_mounts"
    token = uuid.uuid4().hex
    probe_dir = os.path.join(base_dir, f"verifier_{token}", "deep", "nested")
    os.makedirs(probe_dir, exist_ok=True)

    qualifying_size = 501 + secrets.randbelow(5000)
    cases = [
        (f"qualifying_{token}", {"retention_policy": "expired", "size_mb": qualifying_size}),
        (f"boundary_{token}", {"retention_policy": "expired", "size_mb": 500}),
        (f"active_{token}", {"retention_policy": "active", "size_mb": qualifying_size + 100}),
    ]

    for name, metadata in cases:
        with open(os.path.join(probe_dir, name + ".metadata.json"), "w") as f:
            json.dump(metadata, f)
        open(os.path.join(probe_dir, name + ".data"), "a").close()

    csv_path = "/home/user/expired_large_backups.csv"
    if os.path.exists(csv_path):
        os.remove(csv_path)

    script_path = "/home/user/find_expired.py"
    assert os.path.isfile(script_path), f"Expected script not found at {script_path}"
    subprocess.run(
        [sys.executable, script_path],
        cwd="/home/user",
        check=True,
        timeout=15,
    )

    yield
    shutil.rmtree(os.path.join(base_dir, f"verifier_{token}"), ignore_errors=True)

def test_script_exists():
    script_path = "/home/user/find_expired.py"
    assert os.path.isfile(script_path), f"Expected script not found at {script_path}"

def test_csv_output():
    csv_path = "/home/user/expired_large_backups.csv"
    assert os.path.isfile(csv_path), f"Expected output CSV not found at {csv_path}"

    base_dir = "/home/user/storage_mounts/"
    expected_records = []

    # Derive expected state directly from the filesystem
    for root, _, files in os.walk(base_dir):
        for filename in files:
            if filename.endswith(".metadata.json"):
                metadata_path = os.path.join(root, filename)
                data_filename = filename[:-len(".metadata.json")] + ".data"
                data_path = os.path.join(root, data_filename)

                with open(metadata_path, 'r') as f:
                    try:
                        metadata = json.load(f)
                    except json.JSONDecodeError:
                        continue

                if metadata.get("retention_policy") == "expired" and metadata.get("size_mb", 0) > 500:
                    expected_records.append((data_path, str(metadata["size_mb"])))

    # Read the actual CSV
    actual_records = []
    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            assert len(row) == 2, f"Invalid CSV format in row: {row}. Expected 2 columns."
            actual_records.append((row[0].strip(), row[1].strip()))

    # Sort both lists for order-independent comparison
    expected_records.sort()
    actual_records.sort()

    assert actual_records == expected_records, (
        f"CSV contents do not match expected records.\n"
        f"Expected: {expected_records}\n"
        f"Actual: {actual_records}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
