#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import secrets
import subprocess


def test_c_source_exists():
    """Test that the C source code file exists."""
    assert os.path.exists("/home/user/process_data.c"), "The C program source file /home/user/process_data.c is missing."


def test_executable_exists():
    """Test that the compiled executable exists."""
    assert os.path.exists("/home/user/processor"), "The compiled executable /home/user/processor is missing. Did you compile the program?"
    assert os.access("/home/user/processor", os.X_OK), "The file /home/user/processor is not executable."


def test_output_file_exists():
    """Test that the output CSV file exists."""
    assert os.path.exists("/home/user/clean_telemetry.csv"), "The output file /home/user/clean_telemetry.csv is missing. Did you run the program?"


def test_output_content_correct():
    """Test that the output CSV content matches the expected reshaped and deduplicated data."""
    input_file = "/home/user/raw_sensors.csv"
    output_file = "/home/user/clean_telemetry.csv"

    assert os.path.exists(input_file), f"Input file {input_file} is missing."
    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    # Derive expected output
    expected_rows = []
    seen = set()

    with open(input_file, "r") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if not row or len(row) < 5:
                continue
            sensor_id = row[0]
            timestamp = row[1]
            metric_A = float(row[2])
            metric_B = float(row[3])
            event_log = row[4]

            key = (sensor_id, timestamp)
            if key in seen:
                continue
            seen.add(key)

            # Normalize event log
            event = event_log.split(';')[0].lower()

            expected_rows.append(f"{sensor_id},{timestamp},metric_A,{metric_A:.2f},{event}")
            expected_rows.append(f"{sensor_id},{timestamp},metric_B,{metric_B:.2f},{event}")

    expected_content = "\n".join(expected_rows)

    with open(output_file, "r") as f:
        actual_content = f.read().strip()

    # We compare line by line to give better error messages
    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows in output, but got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Row {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"


def test_programs_execute_and_transform_fresh_input():
    """Compile the submitted source and exercise both it and the submitted executable."""
    input_file = "/home/user/raw_sensors.csv"
    output_file = "/home/user/clean_telemetry.csv"
    source_file = "/home/user/process_data.c"
    submitted_executable = "/home/user/processor"

    with open(input_file, "rb") as f:
        original_input = f.read()
    with open(output_file, "rb") as f:
        original_output = f.read()

    nonce = secrets.token_hex(4)
    base_timestamp = 1800000000 + secrets.randbelow(10000000)
    sensor1 = f"X{nonce[:6]}"
    sensor2 = f"Y{nonce[2:8]}"
    a1 = secrets.randbelow(8000) + 100
    b1 = secrets.randbelow(8000) + 100
    a2 = secrets.randbelow(8000) + 100
    b2 = secrets.randbelow(8000) + 100

    def number(cents):
        return f"{cents // 100}.{cents % 100:02d}"

    token1 = f"MiXeD_{nonce.upper()}"
    token2 = f"NoSemi{nonce.upper()}"
    generated_input = (
        "sensor_id,timestamp,metric_A,metric_B,event_log\n"
        f"{sensor1},{base_timestamp},{number(a1)},{number(b1)},{token1};Ignored;Tail\n"
        f"{sensor2},{base_timestamp},-{number(a2)},{number(b2)},SECOND_{nonce.upper()};Extra\n"
        f"{sensor1},{base_timestamp},999.99,888.88,DUPLICATE;MUST_IGNORE\n"
        f"{sensor1},{base_timestamp + 1},12.3,-7,{token2}\n"
    )
    expected_lines = [
        f"{sensor1},{base_timestamp},metric_A,{number(a1)},{token1.lower()}",
        f"{sensor1},{base_timestamp},metric_B,{number(b1)},{token1.lower()}",
        f"{sensor2},{base_timestamp},metric_A,-{number(a2)},second_{nonce.lower()}",
        f"{sensor2},{base_timestamp},metric_B,{number(b2)},second_{nonce.lower()}",
        f"{sensor1},{base_timestamp + 1},metric_A,12.30,{token2.lower()}",
        f"{sensor1},{base_timestamp + 1},metric_B,-7.00,{token2.lower()}",
    ]

    compiled_executable = f"/tmp/source_processor_{nonce}"
    try:
        compile_result = subprocess.run(
            ["gcc", "-O3", "-o", compiled_executable, source_file],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert compile_result.returncode == 0, (
            "The submitted C source did not compile with gcc -O3:\n"
            + compile_result.stderr
        )

        for executable in (submitted_executable, compiled_executable):
            with open(input_file, "w", newline="") as f:
                f.write(generated_input)
            if os.path.exists(output_file):
                os.remove(output_file)

            result = subprocess.run(
                [executable],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"{executable} exited with status {result.returncode}.\n"
                f"stderr:\n{result.stderr}"
            )
            assert os.path.exists(output_file), f"{executable} did not create {output_file}."

            with open(output_file, "r") as f:
                actual_lines = [line.strip() for line in f.read().splitlines() if line.strip()]
            assert actual_lines == expected_lines, (
                f"{executable} produced incorrect output for fresh runtime input.\n"
                f"Expected: {expected_lines}\nActual:   {actual_lines}"
            )
    finally:
        with open(input_file, "wb") as f:
            f.write(original_input)
        with open(output_file, "wb") as f:
            f.write(original_output)
        if os.path.exists(compiled_executable):
            os.remove(compiled_executable)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
