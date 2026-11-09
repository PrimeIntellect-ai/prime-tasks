#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import stat
import subprocess
from decimal import Decimal

SOURCE = "/home/user/src/etl.cpp"
BINARY = "/home/user/src/etl"
INPUT = "/home/user/data/telemetry.log"
OUTPUT = "/home/user/output/clean_telemetry.csv"

ORIGINAL_EXPECTED = [
    "timestamp,sensor,temperature,status",
    "2023-10-12T08:14:00Z,S100,45.2,active",
    "2023-10-12T08:15:00Z,S101,12.1,ok",
    "2023-10-12T08:16:00Z,S103,59.9,warn",
]

def read_lines():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} does not exist"
    with open(OUTPUT, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]

def expected_for(raw):
    result = ["timestamp,sensor,temperature,status"]
    for line in raw.splitlines():
        timestamp, sensor, temperature_text, status_field = line.split(" | ")
        temperature = Decimal(temperature_text)
        if temperature < Decimal("-20.0") or temperature > Decimal("60.0"):
            continue
        assert status_field.startswith('status="') and status_field.endswith('"')
        status_value = status_field[len('status="'):-1]
        status_value = re.sub(r"\\u[0-9a-fA-F]{4}", "", status_value)
        aligned = timestamp[:14] + "00Z"
        result.append(f"{aligned},{sensor},{temperature:.1f},{status_value}")
    return result

def run_program():
    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)
    completed = subprocess.run(
        [BINARY], cwd="/home/user", text=True, capture_output=True, timeout=10
    )
    assert completed.returncode == 0, (
        f"ETL program failed with exit code {completed.returncode}\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(OUTPUT), f"ETL program did not create {OUTPUT}"
    return read_lines()

def main():
    assert os.path.lexists(SOURCE), f"Missing required source file {SOURCE}"
    source_stat = os.lstat(SOURCE)
    assert stat.S_ISREG(source_stat.st_mode), f"{SOURCE} must be a regular C++ source file"

    # Preserve the original assertion that the agent generated the requested output.
    assert read_lines() == ORIGINAL_EXPECTED, (
        f"Content of {OUTPUT} does not match the expected output"
    )

    with open(INPUT, "rb") as f:
        original_input = f.read()
    with open(OUTPUT, "rb") as f:
        original_output = f.read()

    try:
        compiled = subprocess.run(
            ["g++", "-std=c++17", "-O2", SOURCE, "-o", BINARY],
            text=True, capture_output=True, timeout=30
        )
        assert compiled.returncode == 0, (
            f"Failed to compile {SOURCE}\nstdout:\n{compiled.stdout}\n"
            f"stderr:\n{compiled.stderr}"
        )
        binary_stat = os.lstat(BINARY)
        assert stat.S_ISREG(binary_stat.st_mode) and os.access(BINARY, os.X_OK), (
            f"Compiled artifact {BINARY} is not an executable regular file"
        )

        # Execute the compiled source against the supplied data as well.
        assert run_program() == ORIGINAL_EXPECTED

        # A randomized input prevents a fixed copy of the known CSV from passing.
        token = secrets.token_hex(8)
        second = secrets.randbelow(60)
        minute = secrets.randbelow(60)
        hidden_input = "\n".join([
            f"2024-02-29T23:{minute:02d}:{second:02d}Z | X{token}A | 60.0 | status=\"alpha{token}\\u2713tail\\uAbCd\"",
            f"2025-01-02T03:04:01Z | X{token}B | -20.0 | status=\"low{token}\"",
            f"2025-06-07T08:09:58Z | X{token}DROP1 | 60.01 | status=\"drop\\u0021\"",
            f"2025-06-07T08:10:02Z | X{token}DROP2 | -20.01 | status=\"drop\"",
            f"2026-11-12T13:14:47Z | X{token}C | 7.26 | status=\"pre\\u0000mid\\uFFFFpost{token}\"",
        ]) + "\n"
        with open(INPUT, "w", encoding="utf-8", newline="") as f:
            f.write(hidden_input)
        actual = run_program()
        expected = expected_for(hidden_input)
        assert actual == expected, (
            "Compiled ETL program failed the generated telemetry case.\n"
            f"Expected:\n{chr(10).join(expected)}\n\n"
            f"Actual:\n{chr(10).join(actual)}"
        )
    finally:
        with open(INPUT, "wb") as f:
            f.write(original_input)
        with open(OUTPUT, "wb") as f:
            f.write(original_output)

if __name__ == "__main__":
    main()
TEST_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
