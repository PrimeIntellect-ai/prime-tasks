#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import secrets
import stat
import subprocess
from collections import Counter

import pytest


def test_edges_txt_content():
    file_path = "/home/user/edges.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_edges = {
        "Raw_Climate_Data|Cleaned_Climate_Data|Filter",
        "Cleaned_Climate_Data|Regional_Aggregates|GroupBy",
        "Regional_Aggregates|Global_Aggregates|Merge",
        "Global_Aggregates|Global_Warming_Model|Train",
        "Cleaned_Climate_Data|Anomaly_Detection|Detect",
        "Anomaly_Detection|Global_Warming_Model|Feedback",
        "Raw_Climate_Data|Visualization_Dashboard|Plot",
        "Global_Aggregates|Visualization_Dashboard|Plot"
    }

    actual_edges = set(lines)

    assert len(lines) == 8, f"Expected exactly 8 lines in {file_path}, found {len(lines)}."
    assert actual_edges == expected_edges, "The contents of edges.txt do not match the expected edges."


def test_path_txt_content():
    file_path = "/home/user/path.txt"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_path = [
        "Raw_Climate_Data",
        "Cleaned_Climate_Data",
        "Anomaly_Detection",
        "Global_Warming_Model"
    ]

    assert lines == expected_path, f"The contents of {file_path} do not match the expected shortest path."


def test_extract_edges_script_executes_and_joins_dynamic_data():
    script = "/home/user/extract_edges.sh"
    assert os.path.exists(script), f"File {script} is missing."
    assert not os.path.islink(script), f"File {script} must be a regular script, not a symlink."
    assert stat.S_ISREG(os.stat(script).st_mode), f"File {script} is not a regular file."
    assert os.access(script, os.X_OK), f"File {script} is not executable."

    protected = [
        "/home/user/datasets.csv",
        "/home/user/relationships.csv",
        "/home/user/edges.txt",
        "/home/user/path.txt",
    ]
    backups = {path: open(path, "rb").read() for path in protected}
    modes = {path: stat.S_IMODE(os.stat(path).st_mode) for path in protected}

    token = secrets.token_hex(8)
    base = secrets.randbelow(800000) + 100000
    ids = [str(base + i * 17) for i in range(5)]
    names = [f"Dynamic_{token}_{label}" for label in ("Alpha", "Beta", "Gamma", "Delta", "Epsilon")]
    transforms = [f"Tx_{token}_{i}" for i in range(4)]

    dataset_rows = [
        (ids[3], names[3]),
        (ids[0], names[0]),
        (ids[4], names[4]),
        (ids[2], names[2]),
        (ids[1], names[1]),
    ]
    relationship_rows = [
        (ids[0], ids[2], transforms[0]),
        (ids[2], ids[1], transforms[1]),
        (str(base + 9999), ids[0], f"InvalidSource_{token}"),
        (ids[1], ids[3], transforms[2]),
        (ids[4], ids[0], transforms[3]),
        (ids[0], str(base + 8888), f"InvalidTarget_{token}"),
    ]
    expected = [
        f"{names[0]}|{names[2]}|{transforms[0]}",
        f"{names[2]}|{names[1]}|{transforms[1]}",
        f"{names[1]}|{names[3]}|{transforms[2]}",
        f"{names[4]}|{names[0]}|{transforms[3]}",
    ]

    try:
        with open("/home/user/datasets.csv", "w", newline="") as f:
            f.write("id,name\n")
            for dataset_id, name in dataset_rows:
                f.write(f"{dataset_id},{name}\n")

        with open("/home/user/relationships.csv", "w", newline="") as f:
            f.write("source_id,target_id,transformation\n")
            for source_id, target_id, transformation in relationship_rows:
                f.write(f"{source_id},{target_id},{transformation}\n")

        result = subprocess.run(
            [script],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            check=False,
        )
        assert result.returncode == 0, (
            f"{script} exited with status {result.returncode}. stderr: {result.stderr}"
        )
        actual = [line.strip() for line in result.stdout.splitlines() if line.strip()]
        assert len(actual) == len(expected), (
            f"The script should emit exactly {len(expected)} valid dynamic relationships; "
            f"it emitted {len(actual)}."
        )
        assert Counter(actual) == Counter(expected), (
            "The script did not correctly join dynamically supplied dataset and relationship IDs."
        )
    finally:
        for path, content in backups.items():
            if os.path.isdir(path):
                os.rmdir(path)
            with open(path, "wb") as f:
                f.write(content)
            os.chmod(path, modes[path])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
