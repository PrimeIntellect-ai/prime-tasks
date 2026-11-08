#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile


def test_clean_csv_exists_and_format():
    """Verify that the clean.csv file exists and has the correct extracted data."""
    file_path = "/home/user/clean.csv"
    assert os.path.exists(file_path), f"The file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} is not a regular file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "0.0,10.0",
        "0.5,11.5",
        "1.0,15.0",
        "1.5,45.0",
        "2.0,80.0",
        "2.5,30.0",
        "3.0,10.0"
    ]

    actual_lines = content.split('\n')
    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {file_path}, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        # Allow optional spaces around the comma
        actual_cleaned = actual.replace(" ", "")
        assert actual_cleaned == expected, f"Line {i+1} in {file_path} does not match expected. Expected: '{expected}', Actual: '{actual}'"


def test_analyze_rs_exists():
    """Verify that the analyze.rs file exists."""
    file_path = "/home/user/analyze.rs"
    assert os.path.exists(file_path), f"The file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} is not a regular file."


def test_report_txt_contents():
    """Verify that the report.txt file contains the correct calculated values."""
    file_path = "/home/user/report.txt"
    assert os.path.exists(file_path), f"The file {file_path} is missing."
    assert os.path.isfile(file_path), f"The path {file_path} is not a regular file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "Max Power Derivative: 70.00",
        "Total Energy: 95.75"
    ]

    actual_lines = content.split('\n')
    assert len(actual_lines) >= 2, f"Expected at least 2 lines in {file_path}, found {len(actual_lines)}."

    assert actual_lines[0].strip() == expected_lines[0], f"First line of report.txt is incorrect. Expected: '{expected_lines[0]}', Actual: '{actual_lines[0]}'"
    assert actual_lines[1].strip() == expected_lines[1], f"Second line of report.txt is incorrect. Expected: '{expected_lines[1]}', Actual: '{actual_lines[1]}'"


def test_analyzer_compiles_runs_and_computes_from_input():
    clean_path = "/home/user/clean.csv"
    report_path = "/home/user/report.txt"

    with open(clean_path, "rb") as f:
        original_clean = f.read()
    with open(report_path, "rb") as f:
        original_report = f.read()

    def run_analyzer(binary):
        if os.path.lexists(report_path):
            os.unlink(report_path)
        result = subprocess.run(
            [binary], cwd="/home/user", capture_output=True, text=True, timeout=10
        )
        assert result.returncode == 0, (
            f"Compiled analyzer exited with {result.returncode}. "
            f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
        )
        assert os.path.exists(report_path), "The analyzer did not create /home/user/report.txt."
        assert os.path.isfile(report_path), "The analyzer's report path is not a regular file."
        with open(report_path, "r") as f:
            return f.read().strip()

    try:
        with tempfile.TemporaryDirectory() as build_dir:
            binary = os.path.join(build_dir, "analyze")
            compiled = subprocess.run(
                ["rustc", "/home/user/analyze.rs", "-o", binary],
                capture_output=True, text=True, timeout=30
            )
            assert compiled.returncode == 0, (
                f"analyze.rs failed to compile. stdout: {compiled.stdout!r}; "
                f"stderr: {compiled.stderr!r}"
            )

            # Remove the pre-existing report and require the compiled program to
            # reproduce the required result for the original cleaned telemetry.
            original_output = run_analyzer(binary)
            assert original_output == (
                "Max Power Derivative: 70.00\nTotal Energy: 95.75"
            ), f"Analyzer produced an incorrect report for the original data: {original_output!r}"

            # Exercise the program on fresh, unpredictable data so a hardcoded
            # report cannot pass. Integer times/powers keep two-decimal rounding exact.
            rng = secrets.SystemRandom()
            times = [rng.randint(2, 20)]
            for _ in range(6):
                times.append(times[-1] + rng.randint(1, 4))
            powers = [rng.randint(1, 120) for _ in times]

            dynamic_csv = "\n".join(
                f"{t}.0,{p}.0" for t, p in zip(times, powers)
            ) + "\n"
            with open(clean_path, "w") as f:
                f.write(dynamic_csv)

            derivatives = [
                (powers[i + 1] - powers[i]) / (times[i + 1] - times[i])
                for i in range(len(times) - 1)
            ]
            energy = sum(
                (powers[i] + powers[i + 1]) * (times[i + 1] - times[i]) / 2.0
                for i in range(len(times) - 1)
            )
            expected = (
                f"Max Power Derivative: {max(derivatives):.2f}\n"
                f"Total Energy: {energy:.2f}"
            )
            dynamic_output = run_analyzer(binary)
            assert dynamic_output == expected, (
                f"Analyzer did not compute the dynamic input correctly. "
                f"Expected {expected!r}, got {dynamic_output!r}"
            )
    finally:
        with open(clean_path, "wb") as f:
            f.write(original_clean)
        if os.path.lexists(report_path):
            os.unlink(report_path)
        with open(report_path, "wb") as f:
            f.write(original_report)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
