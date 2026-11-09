#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from datetime import datetime, timezone


def test_cleaned_data_exists_and_correct():
    file_path = "/home/user/cleaned_data.csv"

    # Check if the output file exists
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    expected_content = """1698825600,SENS-01,10.0,ALL CLEAR,10.00
1698825660,SENS-01,15.0,MINOR ISSUES,12.50
1698825720,SENS-01,20.0,ERROR 404,15.00
1698825780,SENS-01,10.0,FIXED,15.00
1698825840,SENS-01,12.0,OK,14.00"""

    with open(file_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, f"Content of {file_path} does not match the expected final state.\nExpected:\n{expected_content}\n\nActual:\n{actual_content}"


def test_process_script_on_fresh_input():
    script_path = "/home/user/process.sh"
    input_path = "/home/user/raw_data.txt"
    output_path = "/home/user/cleaned_data.csv"

    assert os.path.isfile(script_path), f"Required Bash script {script_path} is missing."

    token = secrets.token_hex(4)
    base_epoch = 1700000000 + secrets.randbelow(20000000)
    values = [secrets.randbelow(111) - 30 for _ in range(8)]
    remark_templates = [
        "  Alpha!!!  beta?? {token}  ",
        "##mixed-CASE__text {token}",
        "  error:  {token} / code 7  ",
        "punctuation...EVERYWHERE!!! {token}",
        "  two  internal   spaces {token}  ",
        "OK! [{token}]",
        "sensor's value = 42; {token}",
        "  final***Reading {token}  ",
    ]

    raw_lines = []
    expected_lines = []
    seen_values = []

    for i, value in enumerate(values):
        epoch = base_epoch + i * 67
        dt = datetime.fromtimestamp(epoch, timezone.utc)
        if i % 2 == 0:
            timestamp = dt.strftime("%Y-%m-%d %H:%M:%S UTC")
        else:
            timestamp = dt.strftime("%Y-%m-%dT%H:%M:%SZ")

        sensor = f" sEnS-{token}-{i} "
        value_text = f"{value}.0"
        remarks = remark_templates[i].format(token=token)
        raw_lines.append(f"{timestamp} |{sensor}| {value_text} | {remarks}")

        cleaned_sensor = sensor.strip().upper()
        cleaned_remarks = re.sub(r"[^A-Za-z0-9 ]", "", remarks).upper().strip()
        seen_values.append(value)
        window = seen_values[-3:]
        rolling_average = sum(window) / len(window)
        expected_lines.append(
            f"{epoch},{cleaned_sensor},{value_text},{cleaned_remarks},{rolling_average:.2f}"
        )

    with open(input_path, "w") as f:
        f.write("\n".join(raw_lines) + "\n")

    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run(
        ["bash", script_path],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Executing {script_path} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(output_path), f"Executing {script_path} did not create {output_path}."

    with open(output_path, "r") as f:
        actual_content = f.read().strip()
    expected_content = "\n".join(expected_lines)
    assert actual_content == expected_content, (
        f"Script output for a fresh input was incorrect.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
