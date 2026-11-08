#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import subprocess
import uuid

import pytest


def test_pipeline_script_exists():
    """Check if pipeline.sh exists and is executable."""
    script_path = "/home/user/pipeline.sh"
    assert os.path.exists(script_path), f"Script not found: {script_path}"
    assert os.path.isfile(script_path), f"Path is not a file: {script_path}"
    assert os.access(script_path, os.X_OK), f"Script is not executable: {script_path}"


def test_venv_and_csvkit_installed():
    """Check if the virtual environment exists and csvkit is installed."""
    venv_python = "/home/user/venv/bin/python"
    assert os.path.exists(venv_python), f"Virtual environment python not found at {venv_python}"

    try:
        result = subprocess.run(
            ["/home/user/venv/bin/pip", "show", "csvkit"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=True
        )
        assert "Name: csvkit" in result.stdout, "csvkit does not appear to be installed in the virtual environment."
    except subprocess.CalledProcessError:
        pytest.fail("Failed to run pip show csvkit in the virtual environment. Is csvkit installed?")


def test_clean_tokens_csv():
    """Check the outputs produced for the supplied dataset."""
    file_path = "/home/user/clean_tokens.csv"
    assert os.path.exists(file_path), f"Output file not found: {file_path}"

    expected_content = """item_id,publish_date,tokens
1,2023-01-15,hello world great item
4,2023-04-20,testing pipeline reproducibility
5,2023-05-05,just letters and spaces
6,2023-06-12,extra spaces everywhere"""

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"The contents of {file_path} do not match the expected output."


def test_row_count_txt():
    """Check the count produced for the supplied dataset."""
    file_path = "/home/user/row_count.txt"
    assert os.path.exists(file_path), f"Output file not found: {file_path}"

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "4", f"Expected row_count.txt to contain '4', but found '{content}'."


def test_pipeline_executes_on_new_csv_data():
    """Replace the input, execute the pipeline, and independently derive its output."""
    nonce = uuid.uuid4().hex[:10]
    rows = [
        ["101", "2024-01-02", f'Hello, "WORLD"!!!  Code9 {nonce.upper()}'],
        ["-102", "2024-02-03", "invalid negative identifier"],
        ["A103", "2024-03-04", "invalid alphabetic identifier"],
        ["104", "2024/04/05", "invalid slash date"],
        ["105", "2024-5-06", "invalid short month"],
        ["106", "2024-06-07", f"  Multiple     spaces, punctuation... and 123 {nonce}  "],
        ["107", "2024-07-08", "Numbers123touchWords and hyphen-joined"],
        ["108", "2024-08-09", "1234 !!!"],
    ]

    def tokenize(value):
        value = re.sub(r"[^a-z ]", "", value.lower())
        return re.sub(r" +", " ", value).strip()

    expected = [["item_id", "publish_date", "tokens"]]
    for item_id, publish_date, raw_text in rows:
        if re.fullmatch(r"[0-9]+", item_id) and re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", publish_date):
            expected.append([item_id, publish_date, tokenize(raw_text)])

    with open("/home/user/raw_data.csv", "w", newline="", encoding="utf-8") as f:
        writer = csv.writer(f)
        writer.writerow(["item_id", "publish_date", "raw_text"])
        writer.writerows(rows)

    for path in ("/home/user/clean_tokens.csv", "/home/user/row_count.txt"):
        if os.path.exists(path):
            os.unlink(path)

    result = subprocess.run(
        ["/home/user/pipeline.sh"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=240,
    )
    assert result.returncode == 0, (
        f"pipeline.sh failed with exit code {result.returncode}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile("/home/user/clean_tokens.csv"), "Pipeline did not create clean_tokens.csv"
    with open("/home/user/clean_tokens.csv", newline="", encoding="utf-8") as f:
        actual = list(csv.reader(f))
    assert actual == expected, f"Unexpected output for replacement input: {actual!r}"

    assert os.path.isfile("/home/user/row_count.txt"), "Pipeline did not create row_count.txt"
    with open("/home/user/row_count.txt", encoding="utf-8") as f:
        count = f.read().strip()
    assert count == str(len(expected) - 1), f"Unexpected row count: {count!r}"

    result = subprocess.run(
        ["/home/user/venv/bin/pip", "show", "csvkit"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    assert result.returncode == 0 and "Name: csvkit" in result.stdout, "csvkit is not installed after pipeline execution"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
