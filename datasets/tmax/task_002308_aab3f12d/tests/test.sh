#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import json
import hashlib
import subprocess
import gzip
import csv
import pytest


def load_manifest():
    manifest_path = "/app/legacy_backups.sha256"
    assert os.path.isfile(manifest_path), f"Trusted source manifest {manifest_path} is missing."

    manifest = {}
    with open(manifest_path, "r", encoding="utf-8") as f:
        for line in f:
            digest, path = line.rstrip("\n").split(None, 1)
            path = path.lstrip(" *")
            manifest[os.path.basename(path)] = digest
    return manifest


def file_sha256(path):
    digest = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def test_optimized_logs_size_and_content():
    output_path = "/home/user/optimized_logs.csv.gz"
    assert os.path.exists(output_path), f"File {output_path} does not exist."

    size = os.path.getsize(output_path)
    assert size < 1200000, f"File size {size} bytes is not strictly less than the 1200000 bytes threshold."

    # Verify that all original source archives still exist and are unchanged.
    backup_dir = "/home/user/legacy_backups"
    expected_names = {f"backup_{i:02d}.pck" for i in range(50)}
    manifest = load_manifest()
    assert set(manifest) == expected_names, "Trusted source manifest does not describe all 50 backups."

    for name in sorted(expected_names):
        pck_file = os.path.join(backup_dir, name)
        assert os.path.exists(pck_file), f"Required source backup {pck_file} is missing."
        assert stat.S_ISREG(os.lstat(pck_file).st_mode), f"Required source backup {pck_file} is not a regular file."
        assert file_sha256(pck_file) == manifest[name], f"Required source backup {pck_file} was modified."

    # Recalculate expected valid rows from the verified source files.
    expected_rows = []
    for i in range(50):
        pck_file = os.path.join(backup_dir, f"backup_{i:02d}.pck")
        proc = subprocess.run(["/app/pck_unpack", pck_file], capture_output=True, text=True)
        assert proc.returncode == 0, f"Failed to unpack required source backup {pck_file}."
        for line in proc.stdout.splitlines():
            line = line.strip()
            if not line:
                continue
            try:
                data = json.loads(line)
                payload = data.get("payload", "")
                checksum = data.get("checksum", "")
                if hashlib.md5(payload.encode("utf-8")).hexdigest() == checksum:
                    expected_rows.append((data.get("timestamp", ""), data.get("severity", ""), payload))
            except Exception:
                pass

    assert expected_rows, "The verified legacy backups unexpectedly contain no valid rows."

    # Read the generated CSV.
    actual_rows = []
    try:
        with gzip.open(output_path, "rt", encoding="utf-8") as f:
            reader = csv.reader(f)
            headers = next(reader)
            assert headers == ["timestamp", "severity", "payload"], f"Incorrect CSV headers: {headers}"
            for row in reader:
                actual_rows.append(tuple(row))
    except Exception as e:
        pytest.fail(f"Failed to read or parse {output_path}: {e}")

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} valid rows, but got {len(actual_rows)}."

    # Sort both lists to compare contents irrespective of the sorting strategy used for compression.
    expected_rows.sort()
    actual_rows.sort()

    assert actual_rows == expected_rows, "The extracted CSV data does not match the expected valid rows from the legacy backups."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
