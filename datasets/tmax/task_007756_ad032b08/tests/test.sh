#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess

SCRIPT_FILE = "/home/user/parse_gcode.py"
EXPECTED_ARCHIVE_OUTPUT = [
    "0.200",
    "0.400",
    "0.600",
    "0.800",
    "1.000",
    "1.200",
]


def run_parser(input_text):
    result = subprocess.run(
        ["python3", SCRIPT_FILE],
        input=input_text,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"Parser exited with status {result.returncode}. stderr: {result.stderr}"
    )
    return result.stdout.strip().splitlines()


def test_z_layers_output():
    output_file = "/home/user/z_layers.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

    with open(output_file, "r") as f:
        content = f.read().strip().splitlines()

    assert content == EXPECTED_ARCHIVE_OUTPUT, (
        f"Content of {output_file} does not match expected output. Got: {content}"
    )


def test_python_script_exists():
    assert os.path.isfile(SCRIPT_FILE), f"Python script {SCRIPT_FILE} does not exist."


def test_parser_on_streamed_archive():
    command = (
        "cat /home/user/archive/data.tar.gz.parta "
        "/home/user/archive/data.tar.gz.partb "
        "/home/user/archive/data.tar.gz.partc | "
        "tar -xzOf - machine.gcode | "
        "python3 /home/user/parse_gcode.py"
    )
    result = subprocess.run(
        ["bash", "-o", "pipefail", "-c", command],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"Streaming pipeline failed with status {result.returncode}. "
        f"stderr: {result.stderr}"
    )
    assert result.stdout.strip().splitlines() == EXPECTED_ARCHIVE_OUTPUT


def test_parser_behavior_on_derived_input():
    rng = random.SystemRandom()
    values = rng.sample(range(1, 10000), 8)
    expected = [f"{value / 1000:.3f}" for value in sorted(values)]

    lines = [
        "G21",
        " G1 Z123.456 F100",       # Does not start exactly with G1 Z
        "G1  Z123.456 F100",       # Two spaces before Z
        "G0 Z123.456",
        "G1 X2.000 Z123.456",
        "g1 Z123.456",
        "prefixG1 Z123.456",
        "G1 Znot-a-number",
        "G1 Z",
    ]

    for value in values:
        token = f"{value / 1000:.3f}"
        lines.append(f"G1 Z{token} F{rng.randrange(100, 9000)}")
        # The same numeric value with an additional trailing zero must be deduplicated.
        lines.append(f"G1 Z{token}0")

    rng.shuffle(lines)
    actual = run_parser("\n".join(lines) + "\n")
    assert actual == expected, f"Parser output was {actual}; expected {expected}"


def test_no_gcode_file_on_disk():
    # The task explicitly states not to extract the .gcode file to disk.
    assert not os.path.exists("/home/user/machine.gcode"), "/home/user/machine.gcode was extracted to disk, but it should have been streamed."
    assert not os.path.exists("/home/user/archive/machine.gcode"), "machine.gcode was found in the archive directory."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
