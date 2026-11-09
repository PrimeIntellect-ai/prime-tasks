#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import subprocess
import tempfile

APP_DIR = "/home/user/telemetry_app"
SOURCE_FILE = os.path.join(APP_DIR, "telemetry_processor.c")
FINAL_OUTPUT_FILE = os.path.join(APP_DIR, "final_count.txt")
BINARY_FILE = os.path.join(APP_DIR, "telemetry_processor")


def expected_output(data_dir):
    count = 0
    for name in os.listdir(data_dir):
        path = os.path.join(data_dir, name)
        if os.path.isfile(path):
            with open(path, "rb") as f:
                count += len(f.read().split())
    return f"Total records: {count}"


def run_processor(binary, data_dir, timeout=15):
    result = subprocess.run(
        [binary, data_dir],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=timeout,
        check=False,
    )
    assert result.returncode == 0, (
        f"{binary} exited with status {result.returncode}. stderr: {result.stderr}"
    )
    return result.stdout.strip()


def test_binary_exists():
    assert os.path.isfile(BINARY_FILE), f"Compiled binary {BINARY_FILE} does not exist. Did you compile the C program?"
    assert os.access(BINARY_FILE, os.X_OK), f"File {BINARY_FILE} is not executable."
    with open(BINARY_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY_FILE} is not a compiled ELF binary."


def test_final_output_exists():
    assert os.path.isfile(FINAL_OUTPUT_FILE), f"Final output file {FINAL_OUTPUT_FILE} does not exist."


def test_final_output_content():
    assert os.path.isfile(FINAL_OUTPUT_FILE), f"Final output file {FINAL_OUTPUT_FILE} does not exist."
    with open(FINAL_OUTPUT_FILE, "r") as f:
        content = f.read().strip()

    expected_count = 50 * 100
    expected_string = f"Total records: {expected_count}"

    assert content == expected_string, f"Expected '{expected_string}', but found '{content}'. Check your C code fixes for race conditions, hangs, and crashes."


def test_repaired_source_compiles_and_both_binaries_process_data_safely():
    assert os.path.isfile(SOURCE_FILE), f"Repaired source {SOURCE_FILE} does not exist."

    with tempfile.TemporaryDirectory() as work_dir:
        rebuilt_binary = os.path.join(work_dir, "telemetry_processor_rebuilt")
        compile_result = subprocess.run(
            ["gcc", "-pthread", SOURCE_FILE, "-o", rebuilt_binary],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            check=False,
        )
        assert compile_result.returncode == 0, f"Repaired source does not compile: {compile_result.stderr}"

        original_data = os.path.join(APP_DIR, "data")
        original_expected = expected_output(original_data)
        with open(FINAL_OUTPUT_FILE, "r") as f:
            saved_output = f.read().strip()

        for binary in (BINARY_FILE, rebuilt_binary):
            for _ in range(3):
                actual = run_processor(binary, original_data)
                assert actual == original_expected, f"Expected '{original_expected}', but {binary} printed '{actual}'."
                assert actual == saved_output, "final_count.txt is not the output produced by the repaired program."

        generated_data = os.path.join(work_dir, "generated_data")
        os.mkdir(generated_data)
        for i in range(80):
            token_count = 1800 + secrets.randbelow(401)
            words = [f"record_{i}_{j}" for j in range(token_count)]
            words[secrets.randbelow(token_count)] = "record#with#several#hashes"
            words[secrets.randbelow(token_count)] = "L" * (4096 + secrets.randbelow(4096))
            with open(os.path.join(generated_data, f"input_{i:03d}.log"), "w") as f:
                f.write(" ".join(words))

        generated_expected = expected_output(generated_data)
        for binary in (BINARY_FILE, rebuilt_binary):
            for _ in range(4):
                actual = run_processor(binary, generated_data)
                assert actual == generated_expected, f"Expected '{generated_expected}', but {binary} printed '{actual}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
