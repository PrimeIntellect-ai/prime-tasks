#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import subprocess

import pytest

C_FILE = "/home/user/processor.c"
BINARY = "/home/user/processor"
RAW_FILE = "/home/user/raw_sensors.csv"
OUTPUT_FILE = "/home/user/output.csv"

ORIGINAL_INPUT = (
    "Hour,StationA_Temp,StationA_Status,StationB_Temp,StationB_Status\n"
    "8,15.5,En_línea,22.1,正常\n"
    "11,,Error_🔥,23.0,警告\n"
    "14,16.2,En_línea,,正常\n"
)

ORIGINAL_EXPECTED = (
    "Hour,Station,Temp,Status\n"
    "8,A,15.5,En_línea\n"
    "8,B,22.1,正常\n"
    "9,A,15.5,En_línea\n"
    "9,B,22.1,正常\n"
    "10,A,15.5,En_línea\n"
    "10,B,22.1,正常\n"
    "11,A,15.5,Error_🔥\n"
    "11,B,23.0,警告\n"
    "12,A,15.5,Error_🔥\n"
    "12,B,23.0,警告\n"
    "13,A,15.5,Error_🔥\n"
    "13,B,23.0,警告\n"
    "14,A,16.2,En_línea\n"
    "14,B,23.0,正常"
)


def test_processor_files_exist():
    """Test that the C source and compiled binary exist."""
    assert os.path.exists(C_FILE), f"C source file {C_FILE} is missing."
    assert os.path.isfile(C_FILE), f"C source path {C_FILE} is not a file."
    assert os.path.exists(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.path.isfile(BINARY), f"Compiled binary path {BINARY} is not a file."
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Binary {BINARY} is not a compiled ELF executable."


def test_output_csv_exists():
    """Test that the output.csv file was generated."""
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."
    assert os.path.isfile(OUTPUT_FILE), f"Path {OUTPUT_FILE} is not a file."


def test_output_csv_content():
    """Retain the exact check for the supplied input and generated output."""
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert content == ORIGINAL_EXPECTED, (
        "The content of output.csv does not match the expected reshaped and gap-filled data."
    )


def derive_expected(input_text):
    rows = list(csv.reader(input_text.splitlines()))
    assert rows[0] == [
        "Hour", "StationA_Temp", "StationA_Status",
        "StationB_Temp", "StationB_Status"
    ]

    observations = {}
    for row in rows[1:]:
        assert len(row) == 5
        observations[int(row[0])] = row[1:]

    minimum = min(observations)
    maximum = max(observations)
    last = {"A": [None, None], "B": [None, None]}
    result = ["Hour,Station,Temp,Status"]

    for hour in range(minimum, maximum + 1):
        if hour in observations:
            fields = observations[hour]
            updates = {"A": fields[0:2], "B": fields[2:4]}
            for station in ("A", "B"):
                for index in range(2):
                    if updates[station][index] != "":
                        last[station][index] = updates[station][index]

        for station in ("A", "B"):
            temp, status = last[station]
            assert temp is not None and status is not None
            result.append(f"{hour},{station},{float(temp):.1f},{status}")

    return "\n".join(result)


def run_case(executable, input_text, expected):
    with open(RAW_FILE, "w", encoding="utf-8", newline="") as f:
        f.write(input_text)
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    completed = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=8,
        check=False,
    )
    assert completed.returncode == 0, (
        f"{executable} exited with {completed.returncode}: "
        f"{completed.stderr.decode('utf-8', errors='replace')}"
    )
    assert os.path.exists(OUTPUT_FILE), f"{executable} did not generate {OUTPUT_FILE}."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a regular file."
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        actual = f.read().strip()
    assert actual == expected, f"{executable} produced incorrect output for a verification input."


def make_dynamic_input():
    token = secrets.token_hex(12)
    base = secrets.randbelow(20) + 2
    a0 = secrets.randbelow(200) / 10.0 - 5.0
    b0 = secrets.randbelow(200) / 10.0 + 10.0
    a1 = a0 + 1.3
    b1 = b0 + 2.7
    return (
        "Hour,StationA_Temp,StationA_Status,StationB_Temp,StationB_Status\n"
        f"{base},{a0:.1f},Conectado_ñ_{token},{b0:.1f},稼働中_{token}\n"
        f"{base + 2},,Alerta_🔥_{token},{b1:.1f},\n"
        f"{base + 5},{a1:.1f},,,警報_{token}\n"
    )


def test_program_is_executed_and_handles_changed_input():
    """Execute both the submitted binary and a fresh build on derived test cases."""
    rebuilt = "/tmp/processor_from_source"
    compilation = subprocess.run(
        ["gcc", C_FILE, "-o", rebuilt],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
        check=False,
    )
    assert compilation.returncode == 0, (
        "processor.c does not compile: "
        + compilation.stderr.decode("utf-8", errors="replace")
    )

    dynamic_input = make_dynamic_input()
    dynamic_expected = derive_expected(dynamic_input)

    for executable in (BINARY, rebuilt):
        run_case(executable, ORIGINAL_INPUT, ORIGINAL_EXPECTED)
        run_case(executable, dynamic_input, dynamic_expected)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
