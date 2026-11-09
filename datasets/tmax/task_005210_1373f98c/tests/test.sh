#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import math
import re
import subprocess
import sys
from datetime import datetime
import pytest


def get_expected_data():
    """Reads the actual sensor data and computes the expected daily aggregations."""
    data = {}

    sensor_a_path = "/home/user/data/sensor_a.csv"
    if os.path.exists(sensor_a_path):
        with open(sensor_a_path, encoding="utf-16le") as f:
            reader = csv.DictReader(f)
            for row in reader:
                dt = datetime.strptime(row["timestamp"], "%Y-%m-%d %H:%M:%S")
                date_str = dt.strftime("%Y-%m-%d")
                temp_c = float(row["temp_c"])
                data.setdefault(date_str, []).append(temp_c)

    sensor_b_path = "/home/user/data/sensor_b.csv"
    if os.path.exists(sensor_b_path):
        with open(sensor_b_path, encoding="iso-8859-1") as f:
            reader = csv.DictReader(f)
            for row in reader:
                dt = datetime.strptime(row["timestamp"], "%m/%d/%Y-%H:%M")
                date_str = dt.strftime("%Y-%m-%d")
                temp_f = float(row["temp_f"])
                temp_c = (temp_f - 32) * 5.0 / 9.0
                data.setdefault(date_str, []).append(temp_c)

    return data


@pytest.fixture(scope="session", autouse=True)
def execute_etl_script():
    """Require the requested Python script and verify that it generates the report."""
    script_path = "/home/user/etl.py"
    report_path = "/home/user/output/report.md"

    assert os.path.isfile(script_path), f"ETL script is missing at {script_path}"
    if os.path.exists(report_path):
        os.remove(report_path)

    result = subprocess.run(
        [sys.executable, script_path],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"ETL script failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_report_file_exists():
    """Test that the report file was generated in the correct location."""
    report_path = "/home/user/output/report.md"
    assert os.path.isfile(report_path), f"Report file is missing at {report_path}"


def test_report_content():
    """Test that the report content accurately reflects the aggregated sensor data."""
    report_path = "/home/user/output/report.md"
    template_path = "/home/user/template.md"

    assert os.path.isfile(report_path), "Cannot check content because report.md is missing."
    assert os.path.isfile(template_path), "Cannot check content because template.md is missing."

    data = get_expected_data()
    assert data, "No data could be read from the sensor files."

    with open(template_path, "r", encoding="utf-8") as f:
        template = f.read().strip()

    with open(report_path, "r", encoding="utf-8") as f:
        actual_output = f.read().strip()

    actual_blocks = actual_output.split("\n\n")
    dates = sorted(data.keys())
    assert len(actual_blocks) == len(dates), (
        "The report must contain one template block per date, separated by a blank line."
    )

    number_pattern = r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?"

    for block, date_str in zip(actual_blocks, dates):
        temps = data[date_str]
        min_c = min(temps)
        max_c = max(temps)
        avg_c = sum(temps) / len(temps)

        pattern = re.escape(template)
        pattern = pattern.replace(re.escape("{DATE}"), re.escape(date_str))
        pattern = pattern.replace(re.escape("{MIN}"), f"(?P<min>{number_pattern})")
        pattern = pattern.replace(re.escape("{MAX}"), f"(?P<max>{number_pattern})")
        pattern = pattern.replace(re.escape("{AVG}"), r"(?P<avg>[+-]?\d+\.\d{2})")

        match = re.fullmatch(pattern, block)
        assert match is not None, (
            f"The report block for {date_str} does not preserve the template structure "
            "or required numeric formatting."
        )
        assert math.isclose(float(match.group("min")), min_c, rel_tol=1e-12, abs_tol=1e-12), (
            f"Incorrect minimum temperature for {date_str}."
        )
        assert math.isclose(float(match.group("max")), max_c, rel_tol=1e-12, abs_tol=1e-12), (
            f"Incorrect maximum temperature for {date_str}."
        )
        assert match.group("avg") == f"{avg_c:.2f}", (
            f"Incorrect average temperature for {date_str}; it must have exactly two decimal places."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
