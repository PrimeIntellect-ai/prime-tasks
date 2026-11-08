#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import secrets
import statistics
import subprocess
from collections import Counter
from pathlib import Path

import pytest

ROOT = Path("/home/user/etl_pipeline")
SOURCE = ROOT / "src/main.rs"
TRAIN_OUTPUT = ROOT / "output_train.csv"
TEST_OUTPUT = ROOT / "output_test.csv"

CANONICAL_DATA = """id,text,value,is_train
1,hello world,10.0,true
2,hello rust,20.0,true
3,rust is fast,30.0,true
4,hello python,100.0,false
5,fast python,110.0,false
"""


def run_pipeline(data):
    (ROOT / "data.csv").write_text(data, encoding="utf-8")
    for output in (TRAIN_OUTPUT, TEST_OUTPUT):
        try:
            output.unlink()
        except FileNotFoundError:
            pass

    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        "`cargo run` failed:\nSTDOUT:\n"
        + result.stdout
        + "\nSTDERR:\n"
        + result.stderr
    )
    assert TRAIN_OUTPUT.is_file(), "cargo run did not create output_train.csv"
    assert TEST_OUTPUT.is_file(), "cargo run did not create output_test.csv"


def nonempty_lines(path):
    with path.open("r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


@pytest.fixture(scope="session", autouse=True)
def execute_canonical_pipeline():
    assert SOURCE.is_file(), f"Expected Rust source file {SOURCE} does not exist"
    assert SOURCE.stat().st_size > 0, f"Rust source file {SOURCE} is empty"

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1"],
        cwd=ROOT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    source_path = SOURCE.resolve()
    binary_sources = {
        Path(target["src_path"]).resolve()
        for package in metadata["packages"]
        for target in package["targets"]
        if "bin" in target.get("kind", [])
    }
    assert source_path in binary_sources, "cargo run is not configured to build src/main.rs"

    run_pipeline(CANONICAL_DATA)


def test_output_files_exist():
    train_path = "/home/user/etl_pipeline/output_train.csv"
    test_path = "/home/user/etl_pipeline/output_test.csv"

    assert os.path.isfile(train_path), f"Expected output file {train_path} does not exist. Did you run `cargo run`?"
    assert os.path.isfile(test_path), f"Expected output file {test_path} does not exist. Did you run `cargo run`?"


def test_output_test_csv_content():
    lines = nonempty_lines(TEST_OUTPUT)

    assert len(lines) == 3, f"Expected 3 lines in output_test.csv (1 header, 2 data rows), but got {len(lines)}"

    expected_header = "id,scaled_value,fast,hello,is,rust,world"
    assert lines[0] == expected_header, f"Header in output_test.csv is incorrect. Expected '{expected_header}', got '{lines[0]}'"

    expected_row_4 = "4,8.0000,0,1,0,0,0"
    assert lines[1] == expected_row_4, f"Row 4 in output_test.csv is incorrect. Expected '{expected_row_4}', got '{lines[1]}'"

    expected_row_5 = "5,9.0000,1,0,0,0,0"
    assert lines[2] == expected_row_5, f"Row 5 in output_test.csv is incorrect. Expected '{expected_row_5}', got '{lines[2]}'"


def test_output_train_csv_content():
    lines = nonempty_lines(TRAIN_OUTPUT)

    assert len(lines) == 4, f"Expected 4 lines in output_train.csv (1 header, 3 data rows), but got {len(lines)}"

    expected_header = "id,scaled_value,fast,hello,is,rust,world"
    assert lines[0] == expected_header, f"Header in output_train.csv is incorrect. Expected '{expected_header}', got '{lines[0]}'"

    expected_row_1 = "1,-1.0000,0,1,0,0,1"
    assert lines[1] == expected_row_1, f"Row 1 in output_train.csv is incorrect. Expected '{expected_row_1}', got '{lines[1]}'"

    expected_row_2 = "2,0.0000,0,1,0,1,0"
    assert lines[2] == expected_row_2, f"Row 2 in output_train.csv is incorrect. Expected '{expected_row_2}', got '{lines[2]}'"

    expected_row_3 = "3,1.0000,1,0,1,1,0"
    assert lines[3] == expected_row_3, f"Row 3 in output_train.csv is incorrect. Expected '{expected_row_3}', got '{lines[3]}'"


def expected_lines(rows, want_train):
    training = [row for row in rows if row[3]]
    vocab = sorted({word for row in training for word in row[1].split()})
    mean = statistics.mean(row[2] for row in training)
    std_dev = statistics.stdev(row[2] for row in training)

    result = ["id,scaled_value," + ",".join(vocab)]
    for row_id, text, value, is_train in rows:
        if is_train != want_train:
            continue
        counts = Counter(text.split())
        scaled = (value - mean) / std_dev
        result.append(
            f"{row_id},{scaled:.4f}," + ",".join(str(counts[word]) for word in vocab)
        )
    return result


def test_pipeline_uses_training_only_parameters_on_fresh_input():
    suffix = secrets.token_hex(6)
    words = [f"alpha{suffix}", f"beta{suffix}", f"gamma{suffix}", f"zeta{suffix}"]
    random.SystemRandom().shuffle(words)
    unseen = f"unseen{secrets.token_hex(6)}"
    base = random.SystemRandom().randint(20, 200)
    step = random.SystemRandom().randint(2, 20)
    ids = [secrets.token_hex(3) for _ in range(5)]

    rows = [
        (ids[0], f"{words[0]} {words[3]} {words[3]}", float(base), True),
        (ids[1], f"{words[1]} {words[0]}", float(base + step), True),
        (ids[2], f"{words[2]} {words[1]}", float(base + 2 * step), True),
        (ids[3], f"{unseen} {words[3]} {words[3]}", float(base + 3 * step), False),
        (ids[4], f"{unseen} {words[2]} {words[0]} {words[0]}", float(base + 4 * step), False),
    ]

    data_lines = ["id,text,value,is_train"]
    for row_id, text, value, is_train in rows:
        data_lines.append(f"{row_id},{text},{value:.1f},{str(is_train).lower()}")
    run_pipeline("\n".join(data_lines) + "\n")

    assert nonempty_lines(TRAIN_OUTPUT) == expected_lines(rows, True)
    assert nonempty_lines(TEST_OUTPUT) == expected_lines(rows, False)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
