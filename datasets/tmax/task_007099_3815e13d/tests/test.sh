#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import subprocess
import tempfile
import uuid
from collections import Counter

import pytest


def test_final_report_exists():
    report_path = "/home/user/final_report.txt"
    assert os.path.exists(report_path), f"The final report file {report_path} was not found."
    assert os.path.isfile(report_path), f"The path {report_path} is not a file."


def test_final_report_content():
    report_path = "/home/user/final_report.txt"
    if not os.path.exists(report_path):
        pytest.fail(f"Cannot check content because {report_path} does not exist.")

    with open(report_path, "r") as f:
        content = f.read()

    expected_lines = [
        "Filename: sensor_1.txt, Mean: 12.0000, Variance: 2.6667",
        "Filename: sensor_2.txt, Mean: 100000000.2000, Variance: 0.0067",
        "Filename: sensor 3.txt, Mean: 6.0000, Variance: 1.0000"
    ]

    for expected in expected_lines:
        assert expected in content, (
            f"Expected output line not found in {report_path}.\n"
            f"Missing: '{expected}'\n"
            f"This indicates either a failure to process a file (e.g. spaces in filename), "
            f"a crash on invalid data, or incorrect math calculations (precision issues)."
        )


def test_run_all_script_modifications():
    script_path = "/home/user/pipeline/run_all.sh"
    assert os.path.exists(script_path), f"Script {script_path} is missing."

    with open(script_path, "r") as f:
        content = f.read()

    assert "for f in $(find" not in content or "IFS=" in content or "while" in content or "-print0" in content, (
        "The run_all.sh script does not appear to correctly handle filenames with spaces. "
        "The naive 'for f in $(find ...)' approach is still present."
    )


def test_process_cpp_modifications():
    cpp_path = "/home/user/pipeline/process.cpp"
    assert os.path.exists(cpp_path), f"Source file {cpp_path} is missing."

    with open(cpp_path, "r") as f:
        content = f.read()

    assert "double" in content, "The C++ program does not seem to use 'double' precision variables as required to fix the floating-point issue."
    assert "try" in content or "catch" in content or "stod" in content, (
        "The C++ program does not seem to contain exception handling (try/catch) "
        "or safer parsing to prevent crashes on invalid arguments."
    )


def run_checked(command, timeout=30):
    result = subprocess.run(command, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, timeout=timeout)
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {command}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def test_fresh_inputs_through_cpp_and_pipeline():
    cpp_path = "/home/user/pipeline/process.cpp"
    script_path = "/home/user/pipeline/run_all.sh"
    process_path = "/home/user/pipeline/process"
    report_path = "/home/user/final_report.txt"
    data_path = "/home/user/data"
    token = uuid.uuid4().hex[:10]
    base = random.SystemRandom().randint(150000000, 850000000)

    # Independently compile the submitted C++ source and exercise that artifact.
    with tempfile.TemporaryDirectory(prefix="verify_process_") as td:
        binary = os.path.join(td, "process_under_test")
        input_name = f"independent input {token}.txt"
        input_path = os.path.join(td, input_name)
        with open(input_path, "w") as f:
            f.write(f"{base}.1\nNOT_A_MEASUREMENT\n{base}.2\n\n{base}.4\n{base}.5\n")

        run_checked(["g++", "-O3", cpp_path, "-o", binary])
        with open(binary, "rb") as f:
            assert f.read(4) == b"\x7fELF", "Compiling process.cpp did not produce an ELF executable."

        result = run_checked([binary, input_path])
        expected = f"Filename: {input_name}, Mean: {base}.3000, Variance: 0.0250"
        assert result.stdout.strip() == expected, (
            "The compiled process.cpp failed on fresh high-magnitude data or did not "
            "skip a malformed line.\n"
            f"Expected: {expected!r}\nActual: {result.stdout.strip()!r}"
        )

    # Replace the data set temporarily, force run_all.sh to rebuild process, and
    # verify its report for unpredictable filenames and values.
    backup_data = f"{data_path}.verifier_backup_{token}"
    old_report = None
    had_report = os.path.isfile(report_path)
    if had_report:
        with open(report_path, "rb") as f:
            old_report = f.read()

    assert os.path.isdir(data_path), f"Data directory {data_path} is missing."
    os.rename(data_path, backup_data)
    os.mkdir(data_path)

    plain_name = f"ordinary_{token}.txt"
    high_name = f"high readings {token}.txt"
    bad_name = f"malformed data {token}.txt"
    expected_lines = [
        f"Filename: {plain_name}, Mean: 12.0000, Variance: 2.6667",
        f"Filename: {high_name}, Mean: {base}.2000, Variance: 0.0067",
        f"Filename: {bad_name}, Mean: 6.0000, Variance: 1.0000",
    ]

    try:
        with open(os.path.join(data_path, plain_name), "w") as f:
            f.write("10.0\n12.0\n14.0\n")
        with open(os.path.join(data_path, high_name), "w") as f:
            f.write(f"{base}.1\n{base}.2\n{base}.3\n")
        with open(os.path.join(data_path, bad_name), "w") as f:
            f.write("5.0\nERROR_FROM_SENSOR\n7.0\n")

        if os.path.lexists(process_path):
            os.remove(process_path)
        run_checked(["bash", script_path])

        assert os.path.isfile(process_path), "run_all.sh did not compile the process executable."
        with open(process_path, "rb") as f:
            assert f.read(4) == b"\x7fELF", "run_all.sh did not create a compiled ELF process executable."
        assert os.path.isfile(report_path), "run_all.sh did not create /home/user/final_report.txt."

        with open(report_path, "r") as f:
            actual_lines = [line.strip() for line in f if line.strip()]
        assert Counter(actual_lines) == Counter(expected_lines), (
            "run_all.sh did not process every fresh data file exactly once with correct output.\n"
            f"Expected lines: {expected_lines!r}\nActual lines: {actual_lines!r}"
        )
    finally:
        shutil.rmtree(data_path, ignore_errors=True)
        os.rename(backup_data, data_path)
        if had_report:
            with open(report_path, "wb") as f:
                f.write(old_report)
        elif os.path.exists(report_path):
            os.remove(report_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
