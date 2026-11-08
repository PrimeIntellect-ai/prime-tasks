#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import math
import os
import subprocess
import re
import pytest

def test_anomaly_report():
    gen_log = "/home/user/logs/generator.log"
    assert os.path.exists(gen_log), f"{gen_log} is missing"

    with open(gen_log, "r") as f:
        lines = f.readlines()

    assert len(lines) >= 74, "generator.log does not have enough lines to find the anomaly."

    # The anomaly is at line 74 (index 73)
    line_74 = lines[73].strip()
    match = re.match(r"\[(.*?)\] Generated value: (.*)", line_74)
    assert match, "Line 74 in generator.log is not in the expected format."

    timestamp = match.group(1)
    value = match.group(2)

    report_file = "/home/user/anomaly_report.txt"
    assert os.path.exists(report_file), f"{report_file} is missing. You need to create the report."

    with open(report_file, "r") as f:
        report_content = f.read().strip()

    expected_report = f"Timestamp: {timestamp}, Value: {value}"
    assert report_content == expected_report, (
        f"anomaly_report.txt content is incorrect.\n"
        f"Expected: '{expected_report}'\n"
        f"Got: '{report_content}'"
    )

def test_build_success():
    build_script = "/home/user/build.sh"
    assert os.path.exists(build_script), f"{build_script} is missing"

    result = subprocess.run([build_script], capture_output=True, text=True)
    assert result.returncode == 0, (
        f"build.sh failed with exit code {result.returncode}.\n"
        f"Stdout:\n{result.stdout}\n"
        f"Stderr:\n{result.stderr}"
    )

def test_processor_on_derived_inputs():
    processor = "/home/user/processor.sh"
    data_file = "/home/user/data.txt"
    build_script = "/home/user/build.sh"

    assert os.path.isfile(processor), f"{processor} is missing or is not a regular file"
    assert os.access(processor, os.X_OK), f"{processor} is not executable"

    with open(data_file, "rb") as f:
        original_data = f.read()

    probe_values = ["2", "0.25", "81", "99.99", "-42.5", "7"]
    result = None
    probe_lines = []
    restore_result = None
    try:
        with open(data_file, "w") as f:
            f.write("\n".join(probe_values) + "\n")

        result = subprocess.run([processor], capture_output=True, text=True, timeout=30)
        if os.path.exists("/home/user/output.txt"):
            with open("/home/user/output.txt", "r") as f:
                probe_lines = f.read().splitlines()
    finally:
        with open(data_file, "wb") as f:
            f.write(original_data)
        restore_result = subprocess.run([build_script], capture_output=True, text=True, timeout=30)

    assert result.returncode == 0, (
        f"processor.sh failed on valid and anomalous probe inputs.\n"
        f"Stdout:\n{result.stdout}\nStderr:\n{result.stderr}"
    )
    assert len(probe_lines) == len(probe_values), (
        f"processor.sh produced {len(probe_lines)} lines for {len(probe_values)} probe inputs"
    )

    for i, (raw_input, raw_output) in enumerate(zip(probe_values, probe_lines), start=1):
        value = float(raw_input)
        if value < 0:
            assert raw_output == "INVALID", (
                f"Probe line {i}: expected INVALID for negative input {raw_input}, got {raw_output}"
            )
        else:
            try:
                actual = float(raw_output)
            except ValueError:
                pytest.fail(f"Probe line {i} is not numeric for input {raw_input}: {raw_output}")
            expected = math.sqrt(value)
            assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-9), (
                f"Probe line {i}: expected sqrt({raw_input}) = {expected}, got {actual}"
            )

    assert restore_result.returncode == 0, (
        f"build.sh failed after restoring the original data.\n"
        f"Stdout:\n{restore_result.stdout}\nStderr:\n{restore_result.stderr}"
    )

def test_output_txt():
    output_file = "/home/user/output.txt"
    assert os.path.exists(output_file), f"{output_file} is missing. Did the processor script run?"

    with open(output_file, "r") as f:
        lines = f.read().splitlines()

    data_file = "/home/user/data.txt"
    assert os.path.exists(data_file), f"{data_file} is missing."
    with open(data_file, "r") as f:
        data_lines = f.read().splitlines()

    assert len(lines) == len(data_lines), (
        f"output.txt has {len(lines)} lines, but data.txt has {len(data_lines)}. "
        f"The processor should output exactly one line per input line."
    )

    invalid_count = 0
    for i, line in enumerate(lines):
        input_value = float(data_lines[i])
        if line == "INVALID":
            invalid_count += 1
            assert input_value < 0, f"Line {i+1} in output.txt is INVALID, but input data was {data_lines[i]} (not negative)."
        else:
            try:
                actual = float(line)
            except ValueError:
                pytest.fail(f"Line {i+1} in output.txt is not a valid number or 'INVALID': {line}")
            assert input_value >= 0, (
                f"Line {i+1} should be INVALID because input {data_lines[i]} is negative."
            )
            expected = math.sqrt(input_value)
            assert math.isclose(actual, expected, rel_tol=1e-9, abs_tol=1e-9), (
                f"Line {i+1} has an incorrect square root for input {data_lines[i]}. "
                f"Expected {expected}, got {actual}."
            )

    assert invalid_count == 1, f"Expected exactly 1 'INVALID' in output.txt, but found {invalid_count}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
