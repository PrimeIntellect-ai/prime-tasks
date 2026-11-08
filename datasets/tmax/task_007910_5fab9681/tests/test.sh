#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import glob
import subprocess
import sys
from collections import defaultdict

import pytest

@pytest.fixture(scope="session", autouse=True)
def execute_process_script():
    """Require and execute the requested automation script from a clean report state."""
    script_path = "/home/user/process_sensors.py"
    assert os.path.isfile(script_path), f"Required script is missing at {script_path}."

    for report_path in glob.glob("/home/user/reports/*.md"):
        os.remove(report_path)

    result = subprocess.run(
        [sys.executable, script_path],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{script_path} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )

def test_reports_directory_exists():
    """Test that the reports directory was created."""
    assert os.path.isdir("/home/user/reports"), "The directory /home/user/reports does not exist."

def test_markdown_reports_content():
    """Test the contents of the generated markdown reports."""
    csv_path = "/home/user/wide_sensors.csv"
    template_path = "/home/user/template.md"

    # Read the original CSV to compute expected values
    sensor_data = defaultdict(list)
    with open(csv_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = row["timestamp"]
            for key, val in row.items():
                if key != "timestamp" and val.strip():
                    sensor_data[key].append((ts, float(val)))

    # Read the template
    with open(template_path, "r") as f:
        template = f.read()

    for sensor, data in sensor_data.items():
        # Sort by timestamp
        data.sort(key=lambda x: x[0])

        values = [v for _, v in data]
        max_val = max(values)
        min_val = min(values)
        avg_val = sum(values) / len(values)

        # Last 3 readings
        last_3 = data[-3:]
        table_lines = ["| Timestamp | Value |", "|---|---|"]
        for ts, val in last_3:
            table_lines.append(f"| {ts} | {val} |")
        table_str = "\n".join(table_lines)

        expected_content = template.replace("{SENSOR}", sensor)
        expected_content = expected_content.replace("{MAX}", f"{max_val:.1f}")
        expected_content = expected_content.replace("{MIN}", f"{min_val:.1f}")
        expected_content = expected_content.replace("{AVG}", f"{avg_val:.2f}")
        expected_content = expected_content.replace("{TABLE}", table_str)

        report_path = f"/home/user/reports/{sensor}.md"
        assert os.path.isfile(report_path), f"Report file for {sensor} is missing at {report_path}."

        with open(report_path, "r") as f:
            actual_content = f.read()

        assert actual_content.strip() == expected_content.strip(), f"Content mismatch in {report_path}.\nExpected:\n{expected_content}\n\nActual:\n{actual_content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
