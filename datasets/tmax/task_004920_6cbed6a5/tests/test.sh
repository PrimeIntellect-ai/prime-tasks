#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import random
import secrets
import subprocess
import tempfile
import pytest

HOME = "/home/user"
RAW = os.path.join(HOME, "raw.tsv")


def test_files_exist():
    """Test that all expected files are created."""
    expected_files = [
        "/home/user/etl.c",
        "/home/user/pipeline.sh",
        "/home/user/run_etl",
        "/home/user/clean_run1.tsv",
        "/home/user/clean_run2.tsv",
        "/home/user/z_stat.txt",
        "/home/user/run_log.txt"
    ]
    for file_path in expected_files:
        assert os.path.exists(file_path), f"Expected file {file_path} is missing."
        assert os.path.isfile(file_path), f"Path {file_path} is not a regular file."


def test_c_program_compiles_and_runs_on_fresh_input():
    """Compile the submitted C source and exercise it on verifier-generated data."""
    binary = "/tmp/verified_run_etl"
    subprocess.run(
        ["gcc", "-O2", "/home/user/etl.c", "-o", binary, "-lm"],
        check=True,
        timeout=30,
    )
    assert os.path.isfile(binary)
    assert os.access(binary, os.X_OK)

    rng = random.Random(int.from_bytes(secrets.token_bytes(16), "big"))
    rows = []
    for i in range(80):
        rating = (i % 5) + 1
        center = 210.0 if rating >= 4 else 390.0
        latency = center + rng.uniform(-45.0, 45.0)
        rows.append((f"VU{i:03d}", f"VI{i:04d}", str(rating), f"{latency:.4f}"))

    # Include valid boundary values and rows that each filter must reject.
    rows.extend([
        ("BOUND1", "ITEM1", "4", "10.0000"),
        ("BOUND2", "ITEM2", "2", "5000.0000"),
        ("LOW", "ITEM3", "5", "9.9999"),
        ("HIGH", "ITEM4", "1", "5000.0001"),
        ("BADR0", "ITEM5", "0", "250.0000"),
        ("BADR6", "ITEM6", "6", "300.0000"),
    ])
    rng.shuffle(rows)
    raw_bytes = b"".join(("\t".join(row) + "\n").encode() for row in rows)

    valid = []
    g1 = []
    g2 = []
    for row in rows:
        rating = int(row[2])
        latency = float(row[3])
        if rating in (1, 2, 3, 4, 5) and 10.0 <= latency <= 5000.0:
            valid.append(row)
            (g1 if rating >= 4 else g2).append(latency)
    expected_clean = b"".join(("\t".join(row) + "\n").encode() for row in valid)
    mean1 = sum(g1) / len(g1)
    mean2 = sum(g2) / len(g2)
    var1 = sum((x - mean1) ** 2 for x in g1) / (len(g1) - 1)
    var2 = sum((x - mean2) ** 2 for x in g2) / (len(g2) - 1)
    expected_z = f"{abs(mean1 - mean2) / math.sqrt(var1 / len(g1) + var2 / len(g2)):.3f}"

    original_raw = open(RAW, "rb").read()
    try:
        with open(RAW, "wb") as f:
            f.write(raw_bytes)
        with tempfile.TemporaryDirectory() as workdir:
            subprocess.run([binary], cwd=workdir, check=True, timeout=30)
            clean_path = os.path.join(workdir, "clean.tsv")
            z_path = os.path.join(workdir, "z_stat.txt")
            assert os.path.isfile(clean_path), "Compiled ETL did not create clean.tsv"
            assert os.path.isfile(z_path), "Compiled ETL did not create z_stat.txt"
            with open(clean_path, "rb") as f:
                assert f.read() == expected_clean
            with open(z_path, "r") as f:
                assert f.read().strip() == expected_z
    finally:
        with open(RAW, "wb") as f:
            f.write(original_raw)
        if os.path.exists(binary):
            os.remove(binary)


def test_pipeline_executes_successfully():
    """Run the submitted reproducibility pipeline from a clean output state."""
    for name in ["run_etl", "clean.tsv", "clean_run1.tsv", "clean_run2.tsv", "z_stat.txt", "run_log.txt"]:
        path = os.path.join(HOME, name)
        if os.path.lexists(path):
            if os.path.isdir(path):
                raise AssertionError(f"Unexpected directory at {path}")
            os.remove(path)

    subprocess.run(["bash", "/home/user/pipeline.sh"], cwd=HOME, check=True, timeout=60)
    run_etl = os.path.join(HOME, "run_etl")
    assert os.path.isfile(run_etl), "pipeline.sh did not create run_etl"
    assert os.access(run_etl, os.X_OK), "run_etl is not executable"


def test_run_log_content():
    """Test that run_log.txt contains exactly 'Reproducible'."""
    with open("/home/user/run_log.txt", "r") as f:
        content = f.read().strip()
    assert content == "Reproducible", f"Expected 'Reproducible' in run_log.txt, but got '{content}'."


def test_clean_tsv_content():
    """Test that clean_run1.tsv and clean_run2.tsv match the expected filtered data."""
    raw_path = "/home/user/raw.tsv"
    clean1_path = "/home/user/clean_run1.tsv"
    clean2_path = "/home/user/clean_run2.tsv"

    expected_rows = []
    with open(raw_path, "r", newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        for row in reader:
            if len(row) < 4:
                continue
            rating = int(row[2])
            latency = float(row[3])
            if rating in [1, 2, 3, 4, 5] and 10.0 <= latency <= 5000.0:
                expected_rows.append(row)

    for clean_path in [clean1_path, clean2_path]:
        actual_rows = []
        with open(clean_path, "r", newline="") as f:
            reader = csv.reader(f, delimiter="\t")
            actual_rows = list(reader)

        assert len(actual_rows) == len(expected_rows), f"Row count mismatch in {clean_path}. Expected {len(expected_rows)}, got {len(actual_rows)}."
        for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
            assert actual == expected, f"Row {i+1} mismatch in {clean_path}. Expected {expected}, got {actual}."


def test_z_stat_content():
    """Test that z_stat.txt contains the correct calculated Z-statistic."""
    raw_path = "/home/user/raw.tsv"

    g1 = []
    g2 = []
    with open(raw_path, "r", newline="") as f:
        reader = csv.reader(f, delimiter="\t")
        for row in reader:
            if len(row) < 4:
                continue
            rating = int(row[2])
            latency = float(row[3])
            if rating in [1, 2, 3, 4, 5] and 10.0 <= latency <= 5000.0:
                if rating >= 4:
                    g1.append(latency)
                else:
                    g2.append(latency)

    n1 = len(g1)
    n2 = len(g2)

    mean1 = sum(g1) / n1 if n1 > 0 else 0
    mean2 = sum(g2) / n2 if n2 > 0 else 0

    var1 = sum((x - mean1) ** 2 for x in g1) / (n1 - 1) if n1 > 1 else 0
    var2 = sum((x - mean2) ** 2 for x in g2) / (n2 - 1) if n2 > 1 else 0

    z = abs(mean1 - mean2) / math.sqrt((var1 / n1) + (var2 / n2))
    expected_z = f"{z:.3f}"

    with open("/home/user/z_stat.txt", "r") as f:
        actual_z = f.read().strip()

    assert actual_z == expected_z, f"Expected Z-statistic {expected_z}, but got {actual_z} in z_stat.txt."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
