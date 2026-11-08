#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import tarfile
import gzip
import pytest

def test_incremental_backup_exists():
    path = "/home/user/incremental.tar.gz"
    assert os.path.isfile(path), f"File {path} does not exist"

def test_incremental_backup_contents():
    path = "/home/user/incremental.tar.gz"
    assert tarfile.is_tarfile(path), f"File {path} is not a valid tar archive"

    expected_contents = {
        "logs/file3.log": (
            b"INFO: System running normally - log file 3\n"
            b"ERROR: Minor issue\n"
            b"FATAL: disk crash\n"
        ),
        "logs/file7.log": (
            b"INFO: System running normally - log file 7\n"
            b"WARN: High CPU\n"
        ),
        "logs/file11.log": (
            b"INFO: New process started\n"
            b"FATAL: memory leak\n"
            b"FATAL: cpu fire\n"
        ),
        "logs/file12.log": b"DEBUG: Nothing to see here\n",
    }

    with tarfile.open(path, "r:gz") as tar:
        file_members = [m for m in tar.getmembers() if m.isfile()]
        members = [m.name for m in file_members]

        expected_members = {
            "logs/file3.log",
            "logs/file7.log",
            "logs/file11.log",
            "logs/file12.log"
        }

        # Check if the members match exactly
        assert set(members) == expected_members, f"Archive {path} does not contain exactly the expected files. Found: {members}"
        assert len(members) == len(expected_members), f"Archive {path} contains duplicate file members. Found: {members}"

        for member in file_members:
            extracted = tar.extractfile(member)
            assert extracted is not None, f"Could not read {member.name} from {path}"
            actual = extracted.read()
            assert actual == expected_contents[member.name], (
                f"Archived contents of {member.name} do not match the updated log file"
            )

def test_fatal_errors_exists():
    path = "/home/user/fatal_errors.gz"
    assert os.path.isfile(path), f"File {path} does not exist"

def test_fatal_errors_contents():
    path = "/home/user/fatal_errors.gz"

    try:
        with gzip.open(path, "rt") as f:
            lines = f.readlines()
    except OSError:
        pytest.fail(f"File {path} is not a valid gzip file")

    # Strip whitespace/newlines and filter empty lines
    actual_lines = [line.strip() for line in lines if line.strip()]

    expected_lines = [
        "FATAL: cpu fire",
        "FATAL: disk crash",
        "FATAL: memory leak"
    ]

    assert actual_lines == expected_lines, f"Contents of {path} do not match the expected sorted FATAL lines. Found: {actual_lines}"

    # Independently derive the required output from the submitted archive.
    archive_lines = []
    with tarfile.open("/home/user/incremental.tar.gz", "r:gz") as tar:
        for member in tar.getmembers():
            if not member.isfile():
                continue
            extracted = tar.extractfile(member)
            assert extracted is not None
            for line in extracted.read().decode("utf-8").splitlines():
                if "FATAL" in line:
                    archive_lines.append(line.strip())

    assert actual_lines == sorted(archive_lines), (
        "fatal_errors.gz was not produced from the FATAL lines in incremental.tar.gz"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
