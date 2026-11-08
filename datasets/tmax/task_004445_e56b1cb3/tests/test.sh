#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_clean_metrics_exists():
    """Test that the clean_metrics.csv file exists."""
    file_path = "/home/user/clean_metrics.csv"
    assert os.path.exists(file_path), f"File {file_path} is missing. The C program may not have run or failed to produce output."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."


def test_clean_metrics_content():
    """Test that the clean_metrics.csv file has the correct content after processing."""
    file_path = "/home/user/clean_metrics.csv"

    expected_content = (
        "1000,v1.0,45.5\n"
        "1010,v1.0,46.0\n"
        "1020,v1.0,0.0\n"
        "1030,v1.2,50.0\n"
        "1040,v1.2,52.0\n"
        "1050,v1.2,0.0\n"
        "1060,v1.2,0.0\n"
        "1070,v1.3,49.5\n"
    )

    with open(file_path, "r") as f:
        content = f.read()

    content = content.replace("\r\n", "\n")
    if not content.endswith("\n") and content:
        content += "\n"

    assert content == expected_content, f"Content of {file_path} does not match the expected clean data. Check your C program's validation, deduplication, and gap-filling logic."


def test_processor_binary_exists():
    """Test that the compiled C program exists."""
    file_path = "/home/user/processor"
    assert os.path.exists(file_path), f"Compiled binary {file_path} is missing."
    assert os.access(file_path, os.X_OK), f"File {file_path} is not executable."


def test_processor_c_source_exists():
    """Test that the C source code exists."""
    file_path = "/home/user/processor.c"
    assert os.path.exists(file_path), f"C source file {file_path} is missing."
TEST_EOF

cat << 'DYNAMIC_EOF' > /tmp/test_processor_behavior.py
import os
import secrets
import subprocess

RAW = "/home/user/raw_metrics.csv"
OUT = "/home/user/clean_metrics.csv"
SUBMITTED = "/home/user/processor"
SOURCE = "/home/user/processor.c"
REBUILT = "/tmp/processor_rebuilt"


def expected_output(rows):
    result = []
    seen_valid_timestamps = set()
    previous_timestamp = None
    previous_config = None

    for timestamp, config, temperature in rows:
        if temperature < 0.0 or temperature > 150.0:
            continue
        if timestamp in seen_valid_timestamps:
            continue
        seen_valid_timestamps.add(timestamp)

        if previous_timestamp is not None:
            missing = previous_timestamp + 10
            while missing < timestamp:
                result.append(f"{missing},{previous_config},0.0\n")
                missing += 10

        result.append(f"{timestamp},{config},{temperature:.1f}\n")
        previous_timestamp = timestamp
        previous_config = config

    return "".join(result)


def make_fixture():
    base = (170000000 + secrets.randbelow(100000)) * 10
    configs = ["v" + secrets.token_hex(3) for _ in range(4)]
    a, b, c, d = configs
    rows = [
        (base, a, -0.1),
        (base, a, 0.0),
        (base, b, 71.2),
        (base + 10, b, 150.1),
        (base + 10, b, 42.7),
        (base + 10, c, 43.8),
        (base + 40, c, 150.0),
        (base + 40, d, 12.4),
        (base + 50, c, 999.0),
        (base + 70, d, 63.5),
    ]
    return rows


def run_case(executable, rows):
    with open(RAW, "w", newline="\n") as f:
        for timestamp, config, temperature in rows:
            f.write(f"{timestamp},{config},{temperature:.1f}\n")

    try:
        os.unlink(OUT)
    except FileNotFoundError:
        pass

    completed = subprocess.run(
        [executable],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
        check=False,
    )
    assert completed.returncode == 0, (
        f"{executable} exited with status {completed.returncode}: "
        f"{completed.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(OUT), f"{executable} did not create {OUT}"

    with open(OUT, "r", newline="") as f:
        actual = f.read().replace("\r\n", "\n")
    if actual and not actual.endswith("\n"):
        actual += "\n"

    expected = expected_output(rows)
    assert actual == expected, (
        f"Incorrect output from {executable}.\nExpected:\n{expected}\nActual:\n{actual}"
    )


assert os.path.isfile(SUBMITTED), "Compiled processor is not a regular file"
with open(SUBMITTED, "rb") as f:
    assert f.read(4) == b"\x7fELF", "processor must be a compiled executable"

subprocess.run(
    ["gcc", "-std=c11", "-O2", "-Wall", "-Wextra", SOURCE, "-o", REBUILT],
    stdout=subprocess.PIPE,
    stderr=subprocess.PIPE,
    timeout=15,
    check=True,
)

run_case(SUBMITTED, make_fixture())
run_case(REBUILT, make_fixture())
DYNAMIC_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1 && \
   python3 /tmp/test_processor_behavior.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
