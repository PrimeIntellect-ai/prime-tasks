#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import pytest

REPO = "/home/user/math_processor"
SOURCE_FILE = os.path.join(REPO, "src/main.rs")
CARGO_FILE = os.path.join(REPO, "Cargo.toml")
OUTPUT_FILE = "/home/user/output.txt"
INPUTS_FILE = os.path.join(REPO, "inputs.txt")
SECRET = 987654321
MASK_64 = (1 << 64) - 1
ORIGINAL_INPUTS = [10, 50, 100]


def compute_sequence(n: int, secret: int) -> int:
    if n == 0:
        return 0
    if n == 1:
        return 1
    a = 0
    b = 1
    for _ in range(2, n + 1):
        next_val = (b * secret + a) & MASK_64
        a = b
        b = next_val
    return b


def expected_lines(inputs):
    return [f"Input: {n}, Output: {compute_sequence(n, SECRET)}" for n in inputs]


def run_application():
    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=REPO,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
    )
    assert result.returncode == 0, (
        "cargo run failed.\nstdout:\n"
        + result.stdout
        + "\nstderr:\n"
        + result.stderr
    )
    assert os.path.isfile(OUTPUT_FILE), f"The application did not create {OUTPUT_FILE}."


@pytest.fixture(scope="session", autouse=True)
def verify_and_execute_submission():
    assert os.path.isfile(SOURCE_FILE), f"The Rust source file {SOURCE_FILE} is missing."
    assert os.path.isfile(CARGO_FILE), f"The Cargo manifest {CARGO_FILE} is missing."

    with open(SOURCE_FILE, "r") as f:
        source = f.read()
    secret_match = re.search(r"\bconst\s+SECRET\s*:\s*u64\s*=\s*([0-9_]+)\s*;", source)
    assert secret_match, "src/main.rs must define SECRET as a u64 constant."
    restored_secret = int(secret_match.group(1).replace("_", ""))
    assert restored_secret == SECRET, "The original SECRET value was not restored in src/main.rs."

    with open(INPUTS_FILE, "rb") as f:
        original_bytes = f.read()
    parsed_original = [int(line.strip()) for line in original_bytes.decode().splitlines() if line.strip()]
    assert parsed_original == ORIGINAL_INPUTS, "inputs.txt was modified from the provided task inputs."

    hidden_inputs = [0, 1, 2, 3, 4, 7, 19, 64, 127]
    try:
        with open(INPUTS_FILE, "w") as f:
            f.write("\n".join(map(str, hidden_inputs)) + "\n")
        run_application()
        with open(OUTPUT_FILE, "r") as f:
            hidden_lines = [line.strip() for line in f if line.strip()]
        assert hidden_lines == expected_lines(hidden_inputs), (
            "The Rust application did not implement the required u64 wrapping sequence "
            "for verifier-selected inputs."
        )
    finally:
        with open(INPUTS_FILE, "wb") as f:
            f.write(original_bytes)

    run_application()
    yield


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"The final output file {OUTPUT_FILE} was not created."


def test_output_file_contents():
    assert os.path.isfile(INPUTS_FILE), f"The inputs file {INPUTS_FILE} is missing."

    with open(INPUTS_FILE, "r") as f:
        inputs = [int(line.strip()) for line in f if line.strip()]

    expected_outputs = {str(n): str(compute_sequence(n, SECRET)) for n in inputs}

    with open(OUTPUT_FILE, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(inputs), f"Expected {len(inputs)} lines in {OUTPUT_FILE}, but got {len(lines)}."

    for line in lines:
        assert "Input: " in line and ", Output: " in line, f"Output line format is incorrect: '{line}'"
        parts = line.split(", Output: ")
        in_val = parts[0].replace("Input: ", "").strip()
        out_val = parts[1].strip()

        assert in_val in expected_outputs, f"Found unexpected input value '{in_val}' in {OUTPUT_FILE}."
        assert expected_outputs[in_val] == out_val, (
            f"Mismatch for Input: {in_val}. "
            f"Expected Output: {expected_outputs[in_val]}, but got Output: {out_val}."
        )

    assert lines == expected_lines(inputs), (
        "The output must contain exactly one correctly ordered line for every input."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
