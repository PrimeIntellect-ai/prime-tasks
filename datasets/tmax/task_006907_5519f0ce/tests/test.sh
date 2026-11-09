#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import secrets
import subprocess
import sys
from decimal import Decimal
import pytest


def test_pipeline_script_exists():
    script_path = "/home/user/pipeline.py"
    assert os.path.isfile(script_path), f"Pipeline script {script_path} does not exist."


def test_output_summary_exists_and_correct():
    output_path = "/home/user/output/summary.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    with open(output_path, 'r', newline='', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Output file is empty."

    # Check header
    header = rows[0]
    assert header == ['Region', 'Total_Revenue'], f"Expected header ['Region', 'Total_Revenue'], got {header}"

    # Check data rows
    data = rows[1:]
    assert len(data) == 3, f"Expected 3 data rows, got {len(data)}"

    # Check contents and sorting
    expected_data = [
        ['EU', '3500.50'],
        ['UK', '4201.00'],
        ['US', '3500.50']
    ]

    for i, expected_row in enumerate(expected_data):
        assert data[i] == expected_row, f"Row {i+1} mismatch: expected {expected_row}, got {data[i]}"


def test_pipeline_executes_and_transforms_fresh_inputs():
    script_path = "/home/user/pipeline.py"
    output_path = "/home/user/output/summary.csv"
    data_paths = {
        name: f"/home/user/data/{name}"
        for name in ("us_sales.csv", "eu_sales.csv", "uk_sales.csv")
    }

    original_data = {
        name: open(path, "rb").read() for name, path in data_paths.items()
    }
    original_output = open(output_path, "rb").read() if os.path.exists(output_path) else None

    def random_amount():
        return Decimal(110001 + secrets.randbelow(390000)) / Decimal(100)

    us_amount = random_amount()
    eu_amount = random_amount()
    uk_amount = random_amount()
    shared_us = random_amount()
    shared_eu = random_amount()

    inputs = {
        "us_sales.csv": [
            ["Date", "Region", "Revenue"],
            ["2024-01-01", "US", f"${us_amount:.2f}"],
            ["2024-01-02", "US", "$1000.00"],
            ["2024-01-03", "Shared", f"${shared_us:.2f}"],
        ],
        "eu_sales.csv": [
            ["Date", "Region", "Revenue"],
            ["2024-02-01", "EU", f"{eu_amount:.2f}".replace(".", ",")],
            ["2024-02-02", "EU", "999,99"],
            ["2024-02-03", "Shared", f"{shared_eu:.2f}".replace(".", ",")],
        ],
        "uk_sales.csv": [
            ["Date", "Region", "Revenue"],
            ["2024-03-01", "UK", f"£{uk_amount:.2f}"],
            ["2024-03-02", "UK", "£1000.00"],
            ["2024-03-03", "Shared", "£12.34"],
        ],
    }

    expected = [
        ["EU", f"{eu_amount:.2f}"],
        ["Shared", f"{shared_us + shared_eu:.2f}"],
        ["UK", f"{uk_amount:.2f}"],
        ["US", f"{us_amount:.2f}"],
    ]

    try:
        for name, rows in inputs.items():
            with open(data_paths[name], "w", newline="", encoding="utf-8") as f:
                csv.writer(f).writerows(rows)

        if os.path.exists(output_path):
            os.remove(output_path)

        result = subprocess.run(
            [sys.executable, script_path],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, (
            f"Pipeline execution failed with code {result.returncode}. "
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert os.path.isfile(output_path), "Pipeline did not generate /home/user/output/summary.csv."

        with open(output_path, "r", newline="", encoding="utf-8") as f:
            rows = list(csv.reader(f))

        assert rows, "Pipeline generated an empty output file."
        assert rows[0] == ["Region", "Total_Revenue"], (
            f"Expected header ['Region', 'Total_Revenue'], got {rows[0]}"
        )
        assert rows[1:] == expected, f"Expected fresh-input results {expected}, got {rows[1:]}"
    finally:
        os.makedirs("/home/user/data", exist_ok=True)
        os.makedirs("/home/user/output", exist_ok=True)
        for name, content in original_data.items():
            with open(data_paths[name], "wb") as f:
                f.write(content)
        if original_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
