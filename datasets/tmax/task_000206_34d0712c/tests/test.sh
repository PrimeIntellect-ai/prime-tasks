#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

CONFIG = "/home/user/dataset/config.txt"
SOURCE = "/home/user/transform.c"
BINARY = "/home/user/transform"
OUTPUT = "/home/user/dataset/normalized_experiment_01.gcode"


def test_transform_c_exists():
    assert os.path.isfile(SOURCE), f"Expected C source file {SOURCE} is missing."


def test_transform_executable_exists():
    assert os.path.isfile(BINARY), f"Expected compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"File {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"Expected {BINARY} to be a compiled ELF binary."


def test_normalized_gcode_output():
    assert os.path.isfile(OUTPUT), f"Expected output file {OUTPUT} is missing."

    expected_output = (
        "G1 X110.5 Y70.0 F3000\n"
        "G0 X115.0 Y75.5\n"
        "G1 X120.0 Y80.0 E1.5\n"
    )

    with open(OUTPUT, "r", encoding="utf-8") as f:
        actual_output = f.read()

    assert actual_output.strip() == expected_output.strip(), (
        f"Content of {OUTPUT} does not match expected output.\n"
        f"Expected:\n{expected_output}\n"
        f"Actual:\n{actual_output}"
    )


def decimal_tenths(value):
    sign = "-" if value < 0 else ""
    value = abs(value)
    return f"{sign}{value // 10}.{value % 10}"


def make_case(x_offset, y_offset, coordinates):
    suffixes = [" F2875", "", " E2.7 S41"]
    commands = ["G1", "G0", "G1"]
    input_lines = []
    expected_lines = []
    for command, suffix, (x, y) in zip(commands, suffixes, coordinates):
        input_lines.append(
            f"{command} X{decimal_tenths(x)} Y{decimal_tenths(y)}{suffix}\n"
        )
        expected_lines.append(
            f"{command} X{decimal_tenths(x + x_offset)} "
            f"Y{decimal_tenths(y + y_offset)}{suffix}\n"
        )
    return "".join(input_lines), "".join(expected_lines)


def run_transform(program, stdin_text, expected):
    result = subprocess.run(
        [program],
        input=stdin_text,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert result.returncode == 0, (
        f"{program} exited with status {result.returncode}. stderr: {result.stderr}"
    )
    assert result.stdout == expected, (
        f"{program} produced incorrect output.\n"
        f"Expected:\n{expected!r}\nActual:\n{result.stdout!r}"
    )


def test_source_and_binary_read_config_and_stdin_dynamically():
    rng = secrets.SystemRandom()
    coordinates = []
    for _ in range(3):
        coordinates.append((rng.randrange(-800, 801), rng.randrange(-800, 801)))

    offset_sets = [
        (rng.randrange(25, 151), rng.randrange(-175, -24)),
        (rng.randrange(-190, -39), rng.randrange(40, 181)),
    ]

    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "transform_from_source")
        compile_result = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
            check=False,
        )
        assert compile_result.returncode == 0, (
            f"transform.c did not compile successfully:\n{compile_result.stderr}"
        )

        with open(CONFIG, "rb") as f:
            original_config = f.read()
        try:
            for x_offset, y_offset in offset_sets:
                with open(CONFIG, "w", encoding="utf-8") as f:
                    f.write(decimal_tenths(x_offset) + "\n")
                    f.write(decimal_tenths(y_offset) + "\n")

                stdin_text, expected = make_case(x_offset, y_offset, coordinates)
                run_transform(BINARY, stdin_text, expected)
                run_transform(rebuilt, stdin_text, expected)
        finally:
            with open(CONFIG, "wb") as f:
                f.write(original_config)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
