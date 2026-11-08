#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile
import uuid

TOOL_DIR = "/home/user/log_tool"
SOURCE = os.path.join(TOOL_DIR, "aggregator.c")
EXECUTABLE = os.path.join(TOOL_DIR, "aggregator")
TIMELINE = "/home/user/timeline.txt"
PRODUCTION_LOGS = [
    "/home/user/logs/service_a.log",
    "/home/user/logs/service_b.log",
]

EXPECTED_PRODUCTION_LINES = [
    "1620000001 Service B initialized",
    "1620000005 Service A started",
    "1620000008 Service B waiting",
    "1620000010 Service A connecting",
    "1620000015 Service B error",
    "1620000020 Service A connected",
]


def run_tool(binary, inputs):
    result = subprocess.run(
        [binary, *inputs],
        cwd=TOOL_DIR,
        capture_output=True,
        text=True,
        timeout=5,
    )
    assert result.returncode == 0, (
        f"{binary} failed with return code {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert os.path.isfile(TIMELINE), f"{binary} did not create {TIMELINE}."
    with open(TIMELINE, "r") as f:
        return [line.rstrip("\n") for line in f]


def test_aggregator_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Compiled executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_timeline_txt_exists():
    assert os.path.isfile(TIMELINE), f"Output file {TIMELINE} is missing."


def test_source_builds_with_make_and_as_c_program():
    clean = subprocess.run(
        ["make", "clean"], cwd=TOOL_DIR, capture_output=True, text=True, timeout=10
    )
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"

    build = subprocess.run(
        ["make"], cwd=TOOL_DIR, capture_output=True, text=True, timeout=10
    )
    assert build.returncode == 0, f"make failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(EXECUTABLE), f"make did not create {EXECUTABLE}."
    assert os.access(EXECUTABLE, os.X_OK), f"make output {EXECUTABLE} is not executable."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "make output is not a compiled ELF executable."

    direct_binary = "/tmp/aggregator_from_submitted_source"
    compile_result = subprocess.run(
        [
            "gcc",
            "-Wall",
            "-Werror=implicit-function-declaration",
            "-o",
            direct_binary,
            SOURCE,
        ],
        cwd=TOOL_DIR,
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert compile_result.returncode == 0, (
        "aggregator.c does not compile with the required flags:\n"
        f"{compile_result.stdout}\n{compile_result.stderr}"
    )


def test_built_tool_sorts_fresh_inputs_and_ignores_corruption():
    token = uuid.uuid4().hex
    timestamps = secrets.SystemRandom().sample(range(100000, 900000), 8)
    records = [(timestamp, f"event_{token}_{i}") for i, timestamp in enumerate(timestamps)]
    expected = [f"{timestamp} {message}" for timestamp, message in sorted(records)]

    direct_binary = "/tmp/aggregator_from_submitted_source"
    assert os.path.isfile(direct_binary) and os.access(direct_binary, os.X_OK)

    restore_result = None
    try:
        with tempfile.TemporaryDirectory(prefix="aggregator_verifier_") as temp_dir:
            first_log = os.path.join(temp_dir, "first.log")
            second_log = os.path.join(temp_dir, "second.log")

            with open(first_log, "w") as f:
                for timestamp, message in records[::2]:
                    f.write(f"{timestamp} {message}\n")
                f.write(f"CORRUPTED_{token}\n")
                f.write("\n")

            with open(second_log, "w") as f:
                f.write(f"BROKEN_{token}\n")
                for timestamp, message in records[1::2]:
                    f.write(f"{timestamp} {message}\n")

            for binary in (EXECUTABLE, direct_binary):
                actual = run_tool(binary, [first_log, second_log])
                assert actual == expected, (
                    f"{binary} did not sort fresh inputs correctly or failed to exclude "
                    f"lines without spaces.\nExpected: {expected}\nGot: {actual}"
                )
    finally:
        restore_result = subprocess.run(
            [EXECUTABLE, *PRODUCTION_LOGS],
            cwd=TOOL_DIR,
            capture_output=True,
            text=True,
            timeout=5,
        )

    assert restore_result.returncode == 0, (
        "The compiled aggregator failed on the production logs.\n"
        f"stdout: {restore_result.stdout}\nstderr: {restore_result.stderr}"
    )


def test_timeline_txt_content():
    with open(TIMELINE, "r") as f:
        actual_lines = f.readlines()

    actual_lines_clean = [line.strip() for line in actual_lines if line.strip()]

    assert actual_lines_clean == EXPECTED_PRODUCTION_LINES, (
        f"Timeline content is incorrect.\nExpected:\n{EXPECTED_PRODUCTION_LINES}"
        f"\nGot:\n{actual_lines_clean}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
