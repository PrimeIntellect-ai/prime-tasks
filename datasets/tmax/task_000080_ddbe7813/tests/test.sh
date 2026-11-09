#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess


def test_processor_c_exists():
    assert os.path.isfile("/home/user/processor.c"), "/home/user/processor.c does not exist."


def test_merged_csv_exists():
    assert os.path.isfile("/home/user/merged.csv"), "/home/user/merged.csv does not exist. Did you run your C program?"


def test_merged_csv_content():
    expected_lines = [
        "1,30.0,IDLE",
        "2,31.0,IDLE",
        "3,32.0,IDLE",
        "4,33.0,IDLE",
        "5,34.0,IDLE",
        "6,33.0,ACTIVE",
        "7,32.0,ACTIVE",
        "8,31.0,ACTIVE",
        "9,30.0,ACTIVE",
        "10,29.0,ACTIVE",
        "11,28.0,ACTIVE",
        "12,28.5,ERROR",
        "13,29.0,ERROR",
        "14,29.5,ERROR",
        "15,30.0,ERROR"
    ]

    with open("/home/user/merged.csv", "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in merged.csv, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines), start=1):
        assert actual == expected, f"Line {i} mismatch: expected '{expected}', got '{actual}'."


def _make_case(temp_times, state_times):
    # Temperatures are represented in tenths. Choosing an integral-tenth slope
    # makes every interpolated answer exact and avoids cross-language rounding issues.
    value = secrets.choice(range(180, 361))
    temperatures = [(temp_times[0], value)]
    slopes = []
    for next_time in temp_times[1:]:
        slope = secrets.choice([-7, -5, -3, -2, 2, 3, 5, 7])
        slopes.append(slope)
        value += slope * (next_time - temperatures[-1][0])
        temperatures.append((next_time, value))

    token = secrets.token_hex(4).upper()
    states = [(timestamp, f"S{index}_{token}") for index, timestamp in enumerate(state_times)]

    expected = []
    segment = 0
    state_index = 0
    for timestamp in range(1, 16):
        while segment + 1 < len(temperatures) and timestamp > temperatures[segment + 1][0]:
            segment += 1
        start_time, start_value = temperatures[segment]
        if timestamp == start_time:
            value_tenths = start_value
        else:
            value_tenths = start_value + slopes[segment] * (timestamp - start_time)

        while state_index + 1 < len(states) and states[state_index + 1][0] <= timestamp:
            state_index += 1
        expected.append(f"{timestamp},{value_tenths / 10:.1f},{states[state_index][1]}")

    return temperatures, states, expected


def _run_case(binary, temp_times, state_times):
    temperatures, states, expected = _make_case(temp_times, state_times)

    with open("/home/user/temperature.csv", "w") as f:
        for timestamp, value_tenths in temperatures:
            f.write(f"{timestamp},{value_tenths / 10:.1f}\n")

    with open("/home/user/state.csv", "w") as f:
        for timestamp, state in states:
            f.write(f"{timestamp},{state}\n")

    if os.path.exists("/home/user/merged.csv"):
        os.remove("/home/user/merged.csv")

    result = subprocess.run(
        [binary], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=10
    )
    assert result.returncode == 0, f"Compiled processor exited with {result.returncode}: {result.stderr}"
    assert os.path.isfile("/home/user/merged.csv"), "Compiled processor did not create /home/user/merged.csv"

    with open("/home/user/merged.csv", "r") as f:
        actual = [line.strip() for line in f if line.strip()]

    assert len(actual) == len(expected), f"Expected {len(expected)} generated rows, found {len(actual)}"
    for index, (actual_line, expected_line) in enumerate(zip(actual, expected), start=1):
        assert actual_line == expected_line, f"Generated-input line {index}: expected '{expected_line}', got '{actual_line}'"


def test_z_compiled_processor_handles_input_files():
    binary = "/home/user/processor"
    compile_result = subprocess.run(
        ["gcc", "/home/user/processor.c", "-o", binary],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, f"processor.c failed to compile: {compile_result.stderr}"
    assert os.path.isfile(binary) and os.access(binary, os.X_OK), "Compilation did not produce an executable processor"

    _run_case(binary, [1, 4, 10, 15], [1, 3, 8, 14])
    _run_case(binary, [1, 6, 9, 12, 15], [1, 2, 7, 11, 15])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
