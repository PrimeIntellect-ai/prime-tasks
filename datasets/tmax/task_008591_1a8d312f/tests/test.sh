#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from pathlib import Path


def test_cpp_source_exists():
    cpp_path = "/home/user/process_data.cpp"
    assert os.path.exists(cpp_path), f"The C++ source file {cpp_path} does not exist."
    assert os.path.isfile(cpp_path), f"{cpp_path} is not a file."


def test_executable_exists():
    exe_path = "/home/user/process_data"
    assert os.path.exists(exe_path), f"The compiled executable {exe_path} does not exist."
    assert os.path.isfile(exe_path), f"{exe_path} is not a file."
    assert os.access(exe_path, os.X_OK), f"The file {exe_path} is not executable."


def test_processed_sensors_output():
    output_path = "/home/user/processed_sensors.csv"
    assert os.path.exists(output_path), f"The output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"{output_path} is not a file."

    expected_lines = [
        "2023-10-12T14:35:00,0.3775",
        "2023-10-12T14:37:00,0.3900",
        "2023-10-12T14:38:00,1.0000",
        "2023-10-12T14:39:00,0.0000"
    ]

    with open(output_path, "r", encoding="utf-8") as f:
        actual_content = f.read().strip()

    actual_lines = [line.strip() for line in actual_content.split('\n') if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {output_path}, but found {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i+1}: expected '{expected}', but got '{actual}'."


def test_program_parses_and_processes_altered_csv():
    source = Path("/home/user/process_data.cpp")
    submitted_exe = Path("/home/user/process_data")
    raw_path = Path("/home/user/raw_sensors.csv")
    output_path = Path("/home/user/processed_sensors.csv")
    rebuilt_exe = Path(f"/tmp/process_data_rebuilt_{secrets.token_hex(8)}")

    compile_result = subprocess.run(
        ["g++", "-std=c++17", str(source), "-o", str(rebuilt_exe)],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        "process_data.cpp did not compile with the required command:\n"
        + compile_result.stdout + compile_result.stderr
    )

    rng = random.SystemRandom()
    token = secrets.token_hex(10)
    year = rng.randint(2024, 2032)
    month = rng.randint(1, 12)
    day = rng.randint(1, 28)
    hour = rng.randint(0, 22)

    def timestamp(index):
        minute = (rng.randint(0, 40) + index * 3) % 60
        second = rng.randint(1, 59)
        return f"{year:04d}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}:{second:02d}"

    records = [
        (101, timestamp(0), "TEMP_B", rng.randint(-30, 130), f"ignored,{token}\nwith an embedded newline"),
        (102, timestamp(1), "TEMP_A", rng.randint(-40, 140), f"first matching record {token}\ncontinued on another line"),
        (103, timestamp(2), "TEMP_A ", rng.randint(-40, 140), "near-match sensor must be ignored"),
        (104, timestamp(3), "TEMP_A", 150 + rng.randint(1, 70), "high anomaly, clamp to one"),
        (105, timestamp(4), "PRESS_A", rng.randint(-40, 140), "another ignored sensor"),
        (106, timestamp(5), "TEMP_A", -50 - rng.randint(1, 70), "low anomaly\nclamp to zero"),
        (107, timestamp(6), "TEMP_A", rng.randint(-40, 140), f"contains a comma, a newline\nand a \"quoted\" word {token}"),
    ]

    def encode_record(record):
        ident, ts, sensor, value, description = record
        escaped_description = description.replace('"', '""')
        return f'{ident},{ts},{sensor},{value},"{escaped_description}"'

    raw_content = "id,timestamp,sensor_id,value,description\n"
    raw_content += "\n".join(encode_record(record) for record in records) + "\n"

    expected = []
    for _, ts, sensor, value, _ in records:
        if sensor == "TEMP_A":
            normalized = (float(value) + 50.0) / 200.0
            normalized = max(0.0, min(1.0, normalized))
            expected.append(f"{ts[:16]}:00,{normalized:.4f}")

    original_raw = raw_path.read_bytes()
    original_output = output_path.read_bytes()
    try:
        raw_path.write_text(raw_content, encoding="utf-8")

        # Exercise both the artifact supplied by the agent and a fresh build of
        # the submitted C++ source. Removing the output prevents a no-op binary
        # from passing by leaving another run's result in place.
        for executable in (submitted_exe, rebuilt_exe):
            if output_path.exists():
                output_path.unlink()
            result = subprocess.run(
                [str(executable)],
                cwd="/home/user",
                capture_output=True,
                text=True,
                timeout=15,
            )
            assert result.returncode == 0, (
                f"{executable} exited with status {result.returncode}:\n"
                + result.stdout + result.stderr
            )
            assert output_path.exists() and output_path.is_file(), (
                f"{executable} did not create {output_path}"
            )
            actual = output_path.read_text(encoding="utf-8").splitlines()
            assert actual == expected, (
                f"{executable} produced incorrect output for an altered CSV.\n"
                f"Expected: {expected!r}\nActual: {actual!r}"
            )
    finally:
        raw_path.write_bytes(original_raw)
        output_path.write_bytes(original_output)
        if rebuilt_exe.exists():
            rebuilt_exe.unlink()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
