#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import shutil
import subprocess

SOURCE = "/home/user/generate_config.c"
EXECUTABLE = "/home/user/generate_config"
OUTPUT = "/home/user/final_config.txt"

EXPECTED_LINES = [
    "alias: user201@eng.domain.com",
    "route: 10.5.0.201",
    "alias: user202@hr.domain.com",
    "route: 10.2.0.202",
    "alias: user203@mkt.domain.com",
    "route: 10.3.0.203",
    "alias: user204@it.domain.com",
    "route: 10.9.0.204",
    "alias: user205@eng.domain.com",
    "route: 10.4.0.205",
    "alias: user206@fin.domain.com",
    "route: 10.6.0.206",
    "alias: user207@sales.domain.com",
    "route: 10.3.0.207",
    "alias: user208@rnd.domain.com",
    "route: 10.8.0.208",
]


def assert_output_accuracy(label):
    assert os.path.exists(OUTPUT), f"{label} did not create {OUTPUT}."

    with open(OUTPUT, "r", encoding="utf-8") as f:
        raw = f.read()

    agent_lines = [line.strip() for line in raw.splitlines() if line.strip()]
    remaining = list(agent_lines)
    correct = 0
    for expected in EXPECTED_LINES:
        if expected in remaining:
            correct += 1
            remaining.remove(expected)

    accuracy = correct / len(EXPECTED_LINES)
    threshold = 0.85
    assert accuracy >= threshold, (
        f"Accuracy {accuracy:.2f} is below the threshold of {threshold:.2f}. "
        f"Correct lines: {correct}/{len(EXPECTED_LINES)}."
    )

    actual_lines = raw.splitlines()
    assert actual_lines == EXPECTED_LINES, (
        f"{label} must produce exactly two correctly ordered lines per user."
    )


def run_and_check(program, label):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    result = subprocess.run(
        [program],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{label} exited with status {result.returncode}. stderr: {result.stderr}"
    )
    assert_output_accuracy(label)


def test_c_program_exists():
    assert os.path.exists(SOURCE), "C source file /home/user/generate_config.c is missing."
    assert os.path.isfile(SOURCE), "/home/user/generate_config.c is not a regular file."
    assert os.path.exists(EXECUTABLE), "Compiled executable /home/user/generate_config is missing."
    assert os.path.isfile(EXECUTABLE), "/home/user/generate_config is not a regular file."
    assert os.access(EXECUTABLE, os.X_OK), "Executable /home/user/generate_config is not executable."

    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/generate_config is not a compiled ELF executable."

    run_and_check(EXECUTABLE, "Submitted executable")

    build_dir = "/tmp/verifier-build"
    shutil.rmtree(build_dir, ignore_errors=True)
    os.makedirs(build_dir)
    rebuilt = os.path.join(build_dir, "generate_config")
    result = subprocess.run(
        ["gcc", SOURCE, "-o", rebuilt],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"generate_config.c failed to compile: {result.stderr}"
    run_and_check(rebuilt, "Executable rebuilt from generate_config.c")


def test_final_config_accuracy():
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} is missing."
    assert_output_accuracy("Final output")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
