#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
import pytest

SOURCE = "/home/user/processor.c"
BINARY = "/home/user/processor"
LARGE_INPUT = "/home/user/large_input.txt"


def run_program(path, input_data, timeout=3):
    result = subprocess.run(
        [path],
        input=input_data,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=timeout,
        check=False,
    )
    assert result.returncode == 0, f"{path} exited with {result.returncode}: {result.stderr}"
    return result.stdout


@pytest.fixture(scope="session")
def compiled_source():
    output = os.path.join(tempfile.mkdtemp(prefix="processor_verify_"), "processor")
    result = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", output],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
        check=False,
    )
    assert result.returncode == 0, f"processor.c did not compile with gcc -O2: {result.stderr}"
    return output


def test_minimal_crash_file():
    path = "/home/user/minimal_crash.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert "3,0,1,1,1" in content, f"File {path} does not contain the correct minimal crash line."

    with open(LARGE_INPUT, "r") as f:
        source_lines = [line.strip() for line in f if line.strip()]
    crashing_lines = []
    for line in source_lines:
        fields = line.split(",")
        if len(fields) == 5 and int(fields[1]) <= 0:
            crashing_lines.append(line)
    assert len(crashing_lines) == 1
    assert content == crashing_lines[0], "minimal_crash.txt must contain exactly the single crashing line."


def test_fixed_output_file():
    path = "/home/user/fixed_output.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "ID: 1, Weight: 16",
        "ID: 2, Weight: 13",
        "Corrupted record ID: 3",
        "ID: 4, Weight: 25"
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual_lines == expected_lines, f"File {path} contents do not match the expected output. Got: {actual_lines}"


def test_processor_c_fixed_formula():
    path = "/home/user/processor.c"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read()

    assert "(a + b) * c" not in content.replace(" ", ""), f"File {path} still contains the buggy weight calculation."
    cleaned_content = content.replace(" ", "")
    assert "a+b*c" in cleaned_content or "a+(b*c)" in cleaned_content, f"File {path} does not contain the corrected weight calculation formula."


def test_processor_binary_exists():
    path = "/home/user/processor"
    assert os.path.isfile(path), f"Compiled binary {path} does not exist."
    assert os.access(path, os.X_OK), f"File {path} is not executable."
    with open(path, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File {path} is not an ELF executable."


def test_required_binary_produced_fixed_output():
    with open(LARGE_INPUT, "r") as f:
        input_data = f.read()
    with open("/home/user/fixed_output.txt", "r") as f:
        saved_output = f.read()
    actual = run_program(BINARY, input_data)
    assert actual == saved_output, "fixed_output.txt is not the output produced by /home/user/processor."


def test_source_and_binary_on_generated_records(compiled_source):
    rng = random.SystemRandom()
    records = []
    expected = []

    # Exercise many undisclosed values, including corrupted records interleaved
    # with valid records so processing must continue after each corruption.
    for index in range(30):
        record_id = rng.randint(10000, 2000000000)
        length = rng.choice([0, -1, -2, -7, -31]) if index % 4 == 1 else rng.randint(1, 17)
        a = rng.randint(-5000, 5000)
        b = rng.randint(-5000, 5000)
        c = rng.randint(-5000, 5000)
        records.append(f"{record_id},{length},{a},{b},{c}")
        if length <= 0:
            expected.append(f"Corrupted record ID: {record_id}")
        else:
            expected.append(f"ID: {record_id}, Weight: {a + b * c}")

    input_data = "\n".join(records) + "\n"
    expected_output = "\n".join(expected) + "\n"

    source_output = run_program(compiled_source, input_data)
    binary_output = run_program(BINARY, input_data)
    assert source_output == expected_output, "Compiled processor.c failed generated behavioral tests."
    assert binary_output == expected_output, "/home/user/processor failed generated behavioral tests."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
