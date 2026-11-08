#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import secrets
import stat
import subprocess

CSV_PATH = "/home/user/measurements.csv"
SCRIPT_PATH = "/home/user/analyze.sh"
REPORT_PATH = "/home/user/sensor_report.txt"


def derive_expected(csv_path):
    sensor_data = {}
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            next(reader)
        except StopIteration:
            pass

        for row in reader:
            if len(row) != 3:
                continue
            _, sensor, val_str = row
            if not val_str.strip():
                continue
            try:
                val = float(val_str)
            except ValueError:
                continue
            if val < -10.0 or val > 50.0:
                continue
            sensor_data.setdefault(sensor, []).append(val)

    expected_lines = []
    for sensor in sorted(sensor_data.keys()):
        vals = sensor_data[sensor]
        if not vals:
            continue
        avg = sum(vals) / len(vals)
        avg_str = f"{round(avg, 2):.2f}"
        num_asterisks = max(0, math.floor(avg))
        expected_lines.append(
            f"Sensor: {sensor} | Avg: {avg_str} | Plot: {'*' * num_asterisks}"
        )
    return expected_lines


def test_sensor_report_content():
    assert os.path.exists(CSV_PATH), f"Input file {CSV_PATH} is missing."
    assert os.path.exists(REPORT_PATH), f"Output file {REPORT_PATH} was not generated."

    expected_lines = derive_expected(CSV_PATH)
    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in the report, but found {len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch on line {i + 1} of {REPORT_PATH}.\n"
            f"Expected: {expected}\nActual:   {actual}"
        )


def run_script():
    result = subprocess.run(
        ["/bin/bash", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(REPORT_PATH), f"Executing {SCRIPT_PATH} did not generate {REPORT_PATH}."


def test_analyze_script_executes_and_handles_unseen_input():
    assert os.path.lexists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing."
    mode = os.lstat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), f"{SCRIPT_PATH} must be a regular Bash script."

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    original_report = None
    if os.path.exists(REPORT_PATH):
        with open(REPORT_PATH, "rb") as f:
            original_report = f.read()

    token = secrets.token_hex(6)
    alpha = f"Alpha_{token}"
    middle = f"Middle_{token}"
    zeta = f"Zeta_{token}"
    dynamic_csv = f"""timestamp,sensor_name,value
2026-01-01T00:00:00,{zeta},10.2
2026-01-01T00:01:00,{alpha},-2.4
2026-01-01T00:02:00,{middle},50.0
2026-01-01T00:03:00,{zeta},11.6
2026-01-01T00:04:00,{alpha},-3.2
2026-01-01T00:05:00,{middle},0.24
2026-01-01T00:06:00,{zeta},
2026-01-01T00:07:00,{alpha},-10.1
2026-01-01T00:08:00,{middle},50.1
2026-01-01T00:09:00,{zeta},999.9
"""

    try:
        # First prove the artifact itself can regenerate the report.
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        run_script()
        assert derive_expected(CSV_PATH) == [
            line.strip()
            for line in open(REPORT_PATH, "r", encoding="utf-8")
            if line.strip()
        ]

        # Replace the fixed fixture with an unpredictable dataset and execute again.
        with open(CSV_PATH, "w", encoding="utf-8", newline="") as f:
            f.write(dynamic_csv)
        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        run_script()

        expected = derive_expected(CSV_PATH)
        with open(REPORT_PATH, "r", encoding="utf-8") as f:
            actual = [line for line in f.read().splitlines() if line.strip()]
        assert actual == expected, (
            "The executed script did not correctly process an unseen dataset.\n"
            f"Expected: {expected!r}\nActual:   {actual!r}"
        )
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        if original_report is None:
            try:
                os.remove(REPORT_PATH)
            except FileNotFoundError:
                pass
        else:
            with open(REPORT_PATH, "wb") as f:
                f.write(original_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
