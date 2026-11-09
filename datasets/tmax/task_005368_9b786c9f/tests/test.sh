#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import math
import os
import secrets
import subprocess
import tempfile


def expected_outputs(data):
    n = len(data)
    mean = sum(data) / n
    variance = sum((x - mean) ** 2 for x in data) / n
    stddev = math.sqrt(variance)

    summary = f"Mean: {mean:.4f}\nStdDev: {stddev:.4f}"
    csv = []
    for i in range(2, n):
        rolling_mean = sum(data[i-2:i+1]) / 3.0
        z_score = (data[i] - mean) / stddev
        csv.append(f"{data[i]:.4f},{rolling_mean:.4f},{z_score:.4f}")
    return summary, csv


def outputs_are_correct(data, summary_path, processed_path):
    if not os.path.isfile(summary_path) or not os.path.isfile(processed_path):
        return False

    expected_summary, expected_csv = expected_outputs(data)
    with open(summary_path, "r") as f:
        if f.read().strip() != expected_summary:
            return False
    with open(processed_path, "r") as f:
        actual_csv = [line.strip() for line in f if line.strip()]
    return actual_csv == expected_csv


def test_summary_and_processed_csv():
    telemetry_path = "/home/user/telemetry.txt"
    summary_path = "/home/user/summary.txt"
    processed_path = "/home/user/processed.csv"

    assert os.path.isfile(telemetry_path), f"Input file {telemetry_path} is missing."
    assert os.path.isfile(summary_path), f"Output file {summary_path} is missing."
    assert os.path.isfile(processed_path), f"Output file {processed_path} is missing."

    # Read telemetry data
    with open(telemetry_path, "r") as f:
        data = [float(line.strip()) for line in f if line.strip()]

    assert len(data) > 2, "Telemetry data must have more than 2 elements."

    # Compute expected summary statistics
    n = len(data)
    mean = sum(data) / n
    variance = sum((x - mean) ** 2 for x in data) / n
    stddev = math.sqrt(variance)

    expected_summary = f"Mean: {mean:.4f}\nStdDev: {stddev:.4f}"

    # Verify summary.txt
    with open(summary_path, "r") as f:
        summary_content = f.read().strip()

    assert summary_content == expected_summary, (
        f"Expected {summary_path} to contain:\n{expected_summary}\n"
        f"But got:\n{summary_content}"
    )

    # Compute expected processed.csv
    expected_csv = []
    for i in range(2, len(data)):
        window = data[i-2:i+1]
        rolling_mean = sum(window) / 3.0
        z_score = (data[i] - mean) / stddev
        expected_csv.append(f"{data[i]:.4f},{rolling_mean:.4f},{z_score:.4f}")

    # Verify processed.csv
    with open(processed_path, "r") as f:
        csv_lines = [line.strip() for line in f if line.strip()]

    assert len(csv_lines) == len(expected_csv), (
        f"Expected {len(expected_csv)} lines in {processed_path}, got {len(csv_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(csv_lines, expected_csv)):
        assert actual == expected, (
            f"Line {i+1} in {processed_path} is incorrect.\n"
            f"Expected: {expected}\n"
            f"Got:      {actual}"
        )

    # Locate an actual C source file written by the agent.
    sources = []
    for root, dirs, files in os.walk("/home/user"):
        for name in files:
            path = os.path.join(root, name)
            if name.endswith(".c") and os.path.isfile(path) and not os.path.islink(path):
                sources.append(path)
    assert sources, "No C source file was found under /home/user."

    original_files = {}
    for path in (telemetry_path, summary_path, processed_path):
        with open(path, "rb") as f:
            original_files[path] = f.read()

    # Values are generated only during verification, so fixed or precomputed output
    # files cannot satisfy these checks.
    cases = []
    for length in (7, 19):
        values = []
        for i in range(length):
            value = (secrets.randbelow(400001) - 200000) / 1000.0 + i * 0.137
            values.append(float(f"{value:.6f}"))
        cases.append(values)

    passed_source = None
    diagnostics = []
    try:
        with tempfile.TemporaryDirectory() as tmpdir:
            for source_index, source in enumerate(sources):
                executable = os.path.join(tmpdir, f"telemetry_program_{source_index}")
                try:
                    compiled = subprocess.run(
                        ["gcc", "-std=c11", "-O2", source, "-lm", "-o", executable],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=20,
                    )
                except (subprocess.SubprocessError, OSError) as exc:
                    diagnostics.append(f"{source}: compilation failed: {exc}")
                    continue

                if compiled.returncode != 0:
                    diagnostics.append(f"{source}: gcc rejected the source")
                    continue

                source_passed = True
                for case in cases:
                    with open(telemetry_path, "w") as f:
                        for value in case:
                            f.write(f"{value:.6f}\n")
                    for output in (summary_path, processed_path):
                        try:
                            os.remove(output)
                        except FileNotFoundError:
                            pass

                    try:
                        run = subprocess.run(
                            [executable],
                            cwd="/home/user",
                            stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE,
                            text=True,
                            timeout=10,
                        )
                    except (subprocess.SubprocessError, OSError):
                        source_passed = False
                        break

                    if run.returncode != 0 or not outputs_are_correct(case, summary_path, processed_path):
                        source_passed = False
                        break

                if source_passed:
                    passed_source = source
                    break
    finally:
        for path, content in original_files.items():
            with open(path, "wb") as f:
                f.write(content)

    assert passed_source is not None, (
        "No submitted C source could be compiled and executed successfully on "
        "verification-generated telemetry inputs. " + "; ".join(diagnostics[:5])
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
