#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import hashlib
import io
import json
import math
import os
import subprocess

SOURCE = "/home/user/analyze.go"
DATA = "/home/user/data.csv"
REPORT = "/home/user/report.json"
BINARY = "/tmp/analyze_submission"


def expected_for(csv_bytes):
    expected_hash = hashlib.sha256(csv_bytes).hexdigest()
    reader = csv.DictReader(io.StringIO(csv_bytes.decode("utf-8")))
    cpu_vals = []
    latency_vals = []
    for row in reader:
        cpu_vals.append(float(row["cpu"]))
        latency_vals.append(float(row["latency"]))

    n = len(cpu_vals)
    assert n > 0, "CSV file is empty or missing data rows."
    mean_cpu = sum(cpu_vals) / n
    mean_latency = sum(latency_vals) / n
    numerator = sum(
        (cpu_vals[i] - mean_cpu) * (latency_vals[i] - mean_latency)
        for i in range(n)
    )
    den_cpu = sum((value - mean_cpu) ** 2 for value in cpu_vals)
    den_latency = sum((value - mean_latency) ** 2 for value in latency_vals)
    correlation = 0.0 if den_cpu == 0 or den_latency == 0 else numerator / math.sqrt(den_cpu * den_latency)
    status = "PASS" if correlation < 0.700 else "FAIL"
    rounded_text = f"{correlation:.3f}"
    exact_report = (
        f'{{"file_hash": "{expected_hash}", "correlation": {rounded_text}, '
        f'"status": "{status}"}}'
    ).encode("utf-8")
    return expected_hash, float(rounded_text), status, exact_report


def run_and_check(csv_bytes):
    with open(DATA, "wb") as f:
        f.write(csv_bytes)
    if os.path.lexists(REPORT):
        os.remove(REPORT)

    subprocess.run([BINARY], check=True, timeout=20, cwd="/home/user")
    assert os.path.isfile(REPORT), f"The report file {REPORT} does not exist."

    with open(REPORT, "rb") as f:
        report_bytes = f.read()

    try:
        data = json.loads(report_bytes.decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        raise AssertionError(f"The file {REPORT} does not contain valid JSON: {exc}")

    assert "file_hash" in data, "Missing 'file_hash' in report.json"
    assert "correlation" in data, "Missing 'correlation' in report.json"
    assert "status" in data, "Missing 'status' in report.json"

    expected_hash, expected_correlation, expected_status, exact_report = expected_for(csv_bytes)
    assert data["file_hash"] == expected_hash, f"Expected file_hash '{expected_hash}', got '{data['file_hash']}'."
    assert data["correlation"] == expected_correlation, f"Expected correlation {expected_correlation}, got {data['correlation']}."
    assert data["status"] == expected_status, f"Expected status '{expected_status}', got '{data['status']}'."
    assert report_bytes == exact_report, (
        "report.json does not use the exact required spacing, field order, or exactly "
        "three displayed decimal places."
    )


def test_analyze_go_exists():
    assert os.path.isfile(SOURCE), "The Go program /home/user/analyze.go does not exist."


def test_compiled_program_generates_correct_reports():
    assert os.path.isfile(DATA), f"The data file {DATA} is missing."
    with open(DATA, "rb") as f:
        original_csv = f.read()

    subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        check=True,
        timeout=60,
        cwd="/home/user",
    )
    assert os.path.isfile(BINARY), "Compiling analyze.go did not produce an executable."

    # This case has an unrounded correlation just below 0.700 but displays as
    # 0.700, ensuring status is based on the actual coefficient.
    r = 0.6996
    noise = math.sqrt(1.0 - r * r)
    x_values = [-2.0, -1.0, 0.0, 1.0, 2.0]
    orthogonal = [1.0, -2.0, 0.0, 2.0, -1.0]
    lines = ["id,cpu,memory,latency"]
    for i, (x, v) in enumerate(zip(x_values, orthogonal), 1):
        latency = 100.0 + r * x + noise * v
        lines.append(f"{i},{30.0 + x:.17g},16.0,{latency:.17g}")
    threshold_csv = ("\n".join(lines) + "\n").encode("utf-8")

    try:
        run_and_check(threshold_csv)
        # Run the submitted artifact on the required original input last, so
        # the final report is the report requested by the instruction.
        run_and_check(original_csv)
    finally:
        with open(DATA, "wb") as f:
            f.write(original_csv)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
