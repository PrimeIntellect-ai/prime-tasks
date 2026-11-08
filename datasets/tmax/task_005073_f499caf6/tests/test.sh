#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from decimal import Decimal


def test_cpp_source_and_binary_exist():
    """Test that the C++ source file and compiled binary exist."""
    source_path = "/home/user/process.cpp"
    binary_path = "/home/user/process"

    assert os.path.exists(source_path), f"C++ source file {source_path} is missing."
    assert os.path.isfile(source_path), f"Path {source_path} is not a file."

    assert os.path.exists(binary_path), f"Compiled binary {binary_path} is missing."
    assert os.path.isfile(binary_path), f"Path {binary_path} is not a file."
    assert os.access(binary_path, os.X_OK), f"Binary {binary_path} is not executable."


def test_binary_is_compiled_executable():
    with open("/home/user/process", "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/process is not a compiled ELF executable."


def test_aggregated_csv_output():
    """Test that the aggregated.csv file exists and contains the correct aggregated data."""
    csv_path = "/home/user/aggregated.csv"
    assert os.path.exists(csv_path), f"Output CSV {csv_path} is missing."

    expected_csv = (
        "Hour,MeanValue,FailCount\n"
        "2023-10-12T08:00:00Z,46.1,1\n"
        "2023-10-12T09:00:00Z,42.0,2\n"
        "2023-10-13T10:00:00Z,10.0,0"
    )

    with open(csv_path, "r") as f:
        content = f.read().strip()

    assert content == expected_csv, f"The content of {csv_path} does not match the expected output.\nExpected:\n{expected_csv}\n\nGot:\n{content}"


def test_pipeline_log_output():
    """Test that the pipeline.log file exists and contains the correct log message."""
    log_path = "/home/user/pipeline.log"
    assert os.path.exists(log_path), f"Pipeline log {log_path} is missing."

    expected_log_line = "Processed 8 records. Found 3 unique hours."

    with open(log_path, "r") as f:
        lines = f.read().strip().splitlines()

    assert any(expected_log_line in line for line in lines), f"Expected log line '{expected_log_line}' not found in {log_path}."


def test_program_on_modified_input():
    rng = secrets.SystemRandom()
    candidate_hours = [
        "2021-01-03T02", "2021-07-19T23", "2022-02-14T11",
        "2023-08-05T00", "2024-03-21T16", "2025-11-30T07",
        "2026-04-09T19", "2027-12-17T05",
    ]
    selected_hours = rng.sample(candidate_hours, 4)
    input_lines = []

    for hour in selected_hours:
        center = Decimal(rng.randrange(-150, 501)) / Decimal(10)
        values = [center - Decimal("1.0"), center, center + Decimal("1.0")]
        statuses = [
            "OK " + secrets.token_hex(4),
            "sensor-FAIL-code " + secrets.token_hex(4),
            rng.choice(["fail lowercase", "PROFILE normal", "FAIL: timeout"])
            + " " + secrets.token_hex(4),
        ]
        rng.shuffle(statuses)
        for value, status in zip(values, statuses):
            minute = rng.randrange(60)
            second = rng.randrange(60)
            input_lines.append(
                f"{hour}:{minute:02d}:{second:02d}Z {value:.1f} {status}"
            )

    rng.shuffle(input_lines)
    telemetry = "\n".join(input_lines) + "\n"

    aggregates = {}
    for line in telemetry.splitlines():
        timestamp, value_text, status = line.split(maxsplit=2)
        bucket = timestamp[:13] + ":00:00Z"
        entry = aggregates.setdefault(bucket, [Decimal("0"), 0, 0])
        entry[0] += Decimal(value_text)
        entry[1] += 1
        entry[2] += int("FAIL" in status)

    expected_rows = ["Hour,MeanValue,FailCount"]
    for bucket in sorted(aggregates):
        total, count, fail_count = aggregates[bucket]
        mean = total / Decimal(count)
        expected_rows.append(f"{bucket},{mean:.1f},{fail_count}")
    expected_csv = "\n".join(expected_rows)

    with open("/home/user/telemetry.txt", "w") as f:
        f.write(telemetry)

    if os.path.exists("/home/user/aggregated.csv"):
        os.remove("/home/user/aggregated.csv")

    marker = "existing-log-entry-" + secrets.token_hex(8)
    with open("/home/user/pipeline.log", "w") as f:
        f.write(marker + "\n")

    result = subprocess.run(
        ["/home/user/process"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"/home/user/process exited with {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )

    assert os.path.isfile("/home/user/aggregated.csv"), "Program did not generate aggregated.csv."
    with open("/home/user/aggregated.csv", "r") as f:
        actual_csv = f.read().strip()
    assert actual_csv == expected_csv, (
        f"Program produced incorrect output for modified telemetry.\n"
        f"Expected:\n{expected_csv}\n\nGot:\n{actual_csv}"
    )

    expected_log = f"Processed {len(input_lines)} records. Found {len(aggregates)} unique hours."
    with open("/home/user/pipeline.log", "r") as f:
        log_lines = f.read().strip().splitlines()
    assert log_lines == [marker, expected_log], (
        "Program must preserve the existing log and append exactly one correct line. "
        f"Expected {[marker, expected_log]!r}, got {log_lines!r}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
