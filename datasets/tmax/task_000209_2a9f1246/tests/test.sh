#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import subprocess
import tempfile
from pathlib import Path

import pytest

BINARY = "/home/user/artifact_filter"
SOURCE = "/home/user/artifact_filter.cpp"


def run_filter(binary, csv_path):
    return subprocess.run(
        [binary, str(csv_path)],
        capture_output=True,
        text=True,
        timeout=10,
    )


def assert_result(binary, csv_path, leaked):
    result = run_filter(binary, csv_path)
    expected_code = 1 if leaked else 0
    expected_status = "STATUS: LEAKED" if leaked else "STATUS: CLEAN"
    assert result.returncode == expected_code, (
        f"{csv_path}: expected exit {expected_code}, got {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert expected_status in result.stdout, (
        f"{csv_path}: expected {expected_status!r} in stdout, got {result.stdout!r}"
    )


def write_csv(path, rows, lineterminator="\n"):
    with open(path, "w", newline="") as f:
        writer = csv.writer(f, lineterminator=lineterminator)
        writer.writerow(["experiment_id", "timestamp", "train_features"])
        writer.writerows(rows)


def test_artifact_filter_exists_and_executable():
    binary_path = BINARY
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} is missing."
    assert os.access(binary_path, os.X_OK), f"Compiled binary {binary_path} is not executable."
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{binary_path} is not a compiled ELF executable."


def test_source_exists_and_compiles(tmp_path):
    assert os.path.isfile(SOURCE), f"C++ source {SOURCE} is missing."
    rebuilt = tmp_path / "rebuilt_artifact_filter"
    result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", str(rebuilt)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"C++ source did not compile: {result.stderr}"
    assert rebuilt.is_file() and os.access(rebuilt, os.X_OK)


def test_corpora_filtering():
    binary_path = BINARY
    clean_dir = "/app/corpora/clean"
    evil_dir = "/app/corpora/evil"

    clean_files = glob.glob(os.path.join(clean_dir, "*.csv"))
    evil_files = glob.glob(os.path.join(evil_dir, "*.csv"))

    assert len(clean_files) > 0, "No clean CSV files found in /app/corpora/clean."
    assert len(evil_files) > 0, "No evil CSV files found in /app/corpora/evil."

    clean_failed = []
    for f in clean_files:
        result = subprocess.run([binary_path, f], capture_output=True, text=True)
        if result.returncode != 0 or "STATUS: CLEAN" not in result.stdout:
            clean_failed.append(os.path.basename(f))

    evil_failed = []
    for f in evil_files:
        result = subprocess.run([binary_path, f], capture_output=True, text=True)
        if result.returncode != 1 or "STATUS: LEAKED" not in result.stdout:
            evil_failed.append(os.path.basename(f))

    errors = []
    if evil_failed:
        errors.append(f"{len(evil_failed)} of {len(evil_files)} evil bypassed: {', '.join(evil_failed)}")
    if clean_failed:
        errors.append(f"{len(clean_failed)} of {len(clean_files)} clean modified (rejected): {', '.join(clean_failed)}")

    if errors:
        pytest.fail(" | ".join(errors))


def test_generated_csvs_and_rebuilt_source(tmp_path):
    rebuilt = tmp_path / "candidate_from_source"
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", SOURCE, "-o", str(rebuilt)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, compile_result.stderr

    case_dir = Path(tempfile.mkdtemp(prefix="af_cases_", dir=str(tmp_path)))

    cases = []

    clean_basic = case_dir / "a.csv"
    write_csv(clean_basic, [
        ["exp-a", "1700000000", "alpha beta gamma"],
        ["exp-b", "1700000001", "protocol alpha zero tango"],
        ["exp-c", "1700000002", "protocol zero tangox"],
        ["exp-d", "1700000003", "zero tango protocol"],
    ])
    cases.append((clean_basic, False))

    clean_boundaries = case_dir / "b.csv"
    write_csv(clean_boundaries, [
        ["exp-a", "1700000010", "alpha protocol zero"],
        ["exp-b", "1700000011", "tango beta gamma"],
        ["protocol zero tango", "1700000012", "safe feature tokens"],
        ["id,protocol zero tango", "1700000013", "still entirely safe"],
    ], lineterminator="\r\n")
    cases.append((clean_boundaries, False))

    evil_mixed_case = case_dir / "c.csv"
    write_csv(evil_mixed_case, [
        ["exp-x", "1700000020", "safe tokens first"],
        ["exp-y", "1700000021", "alpha PrOtOcOl ZeRo TaNgO omega"],
    ])
    cases.append((evil_mixed_case, True))

    evil_quoted_feature = case_dir / "d.csv"
    write_csv(evil_quoted_feature, [
        ["id,with,commas", "1700000030", "PROTOCOL zero tango"],
    ])
    cases.append((evil_quoted_feature, True))

    evil_spacing = case_dir / "e.csv"
    write_csv(evil_spacing, [
        ["exp-z", "1700000040", "before protocol   zero  tango after"],
    ])
    cases.append((evil_spacing, True))

    for binary in (BINARY, str(rebuilt)):
        for csv_path, leaked in cases:
            assert_result(binary, csv_path, leaked)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
