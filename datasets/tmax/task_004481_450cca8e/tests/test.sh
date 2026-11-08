#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import pytest

EXPECTED_CONTENTS = {
    "server1.csv": """server_id,change_id,status,description,timestamp
srv1,c001,APPLIED,"Update nginx workers",2023-01-01T10:00:00Z
srv1,c002,REJECTED,"Invalid port 99999",2023-01-01T10:05:00Z
srv1,c003,APPLIED,"Restart service",2023-01-01T10:10:00Z
""",
    "server2.csv": """server_id,change_id,status,description,timestamp
srv2,c101,APPLIED,"Set max_memory",2023-01-02T11:00:00Z
srv2,c102,REJECTED,"Missing closing bracket
in config file
line 42",2023-01-02T11:05:00Z
srv2,c103,REJECTED,"User 'admin'
does not exist",2023-01-02T11:10:00Z
""",
    "server3.csv": """server_id,change_id,status,description,timestamp
srv3,c201,REJECTED,"Syntax error
unknown directive 'fasthttps'",2023-01-03T12:00:00Z
srv3,c202,APPLIED,"Rollback",2023-01-03T12:15:00Z
""",
}

EXPECTED_LINES = [
    "srv1:c002",
    "srv2:c102",
    "srv2:c103",
    "srv3:c201",
]


def test_raw_configs_directory_exists_and_populated():
    """Test that raw_configs contains the extracted CSV files with their full original data."""
    dir_path = "/home/user/raw_configs"
    assert os.path.exists(dir_path), f"Directory {dir_path} does not exist. Did you extract the tarball?"
    assert os.path.isdir(dir_path), f"Path {dir_path} is not a directory."

    expected_files = ["server1.csv", "server2.csv", "server3.csv"]
    for name in expected_files:
        file_path = os.path.join(dir_path, name)
        assert os.path.exists(file_path), f"File {name} was not found in {dir_path}."
        assert os.path.isfile(file_path), f"Path {file_path} is not a regular file."

        with open(file_path, "rb") as f:
            raw = f.read()
        assert raw, f"File {name} is empty."
        try:
            text = raw.decode("utf-8-sig")
        except UnicodeDecodeError:
            pytest.fail(f"File {name} is not properly UTF-8 encoded.")
        assert text == EXPECTED_CONTENTS[name], (
            f"File {name} does not contain the extracted and encoding-normalized log data."
        )


def test_csv_files_are_utf8():
    """Test that all csv files in raw_configs are UTF-8 encoded."""
    dir_path = "/home/user/raw_configs"
    csv_files = [f for f in os.listdir(dir_path) if f.endswith('.csv')]

    assert len(csv_files) > 0, "No .csv files found in raw_configs."

    for name in csv_files:
        file_path = os.path.join(dir_path, name)
        assert os.path.isfile(file_path), f"Path {file_path} is not a regular file."
        try:
            with open(file_path, 'r', encoding='utf-8-sig', newline='') as f_obj:
                content = f_obj.read()
        except UnicodeDecodeError:
            pytest.fail(f"File {name} is not properly UTF-8 encoded.")
        assert content, f"CSV file {name} is empty."


def test_rejected_changes_output():
    """Test that rejected_changes.txt contains the correct output."""
    output_file = "/home/user/rejected_changes.txt"
    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.isfile(output_file), f"Path {output_file} is not a file."

    with open(output_file, 'r', encoding='utf-8') as f:
        content = f.read().strip().splitlines()

    assert content == EXPECTED_LINES, f"Content of {output_file} does not match expected output. Got: {content}"

    derived = []
    for name in sorted(EXPECTED_CONTENTS):
        file_path = os.path.join("/home/user/raw_configs", name)
        with open(file_path, "r", encoding="utf-8-sig", newline="") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames == [
                "server_id", "change_id", "status", "description", "timestamp"
            ], f"Unexpected CSV header in {name}: {reader.fieldnames}"
            for row in reader:
                if row["status"] == "REJECTED":
                    derived.append(f'{row["server_id"]}:{row["change_id"]}')

    assert sorted(derived) == content, (
        "rejected_changes.txt was not derived correctly from the normalized multiline CSV records."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
