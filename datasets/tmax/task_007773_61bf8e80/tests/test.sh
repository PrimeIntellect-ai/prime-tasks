#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import random
import subprocess

SOURCE_FILE = "/home/user/process_configs.cpp"
INPUT_FILE = "/home/user/config_changes.csv"
OUTPUT_FILE = "/home/user/processed_changes.csv"
EXECUTABLE = "/home/user/process_configs"
EXPECTED_HEADER = ["timestamp", "masked_ip", "server_id", "config_key", "size_delta", "rolling_avg_delta"]


def test_compile_and_execute_cpp_on_original_input():
    assert os.path.isfile(SOURCE_FILE), f"C++ source file {SOURCE_FILE} is missing."

    subprocess.run(
        ["g++", "-O3", "-std=c++17", SOURCE_FILE, "-o", EXECUTABLE],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert os.path.isfile(EXECUTABLE), f"Compiled executable {EXECUTABLE} is missing."

    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    subprocess.run(
        [EXECUTABLE],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )


def test_processed_changes_exists():
    output_file = "/home/user/processed_changes.csv"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."


def test_processed_changes_content():
    input_file = "/home/user/config_changes.csv"
    output_file = "/home/user/processed_changes.csv"

    assert os.path.isfile(input_file), f"Input file {input_file} is missing."
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    expected_rows = []
    expected_header = ["timestamp", "masked_ip", "server_id", "config_key", "size_delta", "rolling_avg_delta"]

    with open(input_file, 'r', newline='') as f:
        reader = csv.DictReader(f)
        deltas = []
        for row in reader:
            if not row or not any(row.values()):
                continue

            timestamp = row["timestamp"]
            ip_parts = row["user_ip"].split(".")
            masked_ip = f"{ip_parts[0]}.{ip_parts[1]}.*.*"
            server_id = row["server_id"]
            config_key = row["config_key"]

            old_size = int(row["old_size_bytes"])
            new_size = int(row["new_size_bytes"])
            size_delta = new_size - old_size
            deltas.append(size_delta)

            window = deltas[-3:]
            rolling_avg = sum(window) / len(window)
            rolling_avg_str = f"{rolling_avg:.2f}"

            expected_rows.append([timestamp, masked_ip, server_id, config_key, str(size_delta), rolling_avg_str])

    with open(output_file, 'r', newline='') as f:
        reader = csv.reader(f)
        actual_data = list(reader)

    assert len(actual_data) > 0, "Output file is empty."
    assert actual_data[0] == expected_header, f"Expected header {expected_header}, but got {actual_data[0]}"

    # Remove empty rows at the end if any
    while actual_data and not any(actual_data[-1]):
        actual_data.pop()

    actual_rows = actual_data[1:]

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, but got {actual}."


def test_cpp_source_exists():
    cpp_file = "/home/user/process_configs.cpp"
    assert os.path.isfile(cpp_file), f"C++ source file {cpp_file} is missing."


def test_executable_processes_unseen_input():
    rng = random.SystemRandom()
    original_input = open(INPUT_FILE, "rb").read()

    rows = []
    expected_rows = []
    deltas = []
    base_timestamp = rng.randrange(1700000000, 1900000000)

    for i in range(8):
        timestamp = str(base_timestamp + i * rng.randrange(2, 20))
        octets = [rng.randrange(1, 224), rng.randrange(0, 256), rng.randrange(0, 256), rng.randrange(1, 255)]
        user_ip = ".".join(str(x) for x in octets)
        server_id = f"dynamic-srv-{rng.randrange(1000, 9999)}-{i}"
        config_key = f"dynamic_key_{rng.randrange(10000, 99999)}_{i}"
        old_size = rng.randrange(50, 10000)
        delta = rng.randrange(-2000, 2001)
        if delta == 0:
            delta = i + 1
        new_size = old_size + delta

        rows.append([timestamp, user_ip, server_id, config_key, str(old_size), str(new_size)])
        deltas.append(delta)
        window = deltas[-3:]
        expected_rows.append([
            timestamp,
            f"{octets[0]}.{octets[1]}.*.*",
            server_id,
            config_key,
            str(delta),
            f"{sum(window) / len(window):.2f}",
        ])

    try:
        with open(INPUT_FILE, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "user_ip", "server_id", "config_key", "old_size_bytes", "new_size_bytes"])
            writer.writerows(rows)
            f.write("\n\n")

        if os.path.exists(OUTPUT_FILE):
            os.remove(OUTPUT_FILE)
        subprocess.run(
            [EXECUTABLE],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
        )

        assert os.path.isfile(OUTPUT_FILE), "Executable did not create the output CSV."
        with open(OUTPUT_FILE, "r", newline="") as f:
            actual_data = list(csv.reader(f))

        assert actual_data, "Output file is empty for unseen input."
        assert actual_data[0] == EXPECTED_HEADER, f"Expected header {EXPECTED_HEADER}, but got {actual_data[0]}"
        while actual_data and not any(actual_data[-1]):
            actual_data.pop()
        assert actual_data[1:] == expected_rows, f"Output for unseen input was incorrect: {actual_data[1:]}"
    finally:
        with open(INPUT_FILE, "wb") as f:
            f.write(original_input)
        subprocess.run(
            [EXECUTABLE],
            check=False,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=10,
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
