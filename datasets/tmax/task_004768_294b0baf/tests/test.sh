#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import io
import os
import tarfile

ARCHIVE = "/home/user/storage/telemetry_logs.tar"
CLEANED_DIR = "/home/user/cleaned_logs"
INVENTORY = "/home/user/inventory.txt"


def expected_cleaned_logs():
    expected = {}
    with tarfile.open(ARCHIVE, "r:*") as outer:
        subarchives = [m for m in outer.getmembers() if m.isfile() and m.name.endswith(".tar.gz")]
        assert subarchives, "No nested .tar.gz archives found."

        for member in subarchives:
            extracted = outer.extractfile(member)
            assert extracted is not None, f"Could not read nested archive {member.name}."
            with tarfile.open(fileobj=io.BytesIO(extracted.read()), mode="r:*") as inner:
                for log_member in inner.getmembers():
                    if not log_member.isfile() or not log_member.name.endswith(".log"):
                        continue
                    filename = os.path.basename(log_member.name)
                    assert filename not in expected, f"Duplicate log filename in archives: {filename}"
                    source = inner.extractfile(log_member)
                    assert source is not None, f"Could not read {log_member.name}."
                    lines = source.read().splitlines(keepends=True)
                    expected[filename] = b"".join(
                        line for line in lines
                        if b"[TRACE]" not in line and b"[DEBUG]" not in line
                    )
    return expected


def test_cleaned_logs_exist_and_correct_lines():
    expected = expected_cleaned_logs()

    # Preserve the original task-specific assertions.
    expected_counts = {
        "node1.log": 50,
        "node2.log": 150,
        "node3.log": 0,
    }
    assert set(expected) == set(expected_counts)
    assert {name: len(data.splitlines()) for name, data in expected.items()} == expected_counts

    assert os.path.isdir(CLEANED_DIR), f"Directory {CLEANED_DIR} is missing."
    actual_files = set(os.listdir(CLEANED_DIR))
    assert actual_files == set(expected_counts), (
        f"Expected files {set(expected_counts)} but found {actual_files} in {CLEANED_DIR}."
    )

    for filename, expected_lines in expected_counts.items():
        filepath = os.path.join(CLEANED_DIR, filename)
        assert os.path.isfile(filepath), f"File {filepath} is missing."
        with open(filepath, "rb") as f:
            actual_data = f.read()

        actual_lines = actual_data.splitlines()
        assert len(actual_lines) == expected_lines, (
            f"Expected {expected_lines} lines in {filename}, but found {len(actual_lines)}."
        )
        for line_num, line in enumerate(actual_lines, 1):
            assert b"[TRACE]" not in line, f"Found [TRACE] in {filename} at line {line_num}."
            assert b"[DEBUG]" not in line, f"Found [DEBUG] in {filename} at line {line_num}."

        assert actual_data == expected[filename], (
            f"{filename} does not exactly match the archive content after filtering."
        )


def test_inventory_file_content():
    assert os.path.isfile(INVENTORY), f"Inventory file {INVENTORY} is missing."
    expected_logs = expected_cleaned_logs()
    expected_lines = {
        f"{filename},{len(content.splitlines())}"
        for filename, content in expected_logs.items()
    }

    # Preserve the original task-specific inventory assertion.
    assert expected_lines == {"node1.log,50", "node2.log,150", "node3.log,0"}

    # Coordinate with any background inventory writers while validating the file.
    with open(INVENTORY, "r") as f:
        fcntl.flock(f.fileno(), fcntl.LOCK_EX)
        try:
            actual_lines = [line.strip() for line in f if line.strip()]
        finally:
            fcntl.flock(f.fileno(), fcntl.LOCK_UN)

    assert set(actual_lines) == expected_lines, (
        f"Expected inventory lines {expected_lines}, but found {set(actual_lines)}."
    )
    assert len(actual_lines) == 3, (
        f"Expected exactly 3 lines in inventory.txt, but found {len(actual_lines)}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
