#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
from decimal import Decimal, ROUND_HALF_UP

INPUT_FILE = "/home/user/input_data.csv"
OUTPUT_FILE = "/home/user/output_data.csv"
EXECUTABLE = "/home/user/process"
CPP_FILE = "/home/user/process_sensors.cpp"

ORIGINAL_INPUT = """timestamp,S1_T,S1_H,S2_T,S2_H
100,20.0,50.0,22.0,55.0
110,,51.0,22.5,
120,21.0,,23.0,56.0
130,,,23.5,57.0
"""

ORIGINAL_EXPECTED = """timestamp,sensor_id,temperature,humidity,temp_roll_avg_3
100,S1,20.00,50.00,20.00
110,S1,20.00,51.00,20.00
120,S1,21.00,51.00,20.33
130,S1,21.00,51.00,20.67
100,S2,22.00,55.00,22.00
110,S2,22.50,55.00,22.25
120,S2,23.00,56.00,22.50
130,S2,23.50,57.00,23.00"""


def write_input(content):
    with open(INPUT_FILE, "w", newline="") as f:
        f.write(content)


def run_and_read(program, input_content):
    write_input(input_content)
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)

    result = subprocess.run(
        [program], cwd="/home/user", text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"{program} exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."
    assert os.path.isfile(OUTPUT_FILE), f"Path {OUTPUT_FILE} is not a file."
    with open(OUTPUT_FILE, "r", newline="") as f:
        return f.read().strip()


def reference_output(input_content):
    lines = input_content.strip().splitlines()
    header = lines[0].split(",")

    columns = {}
    for index, name in enumerate(header[1:], start=1):
        if name.endswith("_T"):
            columns.setdefault(name[:-2], {})["T"] = index
        elif name.endswith("_H"):
            columns.setdefault(name[:-2], {})["H"] = index

    rows = [line.split(",") for line in lines[1:]]
    result = ["timestamp,sensor_id,temperature,humidity,temp_roll_avg_3"]
    two_places = Decimal("0.01")

    for sensor in sorted(columns):
        assert set(columns[sensor]) == {"T", "H"}
        last_t = None
        last_h = None
        temperatures = []

        for row in sorted(rows, key=lambda r: int(r[0])):
            raw_t = row[columns[sensor]["T"]]
            raw_h = row[columns[sensor]["H"]]

            if raw_t != "":
                last_t = Decimal(raw_t)
            elif last_t is None:
                last_t = Decimal(0)

            if raw_h != "":
                last_h = Decimal(raw_h)
            elif last_h is None:
                last_h = Decimal(0)

            temperatures.append(last_t)
            window = temperatures[-3:]
            average = sum(window, Decimal(0)) / Decimal(len(window))

            def fmt(value):
                return str(value.quantize(two_places, rounding=ROUND_HALF_UP))

            result.append(
                f"{int(row[0])},{sensor},{fmt(last_t)},{fmt(last_h)},{fmt(average)}"
            )

    return "\n".join(result)


def make_dynamic_fixture():
    base = 10 + secrets.randbelow(50)
    humidity = 40 + secrets.randbelow(30)
    start = 1000 + secrets.randbelow(50000)
    step = 7 + secrets.randbelow(40)
    timestamps = [start + i * step for i in range(4)]

    # Header sensor order is deliberately different from alphabetical order.
    header = "timestamp,S2_T,S2_H,S10_T,S10_H,A_T,A_H"
    chronological = [
        [timestamps[0], "", "", base + 10, "", "", humidity + 4],
        [timestamps[1], base + 2, humidity + 1, "", humidity + 5, base + 20, humidity + 6],
        [timestamps[2], "", humidity + 2, base + 12, "", "", ""],
        [timestamps[3], base + 5, "", "", humidity + 8, base + 24, humidity + 9],
    ]

    # Input rows are not chronological, so sorting must occur before filling.
    order = [2, 0, 3, 1]
    lines = [header]
    for index in order:
        lines.append(",".join(str(value) for value in chronological[index]))
    return "\n".join(lines) + "\n"


def test_complete_cpp_pipeline():
    assert os.path.exists(CPP_FILE), f"C++ source file {CPP_FILE} is missing."
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.path.isfile(EXECUTABLE), f"Path {EXECUTABLE} is not a file."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."

    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXECUTABLE} is not a compiled executable."

    # Preserve the original exact-content assertion, but first actually execute
    # the submitted artifact on the original fixture.
    content = run_and_read(EXECUTABLE, ORIGINAL_INPUT)
    assert content == ORIGINAL_EXPECTED, (
        f"Content of {OUTPUT_FILE} does not match the expected output."
    )

    # Compile the submitted C++ source independently so both the source and the
    # submitted binary must implement the requested transformation.
    rebuilt = "/tmp/process_from_submitted_source"
    compile_result = subprocess.run(
        ["g++", "-std=c++17", "-O2", CPP_FILE, "-o", rebuilt],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compile_result.returncode == 0, (
        f"Submitted C++ source does not compile: {compile_result.stderr}"
    )
    assert os.path.isfile(rebuilt) and os.access(rebuilt, os.X_OK)

    dynamic_input = make_dynamic_fixture()
    dynamic_expected = reference_output(dynamic_input)

    installed_content = run_and_read(EXECUTABLE, dynamic_input)
    assert installed_content == dynamic_expected, (
        "Submitted executable failed a changed input fixture.\n"
        f"Expected:\n{dynamic_expected}\nActual:\n{installed_content}"
    )

    rebuilt_content = run_and_read(rebuilt, dynamic_input)
    assert rebuilt_content == dynamic_expected, (
        "Executable rebuilt from submitted source failed a changed input fixture.\n"
        f"Expected:\n{dynamic_expected}\nActual:\n{rebuilt_content}"
    )

    # Restore the task's original input and required final output.
    final_content = run_and_read(EXECUTABLE, ORIGINAL_INPUT)
    assert final_content == ORIGINAL_EXPECTED, (
        f"Content of {OUTPUT_FILE} does not match the expected output."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
