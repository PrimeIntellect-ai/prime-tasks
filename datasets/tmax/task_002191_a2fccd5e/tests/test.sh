#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import shutil
import stat
import subprocess
import tempfile
from collections import defaultdict
from pathlib import Path

PROJECT = Path("/home/user/dataset_graph")
CSV_PATH = PROJECT / "graph_data.csv"
SOURCE_PATH = PROJECT / "analyzer.c"
BINARY_PATH = PROJECT / "analyzer"
OUTPUT_PATH = PROJECT / "top_datasets.txt"

ORIGINAL_CSV = """D1,T1
D1,T2
D2,T2
D2,T3
D3,T1
D3,T4
D4,T1
D4,T2
D4,T3
D5,T5
D6,T4
D6,T5
D7,T1
D8,T2
D9,T3
D10,T4
"""


def expected_lines(csv_text):
    dataset_to_tags = defaultdict(set)
    tag_to_datasets = defaultdict(set)

    for row in csv.reader(csv_text.splitlines()):
        if len(row) >= 2:
            d, t = row[0].strip(), row[1].strip()
            dataset_to_tags[d].add(t)
            tag_to_datasets[t].add(d)

    scores = {}
    for d, tags in dataset_to_tags.items():
        neighbors = set()
        for tag in tags:
            neighbors.update(tag_to_datasets[tag])
        neighbors.discard(d)
        scores[d] = len(neighbors)

    ordered = sorted(scores.items(), key=lambda item: (-item[1], item[0]))[:5]
    return [f"{dataset}:{score}" for dataset, score in ordered]


def read_output():
    assert OUTPUT_PATH.is_file(), f"Expected output file {OUTPUT_PATH} does not exist."
    with OUTPUT_PATH.open("r") as f:
        return [line.strip() for line in f if line.strip()]


def run_and_check(executable, csv_text):
    CSV_PATH.write_text(csv_text)
    if OUTPUT_PATH.exists() or OUTPUT_PATH.is_symlink():
        OUTPUT_PATH.unlink()

    completed = subprocess.run(
        [str(executable)],
        cwd=str(PROJECT),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert completed.returncode == 0, (
        f"{executable} exited with {completed.returncode}. stderr: {completed.stderr}"
    )

    actual = read_output()
    expected = expected_lines(csv_text)
    assert len(actual) == 5, f"Expected exactly 5 lines, found {len(actual)}."
    assert actual == expected, f"Expected {expected}, got {actual}."


def test_00_analyzer_artifact_exists_and_runs_on_original_input():
    assert CSV_PATH.is_file(), f"Input file {CSV_PATH} is missing."
    assert CSV_PATH.read_text() == ORIGINAL_CSV, "graph_data.csv was modified."
    assert SOURCE_PATH.is_file(), f"Expected source file {SOURCE_PATH} is missing."
    assert BINARY_PATH.exists(), f"Expected compiled program {BINARY_PATH} is missing."
    assert not BINARY_PATH.is_symlink(), "analyzer must be a compiled regular file, not a symlink."
    mode = BINARY_PATH.stat().st_mode
    assert stat.S_ISREG(mode), "analyzer is not a regular file."
    assert os.access(BINARY_PATH, os.X_OK), "analyzer is not executable."
    with BINARY_PATH.open("rb") as f:
        assert f.read(4) == b"\x7fELF", "analyzer is not an ELF executable."

    run_and_check(BINARY_PATH, ORIGINAL_CSV)


def test_top_datasets_file_exists():
    file_path = "/home/user/dataset_graph/top_datasets.txt"
    assert os.path.isfile(file_path), f"Expected output file {file_path} does not exist. Did you run the program and redirect/write the output?"


def test_top_datasets_content():
    csv_path = "/home/user/dataset_graph/graph_data.csv"
    assert os.path.isfile(csv_path), f"Input file {csv_path} is missing."

    dataset_to_tags = defaultdict(set)
    tag_to_datasets = defaultdict(set)

    with open(csv_path, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) >= 2:
                d, t = row[0].strip(), row[1].strip()
                dataset_to_tags[d].add(t)
                tag_to_datasets[t].add(d)

    scores = {}
    for d, tags in dataset_to_tags.items():
        neighbors = set()
        for t in tags:
            neighbors.update(tag_to_datasets[t])
        neighbors.discard(d)
        scores[d] = len(neighbors)

    sorted_datasets = sorted(scores.items(), key=lambda x: (-x[1], x[0]))
    top_5 = sorted_datasets[:5]
    expected = [f"{d}:{score}" for d, score in top_5]

    with open("/home/user/dataset_graph/top_datasets.txt", "r") as f:
        actual = [line.strip() for line in f if line.strip()]

    assert len(actual) == 5, f"Expected exactly 5 lines in top_datasets.txt, found {len(actual)}."
    for i, (expected_line, actual_line) in enumerate(zip(expected, actual)):
        assert expected_line == actual_line, f"Mismatch at line {i+1}. Expected '{expected_line}', got '{actual_line}'."


def make_random_case():
    nonce = secrets.token_hex(3)
    dataset_count = 10 + secrets.randbelow(8)
    tag_count = 4 + secrets.randbelow(5)
    datasets = [f"X{nonce}{i}" for i in range(dataset_count)]
    tags = [f"Q{nonce}{i}" for i in range(tag_count)]
    rows = []

    for i, dataset in enumerate(datasets):
        selected = {tags[i % tag_count]}
        for tag in tags:
            if secrets.randbelow(100) < 40:
                selected.add(tag)
        for tag in selected:
            rows.append(f"{dataset},{tag}")

    # Duplicate input rows must not inflate a dataset's neighbor count.
    rows.extend(rows[:3])
    return "\n".join(rows) + "\n"


def test_compiled_source_and_submitted_binary_generalize():
    original_csv = CSV_PATH.read_bytes()
    original_output = OUTPUT_PATH.read_bytes() if OUTPUT_PATH.exists() else None

    deterministic_case = """D1,T1
D1,T2
D2,T1
D2,T2
D10,T1
D3,T2
D4,T3
D5,T3
D6,T4
D7,T4
D1,T1
D2,T2
"""

    with tempfile.TemporaryDirectory() as temp_dir:
        fresh_binary = Path(temp_dir) / "analyzer_fresh"
        compiled = subprocess.run(
            ["gcc", str(SOURCE_PATH), "-o", str(fresh_binary)],
            cwd=str(PROJECT),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compiled.returncode == 0, f"analyzer.c did not compile: {compiled.stderr}"

        try:
            cases = [deterministic_case] + [make_random_case() for _ in range(3)]
            for case in cases:
                run_and_check(BINARY_PATH, case)
                run_and_check(fresh_binary, case)
        finally:
            CSV_PATH.write_bytes(original_csv)
            if original_output is None:
                if OUTPUT_PATH.exists() or OUTPUT_PATH.is_symlink():
                    OUTPUT_PATH.unlink()
            else:
                OUTPUT_PATH.write_bytes(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
