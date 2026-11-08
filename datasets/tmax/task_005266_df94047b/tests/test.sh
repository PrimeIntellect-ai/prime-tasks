#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess


def read_nonempty_lines(path):
    with open(path, 'r') as f:
        return [line.strip() for line in f if line.strip()]


def test_output_file_exists():
    path = "/home/user/output.txt"
    assert os.path.isfile(path), f"Output file is missing: {path}"


def test_output_file_contents():
    path = "/home/user/output.txt"
    assert os.path.isfile(path), f"Output file is missing: {path}"

    lines = read_nonempty_lines(path)

    expected_lines = [
        "Timestamp: 100, Lat: 37.7749, Lon: -122.4194",
        "Timestamp: 101, Lat: 34.0522, Lon: -118.2437",
        "Timestamp: 103, Lat: 40.7128, Lon: -74.0060",
        "Timestamp: 104, Lat: 51.5074, Lon: -0.1278",
        "Timestamp: 106, Lat: 48.8566, Lon: 2.3522",
        "Timestamp: 107, Lat: 35.6895, Lon: 139.6917",
        "Timestamp: 108, Lat: -33.8688, Lon: 151.2093",
        "Timestamp: 109, Lat: 55.7558, Lon: 37.6173",
        "Timestamp: 110, Lat: -23.5505, Lon: -46.6333",
        "Timestamp: 111, Lat: -37.8136, Lon: 144.9631"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, but got {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"


def test_process_script_fixes():
    path = "/home/user/process.py"
    assert os.path.isfile(path), f"Python script is missing: {path}"

    with open(path, 'r') as f:
        content = f.read()

    # Preserve the original check for the known incorrect unpacking format.
    assert "<I I f f 8x" not in content, "The script still contains the incorrect struct unpacking format '<I I f f 8x'."


def test_process_script_on_altered_input():
    script_path = "/home/user/process.py"
    input_path = "/home/user/sensor_data.bin"
    output_path = "/home/user/output.txt"

    assert os.path.isfile(script_path), f"Python script is missing: {script_path}"

    with open(input_path, 'rb') as f:
        original_input = f.read()
    original_output = None
    if os.path.exists(output_path):
        with open(output_path, 'rb') as f:
            original_output = f.read()

    rng = secrets.SystemRandom()
    base_ts = 200000 + secrets.randbelow(500000)
    timestamps = rng.sample(range(base_ts, base_ts + 5000), 12)

    records = []
    valid_records = []
    corrupt_positions = set(rng.sample(range(12), 2))
    for i, ts in enumerate(timestamps):
        lat = (secrets.randbelow(1700000001) - 850000000) / 10000000.0
        lon = (secrets.randbelow(3500000001) - 1750000000) / 10000000.0
        if i in corrupt_positions:
            magic = rng.choice([0, 0x12345678, 0xFEEDFACE])
        else:
            magic = 0xDEADBEEF
            valid_records.append((ts, lat, lon))
        records.append((magic, ts, lat, lon))

    expected_lines = [
        f"Timestamp: {ts}, Lat: {lat:.4f}, Lon: {lon:.4f}"
        for ts, lat, lon in sorted(valid_records, key=lambda item: item[0])
    ]

    try:
        with open(input_path, 'wb') as f:
            for record in records:
                f.write(struct.pack('<I I d d', *record))

        try:
            result = subprocess.run(
                ['python3', script_path],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=30,
            )
        except subprocess.TimeoutExpired as exc:
            raise AssertionError("process.py did not finish within 30 seconds") from exc

        assert result.returncode == 0, (
            f"process.py failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.isfile(output_path), "process.py did not create /home/user/output.txt"

        actual_lines = read_nonempty_lines(output_path)
        assert len(actual_lines) == len(expected_lines), (
            f"Expected {len(expected_lines)} valid records on altered input, "
            f"but got {len(actual_lines)}."
        )
        for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
            assert actual == expected, (
                f"Altered-input line {i+1} mismatch.\n"
                f"Expected: {expected}\nActual:   {actual}"
            )
    finally:
        with open(input_path, 'wb') as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(output_path):
                os.remove(output_path)
        else:
            with open(output_path, 'wb') as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
