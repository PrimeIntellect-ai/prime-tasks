#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import glob
import os
import pytest

def test_local_configs_copied():
    upstream_dir = "/home/user/upstream_configs"
    local_dir = "/home/user/local_configs"
    assert os.path.isdir(local_dir), f"Directory {local_dir} does not exist"

    server1 = os.path.join(local_dir, "server1_changes.csv")
    server2 = os.path.join(local_dir, "server2_changes.csv")

    assert os.path.isfile(server1), f"File {server1} was not copied."
    assert os.path.isfile(server2), f"File {server2} was not copied."

    upstream_csvs = sorted(glob.glob(os.path.join(upstream_dir, "*.csv")))
    assert upstream_csvs, f"No CSV files found in {upstream_dir}"
    for source in upstream_csvs:
        destination = os.path.join(local_dir, os.path.basename(source))
        assert os.path.isfile(destination), f"File {destination} was not copied."
        with open(source, "rb") as src, open(destination, "rb") as dst:
            assert dst.read() == src.read(), f"Copied file {destination} does not match {source}."

def test_normalized_changes():
    normalized_file = "/home/user/normalized_changes.csv"
    assert os.path.isfile(normalized_file), f"File {normalized_file} does not exist"

    with open(normalized_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "2023-10-01,nginx.conf,15",
        "2023-10-02,db.conf,12",
        "2023-10-03,nginx.conf,8",
        "2023-10-05,app.json,25",
        "2023-10-01,app.json,5",
        "2023-10-02,nginx.conf,10",
        "2023-10-03,app.json,20",
        "2023-10-04,nginx.conf,5"
    ]

    # Check that all expected lines are in the normalized file, order independent
    assert sorted(lines) == sorted(expected_lines), f"Content of {normalized_file} does not match expected normalized output."

def test_rolling_averages():
    rolling_file = "/home/user/rolling_averages.csv"
    assert os.path.isfile(rolling_file), f"File {rolling_file} does not exist"

    with open(rolling_file, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "2023-10-01,20,20.0",
        "2023-10-02,22,21.0",
        "2023-10-03,28,23.3",
        "2023-10-04,5,18.3",
        "2023-10-05,25,19.3"
    ]

    assert lines == expected_lines, f"Content of {rolling_file} does not match exactly the expected output. Got: {lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
