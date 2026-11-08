#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import shutil
import subprocess
from collections import Counter
from pathlib import Path

import pytest


@pytest.fixture(scope="session")
def pipeline_run():
    required_columns = ["IP", "Date", "Endpoint", "Status"]
    expected_rows = []

    # Derive the expected normalized rows before executing the submitted script.
    for raw_path in sorted(Path("/home/user/raw").glob("*.csv")):
        with raw_path.open("r", newline="") as f:
            reader = csv.DictReader(f)
            assert reader.fieldnames is not None, f"{raw_path} has no header."
            assert all(column in reader.fieldnames for column in required_columns), (
                f"{raw_path} is missing one or more required columns."
            )
            for row in reader:
                if int(row["Status"]) < 500:
                    expected_rows.append({column: row[column] for column in required_columns})

    # Remove previously generated artifacts so the submitted pipeline must recreate them.
    for output_dir in (Path("/home/user/processed"), Path("/home/user/reports")):
        if output_dir.is_symlink() or output_dir.is_file():
            output_dir.unlink()
        elif output_dir.exists():
            shutil.rmtree(output_dir)

    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

    result = subprocess.run(
        ["runuser", "-u", "user", "--", script_path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=120,
    )
    assert result.returncode == 0, (
        f"pipeline.sh exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )

    return expected_rows


def test_pipeline_script_exists_and_executable():
    script_path = "/home/user/pipeline.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_venv_and_csvkit_installed():
    csvcut_path = "/home/user/venv/bin/csvcut"
    assert os.path.isfile(csvcut_path), "csvkit does not appear to be installed in the virtual environment at /home/user/venv."


def test_master_log_csv(pipeline_run):
    master_log_path = "/home/user/processed/master_log.csv"
    assert os.path.isfile(master_log_path), f"The file {master_log_path} does not exist."

    with open(master_log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 10, f"Expected exactly 10 lines in {master_log_path}, but found {len(lines)}."

    header_count = sum(1 for line in lines if line == "IP,Date,Endpoint,Status")
    assert header_count == 1, f"Expected exactly one header row 'IP,Date,Endpoint,Status' in {master_log_path}, but found {header_count}."
    assert lines[0] == "IP,Date,Endpoint,Status", "The first line of master_log.csv must be the header."

    required_columns = ["IP", "Date", "Endpoint", "Status"]
    with open(master_log_path, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == required_columns, (
            f"Expected columns {required_columns}, but found {reader.fieldnames}."
        )
        actual_rows = list(reader)

    expected_counter = Counter(
        tuple(row[column] for column in required_columns) for row in pipeline_run
    )
    actual_counter = Counter(
        tuple(row[column] for column in required_columns) for row in actual_rows
    )
    assert actual_counter == expected_counter, (
        "master_log.csv does not contain exactly the normalized rows from the raw CSVs "
        "with Status values below 500."
    )


def test_summary_md(pipeline_run):
    summary_path = "/home/user/reports/summary.md"
    assert os.path.isfile(summary_path), f"The file {summary_path} does not exist."

    with open(summary_path, "r") as f:
        content = f.read().strip()

    expected_content = (
        "# Endpoint Summary\n"
        "- /api/auth: 3\n"
        "- /api/data: 3\n"
        "- /api/users: 3"
    )

    assert content == expected_content, f"The content of {summary_path} does not match the expected output."

    endpoint_counts = Counter(row["Endpoint"] for row in pipeline_run)
    derived_content = "# Endpoint Summary\n" + "\n".join(
        f"- {endpoint}: {endpoint_counts[endpoint]}" for endpoint in sorted(endpoint_counts)
    )
    assert content == derived_content, (
        "summary.md does not match the endpoint counts derived from the filtered raw data."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
