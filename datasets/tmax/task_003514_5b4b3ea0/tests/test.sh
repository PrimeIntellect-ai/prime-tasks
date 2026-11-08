#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import io
import os
import tarfile
import pytest

EXPECTED_FILES = ["bin_143500.dat", "bin_144500.dat"]


def test_summary_txt_contents():
    """Test that summary.txt contains the correct sorted filenames."""
    summary_path = "/home/user/summary.txt"
    assert os.path.isfile(summary_path), f"File {summary_path} does not exist."

    with open(summary_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_files = ["bin_143500.dat", "bin_144500.dat"]
    assert lines == expected_files, f"Contents of {summary_path} are incorrect. Expected {expected_files}, got {lines}."


def test_anomalies_backup_contents():
    """Test that the backup contains exactly the correct original binary files."""
    backup_path = "/home/user/anomalies_backup.tar.gz"
    assert os.path.isfile(backup_path), f"File {backup_path} does not exist."
    assert tarfile.is_tarfile(backup_path), f"{backup_path} is not a valid tar archive."

    with tarfile.open(backup_path, "r:gz") as tar:
        members = tar.getnames()

        expected_files = ["bin_143500.dat", "bin_144500.dat"]

        # Check that it contains exactly the expected files
        assert sorted(members) == sorted(expected_files), (
            f"Archive {backup_path} contents are incorrect. "
            f"Expected {sorted(expected_files)}, got {sorted(members)}."
        )

        submitted_contents = {}
        for filename in expected_files:
            member = tar.getmember(filename)
            assert member.isfile(), f"Archive member {filename} is not a regular file."
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read archive member {filename}."
            submitted_contents[filename] = extracted.read()

    master_path = "/home/user/research_data/master_dataset.tar"
    with tarfile.open(master_path, "r:") as master:
        sensors_member = master.getmember("sensors.tar.bz2")
        assert sensors_member.isfile(), "sensors.tar.bz2 in the master archive is not a regular file."
        sensors_stream = master.extractfile(sensors_member)
        assert sensors_stream is not None, "Could not read sensors.tar.bz2 from the master archive."
        sensors_bytes = sensors_stream.read()

    with tarfile.open(fileobj=io.BytesIO(sensors_bytes), mode="r:bz2") as sensors:
        for filename in EXPECTED_FILES:
            source_member = sensors.getmember(filename)
            assert source_member.isfile(), f"Source member {filename} is not a regular file."
            source_file = sensors.extractfile(source_member)
            assert source_file is not None, f"Could not read source member {filename}."
            expected_content = source_file.read()
            assert submitted_contents[filename] == expected_content, (
                f"Binary contents of {filename} do not match the corresponding file "
                "in sensors.tar.bz2."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
