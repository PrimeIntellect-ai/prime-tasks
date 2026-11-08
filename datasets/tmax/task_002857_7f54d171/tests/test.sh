#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
from collections import defaultdict


def expected_output(raw_data):
    raw_lines = raw_data.splitlines()
    assert raw_lines, "Input file is empty."

    seen_keys = set()
    sensor_history = defaultdict(list)
    output_lines = [
        "timestamp_ms,sensor_id,temperature,humidity,rolling_avg_temp,status_message"
    ]

    for line in raw_lines[1:]:
        if not line.strip():
            continue

        parts = line.split(b',')
        if len(parts) < 5:
            continue

        timestamp_ms = int(parts[0])
        sensor_id = parts[1].decode('ascii')
        temperature = float(parts[2])
        humidity = float(parts[3])
        status_message_bytes = b','.join(parts[4:])
        status_message = ''.join('?' if b > 127 else chr(b) for b in status_message_bytes)

        if not (-50.0 <= temperature <= 150.0):
            continue
        if not (0.0 <= humidity <= 100.0):
            continue

        key = (timestamp_ms, sensor_id)
        if key in seen_keys:
            continue
        seen_keys.add(key)

        sensor_history[sensor_id].append(temperature)
        recent_temps = sensor_history[sensor_id][-3:]
        rolling_avg = sum(recent_temps) / len(recent_temps)

        output_lines.append(
            f"{timestamp_ms},{sensor_id},{temperature:.1f},{humidity:.1f},"
            f"{rolling_avg:.2f},{status_message}"
        )

    return ("\n".join(output_lines) + "\n").replace("\r\n", "\n")


def run_and_check(program, raw_data, expected):
    input_file = "/home/user/raw_sensor_data.csv"
    output_file = "/home/user/cleaned_sensor_data.csv"

    with open(input_file, "wb") as f:
        f.write(raw_data)
    if os.path.exists(output_file):
        os.remove(output_file)

    result = subprocess.run(
        [program], stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"{program} exited with status {result.returncode}. "
        f"stderr: {result.stderr.decode('utf-8', errors='replace')}"
    )
    assert os.path.isfile(output_file), f"{program} did not create {output_file}."

    with open(output_file, "r", encoding="utf-8") as f:
        actual = f.read().replace("\r\n", "\n")
    assert actual == expected, f"Output produced by {program} is incorrect."


def test_final_state_and_functional_cleaner():
    source_file = "/home/user/cleaner.c"
    executable = "/home/user/cleaner"
    input_file = "/home/user/raw_sensor_data.csv"
    output_file = "/home/user/cleaned_sensor_data.csv"

    # Preserve the original verifier's existence and executability assertions.
    assert os.path.isfile(source_file), "The source file /home/user/cleaner.c does not exist."
    assert os.path.isfile(executable), "The compiled executable /home/user/cleaner does not exist."
    assert os.access(executable, os.X_OK), "The file /home/user/cleaner is not executable."

    # The requested compiled artifact must be a native executable, not an arbitrary script.
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/cleaner is not an ELF executable."

    # Preserve the original exact comparison against the supplied input and output.
    assert os.path.isfile(output_file), f"The output file {output_file} does not exist."
    with open(input_file, "rb") as f:
        original_input = f.read()
    with open(output_file, "rb") as f:
        original_output_bytes = f.read()
    original_expected = expected_output(original_input)
    original_actual = original_output_bytes.decode("utf-8").replace("\r\n", "\n")
    assert original_actual == original_expected, (
        "The content of cleaned_sensor_data.csv does not match the expected processed data."
    )

    sid1 = "A" + secrets.token_hex(3)
    sid2 = "B" + secrets.token_hex(3)
    base = 100000 + secrets.randbelow(800000)
    temp = 10 + secrets.randbelow(20)
    bad_byte1 = bytes([128 + secrets.randbelow(128)])
    bad_byte2 = bytes([128 + secrets.randbelow(128)])

    rows = [
        f"{base},{sid1},{temp}.0,40.0,first".encode(),
        f"{base},{sid1},{temp + 1}.0,41.0,duplicate".encode(),
        f"{base + 1},{sid1},151.0,42.0,invalid_temp".encode(),
        f"{base + 1},{sid1},{temp + 2}.0,42.0,".encode() + b"bad" + bad_byte1 + b"byte",
        f"{base + 2},{sid1},{temp + 3}.0,101.0,invalid_humidity".encode(),
        f"{base + 3},{sid1},{temp + 4}.0,43.0,third".encode(),
        f"{base + 4},{sid1},{temp + 6}.0,44.0,fourth".encode(),
        f"{base + 5},{sid1},{temp + 8}.0,45.0,fifth".encode(),
        f"{base + 10},{sid2},-50.0,0.0,lower_bound".encode(),
        f"{base + 11},{sid2},150.0,100.0,upper_bound".encode(),
        f"{base + 12},{sid2},10.0,50.0,".encode() + bad_byte2 + b"corrupt",
        f"{base + 13},{sid2},20.0,60.0,last".encode(),
    ]
    dynamic_input = (
        b"timestamp_ms,sensor_id,temperature,humidity,status_message\n"
        + b"\n".join(rows)
        + b"\n"
    )
    dynamic_expected = expected_output(dynamic_input)

    fd, rebuilt_executable = tempfile.mkstemp(prefix="rebuilt_cleaner_", dir="/tmp")
    os.close(fd)
    os.unlink(rebuilt_executable)

    try:
        compilation = subprocess.run(
            ["gcc", source_file, "-O2", "-o", rebuilt_executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
        assert compilation.returncode == 0, (
            "cleaner.c could not be compiled with gcc: "
            + compilation.stderr.decode("utf-8", errors="replace")
        )

        # Exercise both the submitted binary and a fresh build from cleaner.c on
        # verifier-generated data, preventing a precomputed output from passing.
        run_and_check(executable, dynamic_input, dynamic_expected)
        run_and_check(rebuilt_executable, dynamic_input, dynamic_expected)
    finally:
        with open(input_file, "wb") as f:
            f.write(original_input)
        with open(output_file, "wb") as f:
            f.write(original_output_bytes)
        if os.path.exists(rebuilt_executable):
            os.remove(rebuilt_executable)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
