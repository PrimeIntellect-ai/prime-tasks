#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import shutil
import subprocess
import tempfile


def test_c_program_exists():
    c_file = "/home/user/workspace/process_telemetry.c"
    assert os.path.isfile(c_file), f"Expected C program at {c_file} is missing."


def test_processed_telemetry_file_exists():
    processed_file = "/home/user/remote_server/archive/processed_telemetry.csv"
    assert os.path.isfile(processed_file), f"Expected processed data file at {processed_file} is missing."


def test_processed_telemetry_content():
    processed_file = "/home/user/remote_server/archive/processed_telemetry.csv"
    assert os.path.isfile(processed_file), f"File {processed_file} does not exist."

    expected_lines = [
        "1001,S001,50.00",
        "1006,S006,60.00",
        "1007,S123,0.00",
        "1008,S999,0.00"
    ]

    with open(processed_file, "r") as f:
        content = f.read().strip().splitlines()

    actual_lines = [line.strip() for line in content if line.strip()]

    assert actual_lines == expected_lines, (
        f"Processed telemetry data is incorrect.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Got:\n{chr(10).join(actual_lines)}"
    )


def test_no_leftover_processed_csv():
    leftover_file = "/home/user/workspace/processed.csv"
    assert not os.path.exists(leftover_file), (
        f"File {leftover_file} should have been moved, but it still exists in the workspace."
    )


def derive_expected(lines):
    expected = []
    integer_re = re.compile(r"[+-]?\d+")
    float_re = re.compile(r"[+-]?(?:\d+(?:\.\d*)?|\.\d+)")

    for line in lines:
        fields = line.split(",")
        if len(fields) != 5:
            continue
        timestamp, sensor_id, temperature, humidity, status = fields
        if not integer_re.fullmatch(timestamp):
            continue
        if int(timestamp) <= 0:
            continue
        if not re.fullmatch(r"S\d{3}", sensor_id):
            continue
        if not float_re.fullmatch(temperature) or not float_re.fullmatch(humidity):
            continue
        temp = float(temperature)
        humid = float(humidity)
        if not (-50.0 <= temp <= 150.0):
            continue
        if not (0.0 <= humid <= 100.0):
            continue
        if status not in ("OK", "WARN"):
            continue
        expected.append(f"{timestamp},{sensor_id},{temp + 0.5 * humid:.2f}")
    return expected


def make_case(rng):
    used = set()

    def sensor():
        while True:
            value = f"S{rng.randrange(1000):03d}"
            if value not in used:
                used.add(value)
                return value

    base = rng.randrange(20000, 900000)
    temp = rng.randrange(-40, 140) + 0.25
    humidity = rng.randrange(0, 50) * 2 + 1
    lines = [
        f"{base},{sensor()},{temp:.2f},{humidity:.1f},OK",
        f"{base + 1},{sensor()},-50.0,100.0,WARN",
        f"{base + 2},{sensor()},150.0,0.0,OK",
        f"0,{sensor()},20.0,40.0,OK",
        f"-7,{sensor()},20.0,40.0,WARN",
        f"{base + 3},A123,20.0,40.0,OK",
        f"{base + 4},S12,20.0,40.0,OK",
        f"{base + 5},S12X,20.0,40.0,OK",
        f"{base + 6},{sensor()},150.01,40.0,OK",
        f"{base + 7},{sensor()},-50.01,40.0,OK",
        f"{base + 8},{sensor()},20.0,100.01,OK",
        f"{base + 9},{sensor()},20.0,-0.01,OK",
        f"{base + 10},{sensor()},not-a-number,40.0,OK",
        f"{base + 11},{sensor()},20.0,nan,OK",
        f"{base + 12},{sensor()},20.0,40.0,ERR",
        f"{base + 13},{sensor()},20.0,40.0,OK,EXTRA",
        f"{base + 14},{sensor()},20.0,40.0",
    ]
    rng.shuffle(lines)
    return lines


def test_compile_and_process_unseen_inputs():
    source = "/home/user/workspace/process_telemetry.c"
    workspace = "/home/user/workspace"
    raw_file = "/home/user/remote_server/raw_telemetry.csv"
    generated_output = os.path.join(workspace, "processed.csv")

    build_dir = tempfile.mkdtemp(prefix="telemetry-verifier-")
    executable = os.path.join(build_dir, "process_telemetry")
    original_raw = None
    if os.path.exists(raw_file):
        with open(raw_file, "rb") as f:
            original_raw = f.read()

    try:
        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-Wall", "-Wextra", source, "-o", executable],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )
        assert compile_result.returncode == 0, (
            "process_telemetry.c did not compile successfully:\n"
            + compile_result.stdout + compile_result.stderr
        )
        assert os.path.isfile(executable) and os.access(executable, os.X_OK)

        rng = random.SystemRandom()
        for _ in range(2):
            lines = make_case(rng)
            expected = derive_expected(lines)
            with open(raw_file, "w", newline="") as f:
                f.write("\n".join(lines) + "\n")

            if os.path.lexists(generated_output):
                os.remove(generated_output)

            result = subprocess.run(
                [executable, raw_file],
                cwd=workspace,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=10,
            )
            assert result.returncode == 0, (
                f"Compiled program exited with status {result.returncode}.\n"
                f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
            )
            assert os.path.isfile(generated_output), (
                "Compiled program did not create processed.csv in its current working directory."
            )
            with open(generated_output, "r") as f:
                actual = [line.strip() for line in f.read().splitlines() if line.strip()]
            assert actual == expected, (
                "Compiled program produced incorrect output for unseen telemetry input.\n"
                f"Expected:\n{chr(10).join(expected)}\n"
                f"Got:\n{chr(10).join(actual)}"
            )
            os.remove(generated_output)
    finally:
        if original_raw is None:
            if os.path.exists(raw_file):
                os.remove(raw_file)
        else:
            with open(raw_file, "wb") as f:
                f.write(original_raw)
        if os.path.lexists(generated_output):
            os.remove(generated_output)
        shutil.rmtree(build_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
