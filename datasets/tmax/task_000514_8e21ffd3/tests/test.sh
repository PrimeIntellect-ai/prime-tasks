#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import re
import secrets
import statistics
import string
import subprocess
from pathlib import Path

CPP_PATH = Path("/home/user/etl_stats.cpp")
RAW_PATH = Path("/home/user/raw_data.csv")
REPORT_PATH = Path("/home/user/etl_report.txt")
BINARY_PATH = Path("/tmp/etl_stats_submission")


def test_etl_stats_cpp_exists():
    """Verify that the C++ source file exists."""
    cpp_path = "/home/user/etl_stats.cpp"
    assert os.path.exists(cpp_path), f"C++ source file {cpp_path} is missing."
    assert os.path.isfile(cpp_path), f"{cpp_path} is not a file."


def test_etl_report_exists_and_correct():
    """Verify that the report file exists and contains the correct statistics."""
    report_path = "/home/user/etl_report.txt"
    assert os.path.exists(report_path), f"Report file {report_path} is missing."
    assert os.path.isfile(report_path), f"{report_path} is not a file."

    with open(report_path, "r") as f:
        content = f.read().strip()

    mean_match = re.search(r"Mean:\s*([0-9.]+)", content)
    assert mean_match is not None, "Could not find 'Mean: <value>' in the report file."

    ci_match = re.search(r"CI:\s*\[([0-9.]+),\s*([0-9.]+)\]", content)
    assert ci_match is not None, "Could not find 'CI: [<lower>, <upper>]' in the report file."

    actual_mean = float(mean_match.group(1))
    actual_lower = float(ci_match.group(1))
    actual_upper = float(ci_match.group(2))

    expected_mean = 3.1000
    expected_lower = 2.0561
    expected_upper = 4.1439

    assert math.isclose(actual_mean, expected_mean, abs_tol=0.0002), \
        f"Expected Mean to be ~{expected_mean:.4f}, but got {actual_mean:.4f}"
    assert math.isclose(actual_lower, expected_lower, abs_tol=0.0002), \
        f"Expected Lower CI to be ~{expected_lower:.4f}, but got {actual_lower:.4f}"
    assert math.isclose(actual_upper, expected_upper, abs_tol=0.0002), \
        f"Expected Upper CI to be ~{expected_upper:.4f}, but got {actual_upper:.4f}"

    assert "Mean: 3.1000" in content, "The Mean value must be formatted to exactly 4 decimal places."
    assert "CI: [2.0561, 4.1439]" in content, "The CI values must be formatted to exactly 4 decimal places."


def expected_report(lengths):
    mean = sum(lengths) / len(lengths)
    sample_sd = statistics.stdev(lengths)
    margin = 1.96 * sample_sd / math.sqrt(len(lengths))
    return f"Mean: {mean:.4f}\nCI: [{mean - margin:.4f}, {mean + margin:.4f}]"


def run_and_check(lengths):
    if REPORT_PATH.exists():
        REPORT_PATH.unlink()
    result = subprocess.run(
        [str(BINARY_PATH)], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, \
        f"Compiled program exited with {result.returncode}: {result.stderr}"
    assert REPORT_PATH.exists() and REPORT_PATH.is_file(), \
        "Running the compiled program did not create /home/user/etl_report.txt"
    actual = REPORT_PATH.read_text()
    expected = expected_report(lengths)
    assert actual in (expected, expected + "\n"), \
        f"Incorrect report for verifier-supplied input. Expected {expected!r}, got {actual!r}"


def random_word(length):
    alphabet = string.ascii_letters
    return ''.join(secrets.choice(alphabet) for _ in range(length))


def test_compile_and_execute_on_derived_inputs():
    original_raw = RAW_PATH.read_bytes()
    original_report = REPORT_PATH.read_bytes()

    compile_result = subprocess.run(
        ["g++", "-O3", "-std=c++17", str(CPP_PATH), "-o", str(BINARY_PATH)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, \
        f"etl_stats.cpp did not compile successfully: {compile_result.stderr}"
    assert BINARY_PATH.exists() and BINARY_PATH.is_file()

    try:
        # First prove the submitted source regenerates the required original report.
        original_lengths = [3, 5, 5, 3, 5, 4, 3, 4, 3] + [1] * 7 + [4, 11, 2, 3]
        RAW_PATH.write_bytes(original_raw)
        run_and_check(original_lengths)

        # Exercise schema validation, tokenization, and calculations on two
        # unpredictable datasets whose answers are derived by the verifier.
        for token_count in (17, 29):
            lengths = [secrets.randbelow(12) + 1 for _ in range(token_count)]
            if len(set(lengths)) == 1:
                lengths[-1] = 12 if lengths[0] != 12 else 1
            words = [random_word(n) for n in lengths]

            lines = []
            pos = 0
            row_id = secrets.randbelow(50000) + 1
            while pos < len(words):
                take = min(secrets.randbelow(4) + 2, len(words) - pos)
                lines.append(f"{row_id},{' '.join(words[pos:pos + take])}")
                row_id += secrets.randbelow(20) + 1
                pos += take

            poison = random_word(80)
            lines.extend([
                f"not_an_integer,{poison}",
                f"123x,{poison}",
                f"missing_comma_{poison}",
                f"77,{poison},{poison}",
            ])
            # Randomize placement so invalid rows cannot be skipped by position.
            for i in range(len(lines) - 1, 0, -1):
                j = secrets.randbelow(i + 1)
                lines[i], lines[j] = lines[j], lines[i]

            RAW_PATH.write_text("\n".join(lines) + "\n")
            run_and_check(lengths)
    finally:
        RAW_PATH.write_bytes(original_raw)
        REPORT_PATH.write_bytes(original_report)
        if BINARY_PATH.exists():
            BINARY_PATH.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
