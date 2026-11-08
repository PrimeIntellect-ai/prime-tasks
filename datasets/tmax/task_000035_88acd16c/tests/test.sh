#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import stat
import subprocess

import pytest

PROJECT = "/home/user/pipeline"
MAIN_RS = os.path.join(PROJECT, "src", "main.rs")
INPUT_CSV = os.path.join(PROJECT, "input.csv")
OUTPUT_CSV = os.path.join(PROJECT, "cleaned.csv")


@pytest.fixture(scope="session")
def pipeline_command():
    """Locate, compile, and execute the Cargo binary whose source is src/main.rs."""
    assert os.path.isfile(MAIN_RS), f"File {MAIN_RS} does not exist."
    assert stat.S_ISREG(os.stat(MAIN_RS).st_mode), f"{MAIN_RS} is not a regular file."

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--format-version", "1", "--no-deps"],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)

    expected_source = os.path.realpath(MAIN_RS)
    matching_targets = []
    for package in metadata.get("packages", []):
        for target in package.get("targets", []):
            if "bin" in target.get("kind", []) and os.path.realpath(target.get("src_path", "")) == expected_source:
                matching_targets.append(target["name"])

    assert matching_targets, "Cargo.toml does not define a binary built from /home/user/pipeline/src/main.rs"
    command = ["cargo", "run", "--quiet", "--bin", matching_targets[0]]

    result = subprocess.run(
        command,
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, f"Rust pipeline failed to compile or run:\n{result.stderr}"
    return command


def test_cleaned_csv_exists(pipeline_command):
    """Check if cleaned.csv was generated."""
    assert os.path.isfile("/home/user/pipeline/cleaned.csv"), "File /home/user/pipeline/cleaned.csv does not exist. Did you run the Rust program?"


def test_cleaned_csv_content(pipeline_command):
    """Check if cleaned.csv contains the correct processed data."""
    expected_lines = [
        "timestamp,distance",
        "1000,22.36",
        "1001,29.15",
        "1003,7.07"
    ]

    with open("/home/user/pipeline/cleaned.csv", "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in cleaned.csv, but found {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual.strip()}'."


def test_pipeline_on_unseen_multiline_input(pipeline_command):
    """Exercise the compiled Rust program on unpredictable CSV records."""
    original_input = open(INPUT_CSV, "rb").read()
    rng = secrets.SystemRandom()
    base_timestamp = rng.randrange(200000, 900000)

    x1 = rng.randrange(6, 30)
    y1 = rng.randrange(6, 30)
    x2 = -rng.randrange(1, 25)
    y2 = rng.randrange(1, 25)

    records = [
        [str(base_timestamp), "North station\nSecond floor, near pump", str(x1), str(y1)],
        [str(base_timestamp + 1), "Outside validation radius", str(rng.randrange(51, 90)), str(rng.randrange(-20, 21))],
        [str(base_timestamp + 2), "Exactly on boundary", "30", "40"],
        [str(base_timestamp + 3), "Quoted \"sensor\" note", str(x2), str(y2)],
    ]
    rng.shuffle(records)

    expected = [["timestamp", "distance"]]
    for timestamp, _notes, x_text, y_text in records:
        distance = math.hypot(float(x_text), float(y_text))
        if distance <= 50.0:
            expected.append([timestamp, f"{distance:.2f}"])

    try:
        with open(INPUT_CSV, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["timestamp", "location_notes", "x", "y"])
            writer.writerows(records)

        result = subprocess.run(
            pipeline_command,
            cwd=PROJECT,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=180,
        )
        assert result.returncode == 0, f"Rust pipeline failed on test input:\n{result.stderr}"
        assert os.path.isfile(OUTPUT_CSV), "Pipeline did not generate cleaned.csv"

        with open(OUTPUT_CSV, "r", newline="") as f:
            raw_output = f.read()
        assert raw_output.splitlines()[0] == "timestamp,distance", "Output header must be exactly timestamp,distance"

        parsed_output = list(csv.reader(raw_output.splitlines()))
        assert parsed_output == expected, f"Unexpected output for generated input: {parsed_output!r}; expected {expected!r}"
        assert all(len(row) == 2 for row in parsed_output), "Every output row must contain exactly two columns"
        assert all(len(row[1].partition(".")[2]) == 2 for row in parsed_output[1:]), "Distances must have exactly two decimal places"
    finally:
        with open(INPUT_CSV, "wb") as f:
            f.write(original_input)
        subprocess.run(
            pipeline_command,
            cwd=PROJECT,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=180,
            check=False,
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
